import SwiftUI

/// A compact horizontal bar meter showing the live microphone input level.
///
/// Renders 20 small vertical capsules whose height grows toward the right.
/// Active capsules are coloured green → yellow → red; inactive ones are dimmed.
/// Colour transitions animate at the `AudioMeterProcessor` update rate (~20 fps)
/// via `withAnimation` on `level` changes.
struct AudioMeterView: View {

    /// Smoothed linear RMS level in [0.0, 1.0] from `AudioMeterProcessor`.
    let level: Float

    // MARK: - Constants

    private static let barCount     = 20
    private static let minBarHeight: CGFloat = 4
    private static let maxBarHeight: CGFloat = 18
    private static let barWidth: CGFloat     = 3
    private static let barSpacing: CGFloat   = 2

    // MARK: - Body

    var body: some View {
        HStack(alignment: .bottom, spacing: Self.barSpacing) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(barColour(for: index))
                    .frame(width: Self.barWidth, height: barHeight(for: index))
                    .opacity(isActive(index: index) ? 1.0 : 0.18)
                    .animation(.easeOut(duration: 0.05), value: scaledLevel)
            }
        }
        .frame(height: Self.maxBarHeight)
    }

    // MARK: - Helpers

    /// Linear RMS mapped to a perceptual [0, 1] scale using a dB conversion.
    ///
    /// Raw linear RMS from the microphone is tiny (speech typically lands between
    /// -40 dB and -10 dBFS), so a direct linear comparison makes almost all bars
    /// inactive. Converting to dB and mapping [-50 dB, 0 dB] → [0, 1] spreads
    /// normal speech levels across the full bar range.
    private var scaledLevel: Float {
        guard level > 0 else { return 0 }
        let dB: Float = 20 * log10(level)   // e.g. -40 for a normal speaking voice
        let floor: Float = -50              // below -50 dBFS → no bars
        return max(0, min(1, (dB - floor) / (-floor)))
    }

    /// Returns `true` when this bar's threshold is at or below the current level.
    private func isActive(index: Int) -> Bool {
        let threshold = Float(index + 1) / Float(Self.barCount)
        return scaledLevel >= threshold
    }

    /// Bar height grows linearly from `minBarHeight` at index 0 to
    /// `maxBarHeight` at the last index, giving a staircase profile.
    private func barHeight(for index: Int) -> CGFloat {
        let fraction = CGFloat(index) / CGFloat(Self.barCount - 1)
        return Self.minBarHeight + fraction * (Self.maxBarHeight - Self.minBarHeight)
    }

    /// Colour zones: green (0–13), yellow (14–17), red (18–19).
    private func barColour(for index: Int) -> Color {
        switch index {
        case ..<14: return .green
        case ..<18: return .yellow
        default:    return .red
        }
    }
}
