import Testing
@testable import PromptGlass

// MARK: - Helpers

/// Extracts only the SpokenTokens from a token array.
private func spoken(_ tokens: [ScriptToken]) -> [SpokenToken] {
    tokens.compactMap { if case .spoken(let t) = $0 { return t } else { return nil } }
}

/// Extracts only the DirectionTokens from a token array.
private func directions(_ tokens: [ScriptToken]) -> [DirectionToken] {
    tokens.compactMap { if case .direction(let t) = $0 { return t } else { return nil } }
}

// MARK: - Tests

struct ScriptParserTests {

    // MARK: Basic spoken text

    @Test func parsesSimpleSentence() {
        let tokens = ScriptParser.parse("Hello and welcome.")
        let words = spoken(tokens)
        #expect(words.count == 3)
        #expect(words[0].displayText == "Hello")
        #expect(words[1].displayText == "and")
        #expect(words[2].displayText == "welcome.")
    }

    @Test func spokenTokensHaveSequentialSpokenIndices() {
        let tokens = ScriptParser.parse("one two three")
        let words = spoken(tokens)
        #expect(words.map(\.spokenIndex) == [0, 1, 2])
    }

    @Test func spokenTokenIndicesMatchPositionInFullArray() {
        let tokens = ScriptParser.parse("one two three")
        let words = spoken(tokens)
        #expect(words.map(\.tokenIndex) == [0, 1, 2])
    }

    @Test func parsesEmptyString() {
        let tokens = ScriptParser.parse("")
        #expect(tokens.isEmpty)
    }

    @Test func parsesWhitespaceOnlyString() {
        let tokens = ScriptParser.parse("   \n\t  ")
        #expect(tokens.isEmpty)
    }

    // MARK: Normalization

    @Test func spokenTokenNormalizesDisplayText() {
        let tokens = ScriptParser.parse("Hello, everyone.")
        let words = spoken(tokens)
        #expect(words[0].normalizedText == "hello")
        #expect(words[1].normalizedText == "everyone")
    }

    @Test func purelyPunctuationWordsAreDropped() {
        // "..." normalizes to "" — should not appear as a spoken token
        let tokens = ScriptParser.parse("wait ... then go")
        let words = spoken(tokens)
        #expect(words.map(\.displayText) == ["wait", "then", "go"])
    }

    @Test func displayTextPreservesOriginalCase() {
        let tokens = ScriptParser.parse("Hello World")
        let words = spoken(tokens)
        #expect(words[0].displayText == "Hello")
        #expect(words[1].displayText == "World")
    }

    // MARK: Bracket parsing

    @Test func parsesStandaloneDirection() {
        let tokens = ScriptParser.parse("[pause]")
        #expect(spoken(tokens).isEmpty)
        let dirs = directions(tokens)
        #expect(dirs.count == 1)
        #expect(dirs[0].displayText == "[pause]")
        #expect(dirs[0].innerText == "pause")
    }

