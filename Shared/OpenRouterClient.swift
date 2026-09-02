import Foundation

/// Talks to OpenRouter (GPT-5.6 Luna with the web-search plugin). Only used when
/// the user has saved an API key; everything sent here is the shared content and
/// the conversation, and the response is web-grounded.
struct OpenRouterClient: Sendable {

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct ChatMessage: Sendable {
        enum Role: String { case system, user, assistant }
        let role: Role
        let content: String
    }

    /// A web-researched section in the same shape the on-device brief uses.
    struct ResearchSection: Decodable, Sendable {
        let title: String
        let body: String
        let icon: String
        let url: String?
    }

    let apiKey: String
    var model: String = OpenRouterKeyStore.model

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    // MARK: - Research (structured, web-grounded sections)

    func research(context: String, existingSummary: String?, kind: LinkPreview.Kind) async throws -> [ResearchSection] {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "sections": [
                    "type": "array",
                    "minItems": 1,
                    "maxItems": 3,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "title": ["type": "string", "description": "Two to four word title, e.g. 'People praising Matic', 'Latest news'."],
                            "body": ["type": "string", "description": "One to three plain sentences. Name the sources (publications, sites) inline when it helps. No markdown."],
                            "icon": ["type": "string", "enum": ["buy", "reviews", "facts", "people", "date", "place", "warning", "link", "idea"]],
                            "url": ["type": ["string", "null"], "description": "The single most useful web page for this section, or null."],
                        ],
                        "required": ["title", "body", "icon", "url"],
                    ],
                ],
            ],
            "required": ["sections"],
        ]

        let focus: String
        switch kind {
        case .product: focus = "Find where to buy it and the current price, and what reviewers say (name the publications)."
        case .post: focus = "Find what the thing discussed actually is, recent news about it, and where to get it if it's a product."
        case .article: focus = "Find the latest developments and other credible coverage of the same story."
        case .page: focus = "Find the most useful recent context about this page's subject."
        }

        let system = """
        You are Dia, a research assistant inside an iOS share sheet. The user shared the content below. \
        Search the web and return one to three sections that add what the content itself doesn't say. \
        \(focus) Be concrete and current; never repeat the existing summary. Plain text only.
        """
        var user = "SHARED CONTENT:\n\(context)"
        if let existingSummary, !existingSummary.isEmpty {
            user += "\n\nEXISTING SUMMARY (do not repeat):\n\(existingSummary)"
        }

        var body = requestBody(messages: [.init(role: .system, content: system), .init(role: .user, content: user)], stream: false)
        body["response_format"] = [
            "type": "json_schema",
            "json_schema": ["name": "research", "strict": true, "schema": schema],
        ]

        let data = try await send(body)
        let completion = try JSONDecoder().decode(Completion.self, from: data)
        guard let text = completion.choices.first?.message?.content, let json = text.data(using: .utf8) else {
            throw Failure(message: "OpenRouter returned an empty answer.")
        }
        let decoded = try JSONDecoder().decode(ResearchEnvelope.self, from: json)
        return decoded.sections
    }

    // MARK: - Chat (streamed, web-grounded)

    func streamAnswer(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(requestBody(messages: messages, stream: true))
                    request.timeoutInterval = 60
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var collected = Data()
                        for try await byte in bytes { collected.append(byte) }
                        throw Failure(message: Self.describe(status: http.statusCode, data: collected))
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else { continue }
                        if let delta = chunk.choices.first?.delta?.content, !delta.isEmpty {
                            continuation.yield(delta)
                        }
                        if let error = chunk.error { throw Failure(message: error.message) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Transport

    private func requestBody(messages: [ChatMessage], stream: Bool) -> [String: Any] {
        [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "plugins": [["id": "web", "max_results": 5]],
            "stream": stream,
            "max_tokens": 700,
        ]
    }

    private func makeRequest(_ body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://jonasleupe.com/little-dia", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Little Dia", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func send(_ body: [String: Any]) async throws -> Data {
        let request = try makeRequest(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure(message: "No response from OpenRouter.") }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure(message: Self.describe(status: http.statusCode, data: data))
        }
        return data
    }

    private static func describe(status: Int, data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return "OpenRouter: \(envelope.error.message)"
        }
        switch status {
        case 401: return "OpenRouter rejected the API key. Check it in the Little Dia app."
        case 402: return "OpenRouter: insufficient credits."
        case 429: return "OpenRouter is rate-limiting requests. Try again in a moment."
        default: return "OpenRouter returned HTTP \(status)."
        }
    }

    // MARK: - Wire types

    private struct Completion: Decodable {
        let choices: [Choice]
        struct Choice: Decodable { let message: Message? }
        struct Message: Decodable { let content: String? }
    }

    private struct StreamChunk: Decodable {
        let choices: [Choice]
        let error: APIError?
        struct Choice: Decodable { let delta: Delta? }
        struct Delta: Decodable { let content: String? }
    }

    private struct ResearchEnvelope: Decodable { let sections: [ResearchSection] }
    private struct APIError: Decodable { let message: String }
    private struct ErrorEnvelope: Decodable { let error: APIError }
}
