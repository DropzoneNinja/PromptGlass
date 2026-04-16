import Testing
@testable import PromptGlass

struct FuzzyMatchTests {

    // MARK: - editDistance(_:_:)

    @Test func identicalStringsHaveZeroDistance() {
        #expect(FuzzyMatch.editDistance("hello", "hello") == 0)
    }

    @Test func emptyStrings() {
        #expect(FuzzyMatch.editDistance("", "") == 0)
        #expect(FuzzyMatch.editDistance("hello", "") == 5)
        #expect(FuzzyMatch.editDistance("", "hello") == 5)
    }

    @Test func singleSubstitution() {
        #expect(FuzzyMatch.editDistance("cat", "bat") == 1)
        #expect(FuzzyMatch.editDistance("hello", "helo") == 1)
    }

    @Test func singleInsertion() {
        #expect(FuzzyMatch.editDistance("hell", "hello") == 1)
    }

    @Test func singleDeletion() {
        #expect(FuzzyMatch.editDistance("hello", "hell") == 1)
    }

    @Test func completelyDifferent() {
        #expect(FuzzyMatch.editDistance("abc", "xyz") == 3)
    }

    // MARK: - similarity(_:_:)

    @Test func identicalStringsHaveMaxSimilarity() {
        #expect(FuzzyMatch.similarity("hello", "hello") == 1.0)
    }

    @Test func emptyStringsHaveMaxSimilarity() {
        #expect(FuzzyMatch.similarity("", "") == 1.0)
    }

    @Test func oneTypoHasHighSimilarity() {
        // "helo" vs "hello" — distance 1, max length 5 → similarity 0.8
        let score = FuzzyMatch.similarity("helo", "hello")
        #expect(score == 0.8)
    }

    @Test func completelyDifferentWordsHaveZeroSimilarity() {
        // "abc" vs "xyz" — distance 3, max length 3 → similarity 0.0
        #expect(FuzzyMatch.similarity("abc", "xyz") == 0.0)
    }

    // MARK: - isMatch(_:_:threshold:)

    @Test func exactMatchPassesDefaultThreshold() {
        #expect(FuzzyMatch.isMatch("energy", "energy"))
    }

    @Test func oneTypoPassesDefaultThreshold() {
        // "enrgy" vs "energy" — distance 1 / length 6 ≈ 0.833 > 0.8
        #expect(FuzzyMatch.isMatch("enrgy", "energy"))
    }

    @Test func veryDifferentWordFailsDefaultThreshold() {
        #expect(!FuzzyMatch.isMatch("cat", "elephant"))
    }

    @Test func customThreshold() {
        // similarity("helo","hello") == 0.8 — fails at threshold 0.9
        #expect(!FuzzyMatch.isMatch("helo", "hello", threshold: 0.9))
        // …but passes at threshold 0.7
        #expect(FuzzyMatch.isMatch("helo", "hello", threshold: 0.7))
    }

    // MARK: - windowScore(recognized:script:offset:)

    @Test func perfectWindowScoreIsOne() {
        let script     = ["hello", "and", "welcome", "to", "the", "show"]
        let recognized = ["hello", "and", "welcome"]
        let score = FuzzyMatch.windowScore(recognized: recognized, script: script, offset: 0)
        #expect(score == 1.0)
    }

    @Test func noMatchGivesLowScore() {
        let script     = ["hello", "and", "welcome"]
        let recognized = ["xyz", "abc", "qrs"]
        let score = FuzzyMatch.windowScore(recognized: recognized, script: script, offset: 0)
        #expect(score < 0.3)
    }

    @Test func offsetWindowMatchesCorrectly() {
        let script     = ["the", "quick", "brown", "fox", "jumps"]
        let recognized = ["brown", "fox"]
        // Should score high at offset 2, low at offset 0
        let scoreAtMatch    = FuzzyMatch.windowScore(recognized: recognized, script: script, offset: 2)
        let scoreAtMismatch = FuzzyMatch.windowScore(recognized: recognized, script: script, offset: 0)
        #expect(scoreAtMatch > scoreAtMismatch)
    }

    @Test func outOfBoundsOffsetReturnsZero() {
        let script     = ["hello"]
        let recognized = ["hello"]
        #expect(FuzzyMatch.windowScore(recognized: recognized, script: script, offset: 99) == 0)
    }

    @Test func emptyRecognizedReturnsZero() {
        let script = ["hello", "world"]
        #expect(FuzzyMatch.windowScore(recognized: [], script: script, offset: 0) == 0)
    }
}
