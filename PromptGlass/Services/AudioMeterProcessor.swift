import AVFoundation
import Observation

/// Computes a smoothed RMS level from microphone buffers and publishes it for
/// display in the teleprompter's live audio visualisation.
///
/// ## Threading
/// `process(buffer:)` is called on the **audio render thread** by
/// `AudioCaptureService.bufferSink`. The RMS computation happens on that thread;
/// the result is dispatched to the main thread at a capped refresh rate so SwiftUI
/// does not redraw faster than necessary.
///
/// ## Usage
/// ```swift
/// audioCapture.bufferSink = { [weak meter] buf, _ in meter?.process(buffer: buf) }
/// ```
@Observable
final class AudioMeterProcessor {

    // MARK: - Observable state

    /// Smoothed linear RMS level in [0.0, 1.0].
    ///
    /// 0.0 = silence, 1.0 = full scale (0 dBFS).
    /// Suitable for driving a level bar or waveform strip directly.
    private(set) var level: Float = 0

    // MARK: - Configuration

    /// Maximum UI update rate. Defaults to 20 fps — smooth enough for a meter
    /// without triggering unnecessary SwiftUI layout passes.
    var maxRefreshRate: Double = 20

    /// Smoothing factor applied each update: `smoothed = α·new + (1-α)·old`.
    /// Range: 0.0 (frozen) … 1.0 (no smoothing). Default 0.3 gives a snappy
    /// attack with a gentle release tail.
    var smoothingFactor: Float = 0.3

    /// Decay multiplier applied each update when the new level is *lower* than
    /// the current smoothed level. Higher values produce a slower release.
    var decayFactor: Float = 0.85

    // MARK: - Private

    // Accessed only on the audio thread — no actor isolation needed.
    private var lastDispatchTime: Double = 0

    // MARK: - Processing

    /// Compute RMS from the buffer and throttle UI updates to `maxRefreshRate`.
    ///
    /// Call this directly from `AudioCaptureService.bufferSink`; it is designed
    /// to be inexpensive on the audio render thread.
    func process(buffer: AVAudioPCMBuffer) {
        let now = CACurrentMediaTime()
        let minInterval = 1.0 / maxRefreshRate
        guard now - lastDispatchTime >= minInterval else { return }
        lastDispatchTime = now

        let rms = Self.computeRMS(buffer: buffer)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let current = self.level
            // Apply smoothing and decay separately so the level rises quickly
            // but falls slowly — typical VU-meter behaviour.
            if rms > current {
                self.level = self.smoothingFactor * rms + (1 - self.smoothingFactor) * current
            } else {
                self.level = self.decayFactor * current
            }
        }
    }

    /// Immediately resets the displayed level to zero (call on session stop).
    func reset() {
        DispatchQueue.main.async { [weak self] in self?.level = 0 }
    }

    // MARK: - RMS computation (static, audio-thread safe)

    /// Returns the root-mean-square of all samples across all channels in `buffer`,
    /// normalised to [0.0, 1.0].
    static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let frameCount  = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return 0 }

        var sumOfSquares: Float = 0
        for ch in 0..<channelCount {
            let data = channelData[ch]
            for frame in 0..<frameCount {
                let sample = data[frame]
                sumOfSquares += sample * sample
            }
        }

        let meanSquare = sumOfSquares / Float(frameCount * channelCount)
        return sqrt(meanSquare)
    }

    /// Returns the peak absolute sample value across all channels in `buffer`.
    static func computePeak(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let frameCount   = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return 0 }

        var peak: Float = 0
        for ch in 0..<channelCount {
            let data = channelData[ch]
            for frame in 0..<frameCount {
                let abs = abs(data[frame])
                if abs > peak { peak = abs }
            }
        }
        return peak
    }
}
