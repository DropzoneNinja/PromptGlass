import SwiftUI

/// Multiline script text editor with a word-count status bar.
///
/// Binds to `ScriptEditorViewModel.selectedDocument.rawText` via
/// `editorVM.updateText(_:)`, which re-parses tokens and marks the document
/// dirty on every keystroke.  The view is disabled while a session is active so
/// the narrator cannot accidentally edit the script mid-performance.
struct ScriptEditorView: View {

    var editorVM: ScriptEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            textEditorArea
            statusBar
        }
    }

    // MARK: - Text editor

    private var textEditorArea: some View {
        SpellCheckTextEditor(text: rawTextBinding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            // Save-error indicator
            if let error = editorVM.saveError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .imageScale(.small)
                Text("Save failed: \(error.localizedDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            // Spoken-word count (directions excluded)
            Text(wordCountLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .animation(.none, value: wordCountLabel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Helpers

    /// Forwards text changes through the VM so parsing and dirty-tracking happen
    /// in one place rather than being scattered across views.
    private var rawTextBinding: Binding<String> {
        Binding(
            get: { editorVM.selectedDocument?.rawText ?? "" },
            set: { editorVM.updateText($0) }
        )
    }

    private var wordCountLabel: String {
        let count = editorVM.spokenTokens.count
        switch count {
        case 0:  return "No spoken words"
        case 1:  return "1 spoken word"
        default: return "\(count) spoken words"
        }
    }
}
