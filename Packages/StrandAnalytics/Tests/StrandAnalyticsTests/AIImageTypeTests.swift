import XCTest
@testable import StrandAnalytics

final class AIImageTypeTests: XCTestCase {
    func testTheTypeFollowsTheBytes() {
        XCTAssertEqual(AIImageType.mime(base64: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00]).base64EncodedString()), "image/jpeg")
        XCTAssertEqual(AIImageType.mime(base64: Data([0x89, 0x50, 0x4E, 0x47, 0x0D]).base64EncodedString()), "image/png")
        XCTAssertEqual(AIImageType.mime(base64: ""), "image/png")
    }
}
