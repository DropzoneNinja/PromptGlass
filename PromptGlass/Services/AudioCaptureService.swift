import AudioToolbox
import AVFoundation
import CoreAudio
import Observation

// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case engineFailedToStart(Error)
    case engineInterrupted

    var errorDescription: String? {
        switch self {
        case .engineFailedToStart(let underlying):
            return "Could not start audio engine: \(underlying.localizedDescription)"
        case .engineInterrupted:
            return "Audio input was interrupted. Check your microphone and restart the session."
        }
    }
}

// MARK: - Service

/// Owns the `AVAudioEngine`, installs a single microphone tap, and fans out each
/// audio buffer to all registered consumers.
///
/// **Single-tap design:** all three consumers — speech recognition, level metering,
/// and file recording — receive the same `AVAudioPCMBuffer` reference from one tap.
/// This avoids the hardware conflict that occurs when multiple taps compete for the
/// same input node.
///
/// **Thread safety:** `bufferSink` is called on the audio render thread.
/// Each consumer is responsible for doing only lightweight, non-blocking work inside
/// the closure (e.g. appending to a request, dispatching to a serial queue).
@Observable
final class AudioCaptureService {

    // MARK: Observable state (update on main thread only)

    /// `true` while the engine is running and the tap is installed.
    private(set) var isRunning = false

    /// Set when the engine fails to start or is interrupted.
    private(set) var captureError: AudioCaptureError?

    /// The PCM format of the microphone tap, available once `start()` succeeds.
    private(set) var tapFormat: AVAudioFormat?

    /// Display name of the audio input device that is actually in use.
    /// Updated each time `start()` is called.
    private(set) var activeInputDeviceName: String = "System Default"

    // MARK: Consumer sink

    /// Called on the **audio render thread** for every captured buffer.
    ///
    /// Wire up all consumers here before calling `start()`:
    /// ```swift
    /// audioCapture.bufferSink = { [weak meter, weak recorder, weak recognizer] buf, time in
    ///     meter?.process(buffer: buf)
    ///     recorder?.append(buffer: buf)
    ///     recognizer?.append(buffer: buf)
    /// }
    /// ```
    var bufferSink: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    // MARK: Private

    private let engine = AVAudioEngine()

    // MARK: Lifecycle

    /// Installs the microphone tap and starts the audio engine.
    ///
    /// - Parameter preferredDeviceUID: The `AVCaptureDevice.uniqueID` of the
    ///   desired input device, or `nil` to use the system default.
    /// - Throws: `AudioCaptureError.engineFailedToStart` if `AVAudioEngine.start()` throws.
    func start(preferredDeviceUID: String? = nil) throws {
        guard !isRunning else { return }
        captureError = nil

        let inputNode = engine.inputNode

        // Attempt to route the engine's input to the user-selected device.
        // This must happen before the tap is installed and the format is read,
        // because the device determines the available sample rate / channel count.
        if let uid = preferredDeviceUID,
           let deviceID = coreAudioDeviceID(forUID: uid),
           let audioUnit = inputNode.audioUnit {
            var id = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            activeInputDeviceName = (status == noErr)
                ? (coreAudioDeviceName(for: deviceID) ?? "Selected Device")
                : (systemDefaultInputName() ?? "System Default")
        } else {
            activeInputDeviceName = systemDefaultInputName() ?? "System Default"
        }

        let format   = inputNode.outputFormat(forBus: 0)
        tapFormat = format

        // Install the single tap. bufferSize is advisory — Core Audio may deliver
        // different sizes. 4096 frames ≈ 85 ms at 48 kHz, suitable for speech.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            self?.bufferSink?(buffer, time)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            tapFormat = nil
            activeInputDeviceName = "System Default"
            let captureErr = AudioCaptureError.engineFailedToStart(error)
            captureError = captureErr
            throw captureErr
        }

        isRunning = true

        // Delay observer registration to skip the spurious AVAudioEngineConfigurationChange
        // that macOS fires during initial hardware warm-up. Genuine mid-session interruptions
        // (e.g. mic unplugged) are still caught once the grace period expires.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isRunning else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.handleConfigurationChange(_:)),
                name: Notification.Name.AVAudioEngineConfigurationChange,
                object: self.engine
            )
        }
    }

    /// Removes the tap and stops the engine.
    ///
    /// Always call `stop()` before releasing the service or starting a new session.
    func stop() {
        guard isRunning else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name.AVAudioEngineConfigurationChange,
            object: engine
        )
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        tapFormat = nil
    }

    // MARK: - Core Audio device helpers

    /// Returns the `AudioDeviceID` whose Core Audio UID matches `uid`, or `nil`.
    ///
    /// `AVCaptureDevice.uniqueID` on macOS equals the Core Audio device UID, so
    /// this bridges between the two frameworks without any extra translation.
    private func coreAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sysObj = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sysObj, &addr, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(sysObj, &addr, 0, nil, &dataSize, &ids) == noErr
        else { return nil }

        return ids.first { coreAudioDeviceUID(for: $0) == uid }
    }

    /// Returns the Core Audio UID string for `deviceID`, or `nil` on failure.
    private func coreAudioDeviceUID(for deviceID: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // Use Unmanaged to safely receive the +1-retained CFString from Core Audio.
        var unmanaged: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        let status = withUnsafeMutablePointer(to: &unmanaged) { ptr in
            AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, ptr)
        }
        return status == noErr ? unmanaged?.takeRetainedValue() as String? : nil
    }

    /// Returns the display name for `deviceID`, or `nil` on failure.
    private func coreAudioDeviceName(for deviceID: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanaged: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        let status = withUnsafeMutablePointer(to: &unmanaged) { ptr in
            AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, ptr)
        }
        return status == noErr ? unmanaged?.takeRetainedValue() as String? : nil
    }

    /// Returns the display name of the system's current default input device.
    private func systemDefaultInputName() -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let sysObj = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(sysObj, &addr, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return nil }
        return coreAudioDeviceName(for: deviceID)
    }

    // MARK: Interruption handling

    @objc private func handleConfigurationChange(_ notification: Notification) {
        // Called when audio hardware changes (e.g. mic disconnected, sample rate forced).
        // Stop cleanly; the ViewModel should surface the error and offer a restart.
        DispatchQueue.main.async { [weak self] in
            self?.stop()
            self?.captureError = .engineInterrupted
        }
    }
}
