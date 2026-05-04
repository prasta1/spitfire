import XCTest
@testable import Spitfire

final class OllamaClientURLTests: XCTestCase {
    func test_endpointAppendsPathToBareHost() {
        let client = OllamaClient(baseURL: URL(string: "http://localhost:11434")!)
        XCTAssertEqual(client.endpoint("/api/tags").absoluteString, "http://localhost:11434/api/tags")
    }

    func test_endpointPreservesBasePathPrefix() {
        let client = OllamaClient(baseURL: URL(string: "http://example.com/ollama")!)
        XCTAssertEqual(client.endpoint("/api/tags").absoluteString, "http://example.com/ollama/api/tags")
    }

    func test_endpointTolerantOfLeadingAndTrailingSlashes() {
        let client = OllamaClient(baseURL: URL(string: "http://example.com/ollama/")!)
        XCTAssertEqual(client.endpoint("api/tags").absoluteString, "http://example.com/ollama/api/tags")
    }

    func test_parsesDateWithMicroseconds() {
        let date = OllamaClient.parseDate("2024-08-04T08:52:19.385406Z")
        XCTAssertNotNil(date)
    }

    func test_parsesDateWithoutFractionalSeconds() {
        let date = OllamaClient.parseDate("2024-08-04T08:52:19Z")
        XCTAssertNotNil(date)
    }
}
