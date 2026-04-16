import CoreGraphics
import Testing
@testable import PromptGlass

// MARK: - Test suite

/// Tests for `ScrollCoordinator`.
///
/// Exercises two categories:
/// - **Static math** (`targetContentOffsetY`, `isWithinTolerance`): pure functions,
///   no AppKit display required.
/// - **Coordination flow** (`updateCurrentToken`, `scrollTarget`): verifies that
///   `updateLayout` + `updateScrollOffset` + `updateCurrentToken` produce the
///   expected `scrollTarget` state, including resize recalculation.
///
/// `anchorFraction = 0.5` is used where exact integer results are needed,
/// since 0.5 is exactly representable in IEEE 754 and avoids floating-point
/// rounding surprises. Tests that specifically exercise the default anchor
/// fraction use approximate comparison.
@MainActor
@Suite("ScrollCoordinator")
struct ScrollCoordinatorTests {

    // MARK: - targetContentOffsetY — anchor placement

    /// The formula `wordOriginY − anchorFraction × viewportHeight` positions
    /// the word at the correct viewport fraction.
    @Test func testAnchorAtZeroFractionEqualsWordY() {
        // anchorFraction = 0.0 → target = wordY − 0 = wordY (no shift)
        let result = ScrollCoordinator.targetContentOffsetY(
            wordOriginY:    300,
            viewportHeight: 600,
            anchorFraction: 0.0,
            contentHeight:  2000
        )
        #expect(result == 300)
    }

    @Test func testAnchorAtHalfViewportHeight() {
        // anchorFraction = 0.5 → target = 700 − 0.5×600 = 700 − 300 = 400
        let result = ScrollCoordinator.targetContentOffsetY(
            wordOriginY:    700,
            viewportHeight: 600,
            anchorFraction: 0.5,
            contentHeight:  2000
        )
        #expect(result == 400)
    }

    @Test func testAnchorAtFullViewportHeight() {
        // anchorFraction = 1.0 → target = 800 − 1.0×600 = 200
        let result = ScrollCoordinator.targetContentOffsetY(
            wordOriginY:    800,
            viewportHeight: 600,
            anchorFraction: 1.0,
            contentHeight:  2000
        )
        #expect(result == 200)
    }

    /// Default anchor fraction (≈ 0.32) places the word in the top third.
    @Test func testDefaultAnchorFractionApproximation() {
        // target ≈ 500 − 0.32×600 = 500 − 192 = 308
        let result = ScrollCoordinator.targetContentOffsetY(
            wordOriginY:    500,
            viewportHeight: 600,
            anchorFraction: 0.32,
            contentHeight:  2000
        )
        #expect(abs(result - 308) < 0.01)
    }

    // MARK: - targetContentOffsetY — clamping

    /// A word near the top produces a negative desired offset; the result
    /// is clamped to 0 (can't scroll above content origin).
    @Test func testClampsToZeroWhenWordNearTop() {
        // desired = 20 − 0.5×600 = 20 − 300 = −280 → clamp to 0
        let result = ScrollCoordinator.targetContentOffsetY(
            wordOriginY:    20,
            viewportHeight: 600,
            anchorFraction: 0.5,
            contentHeight:  2000
        )
        #expect(result == 0)
    }

    /// A word near the bottom produces a desired offset beyond the end of
    /// content; the result is clamped to `contentHeight − viewportHeight`.
    @Test func testClampsToMaxOffsetWhenWordNearBottom() {
        // desired = 1900 − 0.5×600 = 1600; maxOffset = 2000 − 600 = 1400
        let result = ScrollCoordinator.targetContentOffsetY(
            wordOriginY:    1900,
            viewportHeight: 600,
            anchorFraction: 0.5,
            contentHeight:  2000
        )
        #expect(result == 1400)   // clamped to maxOffset
    }

    /// When content is shorter than the viewport there is nowhere to scroll;
    /// the result is always 0 regardless of the word's position.
    @Test func testAlwaysZeroWhenContentShorterThanViewport() {
        let result = ScrollCoordinator.targetContentOffsetY(
            wordOriginY:    150,
            viewportHeight: 600,
            anchorFraction: 0.5,
            contentHeight:  400   // shorter than viewport
        )
        #expect(result == 0)
    }

    /// `maxOffset` is clamped to 0 even when `contentHeight == viewportHeight`.
    @Test func testMaxOffsetIsZeroWhenContentEqualsViewport() {
        let result = ScrollCoordinator.targetContentOffsetY(
            wordOriginY:    400,
            viewportHeight: 600,
            anchorFraction: 0.5,
            contentHeight:  600
        )
        #expect(result == 0)
    }

    // MARK: - isWithinTolerance

