import Foundation

/// HTTP client for the OpenRouter API (openrouter.ai/api/v1).
/// Implements `SpitfireClient` so it can substitute for `OllamaClient` throughout the app.
struct OpenRouterClient {
    static let baseURL = URL(string: "https://openrouter.ai/api/v1")!

    var apiKey: String
    var session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - Wire types

    private struct ModelsResponse: Decodable {
        let data: [ModelEntry]

        struct ModelEntry: Decodable {
            let id: String
            let name: String?
            let description: String?
            let architecture: Architecture?
            let pricing: Pricing?

            struct Architecture: Decodable {
                let modality: String?
                let inputModalities: [String]?
                let outputModalities: [String]?

                enum CodingKeys: String, CodingKey {
                    case modality
                    case inputModalities = "input_modalities"
                    case outputModalities = "output_modalities"
                }
            }

            struct Pricing: Decodable {
                let prompt: String?
                let completion: String?
            }
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
        let usage: Usage?

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

        struct Usage: Decodable {
            let completionTokens: Int?

            enum CodingKeys: String, CodingKey {
                case completionTokens = "completion_tokens"
            }
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

    private func authorizedRequest(for url: URL, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

extension OpenRouterClient: SpitfireClient {
    func listModels() async throws -> [OllamaModel] {
        let url = Self.baseURL.appending(path: "models")
        let (data, _) = try await session.data(for: authorizedRequest(for: url))
        let response = try Self.decoder.decode(ModelsResponse.self, from: data)

        let now = Date()
        return response.data.compactMap { entry -> OllamaModel? in
            // Filter to text-output models only
            let outputsText: Bool
            if let arch = entry.architecture {
                if let outputMods = arch.outputModalities {
                    outputsText = outputMods.contains("text")
                } else if let modality = arch.modality {
                    outputsText = modality.contains("->text")
                } else {
                    outputsText = true
                }
            } else {
                outputsText = true
            }
            guard outputsText, !entry.id.lowercased().contains("embed") else { return nil }

            let hasVision = entry.architecture?.inputModalities?.contains("image") ?? false
            let caps = ModelCapabilities(hasVision ? ["completion", "vision"] : ["completion"])
            let isFree = entry.id.hasSuffix(":free")
                || (entry.pricing?.prompt == "0" && entry.pricing?.completion == "0")
            return OllamaModel(
                name: entry.id,
                model: entry.id,
                modifiedAt: now,
                size: 0,
                digest: entry.id,
                parameterSize: "",
                capabilities: caps,
                isFree: isFree
            )
        }
    }

    func chat(messages: [OllamaMessage], in chat: OllamaChat) async throws -> OllamaMessage {
        let body = chatRequestBody(messages: messages, in: chat, stream: false)
        var req = authorizedRequest(for: Self.baseURL.appending(path: "chat/completions"), method: "POST")
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
                    var req = authorizedRequest(for: Self.baseURL.appending(path: "chat/completions"), method: "POST")
                    req.httpBody = try Self.encoder.encode(body)

                    let streamStart = Date()
                    let (bytes, urlResponse) = try await session.bytes(for: req)
                    if let http = urlResponse as? HTTPURLResponse, http.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes { errorData.append(byte) }
                        throw OllamaError.http(status: http.statusCode, body: String(data: errorData, encoding: .utf8))
                    }
                    var completionTokens: Int? = nil

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        let chunk = try Self.decoder.decode(ChatChunk.self, from: data)
                        if let tokens = chunk.usage?.completionTokens {
                            completionTokens = tokens
                        }
                        guard let choice = chunk.choices.first else { continue }

                        let content = choice.delta.content ?? ""
                        let isDone = choice.finishReason == "stop"

                        var metadata: OllamaMessage.Metadata? = nil
                        if isDone {
                            // Measure wall-clock generation time and attach token count.
                            // evalDuration is used as the denominator for tok/s in MessageRecord.statsText.
                            let totalNs = Int(Date().timeIntervalSince(streamStart) * 1_000_000_000)
                            metadata = OllamaMessage.Metadata(
                                done: true,
                                totalDuration: totalNs,
                                evalCount: completionTokens,
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

    /// Implements title-generation prompt via a single-turn chat completion.
    func generate(prompt: String, in chat: OllamaChat) async throws -> OllamaMessage {
        let userMessage = OllamaMessage(content: prompt, role: .user)
        return try await self.chat(messages: [userMessage], in: chat)
    }
}
