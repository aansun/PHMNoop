import XCTest
@testable import StrandAnalytics

final class PaceOfAgingTests: XCTestCase {
    private let week = 7 * 86_400.0

    private func series(weeks: Int, perYear: Double, noise: [Double] = [], start: Double = 40) -> [PaceOfAging.Reading] {
        (0..<weeks).map { i in
            let jitter = noise.isEmpty ? 0 : noise[i % noise.count]
            return PaceOfAging.Reading(time: 1_700_000_000 + Double(i) * week, fitnessAge: start + perYear * Double(i) / 52 + jitter)
        }
    }

    func testTooFewReadingsGivesNothing() {
        XCTAssertNil(PaceOfAging.compute(series(weeks: 5, perYear: 0)))
        XCTAssertNil(PaceOfAging.compute([]))
    }

    func testSteadyFitnessIsNormalPace() {
        let r = PaceOfAging.compute(series(weeks: 26, perYear: 0))!
        XCTAssertEqual(r.pace, 1.0, accuracy: 1e-9)
        XCTAssertEqual(r.band, .normal)
    }

    func testFallingFitnessAgeIsSlowerThanNormal() {
        // -2 years per year on a clean line: well under 1.0x, never below the dial floor.
        let r = PaceOfAging.compute(series(weeks: 26, perYear: -2))!
        XCTAssertLessThan(r.pace, 0.5)
        XCTAssertGreaterThanOrEqual(r.pace, -1)
        XCTAssertEqual(r.band, .slow)
    }

    func testRisingFitnessAgeIsFasterThanNormal() {
        let r = PaceOfAging.compute(series(weeks: 26, perYear: 3))!
        XCTAssertGreaterThan(r.pace, 1.5)
        XCTAssertLessThanOrEqual(r.pace, 3)
        XCTAssertEqual(r.band, .fast)
    }

    func testNoisyShortHistoryStaysNearNormal() {
        // The same -2 yr/yr line, but six jumpy weeks: the noise must hold the result close to 1.0x.
        let r = PaceOfAging.compute(series(weeks: 6, perYear: -2, noise: [1.5, -1.5, 1.0, -1.0, 2.0, -2.0]))!
        XCTAssertEqual(r.pace, 1.0, accuracy: 0.15)
        XCTAssertEqual(r.confidence, .early)
    }

    func testLongerHistoryTrustsTheTrendMore() {
        let noise: [Double] = [0.8, -0.8, 0.5, -0.5]
        let short = PaceOfAging.compute(series(weeks: 8, perYear: -2, noise: noise))!
        let long = PaceOfAging.compute(series(weeks: 26, perYear: -2, noise: noise))!
        XCTAssertGreaterThan(long.weight, short.weight)
        XCTAssertLessThan(long.pace, short.pace)
    }

    func testDialIsClamped() {
        let low = PaceOfAging.compute(series(weeks: 26, perYear: -60))!.pace
        let high = PaceOfAging.compute(series(weeks: 26, perYear: 80))!.pace
        XCTAssertGreaterThanOrEqual(low, -1); XCTAssertLessThan(low, 0)
        XCTAssertLessThanOrEqual(high, 3); XCTAssertGreaterThan(high, 2)
    }

    func testAStepInTheInputsCannotPinTheDial() {
        // Five flat weeks then a 25-year step down (a profile change): the dial must not sit at the floor.
        let flat = (0..<5).map { PaceOfAging.Reading(time: 1_700_000_000 + Double($0) * week, fitnessAge: 55) }
        let stepped = (5..<8).map { PaceOfAging.Reading(time: 1_700_000_000 + Double($0) * week, fitnessAge: 30) }
        let r = PaceOfAging.compute(flat + stepped)!
        XCTAssertGreaterThan(r.pace, 0.5)
        XCTAssertEqual(r.confidence, .early)
    }

    func testOnlyTheLastSixMonthsCount() {
        // A steep old trend followed by 26 flat weeks reads as normal.
        let old = (0..<20).map { PaceOfAging.Reading(time: 1_600_000_000 + Double($0) * week, fitnessAge: 60 - Double($0)) }
        let flat = (0..<26).map { PaceOfAging.Reading(time: 1_700_000_000 + Double($0) * week, fitnessAge: 40) }
        XCTAssertEqual(PaceOfAging.compute(old + flat)!.pace, 1.0, accuracy: 1e-9)
    }
}
