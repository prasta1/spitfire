import Foundation

/// HTTP client for an Ollama server. Concrete platform-agnostic API surface;
/// SwiftUI views and view models will hold one of these and call its methods.
struct OllamaClient {
    var baseURL: URL
    var session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:11434")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Public API

    /// Sends `messages` for completion against `chat`'s model and returns the
    /// final assistant message in a single response.
    func chat(messages: [OllamaMessage], in chat: OllamaChat) async throws -> OllamaMessage {
        let request = try makeChatRequest(messages: messages, chat: chat, stream: false)
        return try await sendSingle(request, modelName: chat.model)
    }

    /// Streams partial assistant messages as they arrive from /api/chat.
    func chatStream(messages: [OllamaMessage], in chat: OllamaChat) -> AsyncThrowingStream<OllamaMessage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeChatRequest(messages: messages, chat: chat, stream: true)
                    try await streamLines(request, modelName: chat.model, into: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One-shot completion of `prompt` against `chat`'s model. Used for
    /// utility flows like generating a chat title from the first message.
    func generate(prompt: String, in chat: OllamaChat) async throws -> OllamaMessage {
        let request = try makeGenerateRequest(prompt: prompt, chat: chat, stream: false)
        return try await sendSingle(request, modelName: chat.model)
    }

    /// Streaming variant of `generate`.
    func generateStream(prompt: String, in chat: OllamaChat) -> AsyncThrowingStream<OllamaMessage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeGenerateRequest(prompt: prompt, chat: chat, stream: true)
                    try await streamLines(request, modelName: chat.model, into: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Creates a new server-side model based on `chat`'s configuration. Only
    /// generation options that differ from the Ollama defaults are sent in
    /// `parameters`, matching the Flutter app's behavior. `messages` may be
    /// supplied to seed the conversation history of the new model.
    func createModel(
        _ name: String,
        from chat: OllamaChat,
        messages: [OllamaMessage]? = nil
    ) async throws {
        let diff = ChatOptionsDiff(chat.options)
        let wireMessages: [WireMessage]? = (messages?.isEmpty == false)
            ? messages?.map(WireMessage.init(_:))
            : nil

        let body = CreateRequest(
            model: name,
            from: chat.model,
            system: (chat.systemPrompt?.isEmpty == false) ? chat.systemPrompt : nil,
            parameters: diff.isEmpty ? nil : diff,
            messages: wireMessages,
            stream: false
        )

        var request = URLRequest(url: endpoint("/api/create"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, body: data, modelName: chat.model)
    }

    /// Deletes a model from the Ollama server.
    func deleteModel(_ name: String) async throws {
        var request = URLRequest(url: endpoint("/api/delete"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(["model": name])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, body: data, modelName: name)
    }

    /// Lists installed models. Each model is enriched with capabilities from
    /// /api/show; if /api/show fails (older servers, transient errors), the
    /// model is still returned with `capabilities == nil`.
    func listModels() async throws -> [OllamaModel] {
        let tagsURL = endpoint("/api/tags")
        let (data, response) = try await session.data(for: URLRequest(url: tagsURL))
        try validate(response: response, body: data, modelName: nil)

        let tags = try Self.decoder.decode(TagsResponse.self, from: data)

        return try await withThrowingTaskGroup(of: (Int, OllamaModel).self) { group in
            for (index, tag) in tags.models.enumerated() {
                group.addTask {
                    let capabilities = try? await self.showCapabilities(modelName: tag.name)
                    let domain = OllamaModel(
                        name: tag.name,
                        model: tag.model,
                        modifiedAt: tag.modifiedAt,
                        size: tag.size,
                        digest: tag.digest,
                        parameterSize: tag.details.parameterSize,
                        capabilities: capabilities
                    )
                    return (index, domain)
                }
            }
            var slots: [OllamaModel?] = Array(repeating: nil, count: tags.models.count)
            for try await (index, model) in group {
                slots[index] = model
            }
            return slots.compactMap { $0 }.filter { model in
                guard let caps = model.capabilities else { return true }
                return caps.completion
            }
        }
    }

    // MARK: Internals

    private func showCapabilities(modelName: String) async throws -> ModelCapabilities {
        var request = URLRequest(url: endpoint("/api/show"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(["model": modelName])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, body: data, modelName: modelName)
        let show = try Self.decoder.decode(ShowResponse.self, from: data)
        return ModelCapabilities(show.capabilities ?? [])
    }

    private func makeChatRequest(
        messages: [OllamaMessage],
        chat: OllamaChat,
        stream: Bool
    ) throws -> URLRequest {
        var wireMessages = messages.map(WireMessage.init(_:))
        if let prompt = chat.systemPrompt, !prompt.isEmpty {
            wireMessages.insert(WireMessage(role: "system", content: prompt, images: nil), at: 0)
        }
        let body = ChatRequest(model: chat.model, messages: wireMessages, options: chat.options, stream: stream)

        var request = URLRequest(url: endpoint("/api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(body)
        return request
    }

    private func makeGenerateRequest(
        prompt: String,
        chat: OllamaChat,
        stream: Bool
    ) throws -> URLRequest {
        let body = GenerateRequest(
            model: chat.model,
            prompt: prompt,
            system: (chat.systemPrompt?.isEmpty == false) ? chat.systemPrompt : nil,
            options: chat.options,
            stream: stream
        )

        var request = URLRequest(url: endpoint("/api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(body)
        return request
    }

    private func sendSingle(_ request: URLRequest, modelName: String) async throws -> OllamaMessage {
        let (data, response) = try await session.data(for: request)
        try validate(response: response, body: data, modelName: modelName)
        do {
            return try Self.decoder.decode(OllamaMessage.self, from: data)
        } catch {
            throw OllamaError.decoding(String(describing: error))
        }
    }

    private func streamLines(
        _ request: URLRequest,
        modelName: String,
        into continuation: AsyncThrowingStream<OllamaMessage, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        try validate(response: response, body: nil, modelName: modelName)

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            do {
                let message = try Self.decoder.decode(OllamaMessage.self, from: data)
                continuation.yield(message)
            } catch {
                throw OllamaError.decoding(String(describing: error))
            }
        }
        continuation.finish()
    }

    private func validate(response: URLResponse, body: Data?, modelName: String?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 404:
            throw OllamaError.modelNotFound(modelName ?? "model")
        case 500:
            throw OllamaError.internalServerError
        default:
            let bodyString = body.flatMap { String(data: $0, encoding: .utf8) }
            throw OllamaError.http(status: http.statusCode, body: bodyString)
        }
    }

    /// Joins a path against `baseURL`, preserving any path segments already on
    /// the base (so `http://host/ollama` + `/api/tags` → `http://host/ollama/api/tags`).
    func endpoint(_ path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        var segments = (components.path.split(separator: "/").map(String.init))
        segments.append(contentsOf: trimmed.split(separator: "/").map(String.init))
        components.path = "/" + segments.joined(separator: "/")
        return components.url ?? baseURL.appendingPathComponent(trimmed)
    }

    // MARK: JSON

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseDate(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(raw)"
            )
        }
        return d
    }()

    /// Parses Ollama's ISO8601 timestamps. Server uses microsecond precision
    /// (e.g. `2024-08-04T08:52:19.385406Z`); Foundation's ISO8601 parser caps
    /// at milliseconds, so we strip the fractional seconds before parsing.
    static func parseDate(_ raw: String) -> Date? {
        var s = raw
        if let dot = s.firstIndex(of: ".") {
            // Walk forward to find the timezone marker (Z, +, or -)
            var cursor = s.index(after: dot)
            while cursor < s.endIndex, s[cursor].isNumber {
                cursor = s.index(after: cursor)
            }
            s.removeSubrange(dot..<cursor)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: s)
    }
}

// MARK: Wire types (transport-only, not exposed publicly)

private struct ChatRequest: Encodable {
    let model: String
    let messages: [WireMessage]
    let options: OllamaChatOptions
    let stream: Bool
}

private struct GenerateRequest: Encodable {
    let model: String
    let prompt: String
    let system: String?
    let options: OllamaChatOptions
    let stream: Bool
}

private struct WireMessage: Encodable {
    let role: String
    let content: String
    let images: [String]?

    init(role: String, content: String, images: [String]?) {
        self.role = role
        self.content = content
        self.images = images
    }

    init(_ message: OllamaMessage) {
        self.role = message.role.rawValue
        self.content = message.content
        self.images = message.images?.map { $0.base64EncodedString() }
    }
}

private struct TagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
        let name: String
        let model: String
        let modifiedAt: Date
        let size: Int
        let digest: String
        let details: Details

        enum CodingKeys: String, CodingKey {
            case name, model, size, digest, details
            case modifiedAt = "modified_at"
        }

        struct Details: Decodable {
            let parameterSize: String

            enum CodingKeys: String, CodingKey {
                case parameterSize = "parameter_size"
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.parameterSize = (try? c.decode(String.self, forKey: .parameterSize)) ?? ""
            }
        }
    }
}

private struct ShowResponse: Decodable {
    let capabilities: [String]?
}

private struct CreateRequest: Encodable {
    let model: String
    let from: String
    let system: String?
    let parameters: ChatOptionsDiff?
    let messages: [WireMessage]?
    let stream: Bool
}

/// Encodes only the generation options that differ from the Ollama defaults.
/// Matches the Flutter `ApiCreateRequest.fromChat` behavior — sending the
/// full options dict would override the base model's defaults unnecessarily.
private struct ChatOptionsDiff: Encodable {
    let mirostat: Int?
    let mirostatEta: Double?
    let mirostatTau: Double?
    let contextSize: Int?
    let repeatLastN: Int?
    let repeatPenalty: Double?
    let temperature: Double?
    let seed: Int?
    let tailFreeSampling: Double?
    let maxTokens: Int?
    let topK: Int?
    let topP: Double?
    let minP: Double?

    init(_ options: OllamaChatOptions) {
        let d = OllamaChatOptions()
        self.mirostat = options.mirostat != d.mirostat ? options.mirostat : nil
        self.mirostatEta = options.mirostatEta != d.mirostatEta ? options.mirostatEta : nil
        self.mirostatTau = options.mirostatTau != d.mirostatTau ? options.mirostatTau : nil
        self.contextSize = options.contextSize != d.contextSize ? options.contextSize : nil
        self.repeatLastN = options.repeatLastN != d.repeatLastN ? options.repeatLastN : nil
        self.repeatPenalty = options.repeatPenalty != d.repeatPenalty ? options.repeatPenalty : nil
        self.temperature = options.temperature != d.temperature ? options.temperature : nil
        self.seed = options.seed != d.seed ? options.seed : nil
        self.tailFreeSampling = options.tailFreeSampling != d.tailFreeSampling ? options.tailFreeSampling : nil
        self.maxTokens = (options.maxTokens > 0 && options.maxTokens != d.maxTokens) ? options.maxTokens : nil
        self.topK = options.topK != d.topK ? options.topK : nil
        self.topP = options.topP != d.topP ? options.topP : nil
        self.minP = options.minP != d.minP ? options.minP : nil
    }

    var isEmpty: Bool {
        mirostat == nil && mirostatEta == nil && mirostatTau == nil &&
        contextSize == nil && repeatLastN == nil && repeatPenalty == nil &&
        temperature == nil && seed == nil && tailFreeSampling == nil &&
        maxTokens == nil && topK == nil && topP == nil && minP == nil
    }

    enum CodingKeys: String, CodingKey {
        case mirostat
        case mirostatEta = "mirostat_eta"
        case mirostatTau = "mirostat_tau"
        case contextSize = "num_ctx"
        case repeatLastN = "repeat_last_n"
        case repeatPenalty = "repeat_penalty"
        case temperature
        case seed
        case tailFreeSampling = "tfs_z"
        case maxTokens = "num_predict"
        case topK = "top_k"
        case topP = "top_p"
        case minP = "min_p"
    }
}
