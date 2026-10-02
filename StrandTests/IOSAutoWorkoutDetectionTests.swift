import XCTest
import WhoopProtocol
import StrandAnalytics
@testable import Strand

/// iOS-only auto-detection fixtures. These cover the three supported locomotion suggestions without
/// requiring a strap: the detector consumes the same decoded HR, gravity and activity-class rows that
/// the repository reads on device.
final class IOSAutoWorkoutDetectionTests: XCTestCase {
    private let start = 1_700_000_000

    private func hr(_ seconds: Int, bpm: Int) -> [HRSample] {
        (0..<seconds).map { HRSample(ts: start + $0, bpm: bpm) }
    }

    private func gravity(_ seconds: Int, delta: Double) -> [GravitySample] {
        (0..<seconds).map { i in
            GravitySample(ts: start + i, x: i.isMultiple(of: 2) ? 0 : delta, y: 0, z: 1)
        }
    }

    private func steps(_ seconds: Int, activityClass: Int) -> [StepSample] {
        (0..<seconds).map { i in
            StepSample(ts: start + i, counter: i, activityClass: activityClass)
        }
    }

    func testBriskWalkProducesWalkingSuggestion() {
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: hr(15 * 60, bpm: 98),
            gravity: gravity(15 * 60, delta: 0.05),
            steps: steps(15 * 60, activityClass: 1),
            restingBpm: 60,
            savedSpans: [])

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.sport, "Walking")
        XCTAssertGreaterThanOrEqual(suggestions.first?.durationMin ?? 0, 14)
    }

    func testRunProducesRunningSuggestion() {
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: hr(12 * 60, bpm: 150),
            gravity: gravity(12 * 60, delta: 0.4),
            steps: steps(12 * 60, activityClass: 2),
            restingBpm: 60,
            savedSpans: [])

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.sport, "Running")
    }

    func testSustainedCardioWithoutGaitProducesCyclingSuggestion() {
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: hr(15 * 60, bpm: 130),
            gravity: [],
            steps: [],
            restingBpm: 60,
            savedSpans: [])

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.sport, "Cycling")
    }

    func testShortWalkDoesNotProduceSuggestion() {
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: hr(5 * 60, bpm: 98),
            gravity: gravity(5 * 60, delta: 0.05),
            steps: steps(5 * 60, activityClass: 1),
            restingBpm: 60,
            savedSpans: [])

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testSavedWindowIsExcluded() {
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: hr(15 * 60, bpm: 98),
            gravity: gravity(15 * 60, delta: 0.05),
            steps: steps(15 * 60, activityClass: 1),
            restingBpm: 60,
            savedSpans: [SavedWorkoutSpan(startSec: start - 10, endSec: start + 15 * 60 + 10)])

        XCTAssertTrue(suggestions.isEmpty)
    }
}
