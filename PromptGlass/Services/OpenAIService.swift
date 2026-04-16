import Foundation

// MARK: - Error

enum OpenAIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case decodingFailed(Error)
    case decodingFailedWithDebug(Error, debug: CompletionDebugInfo)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key is configured. Add one in Settings (⌘,)."
        case .invalidURL:
            return "The configured API base URL is invalid."
        case .httpError(let code, let body):
            return "API request failed (\(code)): \(body)"
        case .decodingFailed(let error):
            return "Failed to decode API response: \(error.localizedDescription)"
        case .decodingFailedWithDebug(let error, _):
            return "Failed to decode API response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }

    /// The debug info attached to a decoding failure, if any.
    var debugInfo: CompletionDebugInfo? {
        if case .decodingFailedWithDebug(_, let d) = self { return d }
        return nil
    }
}

// MARK: - Private response models

private struct ModelsListResponse: Decodable {
    let data: [OpenAIModelEntry]
}

private struct OpenAIModelEntry: Decodable {
    let id: String
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let max_tokens: Int
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            // Standard content field — null on reasoning/thinking models.
            let content: String?
            // Qwen3, Qwen-thinking and similar models put output here when content is null.
            let reasoning: String?
            // DeepSeek-R1 and compatible servers use this field name instead.
            let reasoning_content: String?

            /// The text to show the user: content → reasoning → reasoning_content → "".
            var effectiveContent: String {
                if let c = content, !c.isEmpty { return c }
                if let r = reasoning, !r.isEmpty { return r }
                return reasoning_content ?? ""
            }
        }
        let message: Message
        let finish_reason: String?
    }
    let choices: [Choice]
}

// MARK: - Debug info

struct CompletionDebugInfo {
    let requestBody: String
    let responseBody: String
    let statusCode: Int?
    let error: String?
}

// MARK: - Service

final class OpenAIService {

    private let apiKey: String
    private let baseURL: String
    private let urlSession: URLSession

    init(apiKey: String, baseURL: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.urlSession = urlSession
    }

    // MARK: - Public API

    /// Fetch available chat models from the API, filtered to known chat-capable prefixes.
    func fetchModels() async throws -> [String] {
        let request = try makeRequest(method: "GET", path: "/v1/models", body: nil as String?)
        let data = try await perform(request)
        do {
            let response = try JSONDecoder().decode(ModelsListResponse.self, from: data)
            let ids = response.data.map(\.id)
            // Only apply the OpenAI chat-model filter when talking to the official
            // endpoint. Custom servers (LM Studio, Ollama, etc.) use arbitrary IDs.
            let isOfficialOpenAI = baseURL.contains("api.openai.com")
            let result = isOfficialOpenAI ? ids.filter(isChatModel) : ids
            return result.sorted().reversed()
        } catch {
            throw OpenAIError.decodingFailed(error)
        }
    }

    /// Send a chat completion and return the assistant's text alongside debug info.
    func complete(
        systemPrompt: String,
        userMessage: String,
        modelID: String,
        maxTokens: Int
    ) async throws -> (content: String, debug: CompletionDebugInfo) {
        let bodyStruct = ChatCompletionRequest(
            model: modelID,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user",   content: userMessage)
            ],
            max_tokens: maxTokens
        )
        let request = try makeRequest(method: "POST", path: "/v1/chat/completions", body: bodyStruct)

        // Capture the request JSON for debug display.
        let requestBody = request.httpBody
            .flatMap { prettyPrint($0) ?? String(data: $0, encoding: .utf8) }
            ?? "(no body)"

        let (data, statusCode) = try await performWithStatus(request)
        let rawResponse = String(data: data, encoding: .utf8) ?? "(non-UTF8 body)"

        do {
            let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            // Prefer content; fall back to reasoning fields used by thinking models
            // (Qwen3 uses `reasoning`, DeepSeek-R1 uses `reasoning_content`).
            let content = response.choices.first?.message.effectiveContent ?? ""
            let debug = CompletionDebugInfo(requestBody: requestBody,
                                           responseBody: rawResponse,
                                           statusCode: statusCode,
                                           error: nil)
            return (content, debug)
        } catch let e as OpenAIError {
            throw e
        } catch {
            let debug = CompletionDebugInfo(requestBody: requestBody,
                                           responseBody: rawResponse,
                                           statusCode: statusCode,
                                           error: error.localizedDescription)
            throw OpenAIError.decodingFailedWithDebug(error, debug: debug)
        }
    }

    /// Verify that the API key and base URL are valid by fetching the models list.
    func testConnection() async throws {
        _ = try await fetchModels()
    }

    // MARK: - Private helpers

    private func makeRequest<Body: Encodable>(
        method: String,
        path: String,
        body: Body?
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw OpenAIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, _) = try await performWithStatus(request)
        return data
    }

    /// Like `perform` but also returns the HTTP status code (nil for non-HTTP responses).
    private func performWithStatus(_ request: URLRequest) async throws -> (Data, Int?) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw OpenAIError.networkError(error)
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        if let code = statusCode, code >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw OpenAIError.httpError(statusCode: code, body: body)
        }
        return (data, statusCode)
    }

    private func prettyPrint(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted)
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    private func isChatModel(_ id: String) -> Bool {
        let prefixes = ["gpt-4", "gpt-3.5", "o1", "o3", "o4"]
        return prefixes.contains { id.hasPrefix($0) }
    }
}
