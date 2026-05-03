import XCTest
import SwiftData
@testable import Rains

@MainActor
final class MessageRecordTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try RainsModelContainer.makeInMemory()
        return ModelContext(container)
    }

    func test_persistsAndFetchesMessage() throws {
        let context = try makeContext()
        let chat = ChatRecord(model: "llama3.2")
        let message = MessageRecord(
            content: "Hello",
            role: .user,
            model: "llama3.2"
        )
        chat.messages = [message]
        context.insert(chat)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MessageRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].content, "Hello")
        XCTAssertEqual(fetched[0].role, .user)
        XCTAssertEqual(fetched[0].chat?.id, chat.id)
    }

    func test_roundTripThroughDomainTypes() {
        let domain = OllamaMessage(content: "Hi", role: .assistant, model: "llama3.2")
        let record = MessageRecord.make(from: domain)
        let restored = record.toDomain()

        XCTAssertEqual(restored.id, domain.id)
        XCTAssertEqual(restored.content, domain.content)
        XCTAssertEqual(restored.role, domain.role)
        XCTAssertEqual(restored.model, domain.model)
    }

    func test_imageRoundTripThroughDomainTypes() {
        let imageData = Data("fake-image-bytes".utf8)
        let domain = OllamaMessage(
            content: "look",
            role: .user,
            images: [imageData]
        )
        let record = MessageRecord.make(from: domain)
        XCTAssertEqual(record.imagesData, imageData)

        let restored = record.toDomain()
        XCTAssertEqual(restored.images, [imageData])
    }
}
