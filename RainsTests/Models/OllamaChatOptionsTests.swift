import XCTest
@testable import Rains

final class OllamaChatOptionsTests: XCTestCase {
    func test_defaultsMatchOllamaDefaults() {
        let options = OllamaChatOptions()
        XCTAssertEqual(options.mirostat, 0)
        XCTAssertEqual(options.contextSize, 2048)
        XCTAssertEqual(options.temperature, 0.8)
        XCTAssertEqual(options.topK, 40)
        XCTAssertEqual(options.topP, 0.9)
        XCTAssertEqual(options.maxTokens, -1)
    }

    func test_encodingOmitsMaxTokensWhenNegative() throws {
        let json = try encodeAsDict(OllamaChatOptions())
        XCTAssertNil(json["num_predict"])
    }

    func test_encodingIncludesMaxTokensWhenPositive() throws {
        var options = OllamaChatOptions()
        options.maxTokens = 256
        let json = try encodeAsDict(options)
        XCTAssertEqual(json["num_predict"] as? Int, 256)
    }

    func test_encodingUsesSnakeCaseKeys() throws {
        let json = try encodeAsDict(OllamaChatOptions())
        XCTAssertNotNil(json["mirostat_eta"])
        XCTAssertNotNil(json["num_ctx"])
        XCTAssertNotNil(json["repeat_last_n"])
        XCTAssertNotNil(json["repeat_penalty"])
        XCTAssertNotNil(json["tfs_z"])
        XCTAssertNotNil(json["top_k"])
        XCTAssertNotNil(json["top_p"])
        XCTAssertNotNil(json["min_p"])
    }

    func test_encodeDecodeRoundTrip() throws {
        var options = OllamaChatOptions()
        options.temperature = 0.42
        options.topK = 12
        options.maxTokens = 128

        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(OllamaChatOptions.self, from: data)
        XCTAssertEqual(decoded, options)
    }

    private func encodeAsDict(_ options: OllamaChatOptions) throws -> [String: Any] {
        let data = try JSONEncoder().encode(options)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}
