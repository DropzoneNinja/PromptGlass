import CoreGraphics
import Foundation
import Observation

/// Bridges the speech alignment engine, audio meter, and scroll coordinator
/// to the teleprompter view.
///
/// ## Responsibilities
/// - Re-expose `SpeechAlignmentEngine.currentSpokenIndex` so the view can
///   highlight the current word without directly coupling to the engine.
/// - Mirror `AudioMeterProcessor.level` for the waveform visualisation.
/// - Own the `ScrollCoordinator` and forward token-index changes to it so
///   the `NSViewRepresentable` wrapper can drive animated scrolling.
/// - Hold the parsed `tokens` array for the currently active script so the
///   teleprompter text view can render them without accessing the editor VM.
///
/// ## Threading
/// `@MainActor` throughout. The underlying services (`SpeechAlignmentEngine`,
/// `AudioMeterProcessor`, `ScrollCoordinator`) are also `@MainActor`, so all
/// property reads are safe.
@MainActor
@Observable
final class TeleprompterViewModel {

    // MARK: - Observable state exposed to views

    /// Parsed tokens for the currently loaded script (spoken + direction).
    ///
    /// Set by `SessionViewModel` when a session starts. The view uses this to
    /// render the full script with per-token visual treatment.
    private(set) var tokens: [ScriptToken] = []

    /// Zero-based index into the spoken-token subset of `tokens`.
    ///
    /// Delegated through to `SpeechAlignmentEngine.currentSpokenIndex` so the
    /// Observation framework propagates changes originating in the engine to any
    /// view that reads this property.
    var currentSpokenIndex: Int { alignmentEngine.currentSpokenIndex }

    /// Smoothed linear RMS level in [0.0, 1.0]. Delegated to `AudioMeterProcessor`.
    var audioLevel: Float { audioMeter.level }

    /// Target content-offset Y for the scroll view, or `nil` if no scroll is needed.
    ///
    /// The `NSViewRepresentable` coordinator observes this and calls
    /// `scrollCoordinator.performScroll(on:animated:)` whenever it becomes non-nil.
    var scrollTarget: CGFloat? { scrollCoordinator.scrollTarget }

    // MARK: - Owned sub-services

    /// Scroll position calculator.  Exposed so the `NSViewRepresentable`
    /// coordinator can call `updateLayout`, `updateScrollOffset`, and
    /// `performScroll` directly.
    let scrollCoordinator: ScrollCoordinator

    // MARK: - Injected service references

    private let alignmentEngine: SpeechAlignmentEngine
    private let audioMeter: AudioMeterProcessor

    // MARK: - Init

    /// - Parameters:
    ///   - alignmentEngine: Shared alignment engine (also owned by `SessionViewModel`).
    ///   - audioMeter: Shared meter processor (also owned by `SessionViewModel`).
    ///   - scrollCoordinator: Injected for testability; defaults to a fresh instance.
    init(
        alignmentEngine: SpeechAlignmentEngine,
        audioMeter: AudioMeterProcessor,
        scrollCoordinator: ScrollCoordinator? = nil
    ) {
        self.alignmentEngine   = alignmentEngine
        self.audioMeter        = audioMeter
        // Default to a fresh coordinator when none is injected (common case).
        // Initialised here (inside the @MainActor init) rather than as a default
        // parameter expression so the @MainActor requirement is satisfied.
        self.scrollCoordinator = scrollCoordinator ?? ScrollCoordinator()
    }

    // MARK: - Script loading

    /// Replace the rendered token list with the tokens from a new script.
    ///
    /// Call when `SessionViewModel.start(document:)` prepares a new session so
    /// the teleprompter view always shows the most up-to-date token array.
    func loadTokens(_ newTokens: [ScriptToken]) {
        tokens = newTokens
    }

    // MARK: - Alignment-driven scroll updates

    /// Forward the latest alignment cursor to the scroll coordinator.
    ///
    /// Call this whenever `currentSpokenIndex` changes — typically from an
    /// `onChange(of: currentSpokenIndex)` modifier in the teleprompter view,
    /// or from `SessionViewModel` via an observation task.
    func tokenIndexDidChange() {
        scrollCoordinator.updateCurrentToken(currentSpokenIndex)
    }

    // MARK: - Settings

    /// Apply updated scroll settings from `SessionSettings`.
    ///
    /// Call from `SessionViewModel` when settings change.
    func applySettings(_ settings: SessionSettings) {
        scrollCoordinator.anchorFraction    = settings.scrollAnchorFraction
        scrollCoordinator.smoothingDuration = settings.scrollSmoothing
    }

    // MARK: - Reset

    /// Clear visual state at the end of a session (tokens stay for review).
    func resetScrollState() {
        scrollCoordinator.updateCurrentToken(0)
    }
}
