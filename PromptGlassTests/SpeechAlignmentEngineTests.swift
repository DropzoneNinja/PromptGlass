import Testing
@testable import PromptGlass

// MARK: - Test suite

/// Tests for `SpeechAlignmentEngine`.
///
/// Each test uses `debounceCount = 1` unless the test is specifically about
/// debounce behaviour, so a single `update()` call commits immediately and
/// we can assert the cursor position without repeating calls.
///
/// The `makeEngine(script:debounce:)` helper parses raw text via `ScriptParser`
/// and loads the resulting spoken tokens into a fresh engine.
@MainActor
@Suite("SpeechAlignmentEngine")
struct SpeechAlignmentEngineTests {

    // MARK: - Helper

    private func makeEngine(script: String, debounce: Int = 1) -> SpeechAlignmentEngine {
        var doc = ScriptDocument(rawText: script)
        ScriptParser.parse(&doc)
        let engine = SpeechAlignmentEngine()
        engine.debounceCount = debounce
        engine.load(spokenTokens: doc.spokenTokens)
        return engine
    }

    // MARK: - Exact word-by-word progression

    /// As the cumulative transcript grows word by word, the cursor advances
    /// exactly one position per new word.
    @Test func testExactProgression() {
        let engine = makeEngine(script: "one two three four five")

        // After "one" the cursor is at 0 (pointing to the word being spoken).
        engine.update(partialTokens: ["one"])
        #expect(engine.currentSpokenIndex == 0)

        engine.update(partialTokens: ["one", "two"])
        #expect(engine.currentSpokenIndex == 1)

        engine.update(partialTokens: ["one", "two", "three"])
        #expect(engine.currentSpokenIndex == 2)

        engine.update(partialTokens: ["one", "two", "three", "four"])
        #expect(engine.currentSpokenIndex == 3)

        engine.update(partialTokens: ["one", "two", "three", "four", "five"])
        #expect(engine.currentSpokenIndex == 4)
    }

    /// Cursor stays at 0 when only the first word is recognized (it equals the
    /// current cursor; nothing to advance to).
    @Test func testFirstWordRecognizedDoesNotAdvance() {
        let engine = makeEngine(script: "alpha beta gamma")
        engine.update(partialTokens: ["alpha"])
        #expect(engine.currentSpokenIndex == 0)
    }

    // MARK: - Missed-word recovery (scan forward)

    /// When the narrator skips a word the engine scans ahead and locks onto the
    /// correct position based on the words that *were* recognized.
    @Test func testMissedWordRecovery() {
        // Script:   the quick brown fox jumps over the lazy dog
        // Indices:   0   1     2     3   4     5    6   7    8
        let engine = makeEngine(script: "the quick brown fox jumps over the lazy dog")

        // Narrator says "the jumps over" — skipped "quick brown fox"
        engine.update(partialTokens: ["the", "jumps", "over"])
        // tail ["the","jumps","over"] matches best at matchStart=3 (["fox","jumps","over"]),
        // giving endPos=5 ("over").
        #expect(engine.currentSpokenIndex >= 4)   // reached at least "jumps"
        #expect(engine.currentSpokenIndex <= 5)   // did not overshoot past "over"
    }

    /// Normal single-word-skip recovery: narrator misses one word, then
    /// recognition catches up on the next two words.
    @Test func testSingleWordSkipRecovery() {
        let engine = makeEngine(script: "start alpha beta gamma end")
        //                               0      1     2    3     4

        // "start" spoken, then narrator skips "alpha" and says "beta gamma"
        engine.update(partialTokens: ["start"])
        #expect(engine.currentSpokenIndex == 0)

        engine.update(partialTokens: ["start", "beta", "gamma"])
        // tail ["start","beta","gamma"]: "beta"+"gamma" match at positions 2+3 (score > "start" alone),
        // so the engine locks onto matchStart=1 giving endPos=3 ("gamma").
        #expect(engine.currentSpokenIndex == 3)
    }

    // MARK: - Skipped-sentence recovery

    /// When the narrator jumps far ahead (e.g. skips a whole paragraph) the
    /// engine recovers and lands near the new location.
    @Test func testSkippedSentenceRecovery() {
        let engine = makeEngine(script:
            "first second third fourth fifth sixth seventh eighth ninth tenth")
        //   0      1      2      3      4      5      6       7       8      9

        // Narrator jumps straight to the end
        engine.update(partialTokens: ["ninth", "tenth"])
        #expect(engine.currentSpokenIndex >= 8)
    }