    @Test func testExactlyAtTargetIsWithinTolerance() {
        #expect(ScrollCoordinator.isWithinTolerance(
            currentOffsetY:    200,
            targetOffsetY:     200,
            viewportHeight:    600,
            toleranceFraction: 0.06
        ))
    }

    /// A small drift (well inside the band) should not trigger a scroll.
    @Test func testSmallDriftIsWithinTolerance() {
        // tolerance ≈ 0.06 × 600 ≈ 36; drift = 15 → inside
        #expect(ScrollCoordinator.isWithinTolerance(
            currentOffsetY:    215,
            targetOffsetY:     200,
            viewportHeight:    600,
            toleranceFraction: 0.06
        ))
    }

    /// A large drift (well outside the band) must trigger a scroll.
    @Test func testLargeDriftIsOutsideTolerance() {
        // tolerance ≈ 36; drift = 100 → outside
        #expect(!ScrollCoordinator.isWithinTolerance(
            currentOffsetY:    300,
            targetOffsetY:     200,
            viewportHeight:    600,
            toleranceFraction: 0.06
        ))
    }

    /// Tolerance band is symmetric — the same distance below the target also
    /// counts as within tolerance.
    @Test func testToleranceIsSymmetric() {
        let below = ScrollCoordinator.isWithinTolerance(
            currentOffsetY:    185,   // 15 below target
            targetOffsetY:     200,
            viewportHeight:    600,
            toleranceFraction: 0.06
        )
        let above = ScrollCoordinator.isWithinTolerance(
            currentOffsetY:    215,   // 15 above target
            targetOffsetY:     200,
            viewportHeight:    600,
            toleranceFraction: 0.06
        )
        #expect(below == true)
        #expect(above == true)
    }

    /// A larger viewport produces a proportionally larger tolerance band, so
    /// the same absolute drift can be within tolerance on a bigger screen.
    @Test func testToleranceScalesWithViewportHeight() {
        // drift = 50; tolerance on small viewport ≈ 0.06×400 = 24 → outside
        #expect(!ScrollCoordinator.isWithinTolerance(
            currentOffsetY: 250, targetOffsetY: 200,
            viewportHeight: 400, toleranceFraction: 0.06
        ))

        // same drift = 50; tolerance on large viewport ≈ 0.06×1200 = 72 → inside
        #expect(ScrollCoordinator.isWithinTolerance(
            currentOffsetY: 250, targetOffsetY: 200,
            viewportHeight: 1200, toleranceFraction: 0.06
        ))
    }

    /// `toleranceFraction = 0.0` means only an exact match avoids scrolling.
    @Test func testZeroToleranceFractionRequiresExactMatch() {
        #expect(!ScrollCoordinator.isWithinTolerance(
            currentOffsetY: 201, targetOffsetY: 200,
            viewportHeight: 600, toleranceFraction: 0.0
        ))
        #expect(ScrollCoordinator.isWithinTolerance(
            currentOffsetY: 200, targetOffsetY: 200,
            viewportHeight: 600, toleranceFraction: 0.0
        ))
    }

    // MARK: - scrollTarget state (no-scroll tolerance band)

    /// When the scroll view is already near the anchor the coordinator
    /// must not request a scroll (avoids jitter on small cursor advances).
    @Test func testScrollTargetNilWhenWithinTolerance() {
        let coordinator = ScrollCoordinator()
        coordinator.anchorFraction    = 0.5
        coordinator.toleranceFraction = 0.06

        coordinator.updateLayout(
            tokenPositions: [3: 600],
            viewportSize:   CGSize(width: 400, height: 600),
            contentHeight:  3000
        )
        // target = 600 − 0.5×600 = 300; set scroll to 310 (drift = 10, tolerance ≈ 36)
        coordinator.updateScrollOffset(310)
        coordinator.updateCurrentToken(3)

        #expect(coordinator.scrollTarget == nil)
    }

    /// When the scroll view is far from the anchor the coordinator must
    /// expose a non-nil target for the view to animate to.
    @Test func testScrollTargetSetWhenOutsideTolerance() {
        let coordinator = ScrollCoordinator()
        coordinator.anchorFraction    = 0.5
        coordinator.toleranceFraction = 0.06

        coordinator.updateLayout(
            tokenPositions: [3: 600],
            viewportSize:   CGSize(width: 400, height: 600),
            contentHeight:  3000
        )
        coordinator.updateScrollOffset(0)   // 300 away from target (300 >> tolerance ≈ 36)
        coordinator.updateCurrentToken(3)

        #expect(coordinator.scrollTarget != nil)
    }

    /// The target value equals what `targetContentOffsetY` returns directly.
    @Test func testScrollTargetMatchesMathFunction() {
        let coordinator = ScrollCoordinator()
        coordinator.anchorFraction = 0.5

        coordinator.updateLayout(
            tokenPositions: [2: 800],
            viewportSize:   CGSize(width: 400, height: 600),
            contentHeight:  3000
        )
        coordinator.updateScrollOffset(0)
        coordinator.updateCurrentToken(2)

        let expected = ScrollCoordinator.targetContentOffsetY(
            wordOriginY: 800, viewportHeight: 600, anchorFraction: 0.5, contentHeight: 3000
        )
        #expect(coordinator.scrollTarget == expected)
    }

    /// An unknown spoken-token index (no entry in `tokenPositions`) must
    /// produce no scroll request rather than crashing or using stale data.
    @Test func testScrollTargetNilForUnknownIndex() {
        let coordinator = ScrollCoordinator()
        coordinator.updateLayout(
            tokenPositions: [0: 100, 1: 200],
            viewportSize:   CGSize(width: 400, height: 600),
            contentHeight:  2000
        )
        coordinator.updateCurrentToken(99)   // not in tokenPositions
        #expect(coordinator.scrollTarget == nil)
    }

    /// A zero-height viewport (e.g. before first layout) must not produce
    /// a scroll request.
    @Test func testScrollTargetNilWhenViewportHeightIsZero() {
        let coordinator = ScrollCoordinator()
        coordinator.updateLayout(
            tokenPositions: [0: 400],
            viewportSize:   .zero,
            contentHeight:  2000
        )
        coordinator.updateCurrentToken(0)
        #expect(coordinator.scrollTarget == nil)
    }

    // MARK: - Resize recalculation

    /// Changing the viewport height causes `updateCurrentToken` to produce a
    /// different scroll target for the same word position.
    @Test func testResizeChangesScrollTarget() {
        let coordinator = ScrollCoordinator()
        coordinator.anchorFraction    = 0.5
        coordinator.toleranceFraction = 0.0   // disable band so target is always non-nil

        // Layout at viewport height 600
        coordinator.updateLayout(
            tokenPositions: [4: 900],
            viewportSize:   CGSize(width: 400, height: 600),
            contentHeight:  4000
        )
        coordinator.updateScrollOffset(0)
        coordinator.updateCurrentToken(4)
        let target600 = coordinator.scrollTarget   // 900 − 0.5×600 = 600

        // Resize to viewport height 800
        coordinator.updateLayout(
            tokenPositions: [4: 900],
            viewportSize:   CGSize(width: 400, height: 800),
            contentHeight:  4000
        )
        coordinator.updateCurrentToken(4)
        let target800 = coordinator.scrollTarget   // 900 − 0.5×800 = 500

        #expect(target600 != nil)
        #expect(target800 != nil)
        // Larger viewport → larger anchor shift → lower target offset
        #expect(target600! > target800!)
        #expect(target600! == 600)
        #expect(target800! == 500)
    }

    /// Changing a token's Y-position (e.g. after font-size change causes
    /// re-layout) produces a new scroll target.
    @Test func testFontChangeCausesRecalculation() {
        let coordinator = ScrollCoordinator()
        coordinator.anchorFraction    = 0.5
        coordinator.toleranceFraction = 0.0

        coordinator.updateLayout(
            tokenPositions: [1: 500],
            viewportSize:   CGSize(width: 400, height: 600),
            contentHeight:  3000
        )
        coordinator.updateScrollOffset(0)
        coordinator.updateCurrentToken(1)
        let before = coordinator.scrollTarget   // 500 − 300 = 200

        // Larger font → word moved further down
        coordinator.updateLayout(
            tokenPositions: [1: 800],
            viewportSize:   CGSize(width: 400, height: 600),
            contentHeight:  4000
        )
        coordinator.updateCurrentToken(1)
        let after = coordinator.scrollTarget    // 800 − 300 = 500

        #expect(before != after)
        #expect(before! == 200)
        #expect(after!  == 500)
    }

    /// After an `updateLayout` call that changes the viewport, calling
    /// `updateCurrentToken` with the same index produces a fresh target
    /// (old cached value is not re-used).
    @Test func testLayoutUpdateInvalidatesStaleTarget() {
        let coordinator = ScrollCoordinator()
        coordinator.anchorFraction    = 0.5
        coordinator.toleranceFraction = 0.0

        coordinator.updateLayout(
            tokenPositions: [0: 400],
            viewportSize:   CGSize(width: 400, height: 600),
            contentHeight:  2000
        )
        coordinator.updateScrollOffset(0)
        coordinator.updateCurrentToken(0)
        let first = coordinator.scrollTarget!   // 400 − 300 = 100

        // Resize to twice the height
        coordinator.updateLayout(
            tokenPositions: [0: 400],
            viewportSize:   CGSize(width: 400, height: 1200),
            contentHeight:  2000
        )
        coordinator.updateCurrentToken(0)
        let second = coordinator.scrollTarget!  // 400 − 600 = 0 (clamped)

        #expect(first  == 100)
        #expect(second == 0)
    }
}
