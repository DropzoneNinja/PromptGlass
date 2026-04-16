import SwiftUI

/// Displays a session's elapsed time in `MM:SS` or `HH:MM:SS` format.
///
/// Consumes the pre-formatted string produced by `SessionViewModel.formattedElapsedTime`
/// so the view itself does no time computation.
struct TimerView: View {

    /// Pre-formatted elapsed time string, e.g. `"00:00"`, `"01:42"`, `"01:02:15"`.
    let elapsed: String

    var body: some View {
        Text(elapsed)
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .monospacedDigit()          // keeps digits fixed-width as they change
            .foregroundStyle(.white)
    }
}

/// A pulsing red dot + "REC" label shown while a session is actively recording.
struct RecordingIndicatorView: View {

    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
                .opacity(pulsing ? 0.25 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: pulsing
                )
            Text("REC")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.red)
        }
        .onAppear { pulsing = true }
    }
}