    /// Larger paragraph-scale jump, verifying the large-jump penalty does not
    /// prevent legitimate recovery.
    ///
    /// Uses NATO phonetic alphabet words — all phonetically distinct — so fuzzy
    /// matching cannot produce false positives (unlike contrived "word1"/"word28"
    /// tokens, which happen to have edit distance 1 and mislead the scorer).
    @Test func testLargeJumpRecovery() {
        let engine = makeEngine(script:
            "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar")
        //   0      1      2       3     4    5       6    7      8     9       10   11   12   13       14

        // Narrator jumps straight to the last three words
        engine.update(partialTokens: ["kilo", "lima", "mike", "november", "oscar"])
        #expect(engine.currentSpokenIndex == 14)
    }

    // MARK: - Repeated-word scenarios

    /// With a script containing many repeated words the cursor advances to the
    /// correct later occurrence, not an early one, as the transcript grows.
    @Test func testRepeatedWordAdvances() {
        let engine = makeEngine(script: "again and again and again and stop")
        //                               0      1   2      3   4      5   6

        // Narrator reads first half: "again and again"
        engine.update(partialTokens: ["again", "and", "again"])
        #expect(engine.currentSpokenIndex == 2)   // cursor at second "again"

        // Narrator continues: "again and again and again"
        engine.update(partialTokens: ["again", "and", "again", "and", "again"])
        #expect(engine.currentSpokenIndex == 4)   // cursor advanced to third "again"

        // Narrator finishes: full transcript
        engine.update(partialTokens: ["again", "and", "again", "and", "again", "and", "stop"])
        #expect(engine.currentSpokenIndex == 6)   // cursor at "stop"
    }

    /// The cursor must never decrease, even when the recognized transcript
    /// happens to match an earlier script position better.
    @Test func testNeverJumpsBackward() {
        let engine = makeEngine(script: "alpha beta gamma delta epsilon")
        //                               0      1    2      3     4

        // Advance to the end
        engine.update(partialTokens: ["alpha", "beta", "gamma", "delta", "epsilon"])
        let highMark = engine.currentSpokenIndex
        #expect(highMark == 4)

        // Feed a transcript that only matches the beginning of the script
        engine.update(partialTokens: ["alpha"])
        #expect(engine.currentSpokenIndex >= highMark)

        engine.update(partialTokens: ["alpha", "beta"])
        #expect(engine.currentSpokenIndex >= highMark)
    }

    // MARK: - Punctuation and case insensitivity

    /// Script words with punctuation and mixed case align correctly with the
    /// plain-lowercase tokens produced by `SpeechRecognitionService`.
    @Test func testPunctuationAndCaseInsensitivity() {
        // Script has commas, exclamation marks, and mixed case
        let engine = makeEngine(script: "Hello, World! How are you?")
        //  normalised spoken tokens:    hello  world  how  are  you
        //  indices:                      0      1      2    3    4

        // Recognition produces plain lowercase, punctuation already stripped
        engine.update(partialTokens: ["hello", "world", "how"])
        #expect(engine.currentSpokenIndex == 2)
    }

    @Test func testContractionsNormalize() {
        let engine = makeEngine(script: "I don't know what you're saying")
        //  normalised:                   i  dont  know  what  youre  saying
        //  indices:                      0  1      2     3     4      5

        engine.update(partialTokens: ["i", "dont", "know", "what", "youre"])
        #expect(engine.currentSpokenIndex == 4)
    }

    // MARK: - Direction tokens excluded from matching

    /// Bracketed stage directions are parsed out of the spoken-token list
    /// and must not occupy a spoken index or interfere with alignment.
    @Test func testDirectionTokensExcluded() {
        // Spoken indices:  hello(0)   world(1) how(2)  are(3) you(4)
        // Direction tokens [smile] and [pause] are invisible to the engine.
        let engine = makeEngine(script: "hello [smile] world how [pause] are you")

        engine.update(partialTokens: ["hello", "world"])
        #expect(engine.currentSpokenIndex == 1)   // "world" is spoken index 1

        engine.update(partialTokens: ["hello", "world", "how", "are", "you"])
        #expect(engine.currentSpokenIndex == 4)   // "you" is spoken index 4
    }

