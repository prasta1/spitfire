import XCTest
@testable import Rains

final class ModelCapabilitiesTests: XCTestCase {
    func test_parsesKnownCapabilities() {
        let caps = ModelCapabilities(["completion", "vision", "tools", "embedding", "thinking"])
        XCTAssertTrue(caps.completion)
        XCTAssertTrue(caps.vision)
        XCTAssertTrue(caps.tools)
        XCTAssertTrue(caps.embedding)
        XCTAssertTrue(caps.thinking)
    }

    func test_emptyListYieldsAllFalse() {
        let caps = ModelCapabilities([])
        XCTAssertFalse(caps.completion)
        XCTAssertFalse(caps.vision)
        XCTAssertFalse(caps.tools)
        XCTAssertFalse(caps.embedding)
        XCTAssertFalse(caps.thinking)
    }

    func test_unknownCapabilitiesIgnored() {
        let caps = ModelCapabilities(["completion", "future-feature"])
        XCTAssertTrue(caps.completion)
        XCTAssertFalse(caps.vision)
    }
}
