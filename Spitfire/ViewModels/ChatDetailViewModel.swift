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
    var pendingImage: Data?
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
        let image = pendingImage
        guard (!trimmed.isEmpty || image != nil), !isStreaming else { return }
        inputText = ""
        pendingImage = nil
        errorMessage = nil

        let userMessage = MessageRecord(content: trimmed, role: .user, imagesData: image)
        chat.messages.append(userMessage)

        let assistantMessage = MessageRecord(content: "", role: .assistant, model: chat.model)
        chat.messages.append(assistantMessage)
        try? context.save()

        // Generate title immediately after first user message (before AI responds)
        if chat.title == "New Chat" && chat.messages.count == 2 {
            Task {
                await generateTitle()
            }
        }

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
                    if chunk.metadata?.done == true {
                        assistantMessage.evalCount = chunk.metadata?.evalCount
                        assistantMessage.evalDuration = chunk.metadata?.evalDuration
                        assistantMessage.totalDuration = chunk.metadata?.totalDuration
                        break
                    }
                }
                try? self.context.save()
            } catch is CancellationError {
                try? self.context.save()
            } catch {
                self.errorMessage = error.localizedDescription
                if assistantMessage.content.isEmpty {
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

    /// Re-streams the most recent assistant message in place. The user
    /// message immediately preceding it stays put; we just empty the
    /// assistant content and ask the server again with the same history.
    func regenerateLastAssistant() {
        guard !isStreaming else { return }
        guard let last = chat.orderedMessages.last(where: { $0.role == .assistant }) else { return }

        last.content = ""
        errorMessage = nil

        let history = chat
            .orderedMessages
            .filter { $0.id != last.id }
            .map { $0.toDomain() }
        let domainChat = chat.toDomain()

        isStreaming = true

        streamTask = Task { [client] in
            defer { self.isStreaming = false }
            do {
                let stream = client.chatStream(messages: history, in: domainChat)
                for try await chunk in stream {
                    try Task.checkCancellation()
                    last.content += chunk.content
                    if chunk.metadata?.done == true {
                        last.evalCount = chunk.metadata?.evalCount
                        last.evalDuration = chunk.metadata?.evalDuration
                        last.totalDuration = chunk.metadata?.totalDuration
                        break
                    }
                }
                try? self.context.save()
            } catch is CancellationError {
                try? self.context.save()
            } catch {
                self.errorMessage = error.localizedDescription
                try? self.context.save()
            }
        }
    }

    /// Generates a title after the first AI response completes.
    /// Runs in background - non-blocking.
    func generateTitle() async {
        guard chat.title == "New Chat" else { return }

        guard let userMsg = chat.orderedMessages.first(where: { $0.role == .user })?.content,
              !userMsg.isEmpty else {
            setFallbackTitle()
            return
        }

        let prompt = "Generate a short title (3-5 words) for a conversation that starts with: \"\(userMsg)\". Only return the title."

        do {
            let response = try await client.generate(prompt: prompt, in: chat.toDomain())
            let title = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(50)
            if !title.isEmpty {
                chat.title = String(title)
                try? context.save()
            } else {
                setFallbackTitle()
            }
        } catch {
            setFallbackTitle()
        }
    }

    private func setFallbackTitle() {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy"
        chat.title = "New Chat - \(formatter.string(from: Date()))"
        try? context.save()
    }
}
