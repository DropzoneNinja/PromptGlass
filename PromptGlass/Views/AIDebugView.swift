import SwiftUI

/// A plain window that shows the raw request and response from the last
/// AI completion call. Open it via the "Debug" button in the AI prompt sheet.
struct AIDebugView: View {

    var aiVM: AIViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    debugSection(
                        title: "Request  →  POST /v1/chat/completions",
                        content: aiVM.lastRequestBody.isEmpty
                            ? "(no request sent yet)"
                            : aiVM.lastRequestBody
                    )
                    Divider()
                    debugSection(
                        title: statusTitle,
                        content: aiVM.lastResponseBody.isEmpty
                            ? "(no response received yet)"
                            : aiVM.lastResponseBody
                    )
                }
                .padding(16)
            }
        }
        .frame(minWidth: 600, idealWidth: 720, maxWidth: .infinity,
               minHeight: 500, idealHeight: 640, maxHeight: .infinity)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Label("AI Debug Output", systemImage: "ladybug")
                .font(.headline)
            Spacer()
            Button {
                let text = "=== REQUEST ===\n\(aiVM.lastRequestBody)\n\n=== RESPONSE ===\n\(aiVM.lastResponseBody)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy request and response to clipboard")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var statusTitle: String {
        if let code = aiVM.lastStatusCode {
            return "Response  ←  HTTP \(code)"
        }
        return "Response  ←"
    }

    private func debugSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(content)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
    }
}
