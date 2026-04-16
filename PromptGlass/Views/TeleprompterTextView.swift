import AppKit
import SwiftUI

/// `NSViewRepresentable` wrapping an `NSScrollView` + `NSTextView` pair that
/// renders script tokens with per-word highlighting and drives animated scrolling
/// via `ScrollCoordinator`.
///
/// ## TextKit stack
/// An explicit TextKit 1 stack (`NSTextStorage` → `NSLayoutManager` →
/// `NSTextContainer` → `NSTextView`) is constructed so `NSLayoutManager` is
/// always available for per-word bounding-rect queries, regardless of the
/// system default (which may be TextKit 2 on macOS 14+).
///
/// ## Update strategy
/// - **Full rebuild** when `tokens`, `fontSize`, or `lineSpacing` change —
///   re-generates the attributed string and refreshes the position map.
/// - **Attribute-only update** when only `currentSpokenIndex` changes —
///   cheaply swaps foreground/background colours without re-flowing glyphs.
///
/// ## Mirror mode
/// Applied as a `CATransform3D` horizontal scale on the scroll view's layer;
/// layout coordinates are unaffected so `ScrollCoordinator` math stays correct.
struct TeleprompterTextView: NSViewRepresentable {

    // MARK: - Inputs (from TeleprompterView)

    let tokens: [ScriptToken]
    let currentSpokenIndex: Int
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let mirrorMode: Bool
    let scrollCoordinator: ScrollCoordinator
    /// Width of the available container, provided by a GeometryReader in the
    /// parent view. Passed as a SwiftUI input so that `updateNSView` is called
    /// on every window resize — not just when the other inputs change.
    let containerWidth: CGFloat

    // MARK: - Coordinator

    final class Coordinator: NSObject {

        var parent: TeleprompterTextView

        /// Character range of each token in the current attributed string,
        /// in the same order as `tokens`. Used for highlighting and position queries.
        var tokenRanges: [(token: ScriptToken, range: NSRange)] = []

        // Sentinels to detect when a full attributed-string rebuild is needed.
        var lastTokenCount: Int    = -1
        var lastFontSize: CGFloat  = -1
        var lastLineSpacing: CGFloat = -1

        init(_ parent: TeleprompterTextView) {
            self.parent = parent
        }

        // MARK: Scroll tracking

        /// Called by `NSView.boundsDidChangeNotification` on the clip view.
        /// Forwards the live scroll position to `ScrollCoordinator` so the
        /// tolerance check always uses the current offset.
        @MainActor @objc func boundsDidChange(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView else { return }
            parent.scrollCoordinator.updateScrollOffset(clipView.bounds.origin.y)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - makeNSView

    func makeNSView(context: Context) -> NSScrollView {
        // ── Explicit TextKit 1 stack ───────────────────────────────────────
        let textStorage   = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView  = false  // width is set manually in updateNSView
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable              = false
        textView.isSelectable            = false
        textView.drawsBackground         = false
        textView.isVerticallyResizable   = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask        = [NSView.AutoresizingMask.width]
        textView.textContainerInset      = NSSize(width: 28, height: 28)

        // ── Scroll view ────────────────────────────────────────────────────
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground       = false
        scrollView.documentView          = textView

        // Receive bounds-change notifications to track the scroll offset.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    // MARK: - updateNSView

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard
            let textView      = scrollView.documentView as? NSTextView,
            let textStorage   = textView.textStorage,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }

        let coordinator = context.coordinator
        coordinator.parent = self   // keep parent current for the bounds-change handler

        // ── Sync text-container width ──────────────────────────────────────
        // Prefer the GeometryReader-provided width; fall back to the scroll
        // view's own bounds only if the parent didn't supply a valid width.
        // Using `containerWidth` as a SwiftUI input guarantees `updateNSView`
        // is called on every window resize, so the layout is never stale.
        let viewWidth = containerWidth > 0
            ? containerWidth
            : max(1, scrollView.contentView.bounds.size.width)
        let inset     = textView.textContainerInset.width * 2
        textContainer.size = NSSize(
            width:  max(1, viewWidth - inset),
            height: CGFloat.greatestFiniteMagnitude
        )

        // ── Rebuild or re-highlight ─────────────────────────────────────────
        let tokensChanged  = tokens.count      != coordinator.lastTokenCount
        let fontChanged    = fontSize          != coordinator.lastFontSize
        let spacingChanged = lineSpacing       != coordinator.lastLineSpacing

        if tokensChanged || fontChanged || spacingChanged {
            let (attrString, ranges) = buildAttributedString()
            textStorage.setAttributedString(attrString)
            coordinator.tokenRanges      = ranges
            coordinator.lastTokenCount   = tokens.count
            coordinator.lastFontSize     = fontSize
            coordinator.lastLineSpacing  = lineSpacing
        } else {
            // Fast path: swap colours without re-flowing glyphs.
            applyHighlighting(to: textStorage, tokenRanges: coordinator.tokenRanges)
        }

        // ── Force layout and size document view ────────────────────────────
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let docHeight  = usedHeight + textView.textContainerInset.height * 2
        textView.setFrameSize(NSSize(width: viewWidth, height: max(1, docHeight)))

        // ── Collect per-token Y positions ──────────────────────────────────
        // Positions are in scroll-view document coordinates (textView-relative Y).
        var positions: [Int: CGFloat] = [:]
        for (token, charRange) in coordinator.tokenRanges {
            guard case .spoken(let st) = token else { continue }
            let gRange = layoutManager.glyphRange(
                forCharacterRange: charRange, actualCharacterRange: nil
            )
            guard gRange.location != NSNotFound, gRange.length > 0 else { continue }
            let rect = layoutManager.boundingRect(forGlyphRange: gRange, in: textContainer)
            // Add the vertical inset to convert from text-container to textView coords.
            positions[st.spokenIndex] = rect.origin.y + textView.textContainerInset.height
        }

        let viewportSize = scrollView.contentView.bounds.size
        scrollCoordinator.updateLayout(
            tokenPositions: positions,
            viewportSize:   viewportSize,
            contentHeight:  max(1, docHeight)
        )

        // ── Drive scrolling ────────────────────────────────────────────────
        scrollCoordinator.updateCurrentToken(currentSpokenIndex)
        if scrollCoordinator.scrollTarget != nil {
            scrollCoordinator.performScroll(on: scrollView, animated: true)
        }

        // ── Mirror mode ────────────────────────────────────────────────────
        scrollView.wantsLayer = true
        scrollView.layer?.transform = mirrorMode
            ? CATransform3DMakeScale(-1, 1, 1)
            : CATransform3DIdentity
    }

