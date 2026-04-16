import Foundation
import Observation

/// Tracks the narrator's position in a parsed script by comparing live partial
/// speech-recognition results against the script's spoken tokens.
///
/// ## Algorithm
/// On each `update(partialTokens:)` call the engine takes the trailing
/// `comparisonWindow` tokens from the cumulative recognized transcript (the
/// "tail") and scores every candidate match-start position in a forward window
/// of the script. Each candidate's *end* position (matchStart + tail.count − 1)
/// is the proposed new cursor. The highest-scoring candidate above
/// `confidenceThreshold` advances the cursor — after it has appeared
/// `debounceCount` consecutive times, to suppress recognition flicker.
///
/// ## Scoring
/// Each window position is scored by `FuzzyMatch.windowScore`, then adjusted:
/// - **Stop-word penalty**: if every tail token is a common function word, the
///   score is halved (too weak to commit a positional advance).
/// - **Large-jump penalty**: smooth linear penalty for jumps exceeding
///   `largeJumpThreshold`, reaching −0.15 at the far edge of the scan window.
///
/// ## Threading
/// This class is `@MainActor`. Call `update(partialTokens:)` from the main actor:
/// ```swift
/// recognitionService.partialResultHandler = { [weak engine] tokens in
///     Task { @MainActor in engine?.update(partialTokens: tokens) }
/// }
/// ```
@MainActor
@Observable
final class SpeechAlignmentEngine {

    // MARK: - Observable state

    /// Zero-based index into the script's `spokenTokens` array representing
    /// the word the narrator is currently speaking.
    ///
    /// Drives word highlighting and scroll position in the teleprompter view.
    /// Never decreases; call `reset()` to restart from the beginning.
    private(set) var currentSpokenIndex: Int = 0

    // MARK: - Configuration

    /// Number of trailing recognized tokens used for each match attempt.
    /// Larger values improve robustness against recognition noise but react
    /// more slowly to short, fast-spoken passages. Default: 6.
    var comparisonWindow: Int = 6

    /// Maximum number of spoken-token positions scanned ahead of the cursor
    /// when looking for the best match. Default: 60.
    var scanForwardLimit: Int = 60

    /// Minimum `FuzzyMatch.windowScore` (after penalties) required to commit
    /// a cursor advance. Range: [0, 1]. Default: 0.55.
    var confidenceThreshold: Double = 0.55

    /// Number of consecutive `update` calls that must agree on the same
    /// candidate position before the cursor moves. Set to 1 to disable
    /// debouncing. Default: 2.
    var debounceCount: Int = 2

    /// Fuzzy similarity threshold forwarded to `FuzzyMatch.windowScore`.
    /// Recognized tokens closer than this to a script token count as a match.
    /// Default: 0.75.
    var fuzzyThreshold: Double = 0.75

    /// Forward jumps larger than this (in spoken-token positions) incur a
    /// linear penalty that reaches −0.15 at `scanForwardLimit`. Default: 10.
    var largeJumpThreshold: Int = 10

    // MARK: - Private state

    private var spokenTokens: [SpokenToken] = []
    /// Pre-computed from `spokenTokens` in `load()` to avoid per-update allocation.
    private var scriptNorm: [String] = []
    private var pendingCursor: Int = -1
    private var pendingCount: Int = 0

    // MARK: - Setup

    /// Load (or reload) the spoken tokens for a new script or new session.
    ///
    /// Calling this implicitly calls `reset()`.
    func load(spokenTokens: [SpokenToken]) {
        self.spokenTokens = spokenTokens
        self.scriptNorm   = spokenTokens.map(\.normalizedText)
        reset()
    }

    /// Reset the cursor and debounce state to index 0.
    ///
    /// Call when the user restarts a session without changing the script.
    func reset() {
        currentSpokenIndex = 0
        pendingCursor      = -1
        pendingCount       = 0
    }

    // MARK: - Core algorithm

