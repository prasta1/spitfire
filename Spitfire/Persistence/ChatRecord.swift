import Foundation
import SwiftData

/// SwiftData persistence record for a chat session.
///
/// Mirrors the `chats` table in the Flutter app. Owns a cascade-deleted
/// collection of `MessageRecord`. Conversion helpers map to/from the
/// `OllamaChat` domain struct used by the API client.
///
/// Generation options are flattened to scalar properties rather than stored
/// as a Codable struct or JSON blob. SwiftData on iOS 17/18 silently fails
/// to roundtrip Data/Codable values inside `@Model`, so primitives are the
/// only reliable path. The `options` computed property hides the verbosity.
@Model
final class ChatRecord {
    var id: UUID = UUID()
    var model: String = ""
    var title: String = "New Chat"
    var systemPrompt: String?
    var createdAt: Date = Date()

    // Flattened OllamaChatOptions fields. Defaults match Ollama's defaults.
    var optMirostat: Int = 0
    var optMirostatEta: Double = 0.1
    var optMirostatTau: Double = 5.0
    var optContextSize: Int = 2048
    var optRepeatLastN: Int = 64
    var optRepeatPenalty: Double = 1.1
    var optTemperature: Double = 0.8
    var optSeed: Int = 0
    var optTailFreeSampling: Double = 1.0
    var optMaxTokens: Int = -1
    var optTopK: Int = 40
    var optTopP: Double = 0.9
    var optMinP: Double = 0.0

    var folder: FolderRecord?

    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.chat)
    var messages: [MessageRecord] = []

    init(
        id: UUID = UUID(),
        model: String,
        title: String = "New Chat",
        systemPrompt: String? = nil,
        options: OllamaChatOptions = OllamaChatOptions(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.model = model
        self.title = title
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.optMirostat = options.mirostat
        self.optMirostatEta = options.mirostatEta
        self.optMirostatTau = options.mirostatTau
        self.optContextSize = options.contextSize
        self.optRepeatLastN = options.repeatLastN
        self.optRepeatPenalty = options.repeatPenalty
        self.optTemperature = options.temperature
        self.optSeed = options.seed
        self.optTailFreeSampling = options.tailFreeSampling
        self.optMaxTokens = options.maxTokens
        self.optTopK = options.topK
        self.optTopP = options.topP
        self.optMinP = options.minP
    }
}

extension ChatRecord {
    var options: OllamaChatOptions {
        get {
            var o = OllamaChatOptions()
            o.mirostat = optMirostat
            o.mirostatEta = optMirostatEta
            o.mirostatTau = optMirostatTau
            o.contextSize = optContextSize
            o.repeatLastN = optRepeatLastN
            o.repeatPenalty = optRepeatPenalty
            o.temperature = optTemperature
            o.seed = optSeed
            o.tailFreeSampling = optTailFreeSampling
            o.maxTokens = optMaxTokens
            o.topK = optTopK
            o.topP = optTopP
            o.minP = optMinP
            return o
        }
        set {
            optMirostat = newValue.mirostat
            optMirostatEta = newValue.mirostatEta
            optMirostatTau = newValue.mirostatTau
            optContextSize = newValue.contextSize
            optRepeatLastN = newValue.repeatLastN
            optRepeatPenalty = newValue.repeatPenalty
            optTemperature = newValue.temperature
            optSeed = newValue.seed
            optTailFreeSampling = newValue.tailFreeSampling
            optMaxTokens = newValue.maxTokens
            optTopK = newValue.topK
            optTopP = newValue.topP
            optMinP = newValue.minP
        }
    }

    static func make(from chat: OllamaChat) -> ChatRecord {
        ChatRecord(
            id: chat.id,
            model: chat.model,
            title: chat.title,
            systemPrompt: chat.systemPrompt,
            options: chat.options
        )
    }

    func toDomain() -> OllamaChat {
        OllamaChat(
            id: id,
            model: model,
            title: title,
            systemPrompt: systemPrompt,
            options: options
        )
    }

    /// Messages in chronological order — matches the Flutter `getMessages`
    /// behavior (ORDER BY timestamp ASC).
    var orderedMessages: [MessageRecord] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    /// Full conversation formatted as Markdown, suitable for sharing or export.
    var markdownTranscript: String {
        let dateStr = createdAt.formatted(date: .abbreviated, time: .omitted)
        var lines: [String] = [
            "# \(title)",
            "**Model:** \(model)  **Date:** \(dateStr)",
            "",
        ]
        for message in orderedMessages where message.role != .system {
            let label = message.role == .user ? "**User**" : "**Assistant**"
            lines.append(label)
            lines.append("")
            lines.append(message.content)
            lines.append("")
            lines.append("---")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Full conversation as plain text (Markdown syntax stripped), suitable for export.
    var plainTextTranscript: String {
        let dateStr = createdAt.formatted(date: .abbreviated, time: .omitted)
        var lines: [String] = [
            title,
            "Model: \(model)  Date: \(dateStr)",
            "",
        ]
        for message in orderedMessages where message.role != .system {
            let label = message.role == .user ? "User" : "Assistant"
            let plain = message.plainContent
            lines.append("[\(label)]")
            lines.append(plain)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
