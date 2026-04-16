import AVFoundation

// MARK: - Errors

enum SpeechRecognitionError: LocalizedError {
    /// No speech recognizer is available for the current locale, or the
    /// recognizer reports `isAvailable == false` (e.g. network issue).
    case recognizerUnavailable
    /// An unexpected error terminated the active recognition task.
    case taskFailed(Error)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is not available right now. Check your internet connection and try again."
        case .taskFailed(let underlying):
            return "Speech recognition stopped unexpectedly: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Protocol

/// Abstracts a speech-to-text backend so the alignment engine is not coupled
/// to `SFSpeechRecognizer` and can be tested with a lightweight stub.
///
/// ## Contract
/// - `start(format:)` must be called before `append(buffer:)` will have any effect.
/// - `partialResultHandler` fires on a **background thread**; dispatch to the
///   main actor before updating `@Observable` state.
/// - Each `partialResultHandler` call replaces the previous value — the token
///   array represents the full recognized transcript so far, not a delta.
protocol SpeechRecognizing: AnyObject {

    /// Called on a **background thread** after each partial recognition update.
    ///
    /// The array contains the full recognized transcript tokenized and normalized
    /// via `TextNormalization.tokenize` — lowercase, punctuation stripped.
    var partialResultHandler: (([String]) -> Void)? { get set }

    /// Start a new recognition session.
    ///
    /// - Parameter format: The PCM format from `AudioCaptureService.tapFormat`.
    /// - Throws: `SpeechRecognitionError.recognizerUnavailable` if the recognizer
    ///   cannot be started.
    func start(format: AVAudioFormat) throws

    /// End the current recognition task.
    ///
    /// Safe to call when not running — no-ops in that case.
    func stop()

    /// Append a PCM buffer to the active recognition request.
    ///
    /// Designed to be called directly from `AudioCaptureService.bufferSink` on
    /// the audio render thread. No-ops if not running.
    func append(buffer: AVAudioPCMBuffer)
}
