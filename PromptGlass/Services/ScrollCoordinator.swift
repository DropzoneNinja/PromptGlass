import AppKit
import Observation

// MARK: - Coordinator

/// Computes the scroll position that keeps the current spoken word anchored
/// near the top third of the teleprompter viewport, and drives the
/// `NSScrollView` animation when a scroll is needed.
///
/// ## Responsibilities
/// 1. Stores per-token Y-positions as reported by the `NSTextView` layout pass.
/// 2. Computes `scrollTarget` — the content-offset Y that places the current
///    word at `anchorFraction × viewportHeight` from the top of the viewport.
/// 3. Suppresses scrolls when the word is already within `toleranceFraction`
///    of the anchor to prevent jitter from small cursor advances.
/// 4. Provides `performScroll(on:animated:)` so the teleprompter's
///    `NSViewRepresentable` can drive the actual `NSScrollView`.
///
/// ## Wiring (Phase 13)
/// The `NSViewRepresentable` Coordinator should:
/// - Call `updateLayout(tokenPositions:viewportSize:contentHeight:)` after each
///   `NSTextView` layout pass and on window/font resize.
/// - Call `updateScrollOffset(_:)` from the `NSScrollViewDelegate`.
/// - Observe `scrollTarget` and call `performScroll(on:animated:)` when it
///   changes to a non-nil value.
///
/// ## Testing
/// The two static methods — `targetContentOffsetY` and `isWithinTolerance` —
/// contain all positional math and can be exercised from unit tests without an
/// AppKit display or `NSScrollView` instance.
@MainActor
@Observable
final class ScrollCoordinator {

    // MARK: - Observable output

    /// Content-offset Y the scroll view should animate to, or `nil` when the
    /// current word is already within the tolerance band.
    ///
    /// Observe this from the `NSViewRepresentable` Coordinator and call
    /// `performScroll(on:animated:)` whenever it becomes non-nil.
    private(set) var scrollTarget: CGFloat? = nil

    // MARK: - Configuration

    /// Vertical fraction of the viewport at which the current word is anchored.
    /// `0.0` = top edge, `1.0` = bottom edge. Default `0.32` ≈ lower edge of
    /// the top third, matching `SessionSettings.scrollAnchorFraction`.
    var anchorFraction: Double = 0.32

    /// Half-band size as a fraction of viewport height. Words already within
    /// `toleranceFraction × viewportHeight` of the anchor are not scrolled to,
    /// preventing jitter from small cursor advances. Default `0.06`.
    var toleranceFraction: Double = 0.06

    /// Duration forwarded to `NSAnimationContext` for animated scrolls.
    var smoothingDuration: TimeInterval = 0.25

    // MARK: - Layout state (set by NSViewRepresentable)

    /// Y-origin of each spoken token in the `NSTextView` coordinate system.
    /// Key: `SpokenToken.spokenIndex`. Populated after each layout pass.
    private(set) var tokenPositions: [Int: CGFloat] = [:]

    /// Visible area of the `NSScrollView` (its `bounds.size`).
    private(set) var viewportSize: CGSize = .zero

    /// Total height of the laid-out text content. Used to clamp the scroll target.
    private(set) var contentHeight: CGFloat = 0

    /// Current `contentView.bounds.origin.y` of the scroll view.
    private(set) var currentScrollOffsetY: CGFloat = 0

    /// Set to `true` by `updateLayout` and cleared by `updateScrollOffset`.
    ///
    /// When `true`, `updateCurrentToken` bypasses the tolerance band and always
    /// produces a non-nil `scrollTarget` so the view re-anchors the current word
    /// after a resize or font change — even when the computed target happens to
    /// equal the current scroll offset.
    private var pendingLayoutReanchor = false

    // MARK: - Layout updates (called by NSViewRepresentable)

    /// Update all layout-dependent state in one call.
    ///
    /// Call after every `NSTextView` layout pass and whenever the window
    /// is resized or font/line-spacing settings change.
    func updateLayout(
        tokenPositions: [Int: CGFloat],
        viewportSize: CGSize,
        contentHeight: CGFloat
    ) {
        self.tokenPositions   = tokenPositions
        self.viewportSize     = viewportSize
        self.contentHeight    = contentHeight
        pendingLayoutReanchor = true
    }

    /// Record the scroll view's current content offset.
    ///
    /// Call from the `NSScrollViewDelegate` `boundsDidChange` notification so
    /// the tolerance check always uses the live position.
    func updateScrollOffset(_ offsetY: CGFloat) {
        currentScrollOffsetY  = offsetY
        pendingLayoutReanchor = false   // scroll view has acknowledged its position
    }

