import Foundation

// MARK: - Session state

/// Lifecycle state of a prompting session.
enum SessionState: Equatable {
    /// No session has been started; the app is in editing mode.
    case idle
    /// Session is actively running — speech recognition, recording, and timer are live.
    case running
    /// Session is temporarily paused; recognition and recording are suspended.
    case paused
    /// Session has ended; results are available.
    case stopped
}

// MARK: - Prompt session

/// Runtime state for a single prompting/performance session.
///
/// Created fresh each time the user starts a session and discarded on stop/reset.
/// Owned and mutated by `SessionViewModel`.
struct PromptSession {
    /// Current lifecycle state.
    var state: SessionState = .idle

    /// Index into the script's spoken-token array indicating the word currently
    /// being spoken (or the last confirmed word). Driven by `SpeechAlignmentEngine`.
    var currentSpokenTokenIndex: Int = 0

    /// Total elapsed time since the session started (pauses excluded).
    var elapsedTime: TimeInterval = 0

    /// File URL of the audio recording, set by `AudioRecordingService` once
    /// recording begins. `nil` until the first audio buffer is written.
    var recordingURL: URL?

    /// Wall-clock time the session was started (used to correlate timestamps).
    var startedAt: Date?

    // MARK: Derived

    var isActive: Bool { state == .running || state == .paused }
    var isRunning: Bool { state == .running }
}
