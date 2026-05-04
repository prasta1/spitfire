import Foundation

/// A single chat message exchanged with the Ollama server.
///
/// Decodable from both `/api/chat` responses (nested `message` object) and
/// `/api/generate` responses (flat `response` field). Outbound encoding is
/// handled by the wire layer in `OllamaClient`, not by this type.
struct OllamaMessage: Identifiable, Equatable {
    let id: UUID
    var content: String
    var images: [Data]?
    var createdAt: Date
    var role: Role
    var model: String?
    var metadata: Metadata?

    init(
        id: UUID = UUID(),
        content: String,
        role: Role,
        images: [Data]? = nil,
        createdAt: Date = Date(),
        model: String? = nil,
        metadata: Metadata? = nil
    ) {
        self.id = id
        self.content = content
        self.role = role
        self.images = images
        self.createdAt = createdAt
        self.model = model
        self.metadata = metadata
    }

    enum Role: String, Codable, CaseIterable, Equatable {
        case user
        case assistant
        case system
    }

    /// Generation metadata returned by the server. All fields optional —
    /// only the final streaming chunk includes timing/eval counters.
    struct Metadata: Codable, Equatable {
        var done: Bool?
        var doneReason: String?
        var totalDuration: Int?
        var loadDuration: Int?
        var promptEvalCount: Int?
        var promptEvalDuration: Int?
        var evalCount: Int?
        var evalDuration: Int?

        enum CodingKeys: String, CodingKey {
            case done
            case doneReason = "done_reason"
            case totalDuration = "total_duration"
            case loadDuration = "load_duration"
            case promptEvalCount = "prompt_eval_count"
            case promptEvalDuration = "prompt_eval_duration"
            case evalCount = "eval_count"
            case evalDuration = "eval_duration"
        }
    }
}

extension OllamaMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case message
        case response
        case createdAt = "created_at"
        case model
    }

    private enum NestedMessageKeys: String, CodingKey {
        case role
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // /api/chat shape: { "message": { "role", "content" }, ... }
        if let nested = try? container.nestedContainer(keyedBy: NestedMessageKeys.self, forKey: .message) {
            self.content = try nested.decode(String.self, forKey: .content)
            self.role = try nested.decode(Role.self, forKey: .role)
        }
        // /api/generate shape: { "response": "...", ... }
        else if let response = try? container.decode(String.self, forKey: .response) {
            self.content = response
            self.role = .assistant
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .message,
                in: container,
                debugDescription: "Expected either 'message' or 'response' field"
            )
        }

        self.id = UUID()
        self.images = nil
        self.createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.metadata = try? Metadata(from: decoder)
    }
}
