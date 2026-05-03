import Foundation
import Observation
import SwiftData

/// View model that orchestrates streaming a chat completion into a
/// `ChatRecord`. Owns no UI state beyond the input field and a streaming
/// flag — message rendering reads directly from the SwiftData record so
/// SwiftUI updates automatically as chunks arrive.
@MainActor
@Observable
final class ChatDetailViewModel {
    let chat: ChatRecord
    var inputText: String = ""
    var isStreaming: Bool = false
    var errorMessage: String?

    private let context: ModelContext
    private let client: OllamaClient
    private var streamTask: Task<Void, Never>?

    init(chat: ChatRecord, context: ModelContext, client: OllamaClient) {
        self.chat = chat
        self.context = context
        self.client = client
    }

    /// Sends `inputText` to the server and starts streaming the assistant's
    /// reply into a fresh `MessageRecord` attached to the chat.
    func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        inputText = ""
        errorMessage = nil

        let userMessage = MessageRecord(content: trimmed, role: .user)
        chat.messages.append(userMessage)

        let assistantMessage = MessageRecord(content: "", role: .assistant, model: chat.model)
        chat.messages.append(assistantMessage)
        try? context.save()

        // Snapshot the conversation history (everything before the empty
        // assistant placeholder) so we don't include the placeholder itself
        // in the request payload.
        let history = chat
            .orderedMessages
            .filter { $0.id != assistantMessage.id }
            .map { $0.toDomain() }
        let domainChat = chat.toDomain()

        isStreaming = true

        streamTask = Task { [client] in
            defer { self.isStreaming = false }

            do {
                let stream = client.chatStream(messages: history, in: domainChat)
                for try await chunk in stream {
                    try Task.checkCancellation()
                    assistantMessage.content += chunk.content
                    if chunk.metadata?.done == true { break }
                }
                try? self.context.save()
            } catch is CancellationError {
                try? self.context.save()
            } catch {
                self.errorMessage = error.localizedDescription
                if assistantMessage.content.isEmpty {
                    // Drop the placeholder so the user isn't left with a
                    // confusing empty bubble after a failed request.
                    self.chat.messages.removeAll { $0.id == assistantMessage.id }
                    self.context.delete(assistantMessage)
                }
                try? self.context.save()
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
    }
}
