import AppKit
import AVFoundation
import Foundation
import Observation

/// Coordinates the full lifecycle of a prompting session.
///
/// ## Session lifecycle
/// ```
/// idle ──start──▶ running ──pause──▶ paused ──resume──▶ running
///                    └──stop──▶ stopped ──reset──▶ idle
/// ```
///
/// ## Service ownership
/// `SessionViewModel` creates and owns all audio + recognition services.
/// It exposes `alignmentEngine` and `audioMeter` so they can be injected into
/// `TeleprompterViewModel`, keeping the two VMs decoupled while sharing a
/// single pipeline.
///
/// ## Audio pipeline wiring
/// ```
/// AudioCaptureService (single mic tap)
///   ├─▶ SpeechRecognitionService.append(buffer:)
///   │      └─▶ partialResultHandler ──▶ SpeechAlignmentEngine.update(partialTokens:)
///   ├─▶ AudioMeterProcessor.process(buffer:)
///   └─▶ AudioRecordingService.append(buffer:)
/// ```
///
/// ## Threading
/// `@MainActor` throughout. Audio callbacks arrive on the audio render thread;
/// they are dispatched back to the main actor before touching any observable state.
@MainActor
@Observable
final class SessionViewModel {

    // MARK: - Observable session state

    /// Full session lifecycle state.
    private(set) var session: PromptSession = PromptSession()

    /// Human-readable elapsed time string (e.g. `"01:42"`).
    private(set) var formattedElapsedTime: String = "00:00"

    /// Non-nil when a recoverable error has occurred (e.g. recording failure).
    /// Does not necessarily mean the session has stopped.
    private(set) var sessionError: String?

    // MARK: - Convenience derived state

    var isRunning:  Bool { session.state == .running }
    var isPaused:   Bool { session.state == .paused  }
    var isActive:   Bool { session.isActive           }
    var isIdle:     Bool { session.state == .idle     }
    var isStopped:  Bool { session.state == .stopped  }

    /// URL of the current recording; available once `start` succeeds.
    var recordingURL: URL? { session.recordingURL }

    /// Display name of the audio input device currently in use.
    /// Reflects the value set by the most recent `start()` call.
    var activeInputDeviceName: String { audioCapture.activeInputDeviceName }

    // MARK: - Owned services (shared with TeleprompterViewModel via injection)

    /// Drives the highlighted word; shared with `TeleprompterViewModel`.
    let alignmentEngine: SpeechAlignmentEngine

    /// Drives the waveform visualisation; shared with `TeleprompterViewModel`.
    let audioMeter: AudioMeterProcessor

    // MARK: - Private services

    private let audioCapture:  AudioCaptureService
    private let recognition:   SpeechRecognitionService
    private let recording:     AudioRecordingService

    // MARK: - Settings

    var settings: SessionSettings {
        didSet { applySettingsToServices() }
    }

    // MARK: - Timer

    private var timerTask: Task<Void, Never>?
    /// Wall-clock time the running period started (used to compute elapsed delta).
    private var runningStartedAt: Date?
    /// Elapsed time accumulated before the most recent pause.
    private var accumulatedTime: TimeInterval = 0

    // MARK: - Init

    init(
        audioCapture:    AudioCaptureService      = AudioCaptureService(),
        recognition:     SpeechRecognitionService  = SpeechRecognitionService(),
        recording:       AudioRecordingService     = AudioRecordingService(),
        alignmentEngine: SpeechAlignmentEngine?    = nil,   // @MainActor — can't be a default expr
        audioMeter:      AudioMeterProcessor       = AudioMeterProcessor(),
        settings:        SessionSettings           = .default
    ) {
        self.audioCapture    = audioCapture
        self.recognition     = recognition
        self.recording       = recording
        // Initialise inside the @MainActor init body so the actor requirement is met.
        self.alignmentEngine = alignmentEngine ?? SpeechAlignmentEngine()
        self.audioMeter      = audioMeter
        self.settings        = settings
    }

    // MARK: - Lifecycle: Start

