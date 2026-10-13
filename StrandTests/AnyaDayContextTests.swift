import XCTest
@testable import Strand

final class AnyaDayContextTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testPartsOfTheDay() {
        XCTAssertEqual(AnyaDayContext.part(hour: 3), .night)
        XCTAssertEqual(AnyaDayContext.part(hour: 7), .morning)
        XCTAssertEqual(AnyaDayContext.part(hour: 12), .midday)
        XCTAssertEqual(AnyaDayContext.part(hour: 16), .afternoon)
        XCTAssertEqual(AnyaDayContext.part(hour: 20), .evening)
        XCTAssertEqual(AnyaDayContext.part(hour: 23), .night)
    }

    func testBedtimeIsCentredOnMidsleepAndWrapsPastMidnight() {
        // Midsleep 03:00, need 8 h: asleep by 23:00.
        XCTAssertEqual(AnyaDayContext.clock(seconds: AnyaDayContext.asleepBySec(midsleepSec: 3 * 3600, needMin: 480)), "23:00")
        // Midsleep 03:30, need 7 h 30: asleep by 23:45.
        XCTAssertEqual(AnyaDayContext.clock(seconds: AnyaDayContext.asleepBySec(midsleepSec: 3 * 3600 + 1800, needMin: 450)), "23:45")
    }

    func testClockLineAlwaysPresentAndMorningPointsAtThePlan() {
        let out = AnyaDayContext.block(.init(now: date(2026, 10, 13, 7, 5), calendar: cal))
        XCTAssertTrue(out.hasPrefix("RIGHT NOW: Tuesday 13 October, 07:05 (morning)."))
        XCTAssertTrue(out.contains("planning part of the day"))
        XCTAssertFalse(out.contains("SLEEP TONIGHT"))
        XCTAssertFalse(out.contains("SUGGESTED SESSION"))
    }

    func testEveningPointsAtReviewAndBedtimeNotANewHardSession() {
        let out = AnyaDayContext.block(.init(now: date(2026, 10, 13, 21, 40), calendar: cal))
        XCTAssertTrue(out.contains("(evening)"))
        XCTAssertTrue(out.contains("review part of the day"))
    }

    func testFullBlockCarriesPlanEffortAndSleep() {
        var i = AnyaDayContext.Input(now: date(2026, 10, 13, 19, 0), calendar: cal)
        i.chargePct = 72
        i.sessionTitle = "Tempo session, 42 min"
        i.sessionMainZone = 4
        i.sessionEffortLow = 11.6
        i.sessionEffortHigh = 17.4
        i.todayEffort = 6.25
        i.usualEffort = 10
        i.weekEffort = 48.4
        i.weeklyEffortGoal = 70
        i.sleepNeedMin = 465
        i.sleepDebtMin = 80
        i.habitualMidsleepSec = 3 * 3600
        let out = AnyaDayContext.block(i)
        XCTAssertTrue(out.contains("Effort so far today 6.2"), out)   // %.1f of 6.25 rounds to even → 6.2
        XCTAssertTrue(out.contains("usual day is about 10.0"))
        XCTAssertTrue(out.contains("last 7 days 48 of the weekly target 70"))
        XCTAssertTrue(out.contains("Tempo session, 42 min, main work in zone 4, about +12-17 Effort"))
        XCTAssertTrue(out.contains("Charge of 72"))
        XCTAssertTrue(out.contains("need about 7h 45m"))
        XCTAssertTrue(out.contains("debt of about 1h 20m"))
        XCTAssertTrue(out.contains("asleep by about 23:07"), out)   // 03:00 − 3 h 52.5 m → 23:07:30 → 23:07
    }

    func testNegligibleDebtIsSaidAsSuch() {
        var i = AnyaDayContext.Input(now: date(2026, 10, 13, 9, 0), calendar: cal)
        i.sleepNeedMin = 480
        i.sleepDebtMin = 0
        XCTAssertTrue(AnyaDayContext.block(i).contains("no meaningful debt"))
    }

    func testNoEffortBankedYetIsStatedNotZeroed() {
        var i = AnyaDayContext.Input(now: date(2026, 10, 13, 9, 0), calendar: cal)
        i.todayEffort = 0
        XCTAssertTrue(AnyaDayContext.block(i).contains("no Effort banked yet today"))
    }
}

/// The zone line added to the recent-workouts block. Twin text pinned in Kotlin `AiCoachWorkoutBlockTest`.
final class AICoachZoneShareTests: XCTestCase {
    func testSharesRoundAndSkipEmptyZones() {
        let json = #"{"z1":0.2,"z2":28.0,"z3":33.5,"z4":18.0,"z5":6.0}"#
        XCTAssertEqual(AICoachEngine.zoneShareText(json), "time in zones Z2 28% Z3 34% Z4 18% Z5 6%")
    }

