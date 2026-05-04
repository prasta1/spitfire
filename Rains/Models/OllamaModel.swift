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

/// A model currently loaded in Ollama's VRAM, from /api/ps.
struct RunningModel: Identifiable, Equatable {
    let name: String
    let sizeVram: Int
    let parameterSize: String
    let quantization: String

    var id: String { name }

    /// Human-readable VRAM usage, e.g. "14.9 GB".
    var formattedVram: String {
        let gb = Double(sizeVram) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(sizeVram) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

/// Progress update from /api/pull streaming response.
struct PullProgress: Equatable {
    let status: String
    let total: Int64
    let completed: Int64

    /// Fraction complete (0.0–1.0), or nil if totals aren't available yet.
    var fraction: Double? {
        guard total > 0 else { return nil }
        return Double(completed) / Double(total)
    }
}

/// A model available in the Ollama registry (from ollama.com search).
struct RegistryModel: Identifiable, Equatable {
    let name: String
    let description: String
    let sizes: [String]
    let capabilities: [String]

    var id: String { name }

    /// Formatted sizes string, e.g. "3B, 8B, 30B"
    var sizesLabel: String {
        sizes.map { $0.uppercased() }.joined(separator: ", ")
    }

    /// Capability badges reusing the same SF Symbol mapping.
    var badgeSymbols: [(symbol: String, label: String)] {
        var result: [(String, String)] = []
        if capabilities.contains("vision")   { result.append(("eye", "Vision")) }
        if capabilities.contains("audio")    { result.append(("waveform", "Audio")) }
        if capabilities.contains("tools")    { result.append(("wrench", "Tools")) }
        if capabilities.contains("thinking") { result.append(("brain", "Thinking")) }
        return result
    }
}

/// Capabilities reported by /api/show. Older Ollama versions don't return
/// this field; missing data resolves to all-false.
struct ModelCapabilities: Equatable {
    var completion: Bool = false
    var vision: Bool = false
    var tools: Bool = false
    var embedding: Bool = false
    var thinking: Bool = false
    var audio: Bool = false

    init(_ list: [String] = []) {
        self.completion = list.contains("completion")
        self.vision = list.contains("vision")
        self.tools = list.contains("tools")
        self.embedding = list.contains("embedding")
        self.thinking = list.contains("thinking")
        self.audio = list.contains("audio")
    }

    /// SF Symbol name/label pairs for active capabilities (excludes completion as near-universal).
    var badgeSymbols: [(symbol: String, label: String)] {
        var result: [(String, String)] = []
        if vision   { result.append(("eye", "Vision")) }
        if audio    { result.append(("waveform", "Audio")) }
        if tools    { result.append(("wrench", "Tools")) }
        if thinking { result.append(("brain", "Thinking")) }
        if embedding { result.append(("square.grid.3x3", "Embedding")) }
        return result
    }
}