    /// Begin a new session for `document`.
    ///
    /// Wires the audio pipeline, starts recognition, begins recording, loads
    /// the script into the alignment engine, and starts the elapsed timer.
    ///
    /// - Parameter document: The script to perform. Must have been parsed by
    ///   `ScriptParser` so `document.spokenTokens` is populated.
    func start(document: ScriptDocument) async {
        guard session.state == .idle || session.state == .stopped else { return }

        sessionError = nil
        session = PromptSession()   // reset to a clean slate

        // 1. Load script into alignment engine.
        alignmentEngine.load(spokenTokens: document.spokenTokens)

        // 2. Wire audio pipeline consumers.
        audioCapture.bufferSink = { [weak self] buffer, _ in
            guard let self else { return }
            self.recognition.append(buffer: buffer)
            self.audioMeter.process(buffer: buffer)
            self.recording.append(buffer: buffer)
        }

        // 3. Wire recognition → alignment engine (dispatch to main actor).
        recognition.partialResultHandler = { [weak self] tokens in
            Task { @MainActor [weak self] in
                self?.alignmentEngine.update(partialTokens: tokens)
            }
        }

        // 4. Start audio capture (using the user-selected device, or system default).
        do {
            try audioCapture.start(preferredDeviceUID: settings.selectedMicrophoneID)
        } catch {
            sessionError = error.localizedDescription
            return
        }

        guard let format = audioCapture.tapFormat else {
            sessionError = "Audio format unavailable after engine start."
            audioCapture.stop()
            return
        }

        // 5. Start speech recognition.
        do {
            try recognition.start(format: format)
        } catch {
            sessionError = error.localizedDescription
            audioCapture.stop()
            return
        }

        // 6. Start recording (non-fatal: session continues even if recording fails).
        do {
            try recording.start(
                format: format,
                scriptName: document.name,
                customDirectory: settings.audioSaveFolderURL
            )
            session.recordingURL = recording.recordingURL
        } catch {
            sessionError = "Recording could not start: \(error.localizedDescription)"
        }

        // 7. Transition to running state.
        session.state    = .running
        session.startedAt = Date()

        startTimer()

        // 8. Watch for errors that arise after a successful start.
        beginServiceErrorWatching()
    }

    // MARK: - Lifecycle: Pause

    /// Pause the session.
    ///
    /// Stops speech recognition so the alignment cursor stops advancing.
    /// The audio capture and recording pipeline remain active so there is no
    /// gap in the audio file and the meter stays live.
    func pause() {
        guard session.state == .running else { return }

        recognition.stop()
        pauseTimer()
        session.state = .paused
    }

    // MARK: - Lifecycle: Resume

    /// Resume a paused session.
    ///
    /// Restarts speech recognition with a fresh task using the existing audio
    /// tap (still running from `start`). The alignment cursor continues from
    /// where it stopped.
    func resume() {
        guard session.state == .paused else { return }
        guard let format = audioCapture.tapFormat else { return }

        do {
            try recognition.start(format: format)
        } catch {
            sessionError = error.localizedDescription
            return
        }

        session.state = .running
        resumeTimer()
    }

    // MARK: - Lifecycle: Stop

    /// End the session and finalise the recording.
    ///
    /// Stops all services. The session transitions to `.stopped`; call `reset()`
    /// to return to `.idle` for a fresh start.
    func stop() {
        guard session.isActive else { return }

        recognition.stop()
        let recordedURL = recording.stop()
        audioCapture.stop()
        audioMeter.reset()
        stopTimer()

        session.recordingURL = recordedURL ?? session.recordingURL
        session.state = .stopped
    }

    // MARK: - Lifecycle: Reset

    /// Return to `.idle` and clear all session state.
    ///
    /// Also resets the alignment engine cursor so the next session starts from
    /// the beginning of the script.
    func reset() {
        if session.isActive { stop() }

        alignmentEngine.reset()
        audioMeter.reset()

        accumulatedTime  = 0
        runningStartedAt = nil
        formattedElapsedTime = "00:00"
        session          = PromptSession()
        sessionError     = nil
    }

    // MARK: - Reveal recording

    /// Open the recordings folder in Finder, selecting the current file.
    func revealRecordingInFinder() {
        recording.revealInFinder()
    }

    // MARK: - Clap marker

    /// Injects a clapperboard sync transient into the audio recording.
    /// No-ops if the session is not active or recording did not start.
    func insertClapMarker() {
        guard session.isActive else { return }
        recording.insertClapMarker()
    }

    // MARK: - Folder selection

    /// Presents an `NSOpenPanel` for folder selection and stores a security-scoped
    /// bookmark in `settings.audioSaveFolderBookmark`.
    func selectAudioSaveFolder() {
        let panel = NSOpenPanel()
        panel.title                   = "Choose Recordings Folder"
        panel.message                 = "Select where PromptGlass should save audio recordings."
        panel.prompt                  = "Select Folder"
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.canCreateDirectories    = true
        panel.allowsMultipleSelection = false

        // Pre-navigate to the existing custom folder if one is set.
        if let existingURL = settings.audioSaveFolderURL {
            _ = existingURL.startAccessingSecurityScopedResource()
            panel.directoryURL = existingURL
            existingURL.stopAccessingSecurityScopedResource()
        }

        guard panel.runModal() == .OK, let chosenURL = panel.url else { return }

        do {
            let bookmark = try chosenURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            settings.audioSaveFolderBookmark = bookmark
            // settings didSet → applySettingsToServices() → PersistenceService.saveSettings(settings)
        } catch {
            sessionError = "Could not save folder permission: \(error.localizedDescription)"
        }
    }

