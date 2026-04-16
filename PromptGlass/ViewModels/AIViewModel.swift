import Foundation
import Observation
import SwiftUI

// MARK: - Environment key

@MainActor
private enum AIViewModelKey: EnvironmentKey {
    // The default is never used in practice — AIViewModel is always injected
    // via .environment(\.aiViewModel, aiVM) in PromptGlassApp.
    static let defaultValue = AIViewModel()
}

extension EnvironmentValues {
    var aiViewModel: AIViewModel {
        get { self[AIViewModelKey.self] }
        set { self[AIViewModelKey.self] = newValue }
    }
}

// MARK: - ViewModel

/// Orchestrates all AI operations: settings management, model loading, and text completion.
///
/// Owned at the `App` level and injected into both the Settings scene and the
/// editor window via SwiftUI's environment.
@Observable
final class AIViewModel {

    // MARK: - Connection test result

    enum ConnectionTestResult: Equatable {
        case success
        case failure(String)
    }

    // MARK: - Observable state

    /// Models fetched from the API; empty until `fetchModels()` succeeds.
    private(set) var availableModels: [String] = []

    /// `true` while a model fetch or completion request is in flight.
    private(set) var isLoading: Bool = false

    /// `true` while a connection test is in flight.
    private(set) var isTestingConnection: Bool = false

    /// Set when an operation fails; shown as an error banner in the UI.
    private(set) var errorMessage: String? = nil

    /// Non-nil after a connection test completes (success or failure).
    private(set) var connectionTestResult: ConnectionTestResult? = nil

    // MARK: - Debug

    /// Raw request JSON from the most recent completion call.
    private(set) var lastRequestBody: String = ""

    /// Raw response body from the most recent completion call.
    private(set) var lastResponseBody: String = ""

    /// HTTP status code from the most recent completion call.
    private(set) var lastStatusCode: Int? = nil

    /// Whether the debug window should be shown.
    var showDebugWindow: Bool = false

    // MARK: - AI settings (non-sensitive; persisted to settings.json)

    var aiSettings: AISettings {
        didSet { persistAISettings() }
    }

    // MARK: - API key (sensitive; stored in Keychain)

    /// The live API key string.  Writing it automatically saves to the Keychain.
    var apiKey: String {
        didSet { saveAPIKey(apiKey) }
    }

    /// `true` when an API key has been configured.
    var isConfigured: Bool { !apiKey.isEmpty }

    // MARK: - Init

    init() {
        let settings = PersistenceService.shared.loadSettings()
        self.aiSettings = settings.aiSettings
        self.apiKey     = KeychainService.loadAPIKey() ?? ""
    }

    // MARK: - Public API

    /// Clear any displayed error message.
    func clearError() { errorMessage = nil }

    /// Fetch available chat models from the API and populate `availableModels`.
    func fetchModels() async {
        guard let service = makeService() else {
            errorMessage = OpenAIError.missingAPIKey.localizedDescription
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            availableModels = try await service.fetchModels()
            // Ensure the currently-selected model ID stays valid.
            if !availableModels.isEmpty, !availableModels.contains(aiSettings.selectedModelID) {
                aiSettings.selectedModelID = availableModels[0]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Verify that the stored API key and base URL are valid.
    func testConnection() async {
        guard let service = makeService() else {
            connectionTestResult = .failure(OpenAIError.missingAPIKey.localizedDescription)
            return
        }
        isTestingConnection = true
        connectionTestResult = nil
        defer { isTestingConnection = false }
        do {
            try await service.testConnection()
            connectionTestResult = .success
        } catch {
            connectionTestResult = .failure(error.localizedDescription)
        }
    }

    /// Run a chat completion with the given user text as the message body.
    /// - Returns: The assistant's reply, or `nil` if the request fails (sets `errorMessage`).
    func complete(userText: String) async -> String? {
        guard let service = makeService() else {
            errorMessage = OpenAIError.missingAPIKey.localizedDescription
            return nil
        }
        isLoading = true
        errorMessage = nil
        lastRequestBody  = ""
        lastResponseBody = ""
        lastStatusCode   = nil
        defer { isLoading = false }
        do {
            let result = try await service.complete(
                systemPrompt: aiSettings.systemPrompt,
                userMessage:  userText,
                modelID:      aiSettings.selectedModelID,
                maxTokens:    aiSettings.maxTokens
            )
            lastRequestBody  = result.debug.requestBody
            lastResponseBody = result.debug.responseBody
            lastStatusCode   = result.debug.statusCode
            return result.content
        } catch let e as OpenAIError {
            if let d = e.debugInfo {
                lastRequestBody  = d.requestBody
                lastResponseBody = d.responseBody
                lastStatusCode   = d.statusCode
            }
            errorMessage = e.localizedDescription
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Private helpers

    private func makeService() -> OpenAIService? {
        guard isConfigured else { return nil }
        return OpenAIService(apiKey: apiKey, baseURL: aiSettings.baseURL)
    }

    private func saveAPIKey(_ key: String) {
        if key.isEmpty {
            try? KeychainService.deleteAPIKey()
        } else {
            try? KeychainService.saveAPIKey(key)
        }
    }

    /// Persist the current `aiSettings` inside the full `SessionSettings` blob.
    /// Loads the current on-disk settings first so other fields are not overwritten.
    private func persistAISettings() {
        var full = PersistenceService.shared.loadSettings()
        full.aiSettings = aiSettings
        try? PersistenceService.shared.saveSettings(full)
    }
}
