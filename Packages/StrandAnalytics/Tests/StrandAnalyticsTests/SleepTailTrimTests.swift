import XCTest
@testable import StrandAnalytics

/// A night that ended where the strap stopped recording, stored as ending when the next data arrived: the stretch in between has
/// no movement at all (exact zeros) and must not be counted as wake.
final class SleepTailTrimTests: XCTestCase {

    private let start = 1_000_000
    private func night(sleepUntil: Int, end: Int) -> SleepSession {
        let stages = [StageSegment(start: start, end: start + 3_600, stage: "light"),
                      StageSegment(start: start + 3_600, end: start + sleepUntil, stage: "deep"),
                      StageSegment(start: start + sleepUntil, end: start + end, stage: "wake")]
        let eff = SleepStager.efficiency(start: start, end: start + end, stages: stages)
        return SleepSession(start: start, end: start + end, efficiency: eff, stages: stages, restingHR: 51, avgHRV: 70)
    }

    /// Movement per epoch: noisy (never zero) up to `until`, then `zeros` epochs of nothing, then noisy again.
    private func motion(epochs n: Int, noisyUntil until: Int, zeros: Int) -> [Double] {
        (0..<n).map { i in (i >= until && i < until + zeros) ? 0 : 0.05 + Double(i % 7) * 0.1 }
    }

    func testAStretchWithNoRecordingAfterTheLastSleepIsCut() {
        let s = night(sleepUntil: 25_200, end: 27_000)            // sleep to 7 h, session to 7.5 h
        let m = motion(epochs: 900, noisyUntil: 840, zeros: 55)  // 840 epochs = 7 h; then 27.5 min of nothing
        let t = SleepTailTrim.trimmed(s, motion: m)
        XCTAssertEqual(t.end, start + 25_200)
        XCTAssertEqual(t.stages.last?.stage, "deep")
        XCTAssertEqual(t.stages.last?.end, start + 25_200)
        XCTAssertEqual(t.efficiency, 1.0, accuracy: 1e-9)          // no wake left
    }

    func testAwakeTimeTheStrapRecordedIsKept() {
        let s = night(sleepUntil: 25_200, end: 27_000)
        let m = (0..<900).map { 0.05 + Double($0 % 7) * 0.1 }    // moving the whole time
        XCTAssertEqual(SleepTailTrim.trimmed(s, motion: m), s)
    }

    func testAGapInTheMiddleOfTheNightIsLeftAlone() {
        let s = night(sleepUntil: 25_200, end: 27_000)
        let m = motion(epochs: 900, noisyUntil: 200, zeros: 60)
        XCTAssertEqual(SleepTailTrim.trimmed(s, motion: m), s)
    }

    func testAGapThatStartsLongAfterTheLastSleepIsLeftAlone() {
        let s = night(sleepUntil: 24_000, end: 27_000)            // sleep to 6 h 40
        let m = motion(epochs: 900, noisyUntil: 850, zeros: 30)  // the gap starts 7 h 5, 25 min after the last sleep
        XCTAssertEqual(SleepTailTrim.trimmed(s, motion: m), s)
    }

    func testAShortGapIsNotEnough() {
        let s = night(sleepUntil: 25_200, end: 27_000)
        let m = motion(epochs: 900, noisyUntil: 840, zeros: 10)  // 5 min
        XCTAssertEqual(SleepTailTrim.trimmed(s, motion: m), s)
    }

    func testNoMovementSeriesLeavesTheNightAlone() {
        let s = night(sleepUntil: 25_200, end: 27_000)
        XCTAssertEqual(SleepTailTrim.trimmed(s, motion: []), s)
    }

    func testAShortWakeAtTheEndIsNotTouched() {
        let s = night(sleepUntil: 26_800, end: 27_000)            // 200 s of wake: inside the grace
        let m = motion(epochs: 900, noisyUntil: 890, zeros: 10)
        XCTAssertEqual(SleepTailTrim.trimmed(s, motion: m), s)
    }
}
