import XCTest
@testable import Strand

final class IOSSleepOnsetResolverTests: XCTestCase {
    private typealias Segment = IOSSleepOnsetResolver.Segment

    func testTrimsOneHundredMinutePreSleepLead() {
        let detectedStart = 0
        let actualOnset = 100 * 60
        let wake = actualOnset + 5 * 60 + 35 * 60
        let stages = [
            Segment(start: detectedStart, end: actualOnset, stage: "wake"),
            Segment(start: actualOnset, end: wake, stage: "light")
        ]

        XCTAssertEqual(
            IOSSleepOnsetResolver.onset(segments: stages, detectedStart: detectedStart, detectedEnd: wake),
            actualOnset
        )
    }

    func testShortNonWakeFragmentBeforeRealOnsetDoesNotWin() {
        let stages = [
            Segment(start: 0, end: 120, stage: "light"),
            Segment(start: 120, end: 2_400, stage: "wake"),
            Segment(start: 2_400, end: 6_000, stage: "light")
        ]

        XCTAssertEqual(IOSSleepOnsetResolver.onset(segments: stages, detectedStart: 0, detectedEnd: 6_000), 2_400)
    }

    func testAllWakeFallsBackToDetectedStart() {
        let stages = [Segment(start: 0, end: 6_000, stage: "wake")]
        XCTAssertEqual(IOSSleepOnsetResolver.onset(segments: stages, detectedStart: 0, detectedEnd: 6_000), 0)
    }

    func testImportedMinuteDictionaryHasNoTimelineAndFallsBack() {
        let json = #"{"light":335,"deep":0,"rem":0,"awake":100}"#
        XCTAssertEqual(IOSSleepOnsetResolver.onset(from: json, detectedStart: 0, detectedEnd: 26_100), 0)
    }

    func testTimelineGapDoesNotSatisfyPersistence() {
        let stages = [
            Segment(start: 0, end: 180, stage: "light"),
            Segment(start: 300, end: 420, stage: "light")
        ]
        XCTAssertEqual(IOSSleepOnsetResolver.onset(segments: stages, detectedStart: 0, detectedEnd: 420), 0)
    }
}