    @Test func testDirectionOnlyScriptHasNoSpokenTokens() {
        // A script with only directions produces an empty spoken-token list;
        // update() must be a safe no-op.
        let engine = makeEngine(script: "[intro] [main] [outro]")
        engine.update(partialTokens: ["intro", "main"])
        #expect(engine.currentSpokenIndex == 0)   // no spoken tokens; cursor stays at 0
    }

    // MARK: - Debounce behaviour

    /// With debounceCount = 3 the cursor only advances after the same candidate
    /// position wins three consecutive update calls.
    @Test func testDebouncePreventsEarlyAdvance() {
        let engine = makeEngine(script: "one two three four five", debounce: 3)

        // Feed the same two-word transcript three times
        engine.update(partialTokens: ["one", "two"])
        #expect(engine.currentSpokenIndex == 0)   // pending (count = 1)

        engine.update(partialTokens: ["one", "two"])
        #expect(engine.currentSpokenIndex == 0)   // pending (count = 2)

        engine.update(partialTokens: ["one", "two"])
        #expect(engine.currentSpokenIndex == 1)   // committed (count = 3)
    }

    /// When the candidate changes between calls the debounce counter resets,
    /// so the cursor only advances once a stable candidate appears.
    @Test func testDebounceResetsOnCandidateChange() {
        let engine = makeEngine(script: "one two three four five", debounce: 2)

        engine.update(partialTokens: ["one", "two"])   // candidate = 1, count = 1
        engine.update(partialTokens: ["one", "two", "three"])  // candidate = 2, count reset to 1
        #expect(engine.currentSpokenIndex == 0)

        engine.update(partialTokens: ["one", "two", "three"])  // candidate = 2 again, count = 2 → commit
        #expect(engine.currentSpokenIndex == 2)
    }

    // MARK: - Confidence threshold

    /// Low-confidence matches (e.g. a single poorly matching token) must not
    /// move the cursor.
    @Test func testLowConfidenceMatchIgnored() {
        let engine = makeEngine(script: "the big red balloon floats in the sky")
        engine.confidenceThreshold = 0.9   // very strict

        // "the blue" — "blue" vs "big" has low similarity; total score < 0.9
        engine.update(partialTokens: ["the", "blue"])
        #expect(engine.currentSpokenIndex == 0)
    }

    // MARK: - Reset and load

    @Test func testResetReturnsCursorToZero() {
        let engine = makeEngine(script: "one two three four five")

        engine.update(partialTokens: ["one", "two", "three", "four", "five"])
        #expect(engine.currentSpokenIndex == 4)

        engine.reset()
        #expect(engine.currentSpokenIndex == 0)
    }

    @Test func testLoadNewScriptResetsCursor() {
        let engine = makeEngine(script: "alpha beta gamma")
        engine.update(partialTokens: ["alpha", "beta", "gamma"])
        #expect(engine.currentSpokenIndex == 2)

        // Load a completely different script
        var doc2 = ScriptDocument(rawText: "one two three four")
        ScriptParser.parse(&doc2)
        engine.load(spokenTokens: doc2.spokenTokens)
        #expect(engine.currentSpokenIndex == 0)
    }

    // MARK: - Edge cases

    @Test func testEmptyPartialTokensIsNoOp() {
        let engine = makeEngine(script: "one two three")
        engine.update(partialTokens: [])
        #expect(engine.currentSpokenIndex == 0)
    }

    @Test func testEmptyScriptIsNoOp() {
        let engine = SpeechAlignmentEngine()
        engine.load(spokenTokens: [])
        engine.update(partialTokens: ["hello", "world"])
        #expect(engine.currentSpokenIndex == 0)
    }

    @Test func testCursorStaysAtLastTokenWhenScriptExhausted() {
        let engine = makeEngine(script: "one two three")
        engine.update(partialTokens: ["one", "two", "three"])
        let last = engine.currentSpokenIndex   // 2
        // More tokens arrive (narrator finished but recognition keeps firing)
        engine.update(partialTokens: ["one", "two", "three", "extra", "words"])
        #expect(engine.currentSpokenIndex == last)
    }
}
