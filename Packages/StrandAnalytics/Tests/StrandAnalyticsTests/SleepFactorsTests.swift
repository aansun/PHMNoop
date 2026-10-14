import XCTest
@testable import StrandAnalytics

final class SleepFactorsTests: XCTestCase {
    private func e(_ day: String, _ q: String, _ yes: Bool) -> SleepFactors.Entry { .init(day: day, question: q, yes: yes) }

    func testQuestionsAreRecognisedByMeaning() {
        XCTAssertEqual(SleepFactors.kind(ofQuestion: "Did you drink any alcohol?"), .alcohol)
        XCTAssertEqual(SleepFactors.kind(ofQuestion: "Did you have caffeine late in the day?"), .lateCaffeine)
        XCTAssertEqual(SleepFactors.kind(ofQuestion: "Did you eat close to bedtime?"), .lateMeal)
        XCTAssertEqual(SleepFactors.kind(ofQuestion: "Ate food close to bedtime?"), .lateMeal)
        XCTAssertNil(SleepFactors.kind(ofQuestion: "Consumed caffeine?"))
        XCTAssertNil(SleepFactors.kind(ofQuestion: "Did you take magnesium?"))
    }

    func testAnAnswerBelongsToTheNightAfterItsDay() {
        XCTAssertEqual(SleepFactors.nextDay("2026-10-31"), "2026-11-01")
        let j = [e("2026-10-12", "Did you drink any alcohol?", true)]
        XCTAssertEqual(SleepFactors.loggedYes(journal: j, wakeDay: "2026-10-13"), [.alcohol])
        XCTAssertTrue(SleepFactors.loggedYes(journal: j, wakeDay: "2026-10-12").isEmpty)
    }

    func testAHabitThatCostsRestIsNamed() {
        // Alcohol on 4 evenings (Rest 60 next morning), none on 6 others (Rest 85).
        var j: [SleepFactors.Entry] = [], rest: [String: Double] = [:]
        for d in 1...4 { j.append(e("2026-10-0\(d)", "Did you drink any alcohol?", true)); rest["2026-10-0\(d + 1)"] = 60 }
        for d in 5...9 { j.append(e("2026-10-0\(d)", "Did you drink any alcohol?", false)); rest["2026-10-\(String(format: "%02d", d + 1))"] = 85 }
        j.append(e("2026-10-10", "Did you drink any alcohol?", false)); rest["2026-10-11"] = 85
        let ev = SleepFactors.evidence(journal: j, restByWakeDay: rest).first { $0.kind == .alcohol }!
        XCTAssertEqual(ev.nYes, 4)
        XCTAssertEqual(ev.nNo, 6)
        XCTAssertEqual(ev.restDelta ?? 0, -25, accuracy: 0.01)
        XCTAssertTrue(ev.costsRest)
    }

    func testTooFewNightsIsNotAPattern() {
        // One late meal, eleven without it: the habit may well matter, but there is no evidence yet.
        var j: [SleepFactors.Entry] = [], rest: [String: Double] = [:]
        j.append(e("2026-10-01", "Did you eat close to bedtime?", true)); rest["2026-10-02"] = 50
        for d in 2...9 { j.append(e("2026-10-0\(d)", "Did you eat close to bedtime?", false)); rest["2026-10-\(String(format: "%02d", d + 1))"] = 85 }
        let ev = SleepFactors.evidence(journal: j, restByWakeDay: rest).first { $0.kind == .lateMeal }!
        XCTAssertEqual(ev.nYes, 1)
        XCTAssertFalse(ev.costsRest)
    }

    func testAHabitThatNeverCostsRestIsNotBlamed() {
        var j: [SleepFactors.Entry] = [], rest: [String: Double] = [:]
        for d in 1...4 { j.append(e("2026-10-0\(d)", "Did you have caffeine late in the day?", true)); rest["2026-10-0\(d + 1)"] = 84 }
        for d in 5...8 { j.append(e("2026-10-0\(d)", "Did you have caffeine late in the day?", false)); rest["2026-10-0\(d + 1)"] = 85 }
        let ev = SleepFactors.evidence(journal: j, restByWakeDay: rest).first { $0.kind == .lateCaffeine }!
        XCTAssertFalse(ev.costsRest)
    }

    func testUnansweredDaysAreNotControls() {
        let ev = SleepFactors.evidence(journal: [e("2026-10-01", "Did you drink any alcohol?", true)],
                                       restByWakeDay: ["2026-10-02": 60, "2026-10-03": 90, "2026-10-04": 90]).first { $0.kind == .alcohol }!
        XCTAssertEqual(ev.nNo, 0)
        XCTAssertNil(ev.restDelta)
    }
}
