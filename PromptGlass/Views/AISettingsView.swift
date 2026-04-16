import SwiftUI

/// Settings panel for the OpenAI AI assistant.
///
/// Presented as a tab inside the macOS Settings window (Cmd+,).
struct AISettingsView: View {

    @Bindable var aiVM: AIViewModel

    // Draft API key — saved to Keychain on submit or focus loss.
    @State private var draftAPIKey: String = ""
    @FocusState private var apiKeyFocused: Bool

    var body: some View {
        Form {
            connectionSection
            modelSection
            systemPromptSection
            aboutSection
        }
        .formStyle(.grouped)
        .onAppear {
            draftAPIKey = aiVM.apiKey
        }
        // Save key when focus moves away from the SecureField.
        .onChange(of: apiKeyFocused) { _, focused in
            if !focused { commitAPIKey() }
        }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section("OpenAI Connection") {
            LabeledContent("API Key") {
                SecureField("sk-…", text: $draftAPIKey)
                    .focused($apiKeyFocused)
                    .onSubmit { commitAPIKey() }
                    .frame(maxWidth: 300)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Base URL") {
                TextField("https://api.openai.com", text: $aiVM.aiSettings.baseURL)
                    .frame(maxWidth: 300)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button {
                    Task { await aiVM.testConnection() }
                } label: {
                    if aiVM.isTestingConnection {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text("Testing…")
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(aiVM.isTestingConnection || !aiVM.isConfigured)

                if let result = aiVM.connectionTestResult {
                    connectionStatusBadge(result)
                }
            }
        }
    }

    private var modelSection: some View {
        Section("Model") {
            LabeledContent("Model") {
                HStack {
                    if aiVM.availableModels.isEmpty {
                        Picker("", selection: $aiVM.aiSettings.selectedModelID) {
                            Text(aiVM.aiSettings.selectedModelID)
                                .tag(aiVM.aiSettings.selectedModelID)
                        }
                        .frame(width: 200)
                        .disabled(true)
                    } else {
                        Picker("", selection: $aiVM.aiSettings.selectedModelID) {
                            ForEach(aiVM.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .frame(width: 200)
                    }

                    Button {
                        Task { await aiVM.fetchModels() }
                    } label: {
                        if aiVM.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Load Models")
                        }
                    }
                    .disabled(aiVM.isLoading || !aiVM.isConfigured)
                }
            }

            LabeledContent("Max Tokens") {
                Stepper(
                    "\(aiVM.aiSettings.maxTokens)",
                    value: $aiVM.aiSettings.maxTokens,
                    in: 256...32768,
                    step: 256
                )
            }
        }
    }

    private var systemPromptSection: some View {
        Section("System Prompt") {
            TextEditor(text: $aiVM.aiSettings.systemPrompt)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
        }
    }

    private var aboutSection: some View {
        Section {
            Link("OpenAI API Documentation",
                 destination: URL(string: "https://platform.openai.com/docs")!)
            .font(.callout)
        }
    }

    // MARK: - Helpers

    private func commitAPIKey() {
        aiVM.apiKey = draftAPIKey
    }

    @ViewBuilder
    private func connectionStatusBadge(_ result: AIViewModel.ConnectionTestResult) -> some View {
        switch result {
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(2)
                .help(message)
        }
    }
}
