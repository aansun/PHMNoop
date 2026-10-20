import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class LiveStrainTests: XCTestCase {
    private func steady(minutes: Int, bpm: Int) -> [HRSample] {
        (0...(minutes * 60)).map { HRSample(ts: 1_000_000 + $0, bpm: bpm) }
    }

    /// The day gate refuses a two-minute window; a running session must not wait ten minutes for its gauge to move.
    func testLiveMovesInTheFirstMinutes() {
        let hr = steady(minutes: 2, bpm: 150)
        XCTAssertNil(StrainScorer.strain(hr, maxHR: 190, restingHR: 60, method: .edwards))
        let live = StrainScorer.liveStrain(hr, maxHR: 190, restingHR: 60, method: .edwards)
        XCTAssertNotNil(live)
        XCTAssertGreaterThan(live ?? 0, 0)
    }

    /// Past the gate the two agree, so the live number and the day's number cannot disagree about the same window.
    func testLiveAgreesWithStrainOnceTheGateIsPassed() {
        let hr = steady(minutes: 15, bpm: 140)
        let day = StrainScorer.strain(hr, maxHR: 190, restingHR: 60, method: .edwards)
        let live = StrainScorer.liveStrain(hr, maxHR: 190, restingHR: 60, method: .edwards)
        XCTAssertEqual(live ?? -1, day ?? -2, accuracy: 0.0001)
    }

    func testLiveGrowsWithTimeAndNeedsTwoSamples() {
        XCTAssertNil(StrainScorer.liveStrain([HRSample(ts: 1, bpm: 150)], maxHR: 190, restingHR: 60))
        let a = StrainScorer.liveStrain(steady(minutes: 2, bpm: 150), maxHR: 190, restingHR: 60) ?? 0
        let b = StrainScorer.liveStrain(steady(minutes: 8, bpm: 150), maxHR: 190, restingHR: 60) ?? 0
        XCTAssertGreaterThan(b, a)
    }
}