    // MARK: - Cursor update

    /// Recompute `scrollTarget` for the newly active spoken-token index.
    ///
    /// Sets `scrollTarget` to the required content-offset Y when the word has
    /// drifted outside the tolerance band, or `nil` when no scroll is needed.
    /// After any `updateLayout` call the tolerance band is bypassed once so the
    /// view always re-anchors on resize or font changes.
    ///
    /// Call this whenever `SpeechAlignmentEngine.currentSpokenIndex` changes.
    func updateCurrentToken(_ spokenIndex: Int) {
        guard let wordY = tokenPositions[spokenIndex],
              viewportSize.height > 0 else {
            scrollTarget = nil
            return
        }

        let target = Self.targetContentOffsetY(
            wordOriginY:    wordY,
            viewportHeight: viewportSize.height,
            anchorFraction: anchorFraction,
            contentHeight:  contentHeight
        )

        // Bypass tolerance after a layout change; the flag is cleared by the
        // next updateScrollOffset call from the live scroll view delegate.
        let withinBand = pendingLayoutReanchor ? false : Self.isWithinTolerance(
            currentOffsetY:    currentScrollOffsetY,
            targetOffsetY:     target,
            viewportHeight:    viewportSize.height,
            toleranceFraction: toleranceFraction
        )

        scrollTarget = withinBand ? nil : target
    }

    // MARK: - AppKit animation

    /// Scroll `scrollView` to `scrollTarget` if it is non-nil.
    ///
    /// Uses `NSAnimationContext` for a smooth, eased animation when `animated`
    /// is `true`; jumps immediately when `false` (e.g. on session start or
    /// after a large skip).
    ///
    /// Call from the `NSViewRepresentable` Coordinator in response to
    /// `scrollTarget` becoming non-nil.
    func performScroll(on scrollView: NSScrollView, animated: Bool = true) {
        guard let target = scrollTarget else { return }
        let destination = CGPoint(x: 0, y: target)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration               = smoothingDuration
                context.timingFunction         = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                scrollView.contentView.animator().setBoundsOrigin(destination)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        } else {
            scrollView.contentView.setBoundsOrigin(destination)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    // MARK: - Pure math (static, testable without display)

    /// Computes the content-offset Y that places a word at `anchorFraction`
    /// from the top of the visible viewport.
    ///
    /// Formula: `clamp(wordOriginY − anchorFraction × viewportHeight,
    ///                 0, contentHeight − viewportHeight)`
    ///
    /// - Parameters:
    ///   - wordOriginY:    Y-origin of the word in `NSTextView` coordinates.
    ///   - viewportHeight: Height of the visible scroll area.
    ///   - anchorFraction: Target fraction from the top (`0` = top, `1` = bottom).
    ///   - contentHeight:  Total content height; used to clamp the result.
    /// - Returns: Clamped content-offset Y in `[0, max(0, contentHeight − viewportHeight)]`.
    static func targetContentOffsetY(
        wordOriginY: CGFloat,
        viewportHeight: CGFloat,
        anchorFraction: Double,
        contentHeight: CGFloat
    ) -> CGFloat {
        let desired   = wordOriginY - CGFloat(anchorFraction) * viewportHeight
        let maxOffset = max(0, contentHeight - viewportHeight)
        return min(max(0, desired), maxOffset)
    }

    /// Returns `true` when the scroll view is already close enough to
    /// `targetOffsetY` that scrolling would be imperceptible.
    ///
    /// The tolerance band is `toleranceFraction × viewportHeight` in each
    /// direction around the target, so larger viewports allow proportionally
    /// more drift before triggering a scroll.
    ///
    /// - Parameters:
    ///   - currentOffsetY:    Current `contentView.bounds.origin.y`.
    ///   - targetOffsetY:     Desired content-offset Y.
    ///   - viewportHeight:    Height of the visible scroll area.
    ///   - toleranceFraction: Half-band size as a fraction of viewport height.
    /// - Returns: `true` if `|current − target| ≤ toleranceFraction × viewportHeight`.
    static func isWithinTolerance(
        currentOffsetY: CGFloat,
        targetOffsetY: CGFloat,
        viewportHeight: CGFloat,
        toleranceFraction: Double
    ) -> Bool {
        let tolerance = CGFloat(toleranceFraction) * viewportHeight
        return abs(currentOffsetY - targetOffsetY) <= tolerance
    }
}
