import XCTest
@testable import Rains

final class OllamaClientTests: XCTestCase {
    private var client: OllamaClient!

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
        client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            session: URLProtocolStub.makeSession()
        )
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func test_chatSendsExpectedRequestBody() async throws {
        URLProtocolStub.responses["/api/chat"] = .init(body: """
        {
          "model": "llama3.2",
          "created_at": "2024-08-04T08:52:19.385Z",
          "message": { "role": "assistant", "content": "Hello back" },
          "done": true
        }
        """.data(using: .utf8)!)

        let chat = OllamaChat(model: "llama3.2", systemPrompt: "Be terse")
        let outgoing = OllamaMessage(content: "Hi", role: .user)
        let reply = try await client.chat(messages: [outgoing], in: chat)

        XCTAssertEqual(reply.content, "Hello back")
        XCTAssertEqual(reply.role, .assistant)

        let request = try XCTUnwrap(URLProtocolStub.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        let bodyData = try XCTUnwrap(request.bodyData())
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        XCTAssertEqual(body["model"] as? String, "llama3.2")
        XCTAssertEqual(body["stream"] as? Bool, false)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2, "system prompt should be prepended as a synthetic message")
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "Be terse")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, "Hi")
    }

    func test_chatOmitsSystemPromptWhenAbsent() async throws {
        URLProtocolStub.responses["/api/chat"] = .init(body: """
        {
          "model": "llama3.2",
          "created_at": "2024-08-04T08:52:19.385Z",
          "message": { "role": "assistant", "content": "ok" },
          "done": true
        }
        """.data(using: .utf8)!)

        let chat = OllamaChat(model: "llama3.2")
        _ = try await client.chat(messages: [.init(content: "Hi", role: .user)], in: chat)

        let request = try XCTUnwrap(URLProtocolStub.requests.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.bodyData())) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
    }

    func test_chatMaps404ToModelNotFound() async {
        URLProtocolStub.responses["/api/chat"] = .init(status: 404, body: Data("model not found".utf8))
        let chat = OllamaChat(model: "missing-model")

        do {
            _ = try await client.chat(messages: [.init(content: "Hi", role: .user)], in: chat)
            XCTFail("expected error")
        } catch let error as OllamaError {
            XCTAssertEqual(error, .modelNotFound("missing-model"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_chatMaps500ToInternalServerError() async {
        URLProtocolStub.responses["/api/chat"] = .init(status: 500, body: Data())
        let chat = OllamaChat(model: "llama3.2")

        do {
            _ = try await client.chat(messages: [.init(content: "Hi", role: .user)], in: chat)
            XCTFail("expected error")
        } catch let error as OllamaError {
            XCTAssertEqual(error, .internalServerError)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_createModelSendsExpectedRequestBody() async throws {
        URLProtocolStub.responses["/api/create"] = .init(body: Data())

        var options = OllamaChatOptions()
        options.temperature = 1.5
        options.topK = 99
        let chat = OllamaChat(model: "llama3.2", systemPrompt: "Be terse", options: options)

        try await client.createModel("my-llama", from: chat)

        let request = try XCTUnwrap(URLProtocolStub.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.bodyData())) as? [String: Any])

        XCTAssertEqual(body["model"] as? String, "my-llama")
        XCTAssertEqual(body["from"] as? String, "llama3.2")
        XCTAssertEqual(body["system"] as? String, "Be terse")
        XCTAssertEqual(body["stream"] as? Bool, false)

        let parameters = try XCTUnwrap(body["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["temperature"] as? Double, 1.5)
        XCTAssertEqual(parameters["top_k"] as? Int, 99)
        XCTAssertNil(parameters["mirostat"], "default values should be omitted")
        XCTAssertNil(parameters["temperature_default"])
    }

    func test_createModelOmitsParametersWhenAllDefault() async throws {
        URLProtocolStub.responses["/api/create"] = .init(body: Data())
        let chat = OllamaChat(model: "llama3.2")

        try await client.createModel("my-llama", from: chat)

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(URLProtocolStub.requests.first?.bodyData())) as? [String: Any])
        XCTAssertNil(body["parameters"], "no diff means parameters should be absent entirely")
        XCTAssertNil(body["system"], "no system prompt should be absent")
        XCTAssertNil(body["messages"], "no messages should be absent")
    }

    func test_deleteModelSendsDeleteWithModelName() async throws {
        URLProtocolStub.responses["/api/delete"] = .init(body: Data())

        try await client.deleteModel("my-llama")

        let request = try XCTUnwrap(URLProtocolStub.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.bodyData())) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "my-llama")
    }

    func test_deleteModelMaps404ToModelNotFound() async {
        URLProtocolStub.responses["/api/delete"] = .init(status: 404, body: Data())

        do {
            try await client.deleteModel("ghost")
            XCTFail("expected error")
        } catch let error as OllamaError {
            XCTAssertEqual(error, .modelNotFound("ghost"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_listModelsCombinesTagsAndShow() async throws {
        URLProtocolStub.responses["/api/tags"] = .init(body: """
        {
          "models": [
            {
              "name": "llama3.2:latest",
              "model": "llama3.2:latest",
              "modified_at": "2024-08-04T08:52:19.385Z",
              "size": 4661211808,
              "digest": "abc123",
              "details": { "parameter_size": "3B" }
            }
          ]
        }
        """.data(using: .utf8)!)

        URLProtocolStub.responses["/api/show"] = .init(body: """
        { "capabilities": ["completion", "vision"] }
        """.data(using: .utf8)!)

        let models = try await client.listModels()
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].name, "llama3.2:latest")
        XCTAssertEqual(models[0].parameterSize, "3B")
        XCTAssertTrue(models[0].capabilities?.completion ?? false)
        XCTAssertTrue(models[0].capabilities?.vision ?? false)
        XCTAssertFalse(models[0].capabilities?.tools ?? true)
    }
}

private extension URLRequest {
    /// `URLRequest.httpBody` is nil when the body was supplied via
    /// `httpBodyStream` (URLProtocolStub receives it as a stream). Drain
    /// either source so tests can assert on what was actually sent.
    func bodyData() -> Data? {
        if let data = httpBody { return data }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
