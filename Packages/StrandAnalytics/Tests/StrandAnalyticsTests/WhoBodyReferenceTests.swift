import XCTest
@testable import StrandAnalytics

final class WhoBodyReferenceTests: XCTestCase {
    func testWeightRangeFollowsBmi18_5ToUnder25() throws {
        let r = try XCTUnwrap(WhoBodyReference.weightRangeKg(heightCm: 178))
        XCTAssertEqual(r.low, 18.5 * 1.78 * 1.78, accuracy: 1e-9)
        XCTAssertEqual(r.high, 24.99 * 1.78 * 1.78, accuracy: 1e-9)
        XCTAssertEqual(r.low, 58.6, accuracy: 0.05)
        XCTAssertEqual(r.high, 79.2, accuracy: 0.05)
    }

    func testNoRangeForAnUnbelievableHeight() {
        XCTAssertNil(WhoBodyReference.weightRangeKg(heightCm: 0))
        XCTAssertNil(WhoBodyReference.weightRangeKg(heightCm: 60))
        XCTAssertNil(WhoBodyReference.weightRangeKg(heightCm: .nan))
    }

    func testWaistCeilingBySex() {
        XCTAssertEqual(WhoBodyReference.waistCeilingCm(sex: "male"), 94)
        XCTAssertEqual(WhoBodyReference.waistCeilingCm(sex: "Female"), 80)
        XCTAssertNil(WhoBodyReference.waistCeilingCm(sex: "nonbinary"))
        XCTAssertNil(WhoBodyReference.waistCeilingCm(sex: ""))
    }
}
