import XCTest
@testable import StrandAnalytics

final class BatteryChargeTrendTests: XCTestCase {
    private let now = 1_800_000_000

    private func series(_ points: [(minutesAgo: Int, soc: Double)]) -> [(ts: Int, soc: Double)] {
        points.map { (ts: now - $0.minutesAgo * 60, soc: $0.soc) }
    }

    func testRisingLevelReadsAsCharging() {
        let t = BatteryEstimator.chargeTrend(samples: series([(30, 40), (20, 45), (10, 50), (1, 55)]), now: now)
        XCTAssertTrue(t.rising)
        // 15 points over 29 minutes: about 31 %/h, so 45 points left is about 1.45 h.
        XCTAssertEqual(t.hoursToFull ?? 0, 1.45, accuracy: 0.05)
    }

    func testFlatOrFallingIsNotCharging() {
        XCTAssertFalse(BatteryEstimator.chargeTrend(samples: series([(30, 80), (10, 80.1), (1, 80)]), now: now).rising)
        XCTAssertFalse(BatteryEstimator.chargeTrend(samples: series([(30, 80), (10, 79), (1, 78)]), now: now).rising)
    }

    func testRiseThatHasStartedToFallIsNotCharging() {
        XCTAssertFalse(BatteryEstimator.chargeTrend(samples: series([(30, 40), (15, 50), (1, 49)]), now: now).rising)
    }

    func testStaleReadingsSayNothingAboutNow() {
        XCTAssertFalse(BatteryEstimator.chargeTrend(samples: series([(44, 40), (40, 50), (30, 60)]), now: now).rising)
    }

    func testClimbBeforeAChargeEndedIsIgnored() {
        let s = series([(30, 40), (20, 50), (10, 60), (1, 60.2)])
        XCTAssertTrue(BatteryEstimator.chargeTrend(samples: s, now: now).rising)
        XCTAssertFalse(BatteryEstimator.chargeTrend(samples: s, now: now, after: now - 5 * 60).rising)
    }

    func testNoTimeToFullFromTwoCloseReadingsOrWhenFull() {
        XCTAssertNil(BatteryEstimator.chargeTrend(samples: series([(5, 50), (1, 52)]), now: now).hoursToFull)
        XCTAssertNil(BatteryEstimator.chargeTrend(samples: series([(30, 97), (1, 99.6)]), now: now).hoursToFull)
    }
}
