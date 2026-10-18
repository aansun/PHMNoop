import XCTest
@testable import StrandAnalytics

final class WorkoutReadTests: XCTestCase {
    private let base = WorkoutBaseline(count: 5, durationS: 2400, distanceM: 5000, avgHr: 140, effort: 40, zoneMin: [2, 22, 14, 2, 0])

    func testFasterAtLowerHeartRateIsTheHeadline() {
        // 5 km in 36 min (7:12/km) against a usual 8:00/km, at 135 bpm against 140.
        let s = WorkoutFacts(durationS: 2160, distanceM: 5000, avgHr: 135, effort: 41, zoneMin: [2, 22, 14, 2, 0])
        let r = WorkoutRead.analyze(s, baseline: base, day: nil)!
        guard case .efficiency(let kind, let pace, let usual, let hr) = r.headline else { return XCTFail("\(r.headline)") }
        XCTAssertEqual(kind, .fasterLowerHr)
        XCTAssertEqual(pace, 432, accuracy: 0.5); XCTAssertEqual(usual, 480, accuracy: 0.5); XCTAssertEqual(hr, -5, accuracy: 0.1)
    }

    func testSlowerAtHigherHeartRate() {
        let s = WorkoutFacts(durationS: 2700, distanceM: 5000, avgHr: 148, effort: 41)
        guard case .efficiency(let kind, _, _, _) = WorkoutRead.analyze(s, baseline: base, day: nil)!.headline else { return XCTFail() }
        XCTAssertEqual(kind, .slowerHigherHr)
    }

    func testSamePaceNeedingMoreHeartRate() {
        let s = WorkoutFacts(durationS: 2400, distanceM: 5000, avgHr: 147, effort: 41)
        guard case .efficiency(let kind, _, _, _) = WorkoutRead.analyze(s, baseline: base, day: nil)!.headline else { return XCTFail() }
        XCTAssertEqual(kind, .samePaceHigherHr)
    }

    func testLongerAndHarderWithoutDistance() {
        let b = WorkoutBaseline(count: 4, durationS: 2400, avgHr: 130, effort: 30)
        let s = WorkoutFacts(durationS: 3600, avgHr: 131, effort: 45)
        let r = WorkoutRead.analyze(s, baseline: b, day: nil)!
        guard case .effort = r.headline else { return XCTFail("\(r.headline)") }
        XCTAssertTrue(r.more.contains { if case .duration = $0 { return true } else { return false } })
    }

    func testOnTheUsualIsTypical() {
        let s = WorkoutFacts(durationS: 2400, distanceM: 5000, avgHr: 140, effort: 40, zoneMin: [2, 22, 14, 2, 0])
        XCTAssertEqual(WorkoutRead.analyze(s, baseline: base, day: nil)?.headline, .typical)
    }

    func testNoBaselineNoVerdictUnlessTheDayTalks() {
        let s = WorkoutFacts(durationS: 2400, distanceM: 5000, avgHr: 140, effort: 40)
        XCTAssertNil(WorkoutRead.analyze(s, baseline: nil, day: nil))
        XCTAssertNil(WorkoutRead.analyze(s, baseline: WorkoutBaseline(count: 1, durationS: 2400), day: nil))
        let d = WorkoutDayContext(dayEffort: 70, rangeLow: 48, rangeHigh: 67, charge: 51)
        guard case .day(let state, _, _, _, _)? = WorkoutRead.analyze(s, baseline: nil, day: d)?.headline else { return XCTFail() }
        XCTAssertEqual(state, .above)
    }

    func testDayAboveRangeOutranksATypicalSession() {
        let s = WorkoutFacts(durationS: 2400, distanceM: 5000, avgHr: 140, effort: 40)
        let d = WorkoutDayContext(dayEffort: 70, rangeLow: 48, rangeHigh: 67, charge: 51)
        guard case .day = WorkoutRead.analyze(s, baseline: base, day: d)!.headline else { return XCTFail() }
    }

    func testHotAirRanksBehindPaceAndHeartRateAndStandsAloneOtherwise() {
        let hot = EnvironmentSnapshot(ts: 1, tempC: 33, feelsLikeC: 39, humidityPct: 70, conditionId: 800, usAqi: 60)
        // A slower session at a higher heart rate: that stays the headline, the heat follows.
        let s = WorkoutFacts(durationS: 2700, distanceM: 5000, avgHr: 148, effort: 41)
        let r = WorkoutRead.analyze(s, baseline: base, day: nil, conditions: hot)!
        guard case .efficiency = r.headline else { return XCTFail("\(r.headline)") }
        XCTAssertTrue(r.more.contains { if case .conditions(.indoors, _) = $0 { return true } else { return false } })
        // A session on the usual: the conditions are the only thing worth saying.
        let usual = WorkoutFacts(durationS: 2400, distanceM: 5000, avgHr: 140, effort: 40, zoneMin: [2, 22, 14, 2, 0])
        guard case .conditions = WorkoutRead.analyze(usual, baseline: base, day: nil, conditions: hot)!.headline else { return XCTFail() }
        // Mild, clean air: nothing added.
        let mild = EnvironmentSnapshot(ts: 1, tempC: 27, feelsLikeC: 28, humidityPct: 60, conditionId: 800, usAqi: 40)
        XCTAssertEqual(WorkoutRead.analyze(usual, baseline: base, day: nil, conditions: mild)?.headline, .typical)
        // Conditions alone are enough for a read, even without a baseline.
        guard case .conditions = WorkoutRead.analyze(usual, baseline: nil, day: nil, conditions: hot)!.headline else { return XCTFail() }
    }
}
