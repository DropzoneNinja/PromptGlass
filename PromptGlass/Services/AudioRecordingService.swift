import AVFoundation
import AppKit
import Observation

// MARK: - Errors

enum AudioRecordingError: LocalizedError {
    case couldNotCreateDirectory(Error)
    case couldNotCreateFile(Error)
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .couldNotCreateDirectory(let e):
            return "Could not create recordings folder: \(e.localizedDescription)"
        case .couldNotCreateFile(let e):
            return "Could not create recording file: \(e.localizedDescription)"
        case .writeFailed(let e):
            return "Audio write failed: \(e.localizedDescription)"
        }
    }
}

// MARK: - Service

/// Records microphone audio to a timestamped `.m4a` file in
/// `~/Library/Application Support/PromptGlass/Recordings/`.
///
/// ## Threading
/// `append(buffer:)` is called on the **audio render thread**.
/// Actual disk writes are dispatched onto a private serial queue so the
/// audio thread is never blocked by I/O.
///
/// ## Usage
/// ```swift
/// try recordingService.start(format: audioCapture.tapFormat!, scriptName: document.name)
/// audioCapture.bufferSink = { [weak recorder] buf, _ in recorder?.append(buffer: buf) }
/// // … session ends …
/// let url = recordingService.stop()   // returns the file URL
/// ```
@Observable
final class AudioRecordingService {

    // MARK: - Observable state

    private(set) var isRecording = false
    private(set) var recordingURL: URL?
    private(set) var recordingError: AudioRecordingError?

    // MARK: - Private

    private var audioFile: AVAudioFile?
    private var recordingFormat: AVAudioFormat?
    private let writeQueue = DispatchQueue(
        label: "com.promptglass.recording.write",
        qos: .userInitiated
    )
    /// Held for the full recording lifetime when writing to a user-chosen
    /// security-scoped directory.  Released in `stop()`.
    private var securityScopedURL: URL?

    // MARK: - Recordings directory

