import Foundation

/// Non-sensitive AI preferences persisted alongside `SessionSettings`.
///
/// The API key is intentionally excluded — it is stored securely in the
/// system Keychain via `KeychainService`.
struct AISettings: Codable, Equatable {

    /// Base URL for the OpenAI-compatible API (default: OpenAI's public endpoint).
    /// Override to use Azure OpenAI, a local model (Ollama/LM Studio), or a proxy.
    var baseURL: String = "https://api.openai.com"

    /// The model ID selected by the user (e.g. "gpt-4o").
    var selectedModelID: String = "gpt-4o"

    /// System prompt sent with every completion request.
    var systemPrompt: String = "You are a helpful writing assistant. Reply with only the revised text, no explanation."

    /// Maximum tokens to request in each completion response.
    /// Reasoning models (Qwen3, DeepSeek-R1) consume tokens during their thinking
    /// phase before producing output, so this needs to be generous.
    var maxTokens: Int = 4096

    static let `default` = AISettings()
}
