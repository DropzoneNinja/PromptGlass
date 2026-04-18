import AppKit
import SwiftUI

/// NSTextView-backed text editor with continuous spell and grammar checking.
///
/// Drop-in replacement for SwiftUI's `TextEditor` in `ScriptEditorView`.
/// Styling (font, line spacing, padding, background) is configured internally
/// so the call site only needs `.frame(maxWidth: .infinity, maxHeight: .infinity)`.
struct SpellCheckTextEditor: NSViewRepresentable {

    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // Spell / grammar checking — underlines only, no silent autocorrect.
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false

        // Match the original TextEditor styling.
        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.font = font

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5
        textView.defaultParagraphStyle = paragraphStyle

        // Carry font, paragraph style, and color into newly typed text.
        // Explicitly set labelColor so the text adapts to dark/light mode;
        // without this NSTextView defaults to black even on dark backgrounds.
        textView.textColor = NSColor.labelColor
        textView.typingAttributes = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]

        // Padding to match the original .padding(.horizontal, 28) / .padding(.top, 16).
        textView.textContainerInset = NSSize(width: 28, height: 16)

        // Transparent background (matches .scrollContentBackground(.hidden)).
        textView.drawsBackground = false

        // Plain-text, undo-capable, fills the scroll view width.
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        textView.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only push text into the view when it changed externally (e.g. document
        // switch). Skip when the change originated here to avoid a feedback loop
        // with the delegate and to preserve the cursor position.
        guard textView.string != text else { return }

        let savedRange = textView.selectedRange()
        textView.string = text

        // Reapply attributes — setting .string clears them.
        if let ps = textView.defaultParagraphStyle, let font = textView.font {
            textView.textColor = NSColor.labelColor
            textView.typingAttributes = [
                .font: font,
                .paragraphStyle: ps,
                .foregroundColor: NSColor.labelColor
            ]
        }

        // Restore cursor, clamped to the new string length.
        let len = (textView.string as NSString).length
        let clampedLocation = min(savedRange.location, len)
        textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SpellCheckTextEditor

        init(_ parent: SpellCheckTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