    /// Process a new partial recognition result and advance the cursor if appropriate.
    ///
    /// - Parameter partialTokens: The **full** recognized transcript so far,
    ///   tokenized and normalized via `TextNormalization.tokenize`. Each call
    ///   replaces the previous; this is the accumulative result from
    ///   `SpeechRecognitionService.partialResultHandler`.
    func update(partialTokens: [String]) {
        guard !spokenTokens.isEmpty, !partialTokens.isEmpty else { return }

        // --- Build the comparison tail ---
        // The trailing `comparisonWindow` tokens represent what the narrator has
        // most recently said. The beginning of the cumulative transcript reflects
        // earlier script positions that have already been passed.
        let tail = Array(partialTokens.suffix(comparisonWindow))

        // --- Define the scan window ---
        // Start slightly *before* the cursor so the tail (which extends back in
        // time) can align correctly when the cursor has already advanced past the
        // window's starting position. Never go below 0.
        let scanStart = max(0, currentSpokenIndex - comparisonWindow + 1)
        let scanEnd   = min(currentSpokenIndex + scanForwardLimit + 1, spokenTokens.count)

        var bestScore:  Double = 0
        var bestEndPos: Int    = currentSpokenIndex

        for matchStart in scanStart..<scanEnd {
            // The proposed cursor position is the *end* of the matched tail.
            let endPos = matchStart + tail.count - 1
            guard endPos >= currentSpokenIndex,
                  endPos < spokenTokens.count else { continue }

            var score = FuzzyMatch.windowScore(
                recognized: tail,
                script:     scriptNorm,
                offset:     matchStart,
                windowSize: tail.count,
                fuzzyThreshold: fuzzyThreshold
            )

            // Stop-word penalty — a window filled entirely with common function
            // words provides weak positional evidence; halve the score so we
            // require an unusually good alignment before committing.
            if tail.allSatisfy({ Self.stopWords.contains($0) }) {
                score *= 0.5
            }

            // Large-jump penalty — smooth linear penalty for long forward jumps,
            // capped at −0.15 at the far edge of the scan window. Prevents
            // coincidental substring matches from causing jarring leaps.
            let jump = endPos - currentSpokenIndex
            if jump > largeJumpThreshold {
                let excess    = Double(jump - largeJumpThreshold)
                let maxExcess = Double(max(scanForwardLimit - largeJumpThreshold, 1))
                score = max(0, score - 0.15 * (excess / maxExcess))
            }

            if score > bestScore {
                bestScore  = score
                bestEndPos = endPos
            }
        }

        // --- Reject weak or non-advancing results ---
        guard bestEndPos > currentSpokenIndex,
              bestScore  >= confidenceThreshold else { return }

        // --- Debounce ---
        // Require the same candidate to win `debounceCount` times in a row
        // before committing, suppressing cursor jitter from noisy partials.
        if bestEndPos == pendingCursor {
            pendingCount += 1
            if pendingCount >= debounceCount {
                currentSpokenIndex = bestEndPos
                pendingCursor      = -1
                pendingCount       = 0
            }
        } else {
            pendingCursor = bestEndPos
            pendingCount  = 1
            if debounceCount <= 1 {
                currentSpokenIndex = bestEndPos
                pendingCursor      = -1
                pendingCount       = 0
            }
        }
    }

    // MARK: - Stop words

    /// Common English function words that carry little positional information.
    /// A tail consisting entirely of these words has its match score halved.
    private static let stopWords: Set<String> = [
        "a", "an", "the",
        "and", "or", "but", "nor", "so", "yet",
        "in", "on", "at", "by", "to", "of", "up", "as", "into", "from",
        "is", "are", "was", "were", "be", "been", "being",
        "i", "me", "my", "we", "our", "you", "your",
        "he", "him", "his", "she", "her", "it", "its",
        "they", "them", "their",
        "that", "this", "these", "those",
        "do", "does", "did", "have", "has", "had",
        "not", "no", "if", "then", "than",
        "with", "about", "for"
    ]
}
