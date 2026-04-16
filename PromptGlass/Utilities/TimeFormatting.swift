import Foundation

/// Formats `TimeInterval` values into human-readable elapsed-time strings
/// for display in the teleprompter timer view.
enum TimeFormatting {

    /// Formats an elapsed time as `MM:SS` or `H:MM:SS`.
    ///
    /// - `0...3599` seconds → `"00:00"` … `"59:59"`
    /// - `3600+` seconds    → `"1:00:00"` … `"n:MM:SS"`
    ///
    /// Fractional seconds are truncated (not rounded).
    static func format(_ interval: TimeInterval) -> String {
        let total   = Int(max(0, interval))   // clamp negatives to zero
        let hours   = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// Returns an accessible label for a time interval, e.g. `"1 hour, 2 minutes, 3 seconds"`.
    /// Intended for VoiceOver on timer controls.
    static func accessibilityLabel(_ interval: TimeInterval) -> String {
        let total   = Int(max(0, interval))
        let hours   = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        var parts: [String] = []
        if hours   > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
        if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
        parts.append("\(seconds) \(seconds == 1 ? "second" : "seconds")")

        return parts.joined(separator: ", ")
    }
}