    func testAndroidKeyShapeIsAccepted() {
        XCTAssertEqual(AICoachEngine.zoneShareText(#"{"zone1":20.0,"zone2":35.0,"zone3":30.0,"zone4":10.0}"#),
                       "time in zones Z1 20% Z2 35% Z3 30% Z4 10%")
    }

    func testNoZoneDataAddsNothing() {
        XCTAssertNil(AICoachEngine.zoneShareText(nil))
        XCTAssertNil(AICoachEngine.zoneShareText("{}"))
        XCTAssertNil(AICoachEngine.zoneShareText(#"{"z1":0.1}"#))
    }
}

final class AnyaDayContextFeelingsTests: XCTestCase {
    func testFeelingsLineIsCappedAtThreeAndAbsentWhenEmpty() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        let now = c.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9))!
        var i = AnyaDayContext.Input(now: now, calendar: c)
        XCTAssertFalse(AnyaDayContext.block(i).contains("HOW RECENT SESSIONS FELT"))
        i.sessionFeelings = ["Running, Challenging", "Cycling, Easy", "Strength, Decent", "Walking, Easy"]
        let out = AnyaDayContext.block(i)
        XCTAssertTrue(out.contains("newest first): Running, Challenging; Cycling, Easy; Strength, Decent."))
        XCTAssertFalse(out.contains("Walking"))
    }
}

/// What Anya is told to do next, for a spread of situations: the same numbers must give the same next step.
final class AnyaNextStepTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }

    private func input(_ hour: Int, _ minute: Int = 0, charge: Double? = 75, kind: String? = "quality",
                       today: Double? = 0, debt: Double? = 20, bedtimeKnown: Bool = true) -> AnyaDayContext.Input {
        var i = AnyaDayContext.Input(now: cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: hour, minute: minute))!, calendar: cal)
        i.chargePct = charge
        i.sessionKind = kind
        i.sessionTitle = kind == nil ? nil : "Tempo session, 42 min"
        i.sessionEffortLow = 12; i.sessionEffortHigh = 17
        i.todayEffort = today; i.usualEffort = 10
        if bedtimeKnown { i.sleepNeedMin = 465; i.sleepDebtMin = debt; i.habitualMidsleepSec = 3 * 3600 }
        return i
    }

    private func step(_ i: AnyaDayContext.Input) -> String { AnyaDayContext.nextStep(i) ?? "" }

    func testMorningQualityDayPointsAtTheSuggestedSession() {
        XCTAssertTrue(step(input(7)).contains("quality session fits today: Tempo session, 42 min"))
    }

    func testLowChargeKeepsTheDayEasy() {
        XCTAssertTrue(step(input(7, charge: 25, kind: "recovery")).hasPrefix("Keep today easy"))
    }

    func testNoChargeYetAsksForSync() {
        XCTAssertTrue(step(input(7, charge: nil, kind: nil)).contains("wear the strap overnight and sync"))
    }

    func testLoadAlreadyBankedMeansRecover() {
        XCTAssertTrue(step(input(13, today: 14)).contains("already banked"))
    }

    func testDebtBringsTheBedtimeIntoTheMorning() {
        let s = step(input(8, charge: 55, kind: "steady", debt: 120))
        XCTAssertTrue(s.contains("2h of sleep debt, be asleep by 23:07"), s)
    }

    func testHardSessionTooCloseToBedtimeIsMadeEasy() {
        // An early sleeper (midsleep 23:00, need 7h 45m → asleep by 19:07): at 16:00 the bed is 187 minutes away.
        var i = input(16)
        i.habitualMidsleepSec = 23 * 3600
        let s = step(i)
        XCTAssertTrue(s.contains("too close to bedtime"), s)
        XCTAssertFalse(s.contains("quality session fits"))
        // The same session in the morning is fine.
        i = input(8)
        i.habitualMidsleepSec = 23 * 3600
        XCTAssertTrue(step(i).contains("quality session fits"))
    }

    func testDoneIsJudgedByTheTodayCardsBand() {
        // Effort 15 on the stored axis is under a 67-86 band, so the load is not done even though it is above the usual day.
        var i = input(13, today: 15)
        i.effortTargetLow = 66.7; i.effortTargetHigh = 85.7
        XCTAssertFalse(step(i).contains("already banked"), step(i))
        i.todayEffort = 70
        XCTAssertTrue(step(i).contains("already banked"), step(i))
    }

    func testEveningWithLoadDoneKeepsItEasyAndNamesBedtime() {
        XCTAssertEqual(step(input(20, 30, today: 15)), "The day's load is done. Eat, hydrate and keep the evening easy so you can be asleep by 23:07.")
    }

    func testEveningWithRoomOffersAShortEasySessionEndingTwoHoursBeforeBed() {
        XCTAssertTrue(step(input(19, 30)).contains("finished at least two hours before 23:07"))
    }

    func testCloseToBedtimeWindsDown() {
        XCTAssertTrue(step(input(21, 40)).hasPrefix("Wind down now"))
    }

    func testPastBedtimeSaysSoAndMiddleOfTheNightSaysSleep() {
        XCTAssertTrue(step(input(23, 50)).contains("already past the target bedtime of 23:07"))
        XCTAssertTrue(step(input(1, 30)).contains("middle of the night"))
    }

    func testEveningWithoutSleepDataStillNeverPushesASession() {
        let s = step(input(21, bedtimeKnown: false))
        XCTAssertFalse(s.contains("quality session"), s)
    }
}
