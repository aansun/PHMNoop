import XCTest
@testable import StrandAnalytics

final class BodyAgeHistoryTests: XCTestCase {
    func testSaturdaysAreTheCompletedWeeksBeforeTheCurrentOneOldestFirst() {
        // 2026-11-16 is a Monday; the Saturday on or before it is 2026-11-14, which the weekly job writes, so the rebuild stops at the 7th.
        let s = BodyAgeHistory.saturdays(before: "2026-11-16", count: 4)
        XCTAssertEqual(s, ["2026-10-17", "2026-10-24", "2026-10-31", "2026-11-07"])
    }

    func testOnASaturdayTheSaturdayItselfIsTheCurrentWeek() {
        XCTAssertEqual(BodyAgeHistory.saturdays(before: "2026-11-14", count: 2), ["2026-10-31", "2026-11-07"])
        // A Friday is still in the week keyed by the Saturday before it (11-07), so the completed weeks end at the one before that.
        XCTAssertEqual(BodyAgeHistory.saturdays(before: "2026-11-13", count: 1), ["2026-10-31"])
    }

    func testSaturdaysCrossAYearEndAndDefaultToTheWeeksThePaceReads() {
        XCTAssertEqual(BodyAgeHistory.saturdays(before: "2027-01-05", count: 3), ["2026-12-12", "2026-12-19", "2026-12-26"])
        let all = BodyAgeHistory.saturdays(before: "2026-11-16")
        XCTAssertEqual(all.count, BodyAgeHistory.maxWeeks)
        XCTAssertEqual(all, all.sorted())
        XCTAssertEqual(Set(all).count, all.count)
    }

    func testBadDayKeysGiveNothing() {
        XCTAssertEqual(BodyAgeHistory.saturdays(before: "not-a-day"), [])
        XCTAssertEqual(BodyAgeHistory.saturdays(before: "2026-11-16", count: 0), [])
        XCTAssertNil(BodyAgeHistory.addDays("2026-13-99x", 1))
    }

    func testAWeekIsTheSevenDaysEndingOnItsSaturday() {
        XCTAssertEqual(BodyAgeHistory.weekDays(endingOn: "2026-11-07"),
                       ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07"])
        XCTAssertEqual(BodyAgeHistory.weekDays(endingOn: "2027-01-02").first, "2026-12-27")
    }

    private func week(rhr: Double) -> VitalityEngine.WeekData {
        VitalityEngine.WeekData(chronoAge: 30, sex: "male", restingHRs: Array(repeating: rhr, count: 7),
                                sleepNights: Array(repeating: 7.5, count: 7), storedConsistency: Array(repeating: 85, count: 7),
                                steps: Array(repeating: 9000, count: 7))
    }

    func testPointsAreWhatTheEngineSaysForEachWeekAndSkipWeeksWithTooLittle() {
        let good = week(rhr: 52), poor = week(rhr: 72)
        let empty = VitalityEngine.WeekData(chronoAge: 30, sex: "male")
        let pts = BodyAgeHistory.points([("2026-10-31", good), ("2026-11-07", empty), ("2026-11-14", poor)])
        XCTAssertEqual(pts.map(\.day), ["2026-10-31", "2026-11-14"])
        let expectedGood = VitalityEngine.compute(VitalityEngine.weeklyInputs(good))!
        XCTAssertEqual(pts[0].bodyAge, expectedGood.bodyAge, accuracy: 1e-12)
        XCTAssertEqual(pts[0].vitality, expectedGood.vitality, accuracy: 1e-12)
        XCTAssertLessThan(pts[0].bodyAge, pts[1].bodyAge, "a lower resting heart rate is a younger age")
    }

    func testTheMarkerKeyAndVersionAreStable() {
        // Stored in the database and read back by later versions: changing either would rebuild every history again.
        XCTAssertEqual(BodyAgeHistory.markerKey, "body_age_model")
        XCTAssertEqual(BodyAgeHistory.modelVersion, 3)
    }
}