    // MARK: - Attributed string construction

    /// Builds the complete attributed string from `tokens` and returns a
    /// parallel array of `(token, characterRange)` pairs for later updates.
    private func buildAttributedString()
        -> (NSAttributedString, [(token: ScriptToken, range: NSRange)])
    {
        let result = NSMutableAttributedString()
        var tokenRanges: [(token: ScriptToken, range: NSRange)] = []
        let paraStyle = makeParagraphStyle()

        for (index, token) in tokens.enumerated() {
            // Space separator between tokens (invisible, uses body font size).
            if index > 0 {
                let spaceAttrs: [NSAttributedString.Key: Any] = [
                    .font:            NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor.clear,
                    .paragraphStyle:  paraStyle,
                ]
                result.append(NSAttributedString(string: " ", attributes: spaceAttrs))
            }

            let display = token.displayText
            let start   = result.length
            let attrs   = baseAttributes(for: token, paragraphStyle: paraStyle)
            result.append(NSAttributedString(string: display, attributes: attrs))

            let range = NSRange(location: start, length: (display as NSString).length)
            tokenRanges.append((token: token, range: range))
        }

        return (result, tokenRanges)
    }

    /// Returns the full set of `NSAttributedString` attributes for one token,
    /// including colour treatment based on its position relative to `currentSpokenIndex`.
    private func baseAttributes(
        for token: ScriptToken,
        paragraphStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {

        var attrs: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraphStyle]

        switch token {
        case .spoken(let st):
            attrs[.font] = NSFont.systemFont(ofSize: fontSize, weight: .medium)
            applySpokenColour(spokenIndex: st.spokenIndex, to: &attrs)

        case .direction:
            let baseFont = NSFont.systemFont(ofSize: fontSize * 0.80, weight: .regular)
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.italic)
            attrs[.font] = NSFont(descriptor: descriptor, size: fontSize * 0.80) ?? baseFont
            attrs[.foregroundColor] = NSColor(white: 1.0, alpha: 0.35)
        }

        return attrs
    }

    /// Sets foreground and background colour on `attrs` for a spoken token.
    private func applySpokenColour(
        spokenIndex: Int,
        to attrs: inout [NSAttributedString.Key: Any]
    ) {
        if spokenIndex < currentSpokenIndex {
            // Already spoken — dim.
            attrs[.foregroundColor] = NSColor(white: 1.0, alpha: 0.28)
        } else if spokenIndex == currentSpokenIndex {
            // Currently spoken — highlighted with a teal accent pill.
            attrs[.foregroundColor] = NSColor.black
            attrs[.backgroundColor] = highlightColour
        } else {
            // Not yet spoken — full brightness.
            attrs[.foregroundColor] = NSColor.white
        }
    }

    /// Accent colour used to highlight the currently spoken word.
    private var highlightColour: NSColor {
        NSColor(calibratedRed: 0.20, green: 0.84, blue: 0.60, alpha: 1.0)
    }

    // MARK: - Fast highlighting update

    /// Updates only foreground/background attributes for spoken tokens so the
    /// layout engine does not need to re-flow glyphs when the cursor advances.
    private func applyHighlighting(
        to textStorage: NSTextStorage,
        tokenRanges: [(token: ScriptToken, range: NSRange)]
    ) {
        textStorage.beginEditing()
        for (token, range) in tokenRanges {
            guard case .spoken(let st) = token else { continue }

            let fg: NSColor
            let bg: NSColor?
            if st.spokenIndex < currentSpokenIndex {
                fg = NSColor(white: 1.0, alpha: 0.28); bg = nil
            } else if st.spokenIndex == currentSpokenIndex {
                fg = .black; bg = highlightColour
            } else {
                fg = .white; bg = nil
            }

            textStorage.addAttribute(.foregroundColor, value: fg, range: range)
            if let bg {
                textStorage.addAttribute(.backgroundColor, value: bg, range: range)
            } else {
                textStorage.removeAttribute(.backgroundColor, range: range)
            }
        }
        textStorage.endEditing()
    }

    // MARK: - Paragraph style

    private func makeParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        // `lineSpacing` is a multiplier; convert the extra fraction to points.
        style.lineSpacing   = (lineSpacing - 1.0) * fontSize
        style.lineBreakMode = .byWordWrapping
        return style
    }
}
