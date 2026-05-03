import Foundation

/// A model installed on the Ollama server. Combines data from /api/tags and
/// (optionally) /api/show.
struct OllamaModel: Identifiable, Equatable {
    let name: String
    let model: String
    let modifiedAt: Date
    let size: Int
    let digest: String
    let parameterSize: String
    let capabilities: ModelCapabilities?

    var id: String { digest }
}

/// Capabilities reported by /api/show. Older Ollama versions don't return
/// this field; missing data resolves to all-false.
struct ModelCapabilities: Equatable {
    var completion: Bool = false
    var vision: Bool = false
    var tools: Bool = false
    var embedding: Bool = false
    var thinking: Bool = false

    init(_ list: [String] = []) {
        self.completion = list.contains("completion")
        self.vision = list.contains("vision")
        self.tools = list.contains("tools")
        self.embedding = list.contains("embedding")
        self.thinking = list.contains("thinking")
    }
}
