import XCTest
@testable import StrandAnalytics

final class EffortAttributionTests: XCTestCase {
    private let d = 7201.0

    func testNoWorkoutsIsAllDailyActivity() {
        let s = EffortAttribution.split(dayEffort: 30, workoutEfforts: [], logDenominator: d)
        XCTAssertEqual(s.dailyPoints, 30, accuracy: 1e-9)
    }

    func testPartsAddUpToTheDay() {
        let s = EffortAttribution.split(dayEffort: 60, workoutEfforts: [40, 25], logDenominator: d)
        XCTAssertEqual(s.total, 60, accuracy: 1e-9)
        XCTAssertGreaterThan(s.dailyPoints, 0)
    }

    func testEffortPointsAreNotAddedLinearly() {
        // A workout of Effort 40 inside a day of Effort 50 is most of the load but not 80% of the points.
        let s = EffortAttribution.split(dayEffort: 50, workoutEfforts: [40], logDenominator: d)
        XCTAssertLessThan(s.workoutPoints[0], 50)
        XCTAssertEqual(s.workoutPoints[0] + s.dailyPoints, 50, accuracy: 1e-9)
        // The share is the share of the LOAD, not of the points.
        let loadShare = (exp(0.40 * log(d)) - 1) / (exp(0.50 * log(d)) - 1)
        XCTAssertEqual(s.workoutPoints[0], loadShare * 50, accuracy: 1e-9)
    }

    func testOverlappingWorkoutsAreScaledToFit() {
        // Two workouts whose loads sum above the day's load: nothing is left for daily activity and the total still matches.
        let s = EffortAttribution.split(dayEffort: 50, workoutEfforts: [50, 50], logDenominator: d)
        XCTAssertEqual(s.dailyPoints, 0, accuracy: 1e-9)
        XCTAssertEqual(s.total, 50, accuracy: 1e-9)
        XCTAssertEqual(s.workoutPoints[0], s.workoutPoints[1], accuracy: 1e-9)
    }

    func testZeroDayHasNoSources() {
        let s = EffortAttribution.split(dayEffort: 0, workoutEfforts: [30], logDenominator: d)
        XCTAssertEqual(s.total, 0)
    }

    func testWorkoutWithoutEffortGetsNothing() {
        let s = EffortAttribution.split(dayEffort: 40, workoutEfforts: [nil, 0], logDenominator: d)
        XCTAssertEqual(s.workoutPoints, [0, 0])
        XCTAssertEqual(s.dailyPoints, 40, accuracy: 1e-9)
    }
}
