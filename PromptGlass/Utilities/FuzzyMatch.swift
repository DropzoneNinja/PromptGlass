import Foundation

/// Character-level fuzzy matching utilities used by `SpeechAlignmentEngine`
/// to score recognized tokens against script tokens.
///
/// All functions expect **pre-normalized** strings (lowercased, punctuation stripped).
/// Run inputs through `TextNormalization.normalize(_:)` before calling these.
enum FuzzyMatch {

    // MARK: - Edit distance

    /// Levenshtein edit distance between two strings.
    ///
    /// Returns 0 for identical strings and grows by 1 for each single-character
    /// insertion, deletion, or substitution required to transform `a` into `b`.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), aLen = a.count
        let b = Array(b), bLen = b.count

        guard aLen > 0 else { return bLen }
        guard bLen > 0 else { return aLen }

        // Use two rolling rows to keep memory O(min(m,n)).
        var prev = Array(0...bLen)
        var curr = [Int](repeating: 0, count: bLen + 1)

        for i in 1...aLen {
            curr[0] = i
            for j in 1...bLen {
                if a[i - 1] == b[j - 1] {
                    curr[j] = prev[j - 1]
                } else {
                    curr[j] = 1 + min(prev[j],       // deletion
                                      curr[j - 1],   // insertion
                                      prev[j - 1])   // substitution
                }
            }
            swap(&prev, &curr)
        }
        return prev[bLen]
    }

    // MARK: - Similarity

    /// Normalized similarity score in `[0.0, 1.0]`.
    ///
    /// `1.0` means the strings are identical; `0.0` means they share no
    /// characters (maximum possible edit distance).
    ///
    /// Formula: `1 - editDistance / max(len(a), len(b))`
    static func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1.0 }
        let maxLen = max(a.count, b.count)
        let dist = editDistance(a, b)
        return 1.0 - Double(dist) / Double(maxLen)
    }

    /// Returns `true` if the similarity between `a` and `b` meets or exceeds
    /// `threshold` (default 0.8 — allows one typo in a typical 5-letter word).
    static func isMatch(_ a: String, _ b: String, threshold: Double = 0.8) -> Bool {
        similarity(a, b) >= threshold
    }

    // MARK: - Sequence scoring

    /// Scores how well a window of recognized tokens `recognized` aligns
    /// starting at position `offset` in `script`.
    ///
    /// Returns a value in `[0.0, 1.0]` — higher is a better match.
    /// The score rewards:
    /// - exact matches (full weight)
    /// - fuzzy matches above threshold (partial weight)
    /// - consecutive match streaks (streak bonus)
    ///
    /// - Parameters:
    ///   - recognized: Normalized recognized-speech tokens (partial result).
    ///   - script: Normalized spoken script tokens.
    ///   - offset: Index into `script` where the comparison window begins.
    ///   - windowSize: Number of script tokens to compare against.
    ///   - fuzzyThreshold: Minimum similarity to count as a fuzzy match.
    static func windowScore(
        recognized: [String],
        script: [String],
        offset: Int,
        windowSize: Int = 6,
        fuzzyThreshold: Double = 0.75
    ) -> Double {
        guard !recognized.isEmpty,
              offset >= 0,
              offset < script.count else { return 0 }

        let recWindow = Array(recognized.prefix(windowSize))
        let scriptSlice = Array(script[offset..<min(offset + windowSize, script.count)])
        guard !scriptSlice.isEmpty else { return 0 }

        var totalScore = 0.0
        var streak = 0

        for (i, recToken) in recWindow.enumerated() {
            guard i < scriptSlice.count else { break }
            let scriptToken = scriptSlice[i]

            if recToken == scriptToken {
                totalScore += 1.0
                streak += 1
            } else {
                let sim = similarity(recToken, scriptToken)
                if sim >= fuzzyThreshold {
                    totalScore += sim
                    streak += 1
                } else {
                    streak = 0
                }
            }

            // Streak bonus: reward consecutive matching tokens.
            if streak > 1 {
                totalScore += Double(streak - 1) * 0.2
            }
        }

        // Normalize to [0, 1] relative to the comparison window length.
        let maxPossible = Double(min(recWindow.count, scriptSlice.count))
        return min(totalScore / maxPossible, 1.0)
    }
}
