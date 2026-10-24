import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// `HRZoneSet.reserveBands`: the zones are the Effort's own bands, so time in them agrees with the weights `StrainScorer` scores.
final class ReserveBandZonesTests: XCTestCase {
    func testBoundariesAreBandsOfTheReserve() {
        let z = HRZoneSet.reserveBands(maxHR: 190, restingHR: 54)
        XCTAssertEqual(z.zones.count, 5)
        XCTAssertEqual(z.zones[0].lower, 54 + 136 * 0.5, accuracy: 1e-9)
        XCTAssertEqual(z.zones[2].upper, 54 + 136 * 0.8, accuracy: 1e-9)
        XCTAssertEqual(z.zones[4].upper, 190, accuracy: 1e-9)
        XCTAssertEqual(z.source, "reserve")
    }

    /// 10 minutes at each of 100, 130, 150, 165 and 180 bpm: zone n holds exactly the minutes the Edwards weight n is applied to.
    func testZoneNumberIsTheEdwardsWeight() {
        let z = HRZoneSet.reserveBands(maxHR: 190, restingHR: 54)
        for bpm in [100, 130, 150, 165, 180, 53, 190] {
            let weight = StrainScorer.zoneWeight(Double(bpm), restingHR: 54, hrReserve: 136)
            XCTAssertEqual(z.zoneNumber(forBPM: Double(bpm)), weight, "\(bpm) bpm")
        }
    }

    func testTimeInZoneCountsTheMinutesPerBand() {
        var hr: [HRSample] = []; var t = 1_700_000_000
        for bpm in [100, 130, 150, 165, 180] { for _ in 0..<600 { hr.append(HRSample(ts: t, bpm: bpm)); t += 1 } }
        let z = HRZones.timeInZone(hr, zoneSet: .reserveBands(maxHR: 190, restingHR: 54))
        XCTAssertEqual(z.seconds.map { Int(($0 / 60).rounded()) }, [10, 0, 10, 10, 10])
    }
}