    /// Clears the custom recordings folder, reverting to the default app-support path.
    func clearAudioSaveFolder() {
        settings.audioSaveFolderBookmark = nil
    }

    // MARK: - Mid-session service error monitoring

    /// Begins observing service error properties so that failures occurring
    /// *after* a successful start are surfaced to the user.
    ///
    /// Uses the Observation framework's `withObservationTracking` in a recursive
    /// pattern: each call registers a one-shot change callback that, once fired,
    /// re-registers itself (when the session is still active) so the next change
    /// is also caught.
    private func beginServiceErrorWatching() {
        watchAudioCaptureError()
        watchRecordingWriteError()
        watchRecognitionTaskError()
    }

    /// Stops the session and surfaces a message when the audio engine is
    /// interrupted (e.g. the microphone is unplugged mid-session).
    private func watchAudioCaptureError() {
        withObservationTracking {
            _ = audioCapture.captureError
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error = self.audioCapture.captureError, self.session.isActive {
                    self.sessionError = error.localizedDescription
                    self.stop()
                }
                // Continue watching while the session is alive or idle (so a
                // fresh start will also be covered).
                if self.session.isActive || self.session.state == .idle {
                    self.watchAudioCaptureError()
                }
            }
        }
    }

    /// Sets a non-fatal session error when an audio-write fails mid-session.
    /// The session continues; the user is notified the recording may be incomplete.
    private func watchRecordingWriteError() {
        withObservationTracking {
            _ = recording.recordingError
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error = self.recording.recordingError, self.session.isActive {
                    // Non-fatal: flag the problem but let recording and alignment continue.
                    self.sessionError = "Recording interrupted: \(error.localizedDescription)"
                }
                if self.session.isActive || self.session.state == .idle {
                    self.watchRecordingWriteError()
                }
            }
        }
    }

    /// Attempts to restart recognition when a task error occurs mid-session.
    /// Recognition failure is non-fatal: audio recording and the timer continue.
    private func watchRecognitionTaskError() {
        withObservationTracking {
            _ = recognition.recognitionError
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.session.state == .running,
                      self.recognition.recognitionError != nil else {
                    if self.session.isActive || self.session.state == .idle {
                        self.watchRecognitionTaskError()
                    }
                    return
                }
                // Attempt an automatic restart — task errors are often transient
                // (e.g. a momentary network hiccup for server-side models).
                if let format = self.audioCapture.tapFormat {
                    do {
                        try self.recognition.start(format: format)
                    } catch {
                        // Restart failed; surface the error but keep the session
                        // alive so audio recording and the elapsed timer continue.
                        self.sessionError =
                            "Speech recognition unavailable: \(error.localizedDescription)"
                    }
                } else {
                    self.sessionError =
                        self.recognition.recognitionError?.localizedDescription
                }
                if self.session.isActive || self.session.state == .idle {
                    self.watchRecognitionTaskError()
                }
            }
        }
    }

    // MARK: - Private: Timer management

    private func startTimer() {
        accumulatedTime  = 0
        runningStartedAt = Date()
        launchTimerTask()
    }

    private func pauseTimer() {
        if let start = runningStartedAt {
            accumulatedTime += Date().timeIntervalSince(start)
        }
        runningStartedAt = nil
        timerTask?.cancel()
        timerTask = nil
        // Snapshot the paused elapsed time.
        session.elapsedTime  = accumulatedTime
        formattedElapsedTime = TimeFormatting.format(accumulatedTime)
    }

    private func resumeTimer() {
        runningStartedAt = Date()
        launchTimerTask()
    }

    private func stopTimer() {
        if let start = runningStartedAt {
            accumulatedTime += Date().timeIntervalSince(start)
        }
        runningStartedAt = nil
        timerTask?.cancel()
        timerTask = nil
        session.elapsedTime  = accumulatedTime
        formattedElapsedTime = TimeFormatting.format(accumulatedTime)
    }

    /// Launches a background `Task` that ticks every 0.5 s and updates the
    /// elapsed time display. Using 0.5 s (rather than 1 s) keeps the display
    /// from lagging visibly behind wall-clock time.
    private func launchTimerTask() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 s
                guard let self, !Task.isCancelled else { break }
                guard self.session.state == .running else { break }
                guard let start = self.runningStartedAt else { break }

                let elapsed = self.accumulatedTime + Date().timeIntervalSince(start)
                self.session.elapsedTime  = elapsed
                self.formattedElapsedTime = TimeFormatting.format(elapsed)
            }
        }
    }

    // MARK: - Private: Settings propagation

    private func applySettingsToServices() {
        // Display-only settings (font size, line spacing, mirror mode) are consumed
        // directly by TeleprompterViewModel.applySettings(_:) at the call site.
        // Persist any change so the next launch restores the user's preferences.
        try? PersistenceService.shared.saveSettings(settings)
    }
}
