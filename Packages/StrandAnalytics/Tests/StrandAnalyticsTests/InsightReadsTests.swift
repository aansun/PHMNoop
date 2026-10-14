import XCTest
@testable import StrandAnalytics

final class InsightReadsTests: XCTestCase {

    // MARK: Sleep

    func testShortNightIsWhatHeldRestBack() {
        let f = SleepFacts(restPct: 62, asleepMin: 330, needMin: 465, debtMin: 70,
                           hoursPct: 71, efficiencyPct: 92, restorativePct: 45, consistencyPct: 90)
        let r = SleepRead.analyze(f)!
        XCTAssertEqual(r.verdict, .heldBack(.duration))
        XCTAssertEqual(r.durationGapMin, -135)
        XCTAssertEqual(r.debtMin, 70)
    }

    func testBrokenSleepIsNamedWhenTheHoursWereFine() {
        let f = SleepFacts(restPct: 68, asleepMin: 470, needMin: 465, hoursPct: 100, efficiencyPct: 50, restorativePct: 70,
                           consistencyPct: 88, awakeMin: 95, wakeEvents: 7)
        let r = SleepRead.analyze(f)!
        XCTAssertEqual(r.verdict, .heldBack(.efficiency))
        XCTAssertEqual(r.wakeEvents, 7)
    }

    func testAnIrregularBedtimeCanBeTheCause() {
        let f = SleepFacts(restPct: 74, asleepMin: 465, needMin: 465, hoursPct: 100, efficiencyPct: 91, restorativePct: 44,
                           consistencyPct: 35, bedShiftMin: 95)
        let r = SleepRead.analyze(f)!
        XCTAssertEqual(r.verdict, .heldBack(.consistency))
        XCTAssertEqual(r.bedShiftMin, 95)
    }

    func testAStrongNightIsCreditedToItsBestPart() {
        let f = SleepFacts(restPct: 91, asleepMin: 480, needMin: 465, hoursPct: 100, efficiencyPct: 95, restorativePct: 52,
                           consistencyPct: 80, hrvDeltaPct: 9)
        let r = SleepRead.analyze(f)!
        if case .carriedBy = r.verdict {} else { XCTFail("expected carriedBy, got \(r.verdict)") }
        XCTAssertEqual(r.body, .supportive)
    }

    func testDeepSleepAgainstUsualIsAPercentage() {
        let f = SleepFacts(restPct: 80, asleepMin: 450, needMin: 465, deepMin: 50, remMin: 100, usualDeepMin: 75, usualRemMin: 100)
        let r = SleepRead.analyze(f)!
        XCTAssertEqual(r.deepDeltaPct, -33)
        XCTAssertEqual(r.remDeltaPct, 0)
    }

    func testNoSleepNoRead() {
        XCTAssertNil(SleepRead.analyze(SleepFacts(asleepMin: 0, needMin: 465)))
    }

    // MARK: Vital

    func testAReadingWellOverTheUsualAndItsStreak() {
        let history = (0..<20).map { 60 + Double($0 % 3) } + [66, 67, 68]
        let r = VitalRead.analyze(latest: 69, history: history)!
        XCTAssertEqual(r.position, .above)
        XCTAssertEqual(r.streakDays, 4)
        XCTAssertGreaterThan(r.pctFromUsual, 5)
    }

    func testARegularReadingIsWithin() {
        let history = (0..<20).map { 60 + Double($0 % 3) }
        let r = VitalRead.analyze(latest: 61, history: history)!
        XCTAssertEqual(r.position, .within)
        XCTAssertEqual(r.streakDays, 1)
    }

    func testTooLittleHistoryGivesNoRead() {
        XCTAssertNil(VitalRead.analyze(latest: 60, history: [58, 59, 60]))
    }

    // MARK: Charge

    func testChargeNamesTheLiftAndTheDrag() {
        let r = ChargeRead.analyze(hrvDeltaPct: 14, rhrDeltaBpm: -1, sleepPct: 52, priorEffort: 20, usualEffort: 20,
                                   respDeltaBpm: 0.1, skinTempDevC: 0.1)
        XCTAssertEqual(r.lift?.factor, .hrv)
        XCTAssertEqual(r.drag?.factor, .sleep)
    }

    func testAQuietDayHasNeitherLiftNorDrag() {
        let r = ChargeRead.analyze(hrvDeltaPct: 1, rhrDeltaBpm: 0, sleepPct: 76, priorEffort: 18, usualEffort: 20,
                                   respDeltaBpm: 0, skinTempDevC: 0)
        XCTAssertNil(r.lift)
        XCTAssertNil(r.drag)
    }

    func testAHardPriorDayDragsCharge() {
        let r = ChargeRead.analyze(hrvDeltaPct: 0, rhrDeltaBpm: 0, sleepPct: 75, priorEffort: 45, usualEffort: 20,
                                   respDeltaBpm: nil, skinTempDevC: nil)
        XCTAssertEqual(r.drag?.factor, .load)
    }

    // MARK: Stress

    func testLongestHighStretchIsFound() {
        let levels: [(hour: Int, level: Double)] = [(8, 0.5), (9, 0.8), (10, 1.2), (11, 2.1), (12, 2.4), (13, 2.2), (14, 1.0), (15, 2.3), (16, 0.7)]
        let r = StressRead.analyze(levels: levels)!
        XCTAssertEqual(r.peakStartHour, 11)
        XCTAssertEqual(r.peakHours, 3)
        XCTAssertEqual(r.calmHours, 3)
        XCTAssertEqual(r.calmSinceHours, 1)
    }

    func testACalmDayHasNoPeak() {
        let levels: [(hour: Int, level: Double)] = (8..<14).map { ($0, 0.6) }
        let r = StressRead.analyze(levels: levels)!
        XCTAssertNil(r.peakStartHour)
        XCTAssertNil(r.calmSinceHours)
    }
}
