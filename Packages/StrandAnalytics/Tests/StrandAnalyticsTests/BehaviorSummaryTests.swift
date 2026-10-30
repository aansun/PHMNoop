import XCTest
@testable import StrandAnalytics

final class BehaviorSummaryTests: XCTestCase {

    private func day(_ i: Int) -> String { String(format: "2026-10-%02d", i) }

    /// Alcohol on days 1-6 (lower outcome), not on days 7-14 (higher outcome).
    private func fixture() -> (answers: [String: [String: Bool]], outcome: [String: Double]) {
        var alcohol: [String: Bool] = [:]
        var outcome: [String: Double] = [:]
        for i in 1...14 {
            alcohol[day(i)] = i <= 6
            outcome[day(i)] = i <= 6 ? 50 + Double(i % 3) : 70 + Double(i % 3)
        }
        // Stretching was logged on two days only.
        let stretching = [day(3): true, day(9): true]
        return (["Alcohol": alcohol, "Stretching": stretching], outcome)
    }

    func testCountsYesAndNoPerBehavior() {
        let f = fixture()
        let rows = BehaviorSummary.rows(answers: f.answers, outcomeByDay: f.outcome, since: "2026-10-01", outcome: "Charge")
        let alcohol = rows.first { $0.behavior == "Alcohol" }!
        XCTAssertEqual(alcohol.yes, 6)
        XCTAssertEqual(alcohol.no, 8)
        let stretching = rows.first { $0.behavior == "Stretching" }!
        XCTAssertEqual(stretching.yes, 2)
        XCTAssertEqual(stretching.no, 0)
    }

    /// An effect is only claimed once there are five of each answer; below that the row carries counts and no figure.
    func testEffectNeedsFiveOfEachAnswer() {
        let f = fixture()
        let rows = BehaviorSummary.rows(answers: f.answers, outcomeByDay: f.outcome, since: "2026-10-01", outcome: "Charge")
        XCTAssertNotNil(rows.first { $0.behavior == "Alcohol" }!.effect)
        XCTAssertTrue(rows.first { $0.behavior == "Alcohol" }!.unlocked)
        XCTAssertNil(rows.first { $0.behavior == "Stretching" }!.effect)
        XCTAssertFalse(rows.first { $0.behavior == "Stretching" }!.unlocked)
        XCTAssertNil(rows.first { $0.behavior == "Stretching" }!.percent)
    }

    func testAlcoholHurtsAndIsListedFirst() {
        let f = fixture()
        let rows = BehaviorSummary.rows(answers: f.answers, outcomeByDay: f.outcome, since: "2026-10-01", outcome: "Charge")
        XCTAssertEqual(rows.first?.behavior, "Alcohol")
        let split = BehaviorSummary.split(rows)
        XCTAssertEqual(split.hurts.map(\.behavior), ["Alcohol"])
        XCTAssertTrue(split.helps.isEmpty)
        XCTAssertLessThan(rows.first!.percent!, -20)
    }

    func testDaysBeforeTheWindowAreIgnored() {
        let f = fixture()
        let rows = BehaviorSummary.rows(answers: f.answers, outcomeByDay: f.outcome, since: "2026-10-07", outcome: "Charge")
        let alcohol = rows.first { $0.behavior == "Alcohol" }
        XCTAssertEqual(alcohol?.yes, 0)
        XCTAssertEqual(alcohol?.no, 8)
        XCTAssertNil(alcohol?.effect)
    }

    func testAnswerStates() {
        let by = ["2026-10-02": true, "2026-10-03": false]
        XCTAssertEqual(BehaviorSummary.answer(by, on: "2026-10-02"), .yes)
        XCTAssertEqual(BehaviorSummary.answer(by, on: "2026-10-03"), .no)
        XCTAssertEqual(BehaviorSummary.answer(by, on: "2026-10-04"), .missing)
    }

    func testMonthLayout() throws {
        // October 2026 starts on a Thursday (weekday 4 with Sunday = 0) and has 31 days.
        let m = try XCTUnwrap(BehaviorSummary.month(year: 2026, month: 10))
        XCTAssertEqual(m.days.count, 31)
        XCTAssertEqual(m.days.first, "2026-10-01")
        XCTAssertEqual(m.days.last, "2026-10-31")
        XCTAssertEqual(m.firstWeekday, 4)
        let feb = try XCTUnwrap(BehaviorSummary.month(year: 2028, month: 2))
        XCTAssertEqual(feb.days.count, 29)
    }
}
