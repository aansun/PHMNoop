import XCTest
@testable import StrandAnalytics

final class DayPlanTests: XCTestCase {
    func testLowChargeIsRecovery() {
        XCTAssertEqual(DayPlan.kind(charge: 20, yesterdayEffort: nil, usualEffort: nil, loadBand: .optimal), .recovery)
    }
    func testExcessiveLoadForcesRecovery() {
        XCTAssertEqual(DayPlan.kind(charge: 90, yesterdayEffort: nil, usualEffort: nil, loadBand: .excessive), .recovery)
    }
    func testHighChargeAndNothingHardIsQuality() {
        XCTAssertEqual(DayPlan.kind(charge: 78, yesterdayEffort: 10, usualEffort: 12, loadBand: .optimal), .quality)
    }
    func testHardYesterdayHoldsQualityBack() {
        XCTAssertEqual(DayPlan.kind(charge: 78, yesterdayEffort: 30, usualEffort: 12, loadBand: .optimal), .steady)
    }
    func testMiddleChargeIsEasyOrSteady() {
        XCTAssertEqual(DayPlan.kind(charge: 45, yesterdayEffort: nil, usualEffort: nil, loadBand: nil), .easy)
        XCTAssertEqual(DayPlan.kind(charge: 60, yesterdayEffort: nil, usualEffort: nil, loadBand: nil), .steady)
    }
    func testStepsAddUp() {
        let p = DayPlan.plan(charge: 78, yesterdayEffort: nil, usualEffort: nil, loadBand: nil, effortPerMinute: [])
        XCTAssertEqual(p.steps.map(\.minutes).reduce(0, +), p.totalMinutes)
        XCTAssertEqual(p.steps.count, 3)
    }
    func testEffortEstimateNeedsThreeSessions() {
        XCTAssertNil(DayPlan.plan(charge: 60, yesterdayEffort: nil, usualEffort: nil, loadBand: nil, effortPerMinute: [0.2, 0.3]).effortLow)
        let p = DayPlan.plan(charge: 60, yesterdayEffort: nil, usualEffort: nil, loadBand: nil, effortPerMinute: [0.2, 0.25, 0.3])
        XCTAssertNotNil(p.effortLow)
        XCTAssertLessThan(p.effortLow!, p.effortHigh!)
    }
}
