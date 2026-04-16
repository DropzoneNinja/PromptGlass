import Foundation

/// Transforms raw script text into a flat array of `ScriptToken` values.
///
/// ## Rules
/// - Whitespace-separated words outside brackets → `SpokenToken`
/// - Text inside `[...]` → `DirectionToken` (displayed but excluded from alignment)
/// - Words whose normalized form is empty (pure punctuation) are silently
///   dropped so they don't occupy spoken-token indices.
/// - An unbalanced `[` with no matching `]` causes everything from the `[`
///   to end-of-text to be treated as a single direction token.
/// - A stray `]` without a preceding `[` is treated as punctuation within
///   the surrounding spoken text and stripped during normalization.
///
/// ## Index semantics
/// - `SpokenToken.spokenIndex` — zero-based position among spoken tokens only.
///   This is the cursor value used by `SpeechAlignmentEngine`.
/// - `SpokenToken.tokenIndex` / `DirectionToken.tokenIndex` — position in
///   the full mixed token array. Used for display layout.
enum ScriptParser {

    // MARK: - Public API

    /// Parses `rawText` and returns the ordered token array.
    static func parse(_ rawText: String) -> [ScriptToken] {
        var tokens: [ScriptToken] = []
        var tokenIndex = 0
        var spokenIndex = 0

        var searchRange = rawText.startIndex..<rawText.endIndex

        while !searchRange.isEmpty {
            if let openRange = rawText.range(of: "[", range: searchRange) {

                // --- Spoken words before the opening bracket ---
                let spokenSegment = String(rawText[searchRange.lowerBound..<openRange.lowerBound])
                appendSpokenWords(
                    from: spokenSegment,
                    into: &tokens,
                    tokenIndex: &tokenIndex,
                    spokenIndex: &spokenIndex
                )

                // --- Bracketed direction ---
                let afterOpen = openRange.upperBound..<rawText.endIndex

                if let closeRange = rawText.range(of: "]", range: afterOpen) {
                    // Balanced pair
                    let innerText = String(rawText[openRange.upperBound..<closeRange.lowerBound])
                    tokens.append(.direction(DirectionToken(
                        displayText: "[\(innerText)]",
                        innerText: innerText,
                        tokenIndex: tokenIndex
                    )))
                    tokenIndex += 1
                    searchRange = closeRange.upperBound..<rawText.endIndex

                } else {
                    // Unbalanced `[` — swallow remainder as a direction token.
                    let innerText = String(rawText[openRange.upperBound...])
                    tokens.append(.direction(DirectionToken(
                        displayText: "[\(innerText)",
                        innerText: innerText,
                        tokenIndex: tokenIndex
                    )))
                    tokenIndex += 1
                    break
                }

            } else {
                // No more brackets — everything remaining is spoken text.
                let spokenSegment = String(rawText[searchRange])
                appendSpokenWords(
                    from: spokenSegment,
                    into: &tokens,
                    tokenIndex: &tokenIndex,
                    spokenIndex: &spokenIndex
                )
                break
            }
        }

        return tokens
    }

    /// Convenience: re-parses `document.rawText` and stores the result in
    /// `document.tokens`. Returns the same document for chaining.
    @discardableResult
    static func parse(_ document: inout ScriptDocument) -> ScriptDocument {
        document.tokens = parse(document.rawText)
        return document
    }

    // MARK: - Private helpers

    /// Splits `text` on whitespace, normalizes each word, and appends
    /// `SpokenToken` values for words that survive normalization.
    private static func appendSpokenWords(
        from text: String,
        into tokens: inout [ScriptToken],
        tokenIndex: inout Int,
        spokenIndex: inout Int
    ) {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        for word in words {
            let normalized = TextNormalization.normalize(word)
            guard !normalized.isEmpty else { continue }     // drop pure-punctuation words
            tokens.append(.spoken(SpokenToken(
                displayText: word,
                normalizedText: normalized,
                spokenIndex: spokenIndex,
                tokenIndex: tokenIndex
            )))
            spokenIndex += 1
            tokenIndex += 1
        }
    }
}