    @Test func parsesInlineDirection() {
        // "Hello [smile] everyone."
        let tokens = ScriptParser.parse("Hello [smile] everyone.")
        #expect(tokens.count == 3)

        if case .spoken(let t) = tokens[0] { #expect(t.displayText == "Hello") }
        else { Issue.record("Expected spoken token at index 0") }

        if case .direction(let d) = tokens[1] {
            #expect(d.displayText == "[smile]")
            #expect(d.innerText == "smile")
        } else { Issue.record("Expected direction token at index 1") }

        if case .spoken(let t) = tokens[2] { #expect(t.displayText == "everyone.") }
        else { Issue.record("Expected spoken token at index 2") }
    }

    @Test func inlineDirectionDoesNotAdvanceSpokenIndex() {
        let tokens = ScriptParser.parse("Hello [smile] everyone.")
        let words = spoken(tokens)
        // spokenIndex should be 0 and 1, skipping the direction
        #expect(words[0].spokenIndex == 0)
        #expect(words[1].spokenIndex == 1)
    }

    @Test func directionTokenIndexReflectsPositionInFullArray() {
        let tokens = ScriptParser.parse("Hello [smile] everyone.")
        let dirs = directions(tokens)
        // "Hello" is tokenIndex 0; "[smile]" is tokenIndex 1
        #expect(dirs[0].tokenIndex == 1)
    }

    @Test func parsesMultipleDirections() {
        let tokens = ScriptParser.parse("[intro] Hello [smile] world [outro]")
        #expect(directions(tokens).count == 3)
        #expect(spoken(tokens).count == 2)
    }

    @Test func parsesDirectionWithMultipleWords() {
        let tokens = ScriptParser.parse("[look to camera 2]")
        let dirs = directions(tokens)
        #expect(dirs.count == 1)
        #expect(dirs[0].innerText == "look to camera 2")
        #expect(dirs[0].displayText == "[look to camera 2]")
    }

    @Test func parsesConsecutiveDirections() {
        let tokens = ScriptParser.parse("[pause][smile]")
        let dirs = directions(tokens)
        #expect(dirs.count == 2)
        #expect(dirs[0].innerText == "pause")
        #expect(dirs[1].innerText == "smile")
    }

    // MARK: Mixed spoken and direction indices

    @Test func tokenIndicesAreContiguousAcrossMixedTokens() {
        let tokens = ScriptParser.parse("one [note] two [note2] three")
        let indices = tokens.map(\.tokenIndex)
        #expect(indices == Array(0..<tokens.count))
    }

    // MARK: Unbalanced brackets

    @Test func unclosedBracketSwallowsRemainder() {
        // "[unclosed" → one direction token with innerText = "unclosed"
        let tokens = ScriptParser.parse("[unclosed")
        let dirs = directions(tokens)
        #expect(dirs.count == 1)
        #expect(dirs[0].innerText == "unclosed")
        #expect(dirs[0].displayText == "[unclosed")
        #expect(spoken(tokens).isEmpty)
    }

    @Test func unclosedBracketMidSentenceSwallowsRestOfText() {
        let tokens = ScriptParser.parse("Hello [unclosed rest of text")
        let words = spoken(tokens)
        let dirs = directions(tokens)
        #expect(words.count == 1)
        #expect(words[0].displayText == "Hello")
        #expect(dirs.count == 1)
        #expect(dirs[0].innerText == "unclosed rest of text")
    }

    @Test func strayClosingBracketTreatedAsPunctuation() {
        // "]" is stripped during normalization — word becomes empty → dropped
        let tokens = ScriptParser.parse("hello ] world")
        let words = spoken(tokens)
        // "]" normalizes to "" and is dropped; only "hello" and "world" remain
        #expect(words.map(\.normalizedText) == ["hello", "world"])
    }

    @Test func emptyBrackets() {
        let tokens = ScriptParser.parse("hello [] world")
        let dirs = directions(tokens)
        let words = spoken(tokens)
        #expect(dirs.count == 1)
        #expect(dirs[0].innerText == "")
        #expect(dirs[0].displayText == "[]")
        #expect(words.count == 2)
    }

    // MARK: PROJECT.md scenario: inline bracket mid-sentence

    @Test func scenarioInlineDirectionMidSentence() {
        // From PROJECT.md: "This is a line [smile] that continues."
        let tokens = ScriptParser.parse("This is a line [smile] that continues.")
        let words = spoken(tokens)
        let dirs = directions(tokens)
        #expect(words.count == 6)
        #expect(dirs.count == 1)
        #expect(dirs[0].innerText == "smile")
        // "smile" should not appear in spoken tokens
        #expect(!words.map(\.normalizedText).contains("smile"))
    }

    // MARK: ScriptDocument convenience

    @Test func parsesScriptDocument() {
        var doc = ScriptDocument(name: "Test", rawText: "Hello [pause] world.")
        ScriptParser.parse(&doc)
        #expect(doc.tokens.count == 3)
        #expect(doc.spokenTokens.count == 2)
    }

    // MARK: Visual tags

    @Test func visualTagIsHidden() {
        let tokens = ScriptParser.parse("[visual: cut to B-roll]")
        let dirs = directions(tokens)
        #expect(dirs.count == 1)
        #expect(dirs[0].isHidden == true)
        #expect(dirs[0].innerText == "visual: cut to B-roll")
    }

    @Test func regularDirectionIsNotHidden() {
        let tokens = ScriptParser.parse("[pause]")
        let dirs = directions(tokens)
        #expect(dirs.count == 1)
        #expect(dirs[0].isHidden == false)
    }

    @Test func visualTagCaseInsensitive() {
        let tokens = ScriptParser.parse("[VISUAL: lower-third graphic]")
        let dirs = directions(tokens)
        #expect(dirs[0].isHidden == true)
    }

    @Test func visualTagDoesNotAffectSpokenIndices() {
        // Spoken tokens around a visual tag must retain contiguous spokenIndex values.
        let tokens = ScriptParser.parse("one [visual: b-roll] two three")
        let words = spoken(tokens)
        #expect(words.count == 3)
        #expect(words.map(\.spokenIndex) == [0, 1, 2])
    }

    @Test func visualColonRequiredToMatch() {
        // "[visualize this]" must NOT be treated as a hidden visual tag.
        let tokens = ScriptParser.parse("[visualize this]")
        let dirs = directions(tokens)
        #expect(dirs.count == 1)
        #expect(dirs[0].isHidden == false)
    }
}
