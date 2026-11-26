import XCTest
@testable import StrandAnalytics

final class PressureLinksTests: XCTestCase {
    private typealias P = PressureLinks.Pressure
    private typealias R = PressureLinks.Reading

    /// `count` days named "a0", "a1", … all reading the same pair.
    private func days(_ prefix: String, _ count: Int, _ s: Double, _ d: Double) -> [String: P] {
        Dictionary(uniqueKeysWithValues: (0..<count).map { (prefix + String($0), P(s, d)) })
    }

    private func compare(yes: (Int, Double, Double), no: (Int, Double, Double)) -> PressureLinks.Comparison {
        let a = days("y", yes.0, yes.1, yes.2), b = days("n", no.0, no.1, no.2)
        let flags = Dictionary(uniqueKeysWithValues: a.keys.map { ($0, true) } + b.keys.map { ($0, false) })
        return PressureLinks.compare(a.merging(b) { x, _ in x }, flags: flags)
    }

    func testDailyMeanWeighsEachDayOnce() {
        let daily = PressureLinks.daily([R(takenAt: 1, systolic: 110, diastolic: 70), R(takenAt: 2, systolic: 130, diastolic: 90),
                                         R(takenAt: 100, systolic: 140, diastolic: 95)]) { $0 < 50 ? "a" : "b" }
        XCTAssertEqual(daily["a"], P(120, 80))
        XCTAssertEqual(daily["b"], P(140, 95))
    }

    func testNeedsFiveDaysOnEachSide() {
        XCTAssertEqual(compare(yes: (4, 140, 90), no: (20, 120, 80)).verdict, .needMore)
        XCTAssertEqual(compare(yes: (5, 140, 90), no: (4, 120, 80)).verdict, .needMore)
        XCTAssertEqual(compare(yes: (5, 140, 90), no: (5, 120, 80)).verdict, .firstHigher)
        XCTAssertNil(compare(yes: (0, 0, 0), no: (5, 120, 80)).difference)
    }

    func testSmallOrOpposedGapsAreNoGap() {
        XCTAssertEqual(compare(yes: (6, 122.4, 81.4), no: (6, 120, 80)).verdict, .same)
        XCTAssertEqual(compare(yes: (6, 123, 80), no: (6, 120, 80)).verdict, .firstHigher)
        XCTAssertEqual(compare(yes: (6, 120, 78), no: (6, 120, 80)).verdict, .firstLower)
        XCTAssertEqual(compare(yes: (6, 125, 77), no: (6, 120, 80)).verdict, .same)
    }

    /// 126.4 and 126.6 read 126 and 127 on screen, so the gap named is the one between those.
    func testGapIsBetweenTheWholeFiguresShown() {
        let c = compare(yes: (6, 126.4, 82), no: (6, 126.6, 82))
        XCTAssertEqual(c.first.mean, P(126, 82))
        XCTAssertEqual(c.second.mean, P(127, 82))
        XCTAssertEqual(c.difference, P(-1, 0))
    }

    func testEarlyWhileASideHoldsFewDays() {
        XCTAssertTrue(compare(yes: (9, 130, 85), no: (30, 120, 80)).early)
        XCTAssertFalse(compare(yes: (10, 130, 85), no: (30, 120, 80)).early)
    }

    func testLevelSplitsAtTheMiddleOfSharedDays() throws {
        var daily: [String: P] = [:], level: [String: Double] = [:]
        for i in 0..<12 { daily["d\(i)"] = i < 6 ? P(130, 85) : P(120, 80); level["d\(i)"] = Double(i) }
        level["unmeasured"] = 1000   // a day with no reading does not move the middle
        let r = try XCTUnwrap(PressureLinks.compareByLevel(daily, level: level, minimumSpread: 2))
        XCTAssertEqual(r.middle, 5.5)
        XCTAssertEqual(r.comparison.first.days, 6)
        XCTAssertEqual(r.comparison.second.days, 6)
        XCTAssertEqual(r.comparison.verdict, .firstHigher)
    }

    func testLevelThatHardlyMovesSaysNothing() {
        let daily = days("d", 12, 120, 80)
        let level = Dictionary(uniqueKeysWithValues: daily.keys.map { ($0, 70.2) })
        XCTAssertNil(PressureLinks.compareByLevel(daily, level: level, minimumSpread: 1))
        XCTAssertNil(PressureLinks.compareByLevel(daily, level: [:], minimumSpread: 1))
    }

    func testBreathPairNeedsBothSidesWithinHalfAnHour() {
        let s = PressureLinks.Session(start: 10_000, end: 10_600)
        let before = R(takenAt: 10_000 - 1800, systolic: 130, diastolic: 85), after = R(takenAt: 10_600 + 1800, systolic: 122, diastolic: 80)
        let pairs = PressureLinks.breathPairs([before, after], sessions: [s])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].change, P(-8, -5))
        XCTAssertTrue(PressureLinks.breathPairs([R(takenAt: 10_000 - 1801, systolic: 130, diastolic: 85), after], sessions: [s]).isEmpty)
        XCTAssertTrue(PressureLinks.breathPairs([before], sessions: [s]).isEmpty)
    }

    func testBreathPairTakesTheNearestReadingsAndUsesEachOnce() {
        let early = PressureLinks.Session(start: 10_000, end: 10_300), late = PressureLinks.Session(start: 10_500, end: 10_800)
        let readings = [R(takenAt: 9_000, systolic: 140, diastolic: 90), R(takenAt: 9_900, systolic: 132, diastolic: 86),
                        R(takenAt: 10_400, systolic: 126, diastolic: 82), R(takenAt: 10_900, systolic: 121, diastolic: 79)]
        let pairs = PressureLinks.breathPairs(readings, sessions: [early, late])
        // The newer session takes 10_400 and 10_900; the older one would need 10_400 again, so it has no pair.
        XCTAssertEqual(pairs.map(\.session), [late])
        XCTAssertEqual(pairs[0].before.takenAt, 10_400)
        XCTAssertEqual(pairs[0].after.takenAt, 10_900)
    }

    func testReminderDatesSkipCoveredAndPassedSlots() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))! }
        let slots = [7 * 60, 19 * 60]
        // 05:00 with nothing measured: both of today's and both of tomorrow's.
        XCTAssertEqual(PressureLinks.reminderDates(now: at(26, 5), minutes: slots, readings: [], days: 2, calendar: cal),
                       [at(26, 7), at(26, 19), at(27, 7), at(27, 19)])
        // Measured at 04:30: this morning's is covered, tonight's is not.
        XCTAssertEqual(PressureLinks.reminderDates(now: at(26, 5), minutes: slots, readings: [Int(at(26, 4, 30).timeIntervalSince1970)], days: 1, calendar: cal),
                       [at(26, 19)])
        // A reading four hours before the slot does not cover it; one in the past of another day never does.
        XCTAssertEqual(PressureLinks.reminderDates(now: at(26, 5), minutes: slots, readings: [Int(at(26, 3).timeIntervalSince1970), Int(at(25, 7).timeIntervalSince1970)],
                                                   days: 1, calendar: cal), [at(26, 7), at(26, 19)])
        // After the morning slot only the evening is left today; out-of-range minutes are ignored.
        XCTAssertEqual(PressureLinks.reminderDates(now: at(26, 8), minutes: slots + [-1, 1440], readings: [], days: 1, calendar: cal), [at(26, 19)])
    }
}
