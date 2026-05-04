import Foundation

/// A user-facing chat session: model selection, optional system prompt, and
/// generation options. Persistence is handled in Phase 2.
struct OllamaChat: Identifiable, Equatable {
    let id: UUID
    var model: String
    var title: String
    var systemPrompt: String?
    var options: OllamaChatOptions

    init(
        id: UUID = UUID(),
        model: String,
        title: String = "New Chat",
        systemPrompt: String? = nil,
        options: OllamaChatOptions = OllamaChatOptions()
    ) {
        self.id = id
        self.model = model
        self.title = title
        self.systemPrompt = systemPrompt
        self.options = options
    }
}

/// Generation options sent to Ollama in the `options` field of /api/chat
/// and /api/generate. Defaults match the Ollama defaults.
struct OllamaChatOptions: Codable, Equatable {
    var mirostat: Int = 0
    var mirostatEta: Double = 0.1
    var mirostatTau: Double = 5.0
    var contextSize: Int = 2048
    var repeatLastN: Int = 64
    var repeatPenalty: Double = 1.1
    var temperature: Double = 0.8
    var seed: Int = 0
    var tailFreeSampling: Double = 1.0
    var maxTokens: Int = -1
    var topK: Int = 40
    var topP: Double = 0.9
    var minP: Double = 0.0

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

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mirostat, forKey: .mirostat)
        try c.encode(mirostatEta, forKey: .mirostatEta)
        try c.encode(mirostatTau, forKey: .mirostatTau)
        try c.encode(contextSize, forKey: .contextSize)
        try c.encode(repeatLastN, forKey: .repeatLastN)
        try c.encode(repeatPenalty, forKey: .repeatPenalty)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(seed, forKey: .seed)
        try c.encode(tailFreeSampling, forKey: .tailFreeSampling)
        // -1 means "no limit" — omit so the server uses its own default rather than rejecting it as a Bad Request.
        if maxTokens > 0 {
            try c.encode(maxTokens, forKey: .maxTokens)
        }
        try c.encode(topK, forKey: .topK)
        try c.encode(topP, forKey: .topP)
        try c.encode(minP, forKey: .minP)
    }
}
