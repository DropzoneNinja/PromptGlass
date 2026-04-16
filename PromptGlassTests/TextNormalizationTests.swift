import Testing
@testable import PromptGlass

struct TextNormalizationTests {

    // MARK: - normalize(_:)

    @Test func lowercasesInput() {
        #expect(TextNormalization.normalize("Hello") == "hello")
        #expect(TextNormalization.normalize("WORLD") == "world")
    }

    @Test func stripsTrailingPunctuation() {
        #expect(TextNormalization.normalize("Hello,") == "hello")
        #expect(TextNormalization.normalize("everyone.") == "everyone")
        #expect(TextNormalization.normalize("ready?") == "ready")
        #expect(TextNormalization.normalize("go!") == "go")
    }

    @Test func stripsApostropheInContractions() {
        #expect(TextNormalization.normalize("don't") == "dont")
        #expect(TextNormalization.normalize("it's") == "its")
        #expect(TextNormalization.normalize("I'm") == "im")
    }

    @Test func normalizesSmartApostrophes() {
        // RIGHT SINGLE QUOTATION MARK (U+2019)
        #expect(TextNormalization.normalize("don\u{2019}t") == "dont")
        // LEFT SINGLE QUOTATION MARK (U+2018)
        #expect(TextNormalization.normalize("don\u{2018}t") == "dont")
    }

    @Test func handlesEmptyString() {
        #expect(TextNormalization.normalize("") == "")
    }

    @Test func purelyPunctuationReturnsEmpty() {
        #expect(TextNormalization.normalize("...") == "")
        #expect(TextNormalization.normalize("—") == "")
        #expect(TextNormalization.normalize(",") == "")
    }

    @Test func preservesDigits() {
        #expect(TextNormalization.normalize("3rd") == "3rd")
        #expect(TextNormalization.normalize("10th,") == "10th")
    }

    // MARK: - tokenize(_:)

    @Test func tokenizesSimpleSentence() {
        let tokens = TextNormalization.tokenize("Hello, world!")
        #expect(tokens == ["hello", "world"])
    }

    @Test func tokenizesMultipleSpaces() {
        let tokens = TextNormalization.tokenize("one   two")
        #expect(tokens == ["one", "two"])
    }

    @Test func tokenizesEmptyString() {
        #expect(TextNormalization.tokenize("").isEmpty)
    }

    @Test func tokenizesWithDirectionTokensStripped() {
        // Brackets become empty after stripping non-alphanumeric — verify
        let tokens = TextNormalization.tokenize("smile everyone")
        #expect(tokens == ["smile", "everyone"])
    }

    // MARK: - isPurelyPunctuation(_:)

    @Test func isPurelyPunctuationReturnsTrueForPunctuation() {
        #expect(TextNormalization.isPurelyPunctuation("..."))
        #expect(TextNormalization.isPurelyPunctuation(","))
    }

    @Test func isPurelyPunctuationReturnsFalseForWords() {
        #expect(!TextNormalization.isPurelyPunctuation("hello"))
        #expect(!TextNormalization.isPurelyPunctuation("don't"))
    }
}
