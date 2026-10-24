import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// `analyzeDay(useSessionMeanRestingHR:)`: the day's resting HR is the mean of the main sleep instead of the lowest session floor,
/// and what is scored against it follows. The default stays the floor, byte-identical to before.
final class AnalyticsEngineSessionMeanRestingHRTests: XCTestCase {
    private let day = "2021-06-15"

    /// A still night whose HR is 48 for the first third and 58 for the rest: the floor is the quiet stretch, the mean sits between.
    private func night() -> (hr: [HRSample], rr: [RRInterval], grav: [GravitySample]) {
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.timeZone = TimeZone(identifier: "UTC"); fmt.dateFormat = "yyyy-MM-dd"
        let end = Int(fmt.date(from: day)!.timeIntervalSince1970) + 6 * 3600
        let start = end - 7 * 3600
        let third = start + (end - start) / 3
        var hr: [HRSample] = [], rr: [RRInterval] = [], grav: [GravitySample] = []
        for t in start..<end {
            hr.append(HRSample(ts: t, bpm: t < third ? 48 : 58))
            grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))
        }
        var toggle = false
        for t in stride(from: start, to: end, by: 2) { rr.append(RRInterval(ts: t, rrMs: toggle ? 1205 : 1195)); toggle.toggle() }
        return (hr, rr, grav)
    }

    private func analyze(_ n: (hr: [HRSample], rr: [RRInterval], grav: [GravitySample]), mean: Bool) -> AnalyticsEngine.DayResult {
        AnalyticsEngine.analyzeDay(day: day, hr: n.hr, rr: n.rr, gravity: n.grav,
                                   profile: UserProfile(weightKg: 75, heightCm: 178, age: 30, sex: "male"),
                                   useSessionMeanRestingHR: mean)
    }

    func testDefaultIsTheFloor() {
        let n = night()
        let r = analyze(n, mean: false)
        XCTAssertEqual(r.daily.restingHr, r.sleepSessions.compactMap { $0.restingHR }.min())
        XCTAssertLessThanOrEqual(r.daily.restingHr ?? 99, 49)
    }

    func testMeanIsTheSessionMeanAndAboveTheFloor() {
        let n = night()
        let floor = analyze(n, mean: false).daily.restingHr!
        let r = analyze(n, mean: true)
        let expected = AnalyticsEngine.primarySessionRestingHR(sessions: r.sleepSessions, hr: n.hr).map { Int($0.rounded()) }
        XCTAssertEqual(r.daily.restingHr, expected, "the day's resting HR is exactly the mean the app stores beside it")
        XCTAssertGreaterThan(r.daily.restingHr!, floor)
        XCTAssertEqual(r.cachedSleep.first?.restingHr, floor, "the session keeps its own floor")
    }

    func testSessionsAreUnchangedByTheFlag() {
        let n = night()
        let a = analyze(n, mean: false), b = analyze(n, mean: true)
        XCTAssertEqual(a.sleepSessions.map { [$0.start, $0.end] }, b.sleepSessions.map { [$0.start, $0.end] })
        XCTAssertEqual(a.daily.totalSleepMin, b.daily.totalSleepMin)
        XCTAssertEqual(a.daily.avgHrv, b.daily.avgHrv)
    }

    func testNoSleepFallsBackToNil() {
        let r = AnalyticsEngine.analyzeDay(day: day, profile: UserProfile(age: 30), useSessionMeanRestingHR: true)
        XCTAssertNil(r.daily.restingHr)
    }
}
