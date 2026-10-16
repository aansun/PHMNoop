import XCTest
@testable import StrandAnalytics

final class TreadmillDistanceTests: XCTestCase {
    func testSteadyWalkIsAboutFiveKilometresAnHour() {
        // 30 min at 110 steps a minute, 175 cm: 3300 steps x 0.723 m = 2385 m, a 4.8 km/h walk.
        let m = TreadmillDistance.estimateMeters(steps: 3300, heightCm: 175, durationS: 1800, gait: .walk)!
        XCTAssertEqual(m, 2385.5, accuracy: 1)
    }

    func testRunStepLengthGrowsWithCadence() {
        let slow = TreadmillDistance.estimateMeters(steps: 30 * 140, heightCm: 175, durationS: 1800, gait: .run)!
        let fast = TreadmillDistance.estimateMeters(steps: 30 * 175, heightCm: 175, durationS: 1800, gait: .run)!
        // 140 spm is about 8 km/h, 175 spm about 11.5 km/h.
        XCTAssertEqual(slow / 1800 * 3.6, 8.2, accuracy: 0.8)
        XCTAssertEqual(fast / 1800 * 3.6, 11.9, accuracy: 0.8)
        XCTAssertGreaterThan(fast, slow)
    }

    func testTooLittleDataGivesNothing() {
        XCTAssertNil(TreadmillDistance.estimateMeters(steps: 20, heightCm: 175, durationS: 600, gait: .walk))
        XCTAssertNil(TreadmillDistance.estimateMeters(steps: 3000, heightCm: 175, durationS: 10, gait: .walk))
        XCTAssertNil(TreadmillDistance.estimateMeters(steps: 3000, heightCm: 0, durationS: 1800, gait: .walk))
    }

    func testGaitFromSportName() {
        XCTAssertEqual(TreadmillDistance.gait(forSport: "Treadmill walk"), .walk)
        XCTAssertEqual(TreadmillDistance.gait(forSport: "Treadmill run"), .run)
        XCTAssertEqual(TreadmillDistance.gait(forSport: "Treadmill"), .run)
    }
}
