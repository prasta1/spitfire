import Foundation

/// HTTP client for the LM Studio local server (OpenAI-compatible API).
/// LM Studio exposes its currently-loaded model(s) at http://localhost:1234/v1
/// using the same SSE streaming format as OpenRouter/OpenAI.
struct LMStudioClient {
    /// Base host URL, e.g. http://localhost:1234. The /v1 path is appended internally.
    var baseURL: URL
    var session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:1234")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private var apiBase: URL { baseURL.appending(path: "v1") }

    // MARK: - Wire types (OpenAI-compatible)

    private struct ModelsResponse: Decodable {
        let data: [ModelEntry]

        struct ModelEntry: Decodable {
            let id: String
        }
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let temperature: Double?
        let maxTokens: Int?

        enum CodingKeys: String, CodingKey {
            case model, messages, stream, temperature
            case maxTokens = "max_tokens"
        }

        struct ChatMessage: Encodable {
            let role: String
            let content: String
        }
    }

    private struct ChatChunk: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let delta: Delta
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }

        struct Delta: Decodable {
            let content: String?
        }
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String
        }
    }

    // MARK: - Helpers

    private func makeRequest(for url: URL, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    private func chatRequestBody(messages: [OllamaMessage], in chat: OllamaChat, stream: Bool) -> ChatRequest {
        var wireMessages: [ChatRequest.ChatMessage] = []
        if let system = chat.systemPrompt, !system.isEmpty {
            wireMessages.append(.init(role: "system", content: system))
        }
        wireMessages += messages.map { .init(role: $0.role.rawValue, content: $0.content) }
        let maxTok = chat.options.maxTokens > 0 ? chat.options.maxTokens : nil
        return ChatRequest(
            model: chat.model,
            messages: wireMessages,
            stream: stream,
            temperature: chat.options.temperature,
            maxTokens: maxTok
        )
    }
}

// MARK: - SpitfireClient

extension LMStudioClient: SpitfireClient {
    func listModels() async throws -> [OllamaModel] {
        let url = apiBase.appending(path: "models")
        let (data, urlResponse) = try await session.data(for: makeRequest(for: url))
        if let http = urlResponse as? HTTPURLResponse, http.statusCode != 200 {
            throw OllamaError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        let response = try Self.decoder.decode(ModelsResponse.self, from: data)
        let now = Date()
        return response.data.map { entry in
            OllamaModel(
                name: entry.id,
                model: entry.id,
                modifiedAt: now,
                size: 0,
                digest: entry.id,
                parameterSize: "",
                capabilities: ModelCapabilities(["completion"]),
                isFree: false
            )
        }
    }

    func chat(messages: [OllamaMessage], in chat: OllamaChat) async throws -> OllamaMessage {
        let body = chatRequestBody(messages: messages, in: chat, stream: false)
        var req = makeRequest(for: apiBase.appending(path: "chat/completions"), method: "POST")
        req.httpBody = try Self.encoder.encode(body)
        let (data, urlResponse) = try await session.data(for: req)
        if let http = urlResponse as? HTTPURLResponse, http.statusCode != 200 {
            throw OllamaError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        let response = try Self.decoder.decode(ChatResponse.self, from: data)
        let content = response.choices.first?.message.content ?? ""
        return OllamaMessage(content: content, role: .assistant)
    }

    func chatStream(messages: [OllamaMessage], in chat: OllamaChat) -> AsyncThrowingStream<OllamaMessage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = chatRequestBody(messages: messages, in: chat, stream: true)
                    var req = makeRequest(for: apiBase.appending(path: "chat/completions"), method: "POST")
                    req.httpBody = try Self.encoder.encode(body)

                    let streamStart = Date()
                    let (bytes, urlResponse) = try await session.bytes(for: req)
                    if let http = urlResponse as? HTTPURLResponse, http.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes { errorData.append(byte) }
                        throw OllamaError.http(status: http.statusCode, body: String(data: errorData, encoding: .utf8))
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        let chunk = try Self.decoder.decode(ChatChunk.self, from: data)
                        guard let choice = chunk.choices.first else { continue }

                        let content = choice.delta.content ?? ""
                        let isDone = choice.finishReason != nil

                        var metadata: OllamaMessage.Metadata? = nil
                        if isDone {
                            let totalNs = Int(Date().timeIntervalSince(streamStart) * 1_000_000_000)
                            metadata = OllamaMessage.Metadata(
                                done: true,
                                totalDuration: totalNs,
                                evalCount: nil,
                                evalDuration: totalNs
                            )
                        }

                        continuation.yield(OllamaMessage(content: content, role: .assistant, metadata: metadata))
                        if isDone { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func generate(prompt: String, in chat: OllamaChat) async throws -> OllamaMessage {
        let userMessage = OllamaMessage(content: prompt, role: .user)
        return try await self.chat(messages: [userMessage], in: chat)
    }
}
