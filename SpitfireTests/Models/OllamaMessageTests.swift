import XCTest
@testable import Spitfire

final class OllamaMessageTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            return OllamaClient.parseDate(raw) ?? Date()
        }
        return d
    }

    func test_decodesChatResponse() throws {
        let json = """
        {
          "model": "llama3.2",
          "created_at": "2024-08-04T08:52:19.385Z",
          "message": { "role": "assistant", "content": "Hello!" },
          "done": true,
          "done_reason": "stop",
          "total_duration": 1234,
          "eval_count": 5
        }
        """.data(using: .utf8)!

        let message = try decoder().decode(OllamaMessage.self, from: json)
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.content, "Hello!")
        XCTAssertEqual(message.model, "llama3.2")
        XCTAssertEqual(message.metadata?.done, true)
        XCTAssertEqual(message.metadata?.doneReason, "stop")
        XCTAssertEqual(message.metadata?.totalDuration, 1234)
        XCTAssertEqual(message.metadata?.evalCount, 5)
    }

    func test_decodesGenerateResponse() throws {
        let json = """
        {
          "model": "llama3.2",
          "created_at": "2024-08-04T08:52:19.385406Z",
          "response": "A short title",
          "done": true
        }
        """.data(using: .utf8)!

        let message = try decoder().decode(OllamaMessage.self, from: json)
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.content, "A short title")
        XCTAssertEqual(message.metadata?.done, true)
    }

    func test_decodesStreamingChunkWithoutMetadata() throws {
        let json = """
        {
          "model": "llama3.2",
          "created_at": "2024-08-04T08:52:19.000Z",
          "message": { "role": "assistant", "content": "Hel" },
          "done": false
        }
        """.data(using: .utf8)!

        let message = try decoder().decode(OllamaMessage.self, from: json)
        XCTAssertEqual(message.content, "Hel")
        XCTAssertEqual(message.metadata?.done, false)
        XCTAssertNil(message.metadata?.totalDuration)
    }

    func test_throwsOnMissingMessageAndResponse() {
        let json = """
        { "model": "llama3.2", "created_at": "2024-08-04T08:52:19.385Z" }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder().decode(OllamaMessage.self, from: json))
    }
}