    private var recordingsDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PromptGlass/Recordings", isDirectory: true)
    }

    // MARK: - Lifecycle

    /// Begins a new recording session.
    ///
    /// - Parameters:
    ///   - format: The `AVAudioFormat` from `AudioCaptureService.tapFormat`.
    ///   - scriptName: Used in the filename so recordings are identifiable.
    ///                 Sanitised before use; defaults to "Recording".
    ///   - customDirectory: A security-scoped URL for a user-chosen folder.
    ///                      When `nil`, falls back to the default Application Support path.
    /// - Throws: `AudioRecordingError` if the directory or file cannot be created.
    func start(format: AVAudioFormat, scriptName: String = "Recording", customDirectory: URL? = nil) throws {
        guard !isRecording else { return }
        recordingError = nil

        // Determine target directory.  For user-chosen security-scoped URLs,
        // start access now and keep it open until stop() — the AVAudioFile
        // handle needs the permission for the entire recording lifetime, not
        // just during directory creation.
        let targetDirectory: URL
        if let custom = customDirectory {
            _ = custom.startAccessingSecurityScopedResource()
            securityScopedURL = custom   // released in stop()
            targetDirectory = custom
        } else {
            targetDirectory = recordingsDirectory
        }

        // Ensure recordings directory exists.
        do {
            try FileManager.default.createDirectory(
                at: targetDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            let err = AudioRecordingError.couldNotCreateDirectory(error)
            recordingError = err
            throw err
        }

        let url = makeFileURL(in: targetDirectory, scriptName: scriptName)

        // AAC/M4A settings. AVAudioFile handles the PCM→AAC conversion internally.
        let fileSettings: [String: Any] = [
            AVFormatIDKey:             kAudioFormatMPEG4AAC,
            AVSampleRateKey:           format.sampleRate,
            AVNumberOfChannelsKey:     min(Int(format.channelCount), 2), // stereo max
            AVEncoderBitRateKey:       128_000,
            AVEncoderAudioQualityKey:  AVAudioQuality.high.rawValue
        ]

        do {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: fileSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            // Release security-scoped access if file creation fails.
            securityScopedURL?.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
            let err = AudioRecordingError.couldNotCreateFile(error)
            recordingError = err
            throw err
        }

        recordingURL = url
        recordingFormat = format
        isRecording = true
    }

    /// Stops recording and flushes the file to disk.
    ///
    /// - Returns: The URL of the completed `.m4a` file, or `nil` if recording
    ///   was never started.
    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return recordingURL }

        isRecording = false

        // Flush remaining queued writes, then release the file handle.
        writeQueue.sync {
            audioFile = nil   // closing AVAudioFile flushes its internal buffers
        }

        recordingFormat = nil

        // Relinquish security-scoped access now that the file is closed.
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil

        return recordingURL
    }

    // MARK: - Buffer ingestion

    /// Enqueues `buffer` for writing to disk.
    ///
    /// Safe to call on the audio render thread — the write is dispatched
    /// asynchronously onto `writeQueue`.
    func append(buffer: AVAudioPCMBuffer) {
        guard isRecording else { return }
        // Retain a local reference so the file cannot be nil'd between the
        // guard above and the async block below.
        guard let file = audioFile else { return }
        writeQueue.async { [weak self] in
            do {
                try file.write(from: buffer)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.recordingError = .writeFailed(error)
                }
            }
        }
    }

    // MARK: - Reveal in Finder

    /// Opens the recordings directory in Finder, selecting the most recent file.
    func revealInFinder() {
        guard let url = recordingURL else {
            NSWorkspace.shared.open(recordingsDirectory)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Clap marker

    /// Injects a double-impulse clapperboard transient directly into the recording.
    /// The two bursts are separated by 80 ms, producing a waveform spike that is
    /// instantly recognisable in any audio editor.
    ///
    /// Safe to call from `@MainActor` — buffer generation and file write are
    /// dispatched asynchronously onto `writeQueue`.
    func insertClapMarker() {
        guard isRecording, let format = recordingFormat, let file = audioFile else { return }
        writeQueue.async { [weak self] in
            guard let self, let buffer = self.makeClapBuffer(format: format) else { return }
            do {
                try file.write(from: buffer)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.recordingError = .writeFailed(error)
                }
            }
        }
    }

    /// Generates a 200 ms double-impulse clapperboard waveform matching `format`.
    ///
    /// Each burst is white noise with a 12 ms exponential decay — the classic
    /// crack transient. Burst 2 starts 80 ms after burst 1, matching clapperboard
    /// convention and making the marker easy to identify visually.
    private func makeClapBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate   = format.sampleRate
        let channelCount = Int(format.channelCount)
        let totalFrames  = AVAudioFrameCount(sampleRate * 0.200)    // 200 ms
        let burst2Offset = AVAudioFrameCount(sampleRate * 0.080)    // 80 ms gap
        let decayConst   = Float(sampleRate * 0.012)                // τ = 12 ms
        let amplitude: Float = 0.85

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
              let channelData = buffer.floatChannelData else { return nil }
        buffer.frameLength = totalFrames

        // Fill channel 0
        let ch0 = channelData[0]
        for frame in 0..<Int(totalFrames) {
            var sample: Float = 0
            // Burst 1
            sample += amplitude * expf(-Float(frame) / decayConst)
                      * Float.random(in: -1.0...1.0)
            // Burst 2
            if frame >= Int(burst2Offset) {
                let age2 = Float(frame - Int(burst2Offset))
                sample += amplitude * expf(-age2 / decayConst)
                          * Float.random(in: -1.0...1.0)
            }
            // Soft-clip to prevent inter-sample overs when both bursts briefly overlap
            ch0[frame] = max(-0.95, min(0.95, sample))
        }

        // Copy channel 0 to all remaining channels
        for ch in 1..<channelCount {
            memcpy(channelData[ch], ch0, Int(totalFrames) * MemoryLayout<Float>.size)
        }

        return buffer
    }

    // MARK: - Helpers

    private func makeFileURL(in directory: URL, scriptName: String) -> URL {
        let sanitised = String(
            scriptName
                .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " -_")).inverted)
                .joined()
                .trimmingCharacters(in: .whitespaces)
                .prefix(40)
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        guard !sanitised.isEmpty else {
            return directory.appendingPathComponent("\(timestamp).m4a")
        }

        let existing = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        let existingCount = existing.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix("_\(sanitised).m4a") ||
                   name.contains("_\(sanitised)-take-")
        }.count
        let takeNumber = existingCount + 1

        return directory.appendingPathComponent("\(timestamp)_\(sanitised)-take-\(takeNumber).m4a")
    }
}
