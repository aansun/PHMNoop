import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// `StrainScorer.loadBreakdown` splits a day's load by heart-rate-reserve band with the arithmetic `strain` uses.
final class StrainLoadBreakdownTests: XCTestCase {
    /// 1 Hz readings: 10 minutes each at 100, 130, 150, 165, 180 bpm.
    private func hr() -> [HRSample] {
        var out: [HRSample] = []; var t = 1_700_000_000
        for bpm in [100, 130, 150, 165, 180] { for _ in 0..<600 { out.append(HRSample(ts: t, bpm: bpm)); t += 1 } }
        return out
    }

    func testEdwardsPartsAddUpToTheTrimp() throws {
        let h = hr()
        let b = try XCTUnwrap(StrainScorer.loadBreakdown(h, maxHR: 190, restingHR: 54, method: .edwards))
        let trimp = StrainScorer.edwardsTRIMP(h, restingHR: 54, hrReserve: 136, durations: StrainScorer.sampleDurationsMinutes(h))
        XCTAssertEqual(b.totalLoad, trimp, accuracy: 1e-6)
        XCTAssertEqual(b.belowLoad, 0, accuracy: 1e-9)
        XCTAssertEqual(b.bands.count, 5)
        XCTAssertEqual(b.peakBPM, 180)
    }

    func testBandsFollowTheReserveAndTheWeights() throws {
        // reserve 136, resting 54: 100 bpm = 33.8% (below), 130 = 55.9% (band 1), 150 = 70.6% (band 3), 165 = 81.6% (band 4), 180 = 92.6% (band 5)
        let b = try XCTUnwrap(StrainScorer.loadBreakdown(hr(), maxHR: 190, restingHR: 54, method: .edwards))
        XCTAssertEqual(b.bands.map { Int($0.minutes.rounded()) }, [10, 0, 10, 10, 10])
        XCTAssertEqual(b.bands[0].load, 10, accuracy: 0.05)      // weight 1
        XCTAssertEqual(b.bands[2].load, 30, accuracy: 0.05)      // weight 3
        XCTAssertEqual(b.bands[4].load, 50, accuracy: 0.05)      // weight 5
        XCTAssertEqual(b.minutesHard, 20, accuracy: 0.1)
        XCTAssertEqual(b.bands[2].lowBPM, 54 + Int((136 * 0.7).rounded()))
    }

    func testBanisterPartsAddUpToTheTrimp() throws {
        let h = hr()
        let bb = StrainScorer.banisterBMen
        let expected = StrainScorer.banisterTRIMP(h, restingHR: 54, hrReserve: 136, durations: StrainScorer.sampleDurationsMinutes(h), b: bb,
                                                  floorRatePerMinute: StrainScorer.banisterBaselineRatePerMinute(b: bb))
        let b = try XCTUnwrap(StrainScorer.loadBreakdown(h, maxHR: 190, restingHR: 54, method: .banister, sex: "male"))
        XCTAssertEqual(b.totalLoad, expected, accuracy: 1e-6)
    }

    func testEffortImpliedByTheLoadMatchesStrain() throws {
        let h = hr()
        let b = try XCTUnwrap(StrainScorer.loadBreakdown(h, maxHR: 190, restingHR: 54, method: .edwards))
        let scored = try XCTUnwrap(StrainScorer.liveStrain(h, maxHR: 190, restingHR: 54, method: .edwards))
        XCTAssertEqual(b.effort(sex: "male"), scored, accuracy: 0.01)
    }

    func testEmptyOrNoReserveIsNil() {
        XCTAssertNil(StrainScorer.loadBreakdown([], maxHR: 190, restingHR: 54))
        XCTAssertNil(StrainScorer.loadBreakdown(hr(), maxHR: 50, restingHR: 54))
    }
}
