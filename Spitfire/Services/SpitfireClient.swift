import Foundation

/// Shared interface for chat backends (Ollama, OpenRouter, etc.).
/// Views and view models depend on this protocol; concrete clients are hidden behind it.
protocol SpitfireClient {
    /// Single-shot chat completion.
    func chat(messages: [OllamaMessage], in chat: OllamaChat) async throws -> OllamaMessage
    /// Streaming chat completion, yielding partial assistant messages as chunks arrive.
    func chatStream(messages: [OllamaMessage], in chat: OllamaChat) -> AsyncThrowingStream<OllamaMessage, Error>
    /// One-shot prompt completion — used for utility flows like title generation.
    func generate(prompt: String, in chat: OllamaChat) async throws -> OllamaMessage
    /// Lists available models for the backend.
    func listModels() async throws -> [OllamaModel]
}

// OllamaClient already implements all four methods — just declare conformance.
extension OllamaClient: SpitfireClient {}
