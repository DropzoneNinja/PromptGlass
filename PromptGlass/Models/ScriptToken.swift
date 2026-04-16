import Foundation

// MARK: - Token kinds

/// A single token in a parsed script — either a spoken word or a bracketed stage direction.
enum ScriptToken {
    case spoken(SpokenToken)
    case direction(DirectionToken)

    /// The text to display in the teleprompter view.
    var displayText: String {
        switch self {
        case .spoken(let t): return t.displayText
        case .direction(let t): return t.displayText
        }
    }

    /// Position of this token in the full (spoken + direction) token array.
    var tokenIndex: Int {
        switch self {
        case .spoken(let t): return t.tokenIndex
        case .direction(let t): return t.tokenIndex
        }
    }
}

// MARK: - Spoken token

/// A word (or contraction) that the narrator will speak.
struct SpokenToken: Equatable {
    /// Original text as written in the script (e.g. "Hello,").
    let displayText: String

    /// Lowercased, punctuation-stripped form used for alignment matching (e.g. "hello").
    let normalizedText: String

    /// Zero-based index among spoken tokens only (direction tokens excluded).
    /// Used by `SpeechAlignmentEngine` to track cursor position.
    let spokenIndex: Int

    /// Zero-based index in the full `ScriptDocument.tokens` array.
    let tokenIndex: Int
}

// MARK: - Direction token

/// A bracketed stage direction such as `[smile]` or `[look to camera 2]`.
/// Displayed visually distinct; never included in speech alignment.
struct DirectionToken: Equatable {
    /// Full bracketed text as written (e.g. "[smile]").
    let displayText: String

    /// Inner content without brackets (e.g. "smile").
    let innerText: String

    /// Zero-based index in the full `ScriptDocument.tokens` array.
    let tokenIndex: Int
}
