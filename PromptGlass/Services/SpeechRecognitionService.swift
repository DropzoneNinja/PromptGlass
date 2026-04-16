import AVFoundation
import Observation
import Speech

// MARK: - Service

/// Wraps `SFSpeechRecognizer` to deliver live, incremental speech-to-text
/// tokens for the `SpeechAlignmentEngine`.
///
/// ## Threading
/// - Call `start()` and `stop()` from the main thread.
/// - `append(buffer:)` is safe to call from the audio render thread.
/// - `partialResultHandler` fires on the Speech framework's internal thread.
///   Consumers must dispatch to the main actor before updating UI or
///   `@Observable` state.
///
/// ## Wiring example
/// ```swift
/// recognitionService.partialResultHandler = { [weak engine] tokens in
///     DispatchQueue.main.async { engine?.update(partialTokens: tokens) }
/// }
/// audioCapture.bufferSink = { [weak recognitionService] buf, _ in
///     recognitionService?.append(buffer: buf)
/// }
/// try recognitionService.start(format: audioCapture.tapFormat!)
/// ```
@Observable
final class SpeechRecognitionService: SpeechRecognizing {

    // MARK: - Observable state

    /// `true` while a recognition task is in progress.
    private(set) var isRunning = false

    /// Set when recognition fails unexpectedly; `nil` while healthy.
    private(set) var recognitionError: SpeechRecognitionError?

    // MARK: - SpeechRecognizing

    var partialResultHandler: (([String]) -> Void)?

    // MARK: - Private

    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    // MARK: - Init

    /// - Parameter locale: Selects the language model. Defaults to `Locale.current`.
    ///   Pass `Locale(identifier: "en-US")` to pin a specific language.
    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - SpeechRecognizing

    func start(format: AVAudioFormat) throws {
        guard !isRunning else { return }
        recognitionError = nil

        guard let recognizer, recognizer.isAvailable else {
            let err = SpeechRecognitionError.recognizerUnavailable
            recognitionError = err
            throw err
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation   // optimised for continuous, free-form speech
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            self?.handleResult(result, error: error)
        }

        isRunning = true
    }

    /// Signals end of audio input and cancels the recognition task.
    ///
    /// Sets `isRunning = false` synchronously so that the `append(buffer:)` guard
    /// and the task-completion handler both see the stopped state immediately.
    func stop() {
        guard isRunning else { return }
        // Set false *before* endAudio/finish so the task-completion handler's
        // guard skips any spurious error assignment from the framework callback.
        isRunning = false

        request?.endAudio()     // signals no more audio to the recognizer
        task?.finish()          // asks for a final result then tears down the task

        request = nil
        task = nil
    }

    /// Thread-safe buffer ingestion — forwards directly to the recognition request.
    ///
    /// `isRunning` is read without explicit synchronisation; the worst case is
    /// delivering one extra buffer after `stop()` is called, which the
    /// already-ended request silently discards.
    func append(buffer: AVAudioPCMBuffer) {
        guard isRunning else { return }
        request?.append(buffer)
    }

    // MARK: - Private: result handling

    private func handleResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        // Deliver normalized tokens on every partial update.
        if let result {
            let tokens = TextNormalization.tokenize(result.bestTranscription.formattedString)
            partialResultHandler?(tokens)
        }

        // Task is done when we receive a final result or an error.
        guard result?.isFinal == true || error != nil else { return }

        // Dispatch state cleanup to the main thread.
        // The guard on isRunning prevents a stop()-initiated cleanup from being
        // misidentified as an unexpected failure: stop() sets isRunning = false
        // before calling finish(), so by the time this dispatch runs, the guard
        // returns early and the error assignment below is skipped.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.isRunning = false
            self.request = nil
            self.task = nil
            if let error {
                self.recognitionError = .taskFailed(error)
            }
        }
    }
}
