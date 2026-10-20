import XCTest
@testable import StrandAnalytics

final class GymCoachTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    /// Monday 19 Oct 2026, 08:00 UTC.
    private var now: Date {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 19; c.hour = 8
        return cal.date(from: c)!
    }
    private func ts(daysAgo: Int, hour: Int = 18) -> Int {
        Int(cal.startOfDay(for: now).timeIntervalSince1970) - daysAgo * 86_400 + hour * 3600
    }
    private func s(_ d: Int, v: Double = 1000, program: String? = "A", hour: Int = 18) -> GymCoach.Session {
        .init(startTs: ts(daysAgo: d, hour: hour), programId: program, volumeKg: v, workingSets: 12)
    }

    func testHabitNeedsFourSessions() {
        XCTAssertNil(GymCoach.habit(sessions: [s(1), s(8), s(15)], now: now, calendar: cal))
    }

    func testUsualWeekdaysAndHour() {
        // Today is a Monday; trained on the last four Mondays and two Thursdays, always about 18:00.
        let sessions = [s(7), s(14), s(21), s(28), s(4), s(11)]
        let h = GymCoach.habit(sessions: sessions, now: now, calendar: cal)!
        XCTAssertEqual(h.usualWeekdays, [2, 5])
        XCTAssertEqual(h.usualHour, 18)
        XCTAssertTrue(h.isUsualDay)
        XCTAssertFalse(h.trainedToday)
        XCTAssertEqual(h.daysSinceLast, 4)
    }

    func testTrainedToday() {
        let h = GymCoach.habit(sessions: [s(0, hour: 6), s(7), s(14), s(21)], now: now, calendar: cal)!
        XCTAssertTrue(h.trainedToday)
    }

    func testTrendComparesTheTwoHalvesOfThirtyDays() {
        let t = GymCoach.trend(sessions: [s(2, v: 1100), s(10, v: 1100), s(20, v: 1000), s(28, v: 1000)], now: now)!
        XCTAssertEqual(t.sessions, 4)
        XCTAssertEqual(t.volumeChangePct!, 10, accuracy: 0.001)
        XCTAssertNil(GymCoach.trend(sessions: [s(2)], now: now)!.volumeChangePct)
        XCTAssertNil(GymCoach.trend(sessions: [s(40)], now: now))
    }

    func testScheduledProgramIsTheOneUsuallyRunOnThisWeekday() {
        let sessions = [s(7, program: "Push"), s(14, program: "Push"), s(3, program: "Pull"), s(10, program: "Pull")]
        XCTAssertEqual(GymCoach.scheduledProgram(sessions: sessions, now: now, calendar: cal), "Push")
    }

    func testScheduledProgramFallsBackToTheOneWaitedLongest() {
        // Today (Monday) has no history; Pull was run longer ago than Push.
        let sessions = [s(2, program: "Push"), s(9, program: "Pull")]
        XCTAssertEqual(GymCoach.scheduledProgram(sessions: sessions, now: now, calendar: cal), "Pull")
    }

    func testConditionBands() {
        XCTAssertEqual(GymCoach.condition(charge: 20, readiness: .primed), .poor)
        XCTAssertEqual(GymCoach.condition(charge: 80, readiness: .rundown), .poor)
        XCTAssertEqual(GymCoach.condition(charge: 45, readiness: nil), .fair)
        XCTAssertEqual(GymCoach.condition(charge: 80, readiness: .strained), .fair)
        XCTAssertEqual(GymCoach.condition(charge: 80, readiness: .primed), .good)
        XCTAssertNil(GymCoach.condition(charge: nil, readiness: .insufficient))
        XCTAssertNil(GymCoach.condition(charge: nil, readiness: nil))
    }

    func testAdjustmentLeavesSetsAloneAndKeepsPlateSteps() {
        let poor = GymCoach.adjust(for: .poor)
        XCTAssertEqual(GymCoach.adjustedWeight(60, poor), 47.5)   // 48 to the nearest 1.25
        XCTAssertEqual(GymCoach.adjustedReps(8, poor), 6)
        XCTAssertEqual(GymCoach.adjustedReps(5, poor), 3)   // not under 60%
        XCTAssertEqual(GymCoach.adjustedReps(2, poor), 2)
        XCTAssertEqual(GymCoach.adjustedSeconds(45, poor), 35)
        XCTAssertEqual(poor.weightCutPct, 20)
        XCTAssertTrue(GymCoach.adjust(for: .good).isNeutral)
        XCTAssertEqual(GymCoach.adjustedWeight(60, GymCoach.adjust(for: .good)), 60)
    }

    func testPickPrefersRestedGroupsAndFamiliarExercises() {
        let c: [GymCoach.Candidate] = [
            .init(name: "Bench", group: "chest", sets: 4), .init(name: "Fly", group: "chest", sets: 3), .init(name: "Pec", group: "chest", sets: 3),
            .init(name: "Squat", group: "legs", sets: 4), .init(name: "Row", group: "back", sets: 3),
        ]
        let out = GymCoach.pick(candidates: c, fatigue: ["chest": 0.7, "legs": 0.1, "back": 0.3], timesDone: ["Bench": 6, "Fly": 2], maxExercises: 3)
        XCTAssertEqual(out.map(\.name), ["Squat", "Row"])   // chest is still loaded
        let all = GymCoach.pick(candidates: c, fatigue: [:], timesDone: ["Bench": 6, "Fly": 2], maxExercises: 5)
        XCTAssertEqual(all.filter { $0.group == "chest" }.map(\.name), ["Bench", "Fly"])   // two a group, the most done first
    }
}
