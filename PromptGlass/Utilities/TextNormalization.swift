import Foundation

/// Stateless helpers for normalizing script and recognized-speech text before alignment.
///
/// Both the script parser and the alignment engine feed text through here so
/// that comparisons are always made on the same canonical form.
enum TextNormalization {

    // MARK: - Primary API

    /// Normalizes a single word for alignment matching:
    /// 1. Lowercases
    /// 2. Replaces curly/smart apostrophes with a plain apostrophe
    /// 3. Strips all remaining punctuation (including the apostrophe itself)
    ///    so "don't" → "dont", "Hello," → "hello"
    static func normalize(_ word: String) -> String {
        word
            .lowercased()
            .normalizingApostrophes()
            .strippingNonAlphanumeric()
    }

    /// Splits raw text on whitespace and returns each component normalized.
    /// Empty tokens (e.g. from multiple spaces) are discarded.
    static func tokenize(_ text: String) -> [String] {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { normalize($0) }
            .filter { !$0.isEmpty }
    }

    /// Returns `true` if the normalized form of `word` is empty — i.e. the
    /// raw word contained only punctuation or whitespace.
    static func isPurelyPunctuation(_ word: String) -> Bool {
        normalize(word).isEmpty
    }
}

// MARK: - Private String helpers

private extension String {

    /// Replaces common curly/smart-quote apostrophe variants with a plain ASCII apostrophe.
    func normalizingApostrophes() -> String {
        self
            .replacingOccurrences(of: "\u{2019}", with: "'")   // RIGHT SINGLE QUOTATION MARK  '
            .replacingOccurrences(of: "\u{2018}", with: "'")   // LEFT SINGLE QUOTATION MARK   '
            .replacingOccurrences(of: "\u{02BC}", with: "'")   // MODIFIER LETTER APOSTROPHE   ʼ
            .replacingOccurrences(of: "\u{02B9}", with: "'")   // MODIFIER LETTER PRIME         ʹ
    }

    /// Keeps only Unicode letters and decimal digits; discards everything else
    /// (punctuation, apostrophes, dashes, symbols).
    func strippingNonAlphanumeric() -> String {
        let allowed = CharacterSet.letters.union(.decimalDigits)
        return unicodeScalars
            .filter { allowed.contains($0) }
            .reduce(into: "") { $0.append(Character($1)) }
    }
}
