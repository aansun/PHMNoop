import XCTest
@testable import StrandAnalytics

final class VitalRangeTests: XCTestCase {

    func testPhasesByNights() {
        XCTAssertEqual(VitalRange.phase(nights: 0), .calibrating(nights: 0))
        XCTAssertEqual(VitalRange.phase(nights: 6), .calibrating(nights: 6))
        XCTAssertEqual(VitalRange.phase(nights: 7), .learning(nights: 7))
        XCTAssertEqual(VitalRange.phase(nights: 13), .learning(nights: 13))
        XCTAssertEqual(VitalRange.phase(nights: 14), .trusted)
        XCTAssertFalse(VitalRange.phase(nights: 6).hasRange)
        XCTAssertTrue(VitalRange.phase(nights: 7).hasRange)
        XCTAssertTrue(VitalRange.phase(nights: 14).isTrusted)
    }

    /// The range counts the reading being judged, so six earlier readings are seven nights.
    func testNoRangeUnderSevenNights() {
        XCTAssertNil(VitalRange.band(history: [60, 61, 59, 60, 62]))
        XCTAssertNotNil(VitalRange.band(history: [60, 61, 59, 60, 62, 61]))
    }

    func testCentreIsTheMedianAndSpreadTheScaledMAD() throws {
        // 14 nights: no widening. Median 60, deviations 0 1 1 2 ... MAD of this set is 1, and the range is two standard deviations either side.
        let h: [Double] = [59, 60, 61, 60, 59, 61, 60, 62, 58, 60, 60, 61, 59]
        let b = try XCTUnwrap(VitalRange.band(history: h))
        XCTAssertEqual(b.nights, 14)
        XCTAssertEqual(b.centre, 60, accuracy: 1e-9)
        XCTAssertEqual(b.spread, 1.4826 * VitalRange.rangeSpreads, accuracy: 1e-9)
        XCTAssertEqual(VitalRange.rangeSpreads, 2, accuracy: 1e-9)
        XCTAssertFalse(b.learning)
    }

    /// One strange night moves a mean and a standard deviation a long way and the median and MAD hardly at all.
    func testOneOutlierBarelyMovesTheRange() throws {
        let calm: [Double] = [60, 61, 59, 60, 62, 58, 60, 61, 59, 60, 61, 60, 59]
        var withOutlier = calm; withOutlier[6] = 95
        let a = try XCTUnwrap(VitalRange.band(history: calm))
        let b = try XCTUnwrap(VitalRange.band(history: withOutlier))
        XCTAssertEqual(a.centre, b.centre, accuracy: 0.5)
        XCTAssertEqual(a.spread, b.spread, accuracy: 1.6)
        // A mean and SD of the same set would put the SD near 9: the range would swallow nearly any reading.
        let m = withOutlier.reduce(0, +) / Double(withOutlier.count)
        let sd = (withOutlier.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(withOutlier.count)).squareRoot()
        XCTAssertGreaterThan(sd, 5 * b.spread / VitalRange.rangeSpreads)
    }

    func testShortRangeIsWiderAndNarrowsToTheFinalOne() throws {
        // The same spread of readings, read at 7, 10 and 14 nights.
        func spread(nights: Int) throws -> Double {
            let h = (0..<(nights - 1)).map { 60.0 + Double($0 % 3) - 1 }   // 59 60 61 59 60 61 ...
            return try XCTUnwrap(VitalRange.band(history: h)).spread
        }
        let s7 = try spread(nights: 7), s14 = try spread(nights: 14)
        XCTAssertGreaterThan(s7, s14)
        // Both medians and MADs are 60 and 1, so the ratio is the widening alone: 1.5 at 7 nights, 1 at 14.
        XCTAssertEqual(s7 / s14, 1.5, accuracy: 0.05)
        XCTAssertEqual(try spread(nights: 20), s14, accuracy: 0.1)
        XCTAssertLessThan(try spread(nights: 10), s7)
        XCTAssertGreaterThan(try spread(nights: 10), s14)
    }

    func testOnlyTheNewestThirtyReadingsCount() throws {
        let old = [Double](repeating: 100, count: 40)
        let recent = [Double](repeating: 60, count: 30)
        let b = try XCTUnwrap(VitalRange.band(history: old + recent))
        XCTAssertEqual(b.centre, 60, accuracy: 1e-9)
        XCTAssertEqual(b.nights, 31)
    }

    func testVerdictUsesTheFloorForASteadyPerson() throws {
        // A perfectly steady person has no spread; one bpm either way is still "in range", two is not.
        let b = try XCTUnwrap(VitalRange.band(history: [Double](repeating: 57, count: 13)))
        XCTAssertEqual(b.spread, 0, accuracy: 1e-9)
        XCTAssertEqual(VitalRange.verdict(58, in: b, floor: 1), .inRange)
        XCTAssertEqual(VitalRange.verdict(59, in: b, floor: 1), .above)
        XCTAssertEqual(VitalRange.verdict(55, in: b, floor: 1), .below)
    }

    func testVerdictFollowsTheSpread() throws {
        let h: [Double] = [50, 70, 55, 65, 60, 52, 68, 58, 62, 60, 57, 63, 59]
        let b = try XCTUnwrap(VitalRange.band(history: h))
        XCTAssertEqual(VitalRange.verdict(b.centre + b.spread * 0.9, in: b, floor: 1), .inRange)
        XCTAssertEqual(VitalRange.verdict(b.centre + b.spread * 1.2, in: b, floor: 1), .above)
        XCTAssertEqual(VitalRange.verdict(b.centre - b.spread * 1.2, in: b, floor: 1), .below)
    }
}
