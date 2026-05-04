import Foundation

/// Error thrown by the Ollama HTTP client.
enum OllamaError: LocalizedError, Equatable {
    case modelNotFound(String)
    case internalServerError
    case invalidResponse
    case http(status: Int, body: String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let model):
            return "\(model) not found on the server."
        case .internalServerError:
            return "Internal server error."
        case .invalidResponse:
            return "Invalid response from server."
        case .http(let status, let body):
            return "HTTP \(status)\(body.map { ": \($0)" } ?? "")"
        case .decoding(let message):
            return "Failed to decode response: \(message)"
        }
    }
}
