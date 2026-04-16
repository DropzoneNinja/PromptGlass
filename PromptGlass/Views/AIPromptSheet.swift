import AppKit
import SwiftUI

/// Sheet that accepts a natural-language instruction and applies the AI's
/// reply to the editor — either replacing selected text or inserting at cursor.
struct AIPromptSheet: View {

    @Environment(\.openWindow) private var openWindow

    var aiVM: AIViewModel

    /// The text that will be sent as context to the AI:
    /// the selected text when there is a selection, or the full document otherwise.
    let contextText: String

    /// `true` when the sheet was opened with an active text selection.
    let hasSelection: Bool

    /// Called with the assistant's reply when the user taps "Apply to Script".
    let onApply: (String) -> Void

    /// Called when the user dismisses the sheet without applying.
    let onCancel: () -> Void

    // MARK: - Local state

    @State private var promptText: String = ""
    @State private var sheetState: SheetState = .idle

    private enum SheetState: Equatable {
        case idle
        case generating
        case ready(String)
        case error(String)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    contextPreview
                    promptInput
                    if case .ready(let result) = sheetState { resultArea(result) }
                    if case .error(let msg) = sheetState { errorBanner(msg) }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 500, idealWidth: 560, maxWidth: 700,
               minHeight: 380, idealHeight: 440)
        // Clear any stale error when the sheet opens.
        .onAppear { aiVM.clearError() }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Assistant")
                    .font(.headline)
                Text(hasSelection
                     ? "Selection will be replaced with the AI's reply."
                     : "The reply will be inserted at the cursor position.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var contextPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hasSelection ? "Selected Text" : "Document Context")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView {
                Text(contextText)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 100)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
    }

    private var promptInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Instruction")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            TextEditor(text: $promptText)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 100)
                .scrollContentBackground(.hidden)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
                .disabled(sheetState == .generating)

            // Hint text when the field is empty.
            if promptText.isEmpty {
                Text("e.g. \"Make this more concise\" or \"Fix any grammar issues\"")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func resultArea(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AI Reply")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button("Re-generate") { generate() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            ScrollView {
                Text(result)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 120)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            )
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .cornerRadius(8)
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) { onCancel() }

            // Debug button — visible after any generate attempt.
            if sheetState != .idle {
                Button {
                    openWindow(id: "ai-debug")
                } label: {
                    Label("Debug", systemImage: "ladybug")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Show raw request and response")
            }

            Spacer()

            if sheetState == .generating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 6)
                Text("Generating…")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                Button("Generate") { generate() }
                    .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if case .ready(let result) = sheetState {
                Button("Apply to Script") { onApply(result) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func generate() {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userMessage = "\(trimmed)\n\n---\n\(contextText)"
        sheetState = .generating
        Task {
            if let reply = await aiVM.complete(userText: userMessage) {
                sheetState = .ready(reply)
            } else {
                sheetState = .error(aiVM.errorMessage ?? "An unknown error occurred.")
            }
        }
    }
}
