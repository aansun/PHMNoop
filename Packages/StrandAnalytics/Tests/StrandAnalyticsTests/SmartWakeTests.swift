import XCTest
@testable import StrandAnalytics
import WhoopProtocol
import WhoopStore

final class SmartWakeTests: XCTestCase {

    /// The wake time of every case: an arbitrary fixed instant.
    private let latest = Date(timeIntervalSince1970: 1_700_000_000)
    private func before(_ seconds: TimeInterval) -> Date { latest.addingTimeInterval(-seconds) }

    private func decide(_ mode: SmartWake.Mode, minutesLeft: Double = 30, asleep: Double = 0, recovery: Double? = nil,
                        dataAgeMin: Double = 2, need: Double = 480, goal: Int = 100, noNight: Bool = false) -> SmartWake.Decision {
        let now = before(minutesLeft * 60)
        let night = noNight ? nil : SmartWake.Night(asleepMin: asleep, recovery: recovery, dataEnd: now.addingTimeInterval(-dataAgeMin * 60))
        return SmartWake.decide(now: now, latest: latest, mode: mode, needMin: need, goalPercent: goal, night: night)
    }

    func testExactModeNeverWakesEarly() {
        XCTAssertEqual(decide(.exact, asleep: 600, recovery: 99), .idle)
    }

    func testOnlyTheHourBeforeCounts() {
        XCTAssertEqual(decide(.goal, minutesLeft: 61, asleep: 600), .idle)
        XCTAssertEqual(decide(.goal, minutesLeft: 60, asleep: 600), .wake)
        XCTAssertEqual(decide(.goal, minutesLeft: 3, asleep: 600), .wake)
        XCTAssertEqual(decide(.goal, minutesLeft: 2, asleep: 600), .idle)
        XCTAssertEqual(decide(.goal, minutesLeft: -5, asleep: 600), .idle)
    }

    func testStaleOrMissingDataAsksForData() {
        XCTAssertEqual(decide(.goal, asleep: 600, dataAgeMin: 20), .wake)
        XCTAssertEqual(decide(.goal, asleep: 600, dataAgeMin: 21), .needData)
        XCTAssertEqual(decide(.green, noNight: true), .needData)
    }

    func testSleepGoalIsAShareOfTheNeed() {
        XCTAssertEqual(decide(.goal, asleep: 479), .keepSleeping)
        XCTAssertEqual(decide(.goal, asleep: 480), .wake)
        XCTAssertEqual(decide(.goal, asleep: 408, goal: 85), .wake)
        XCTAssertEqual(decide(.goal, asleep: 407, goal: 85), .keepSleeping)
        XCTAssertEqual(decide(.goal, asleep: 336, goal: 70), .wake)
        XCTAssertEqual(decide(.goal, asleep: 600, need: 0), .keepSleeping)
    }

    func testGreenNeedsRecoveryAndEnoughSleep() {
        XCTAssertEqual(decide(.green, asleep: 300, recovery: 67), .wake)
        XCTAssertEqual(decide(.green, asleep: 300, recovery: 66.6), .wake)
        XCTAssertEqual(decide(.green, asleep: 300, recovery: 66.4), .keepSleeping)
        XCTAssertEqual(decide(.green, asleep: 239, recovery: 90), .keepSleeping)
        XCTAssertEqual(decide(.green, asleep: 400, recovery: nil), .keepSleeping)
    }

    /// The early wake reads a night that has not ended: the one-day analysis must count the sleep of a still stretch that runs to the last sample.
    func testAnalyzeDayCountsANightStillInProgress() {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.timeZone = TimeZone(identifier: "UTC"); fmt.dateFormat = "yyyy-MM-dd"
        let day = "2021-06-15"
        let now = Int(fmt.date(from: day)!.timeIntervalSince1970) + 4 * 3600 + 1800   // 04:30, still asleep
        let onset = now - 6 * 3600
        var hr: [HRSample] = [], rr: [RRInterval] = [], gravity: [GravitySample] = []
        // An active evening first, then the still night running to the last sample.
        for t in (onset - 3 * 3600)..<onset {
            hr.append(HRSample(ts: t, bpm: 80))
            gravity.append(GravitySample(ts: t, x: sin(Double(t)), y: cos(Double(t)), z: 0.2))
        }
        for t in onset..<now {
            hr.append(HRSample(ts: t, bpm: 50))
            gravity.append(GravitySample(ts: t, x: 0, y: 0, z: 1))
        }
        for t in stride(from: onset, to: now, by: 2) { rr.append(RRInterval(ts: t, rrMs: (t / 2) % 2 == 0 ? 1205 : 1195)) }
        let result = AnalyticsEngine.analyzeDay(day: day, hr: hr, rr: rr, gravity: gravity, profile: UserProfile(age: 30))
        let asleep = result.daily.totalSleepMin ?? 0
        XCTAssertGreaterThan(asleep, 300, "six still hours should count as most of six hours asleep, got \(asleep)")
        XCTAssertLessThanOrEqual(asleep, 361)
    }
}
