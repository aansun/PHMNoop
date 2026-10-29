import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class WhoopStressTests: XCTestCase {
    private let t0 = 1_700_000_000

    /// A baseline of 14 nights at 52 bpm and 85 ms, with a little spread.
    private var baseline: WhoopStress.Baseline {
        let rhr = (0..<14).map { 52 + Double($0 % 3) - 1 }
        let hrv = (0..<14).map { 85 + Double($0 % 4) * 3 - 4 }
        return WhoopStress.Baseline.from(nightlyRMSSD: hrv, nightlyRestingHR: rhr)!
    }

    /// A steady heart rate and R-R that alternate around the mean so the RMSSD is exactly `rmssd`.
    private func stream(bpm: Int, rmssd: Double, seconds: Int, from start: Int) -> (hr: [HRSample], rr: [RRInterval]) {
        let hr = (0..<seconds).map { HRSample(ts: start + $0, bpm: bpm) }
        let mean = 60_000.0 / Double(bpm), d = rmssd / 2
        var rr: [RRInterval] = []
        var t = 0.0, i = 0
        while t < Double(seconds) {
            let v = mean + (i % 2 == 0 ? d : -d)
            rr.append(RRInterval(ts: start + Int(t), rrMs: Int(v.rounded())))
            t += v / 1000; i += 1
        }
        return (hr, rr)
    }

    func testBaselineNeedsFourNights() {
        XCTAssertNil(WhoopStress.Baseline.from(nightlyRMSSD: [80, 85, 90], nightlyRestingHR: [52, 53, 51]))
        let b = baseline
        XCTAssertEqual(b.nights, 14)
        XCTAssertEqual(b.restingHR, 52, accuracy: 0.6)
    }

    func testBaselineUsesOnlyTheNewestFourteenNights() {
        let old = [Double](repeating: 40, count: 20)
        let recent = [Double](repeating: 90, count: 14)
        let b = WhoopStress.Baseline.from(nightlyRMSSD: old + recent, nightlyRestingHR: old + recent)!
        XCTAssertEqual(b.restingHR, 90, accuracy: 1e-9)
        XCTAssertEqual(exp(b.hrvLnMean), 90, accuracy: 1e-6)
    }

    func testATypicalNightIsLowAndATypicalWakingHourIsMedium() {
        let b = baseline
        let night = stream(bpm: Int(b.restingHR.rounded()) + 3, rmssd: exp(b.hrvLnMean), seconds: 3600, from: t0)
        let sleep = WhoopStress.analyze(hr: night.hr, rr: night.rr, sleep: [t0...(t0 + 3600)], baseline: b)
        XCTAssertLessThan(sleep.sleep.low + sleep.sleep.medium + sleep.sleep.high, 61)
        XCTAssertGreaterThan(sleep.sleep.low, 40, "a typical night should read Low")
        XCTAssertEqual(sleep.sleep.high, 0)

        let day = stream(bpm: Int((b.restingHR + 20).rounded()), rmssd: exp(b.hrvLnMean) * 0.6, seconds: 3600, from: t0)
        let wake = WhoopStress.analyze(hr: day.hr, rr: day.rr, baseline: b)
        XCTAssertGreaterThan(wake.nonActivity.medium, 40, "a typical waking hour should read Medium")
    }

    func testRaisedHeartRateAndLowHRVReadsHigh() {
        let b = baseline
        let s = stream(bpm: Int(b.restingHR) + 38, rmssd: exp(b.hrvLnMean) * 0.3, seconds: 3600, from: t0)
        let r = WhoopStress.analyze(hr: s.hr, rr: s.rr, baseline: b)
        XCTAssertGreaterThan(r.nonActivity.high, 40)
        XCTAssertEqual(r.nonActivity.low, 0)
    }

    func testTooLittleHeartRateIsNotScored() {
        let b = baseline
        let hr = (0..<60).map { HRSample(ts: t0 + $0, bpm: 70) }
        let r = WhoopStress.analyze(hr: hr, rr: [], baseline: b)
        XCTAssertTrue(r.epochs.allSatisfy { $0.level == nil })
        XCTAssertEqual(r.total.total, 0)
    }

    func testHeartRateOnlyDropsTheHRVTerm() {
        let b = baseline
        let s = stream(bpm: 72, rmssd: 50, seconds: 1800, from: t0)
        var tuning = WhoopStress.Tuning(); tuning.useHRV = false
        let r = WhoopStress.analyze(hr: s.hr, rr: s.rr, baseline: b, tuning: tuning)
        XCTAssertTrue(r.epochs.compactMap { $0.level }.count > 0)
        XCTAssertTrue(r.epochs.allSatisfy { !$0.usedHRV })
    }

    func testAnActivityIsOutOfNonActivityButInTotalAndPulledTowardNeutral() {
        let b = baseline
        let s = stream(bpm: 150, rmssd: 10, seconds: 3600, from: t0)
        let range = t0...(t0 + 3600)
        let damped = WhoopStress.analyze(hr: s.hr, rr: s.rr, activities: [range], baseline: b)
        XCTAssertEqual(damped.nonActivity.total, 0)
        XCTAssertGreaterThan(damped.total.total, 40)
        var raw = WhoopStress.Tuning(); raw.activityDamping = 0
        let undamped = WhoopStress.analyze(hr: s.hr, rr: s.rr, activities: [range], baseline: b, tuning: raw)
        let a = damped.epochs.compactMap { $0.level }.reduce(0, +) / Double(damped.epochs.compactMap { $0.level }.count)
        let u = undamped.epochs.compactMap { $0.level }.reduce(0, +) / Double(undamped.epochs.compactMap { $0.level }.count)
        XCTAssertLessThan(a, u, "damping must pull exertion toward neutral")
        XCTAssertGreaterThan(a, 1.5, "but exertion still adds to the day")
    }

    func testOneWildReadingCannotMoveTheScoreByTheWholeBand() {
        let b = baseline
        // A heart rate far above anything plausible: the z-score is clamped, so the score stays on the curve's shoulder, below 3.
        let s = stream(bpm: 200, rmssd: 5, seconds: 1800, from: t0)
        let r = WhoopStress.analyze(hr: s.hr, rr: s.rr, baseline: b)
        XCTAssertTrue(r.epochs.compactMap { $0.level }.allSatisfy { $0 < 2.95 })
    }

    func testCurrentIsTheMeanOfTheLastThreeScoredEpochs() {
        let b = baseline
        let s = stream(bpm: 72, rmssd: 50, seconds: 3600, from: t0)
        let r = WhoopStress.analyze(hr: s.hr, rr: s.rr, baseline: b)
        let last3 = r.epochs.compactMap { $0.level }.suffix(3)
        XCTAssertEqual(r.current ?? -1, last3.reduce(0, +) / 3, accuracy: 1e-12)
    }

    func testCalibrationMakesTheUsualWakingStateNeutral() {
        let b = baseline
        // A person whose usual waking heart rate is 30 bpm over resting and whose waking RMSSD is 40% of the nightly one.
        let s = stream(bpm: Int(b.restingHR.rounded()) + 30, rmssd: exp(b.hrvLnMean) * 0.4, seconds: 3 * 3600, from: t0)
        let first = WhoopStress.analyze(hr: s.hr, rr: s.rr, baseline: b)
        let tuned = WhoopStress.calibrated(WhoopStress.Tuning(), from: first.epochs, baseline: b, minEpochs: 20)
        XCTAssertEqual(tuned.wakeHROffsetBPM, 30, accuracy: 1.0)
        XCTAssertEqual(tuned.wakeHRVRatio, 0.4, accuracy: 0.05)
        let again = WhoopStress.analyze(hr: s.hr, rr: s.rr, baseline: b, tuning: tuned)
        let mean = again.epochs.compactMap { $0.level }.reduce(0, +) / Double(again.epochs.compactMap { $0.level }.count)
        XCTAssertEqual(mean, 1.5, accuracy: 0.25, "their usual state is neutral after calibration")
        let before = first.epochs.compactMap { $0.level }.reduce(0, +) / Double(first.epochs.compactMap { $0.level }.count)
        XCTAssertGreaterThan(before, 2.0, "and read as High before it")
    }

    func testCalibrationNeedsEnoughEpochs() {
        let b = baseline
        let s = stream(bpm: 80, rmssd: 40, seconds: 900, from: t0)
        let first = WhoopStress.analyze(hr: s.hr, rr: s.rr, baseline: b)
        let tuned = WhoopStress.calibrated(WhoopStress.Tuning(), from: first.epochs, baseline: b)
        XCTAssertEqual(tuned, WhoopStress.Tuning())
    }

    func testCalibrationRecordRoundTripsAndKeepsTheTwoConstants() throws {
        var t = WhoopStress.Tuning(); t.wakeHROffsetBPM = 17.5; t.wakeHRVRatio = 0.8
        let c = WhoopStress.Calibration(baseline: baseline, tuning: t, newestNight: "2026-10-08")
        let back = try JSONDecoder().decode(WhoopStress.Calibration.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
        XCTAssertEqual(back.tuning.wakeHROffsetBPM, 17.5)
        XCTAssertEqual(back.tuning.wakeHRVRatio, 0.8)
        XCTAssertEqual(back.tuning.hrWeight, WhoopStress.Tuning().hrWeight, "everything else stays stock")
    }

    func testNightFiguresReadRestingHeartRateAndRMSSD() {
        let s = stream(bpm: 54, rmssd: 80, seconds: 2 * 3600, from: t0)
        let f = WhoopStress.nightFigures(hr: s.hr, rr: s.rr, from: t0, to: t0 + 2 * 3600)
        XCTAssertNotNil(f)
        XCTAssertEqual(f!.rhr, 54, accuracy: 0.5)
        XCTAssertEqual(f!.rmssd, 80, accuracy: 4)
        XCTAssertNil(WhoopStress.nightFigures(hr: [], rr: [], from: t0, to: t0 + 7200))
    }

    func testDaytimeResultCarriesTheHighMinutesAndAnHourlyAndHalfHourlyRead() {
        let b = baseline
        let s = stream(bpm: Int(b.restingHR) + 38, rmssd: exp(b.hrvLnMean) * 0.3, seconds: 3 * 3600, from: t0)
        let r = WhoopStress.analyze(hr: s.hr, rr: s.rr, baseline: b)
        let d = WhoopStress.daytimeResult(r)
        XCTAssertGreaterThan(d.hours.count, 1)
        XCTAssertGreaterThan(d.timeline.count, d.hours.count, "the half-hourly read has more points")
        XCTAssertEqual(d.highStressMinutes, r.epochs.filter { ($0.level ?? 0) >= 2 }.count * 5)
        XCTAssertTrue(d.sustainedHigh, "three hours of High in a row")
        XCTAssertNotNil(d.dayMean)
    }
}
