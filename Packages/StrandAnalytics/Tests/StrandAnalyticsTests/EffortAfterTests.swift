import XCTest
@testable import StrandAnalytics

final class EffortAfterTests: XCTestCase {
    func testTwoEffortsAddThroughTrimpNotAsNumbers() {
        let after = StrainScorer.effortAfter(day: 40, adding: 40)
        XCTAssertGreaterThan(after, 40)
        XCTAssertLessThan(after, 80)
        // 40 on the Edwards map is TRIMP 7201^0.4 − 1; twice that maps back to 40 + 100·ln(2)/ln(7201) (about 7.8).
        XCTAssertEqual(after, 40 + 100 * log(2.0) / log(7201.0), accuracy: 0.6)
    }

    func testAnEmptyDayTakesTheActivityAsItIs() {
        XCTAssertEqual(StrainScorer.effortAfter(day: 0, adding: 41.4), 41.4, accuracy: 0.05)
    }

    func testNothingAddedLeavesTheDayAlone() {
        XCTAssertEqual(StrainScorer.effortAfter(day: 33, adding: 0), 33, accuracy: 0.05)
    }

    func testNeverPastTheTopOfTheScale() {
        XCTAssertLessThanOrEqual(StrainScorer.effortAfter(day: 100, adding: 100), 100)
    }
}
