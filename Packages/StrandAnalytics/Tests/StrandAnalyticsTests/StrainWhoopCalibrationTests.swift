import XCTest
import WhoopProtocol
@testable import StrandAnalytics

/// Holds the Banister sedentary floor (`StrainScorer.banisterSedentaryHRR`) to the eight WHOOP-app days it was calibrated on, and
/// records why Banister replaced Edwards as the iOS default: Edwards reads zero on a quiet day where WHOOP shows 2 to 5.
final class StrainWhoopCalibrationTests: XCTestCase {

    private let hrMax = StrainScorer.tanakaHRmax(age: 36)

    private func hr(_ day: WhoopCalibrationDay) -> [HRSample] {
        day.samples.map { HRSample(ts: 1_800_000_000 + $0.minute * 60, bpm: $0.bpm) }
    }

    /// Day Strain on WHOOP's 0-21 axis (PHMN's Effort is 0-100; the app maps 21 to 100 linearly).
    private func score(_ day: WhoopCalibrationDay, _ method: StrainScorer.Method) -> Double {
        (StrainScorer.strain(hr(day), maxHR: hrMax, restingHR: day.restingHR, method: method, sex: "male") ?? 0) * 21.0 / 100.0
    }

    private func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
        var sab = 0.0, saa = 0.0, sbb = 0.0
        for i in a.indices { sab += (a[i] - ma) * (b[i] - mb); saa += (a[i] - ma) * (a[i] - ma); sbb += (b[i] - mb) * (b[i] - mb) }
        return sab / (saa * sbb).squareRoot()
    }

    func testTheFloorIsTheCalibratedValue() {
        XCTAssertEqual(StrainScorer.banisterSedentaryHRR, 0.18, accuracy: 1e-12)
    }

    func testTheFixtureIsWhatItClaimsToBe() {
        let days = WhoopCalibrationFixtures.days
        XCTAssertEqual(days.count, 8)
        for d in days {
            XCTAssertGreaterThan(d.samples.count, 1000, d.label)         // about a day of minutes
            XCTAssertTrue(d.samples.allSatisfy { (35...200).contains($0.bpm) }, d.label)
        }
    }

    func testBanisterTracksWhoopDayStrain() {
        let days = WhoopCalibrationFixtures.days
        let mine = days.map { score($0, .banister) }
        let whoop = days.map { $0.whoopDayStrain }
        let errors = zip(mine, whoop).map { $0 - $1 }
        let mae = errors.map(abs).reduce(0, +) / Double(errors.count)
        let r = pearson(mine, whoop)
        // Measured when the floor was set: MAE 2.4 at 0.18 (3.7 at the old 0.10), and the worst single day 3.7 off.
        XCTAssertLessThan(mae, 2.9, "mean absolute error against WHOOP, 0-21: \(mae)")
        XCTAssertGreaterThan(r, 0.88, "correlation with WHOOP: \(r)")
        for (d, e) in zip(days, errors) { XCTAssertLessThan(abs(e), 4.5, "\(d.label) off by \(e)") }
    }

    func testAQuietDayIsNotScoredAsAModerateOne() {
        // WHOOP showed 1.6 and 2.4 on the two quietest days. With the old floor of 0.10 they came out at 9.5 and 8.5.
        for d in WhoopCalibrationFixtures.days where d.whoopDayStrain < 3 {
            XCTAssertLessThan(score(d, .banister), 5.5, d.label)
        }
    }

    func testEdwardsReadsZeroWhereWhoopDoesNot() {
        // The reason Banister is the default: most of these days never reach half of the heart-rate reserve.
        let zeros = WhoopCalibrationFixtures.days.filter { score($0, .edwards) == 0 }
        XCTAssertGreaterThanOrEqual(zeros.count, 5)
        XCTAssertTrue(zeros.allSatisfy { $0.whoopDayStrain >= 1.5 }, "WHOOP never showed less than 1.6 on these days")
    }

    func testAHardDayStillScoresHigherThanAnEasyOne() {
        let byLabel = Dictionary(uniqueKeysWithValues: WhoopCalibrationFixtures.days.map { ($0.label, $0) })
        XCTAssertGreaterThan(score(byLabel["2026-10-28"]!, .banister), score(byLabel["2026-11-09"]!, .banister) + 5)
    }
}
