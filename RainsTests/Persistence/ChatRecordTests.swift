import XCTest
import SwiftData
@testable import Rains

@MainActor
final class ChatRecordTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try SpitfireModelContainer.makeInMemory()
        return ModelContext(container)
    }

    func test_persistsAndFetchesChat() throws {
        let context = try makeContext()

        var options = OllamaChatOptions()
        options.temperature = 0.42

        let chat = ChatRecord(
            model: "llama3.2",
            title: "Test chat",
            systemPrompt: "Be terse",
            options: options
        )
        context.insert(chat)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ChatRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].model, "llama3.2")
        XCTAssertEqual(fetched[0].title, "Test chat")
        XCTAssertEqual(fetched[0].systemPrompt, "Be terse")
        XCTAssertEqual(fetched[0].options.temperature, 0.42)
    }

    func test_cascadeDeletesMessages() throws {
        let context = try makeContext()

        let chat = ChatRecord(model: "llama3.2")
        let m1 = MessageRecord(content: "Hi", role: .user)
        let m2 = MessageRecord(content: "Hello!", role: .assistant)
        chat.messages = [m1, m2]
        context.insert(chat)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<MessageRecord>()).count, 2)

        context.delete(chat)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatRecord>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MessageRecord>()).count, 0)
    }

    func test_orderedMessagesSortsByCreatedAt() throws {
        let context = try makeContext()

        let chat = ChatRecord(model: "llama3.2")
        let now = Date()
        let m1 = MessageRecord(content: "first", role: .user, createdAt: now)
        let m2 = MessageRecord(content: "second", role: .assistant, createdAt: now.addingTimeInterval(1))
        let m3 = MessageRecord(content: "third", role: .user, createdAt: now.addingTimeInterval(2))
        // Insert out of order to make sure we don't rely on insertion order
        chat.messages = [m3, m1, m2]
        context.insert(chat)
        try context.save()

        XCTAssertEqual(chat.orderedMessages.map(\.content), ["first", "second", "third"])
    }

    func test_roundTripThroughDomainTypes() {
        let chat = OllamaChat(
            model: "llama3.2",
            title: "Trip",
            systemPrompt: "system"
        )
        let record = ChatRecord.make(from: chat)
        let restored = record.toDomain()

        XCTAssertEqual(restored.id, chat.id)
        XCTAssertEqual(restored.model, chat.model)
        XCTAssertEqual(restored.title, chat.title)
        XCTAssertEqual(restored.systemPrompt, chat.systemPrompt)
        XCTAssertEqual(restored.options, chat.options)
    }
}
