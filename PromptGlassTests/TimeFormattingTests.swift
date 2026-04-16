import Testing
@testable import PromptGlass

struct TimeFormattingTests {

    // MARK: - format(_:)

    @Test func formatsZero() {
        #expect(TimeFormatting.format(0) == "00:00")
    }

    @Test func formatsSeconds() {
        #expect(TimeFormatting.format(5)  == "00:05")
        #expect(TimeFormatting.format(59) == "00:59")
    }

    @Test func formatsMinutesAndSeconds() {
        #expect(TimeFormatting.format(60)   == "01:00")
        #expect(TimeFormatting.format(90)   == "01:30")
        #expect(TimeFormatting.format(3599) == "59:59")
    }

    @Test func formatsHoursMinutesAndSeconds() {
        #expect(TimeFormatting.format(3600)  == "1:00:00")
        #expect(TimeFormatting.format(3661)  == "1:01:01")
        #expect(TimeFormatting.format(7322)  == "2:02:02")
    }

    @Test func truncatesFractionalSeconds() {
        #expect(TimeFormatting.format(1.9)  == "00:01")
        #expect(TimeFormatting.format(59.9) == "00:59")
    }

    @Test func clampNegativeToZero() {
        #expect(TimeFormatting.format(-10) == "00:00")
    }

    // MARK: - accessibilityLabel(_:)

    @Test func accessibilityLabelSeconds() {
        #expect(TimeFormatting.accessibilityLabel(1)  == "1 second")
        #expect(TimeFormatting.accessibilityLabel(45) == "45 seconds")
    }

    @Test func accessibilityLabelMinutesAndSeconds() {
        let label = TimeFormatting.accessibilityLabel(90)
        #expect(label == "1 minute, 30 seconds")
    }

    @Test func accessibilityLabelHoursMinutesSeconds() {
        let label = TimeFormatting.accessibilityLabel(3661)
        #expect(label == "1 hour, 1 minute, 1 second")
    }

    @Test func accessibilityLabelZero() {
        #expect(TimeFormatting.accessibilityLabel(0) == "0 seconds")
    }
}
