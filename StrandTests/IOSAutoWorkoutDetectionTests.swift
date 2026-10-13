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

    /// No steps, no motion: a steady, elevated heart rate says there was effort, not that it was a bike. The suggestion stays
    /// generic so the person names it, instead of every such stretch becoming "Cycling".
    func testSustainedCardioWithoutAnyEvidenceStaysGeneric() {
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: hr(15 * 60, bpm: 130),
            gravity: [],
            steps: [],
            restingBpm: 60,
            savedSpans: [])

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.sport, IOSAutoWorkoutDetector.genericSport)
    }

    /// Unsure → three likely sports are offered instead of a single guess; cycling is not among them without gait ticks.
    func testUnnamedSuggestionOffersUpToThreeAlternativesWithoutCyclingWhenTicksAreMissing() {
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: hr(15 * 60, bpm: 130), gravity: [], steps: [], restingBpm: 60, savedSpans: [])

        XCTAssertEqual(suggestions.first?.sport, IOSAutoWorkoutDetector.genericSport)
        let alternatives = suggestions.first?.alternatives ?? []
        XCTAssertFalse(alternatives.isEmpty)
        XCTAssertLessThanOrEqual(alternatives.count, 3)
        XCTAssertFalse(alternatives.contains("Cycling"))
    }

    /// Cycling is named only when the ticks read "still" through the effort, the classifier is confident AND this person has saved
    /// cycling before.
    func testSustainedCardioWithStillTicksProducesCyclingSuggestionForACyclist() {
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: hr(15 * 60, bpm: 135),
            gravity: gravity(15 * 60, delta: 0.01),
            steps: steps(15 * 60, activityClass: 0),
            restingBpm: 60,
            userSports: ["Cycling": 4],
            savedSpans: [])

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.sport, "Cycling")
    }

    /// The same stream for someone who has never saved a ride stays generic, and cycling is the first thing offered.
    func testSameStreamWithoutCyclingHistoryStaysGenericAndOffersCyclingFirst() {
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: hr(15 * 60, bpm: 135),
            gravity: gravity(15 * 60, delta: 0.01),
            steps: steps(15 * 60, activityClass: 0),
            restingBpm: 60,
            savedSpans: [])

        XCTAssertEqual(suggestions.first?.sport, IOSAutoWorkoutDetector.genericSport)
        XCTAssertTrue(suggestions.first?.alternatives.contains("Cycling") ?? false)
    }

    /// Someone who logs the elliptical far more than rides is not told it was a ride, and their own sport comes first.
    func testOwnSportComesFirstWhenItOutweighsCycling() {
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: hr(30 * 60, bpm: 140),
            gravity: gravity(30 * 60, delta: 0.02),
            steps: steps(30 * 60, activityClass: 0),
            restingBpm: 60,
            userSports: ["Elliptical": 6, "Cycling": 3],
            savedSpans: [])

        XCTAssertEqual(suggestions.first?.sport, IOSAutoWorkoutDetector.genericSport)
        XCTAssertEqual(suggestions.first?.alternatives.first, "Elliptical")
    }

    /// A seated stretch with a heart rate lifted by stress (a drive, a presentation) is not a workout.
    func testSeatedStressIsNotASuggestion() {
        let stress = (0..<(30 * 60)).map { HRSample(ts: start + $0, bpm: 84 + ($0 / 60) % 6) }
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: stress,
            gravity: gravity(30 * 60, delta: 0.01),
            steps: steps(30 * 60, activityClass: 0),
            restingBpm: 60,
            savedSpans: [])

        XCTAssertTrue(suggestions.isEmpty)
    }

    /// Two minutes running, two walking, five times over: one running session, not five pieces that are each too short.
    func testRunWalkIntervalsAreOneRunningSession() {
        var hrS: [HRSample] = [], gS: [GravitySample] = [], sS: [StepSample] = []
        for block in 0..<10 {
            let running = block.isMultiple(of: 2)
            for i in 0..<120 {
                let t = start + block * 120 + i
                hrS.append(HRSample(ts: t, bpm: running ? 158 : 118))
                gS.append(GravitySample(ts: t, x: i.isMultiple(of: 2) ? 0 : (running ? 0.4 : 0.1), y: 0, z: 1))
                sS.append(StepSample(ts: t, counter: t - start, activityClass: running ? 2 : 1))
            }
        }
        let suggestions = IOSAutoWorkoutDetector.detect(hr: hrS, gravity: gS, steps: sS, restingBpm: 60, savedSpans: [])

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.sport, "Running")
    }

    /// Sets then rest, no gait: lifting is named, with the person's own word for it when they have one.
    func testSawToothHeartRateWithNoGaitIsStrength() {
        let saw = (0..<(45 * 60)).map { i -> HRSample in
            let phase = Double(i % 150) / 150
            let level = phase < 0.4 ? phase / 0.4 : 1 - (phase - 0.4) / 0.6
            return HRSample(ts: start + i, bpm: 88 + Int((54 * level).rounded()))
        }
        let g = gravity(45 * 60, delta: 0.015)
        let s = steps(45 * 60, activityClass: 0)

        let plain = IOSAutoWorkoutDetector.detect(hr: saw, gravity: g, steps: s, restingBpm: 60, savedSpans: [])
        XCTAssertEqual(plain.first?.sport, "Strength")

        let own = IOSAutoWorkoutDetector.detect(hr: saw, gravity: g, steps: s, restingBpm: 60,
                                                userSports: ["Weightlifting": 8], savedSpans: [])
        XCTAssertEqual(own.first?.sport, "Weightlifting")
    }

    /// Intervals reach a peak that lifting does not: not called strength.
    func testHighPeakIntervalsAreNotNamedStrength() {
        let hiit = (0..<(25 * 60)).map { i in HRSample(ts: start + i, bpm: (i / 30).isMultiple(of: 2) ? 172 : 118) }
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: hiit, gravity: gravity(25 * 60, delta: 0.2), steps: steps(25 * 60, activityClass: 0),
            restingBpm: 60, savedSpans: [])

        XCTAssertNotEqual(suggestions.first?.sport, "Strength")
    }

    /// The deepest REM stretch of a night lifts the heart rate a little: asleep and still is never a workout.
    func testRemSleepHeartRateIsNotASuggestion() {
        let rem = (0..<(15 * 60)).map { HRSample(ts: start + $0, bpm: 72 + ($0 / 45) % 10) }
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: rem, gravity: gravity(15 * 60, delta: 0.002), steps: steps(15 * 60, activityClass: 0),
            restingBpm: 60, savedSpans: [])

        XCTAssertTrue(suggestions.isEmpty)
    }

    /// A manual activity that is running right now is represented by a span that reaches into the future, so the detector
    /// does not suggest it back to the person who is logging it.
    func testActiveSessionSpanSuppressesTheSuggestion() {
        let suggestions = IOSAutoWorkoutDetector.detect(
            hr: hr(15 * 60, bpm: 130),
            gravity: gravity(15 * 60, delta: 0.01),
            steps: steps(15 * 60, activityClass: 0),
            restingBpm: 60,
            savedSpans: [SavedWorkoutSpan(startSec: start - 300, endSec: start + 15 * 60 + 3600)])

        XCTAssertTrue(suggestions.isEmpty)
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
