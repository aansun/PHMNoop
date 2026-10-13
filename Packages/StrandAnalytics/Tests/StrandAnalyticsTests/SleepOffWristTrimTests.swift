import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// A strap taken off at the end of a worn, still stretch must not leave a sleep session that runs through the off-wrist time.
final class SleepOffWristTrimTests: XCTestCase {
    private let ref = 1_749_513_600
    private func at(_ h: Double) -> Int { ref + Int(h * 3600) }
    private func still(_ a: Double, _ b: Double) -> [GravitySample] { (at(a)..<at(b)).map { GravitySample(ts: $0, x: 0, y: 0, z: 1) } }
    private func moving(_ a: Double, _ b: Double) -> [GravitySample] {
        (at(a)..<at(b)).enumerated().map { GravitySample(ts: $0.element, x: Double($0.offset % 2) * 0.5, y: 0, z: 1) }
    }
    private func hr(_ a: Double, _ b: Double, _ bpm: Int) -> [HRSample] { (at(a)..<at(b)).map { HRSample(ts: $0, bpm: bpm) } }

    /// Worn and still 20:00-22:00, strap on the desk 22:00-23:00 (still gravity, no HR), worn again and a real night after it.
    /// The evening session must end where the strap came off, not an hour later.
    func testOffWristHourIsNotInsideTheSession() {
        let g = moving(12, 20) + still(20, 23) + moving(23, 24.5) + still(24.5, 31)
        let h = hr(12, 20, 72) + hr(20, 22, 60) + hr(23, 24.5, 70) + hr(24.5, 31, 52)
        let sessions = SleepStager.detectSleep(hr: h, gravity: g)
        let evening = sessions.filter { $0.start < at(24) }
        for s in evening {
            XCTAssertLessThanOrEqual(s.end, at(22) + 120, "an evening session must stop where the HR stopped (22:00), not run into the off-wrist hour")
        }
        XCTAssertTrue(sessions.contains { $0.start >= at(24) }, "the real night after it is still found")
    }

    /// A worn night with a short off-wrist tail is still one night; only its end moves back to where the HR stopped.
    func testNightWithShortOffWristTailIsOneSessionEndingAtLastHR() {
        let start = at(1)
        let worn = 210 * 60, tail = 30 * 60
        let g = (0..<(worn + tail)).map { GravitySample(ts: start + $0, x: 0, y: 0, z: 1) }
        let h = (0..<worn).map { HRSample(ts: start + $0, bpm: 50) }
        let sessions = SleepStager.detectSleep(hr: h, gravity: g)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertLessThanOrEqual(sessions[0].end, start + worn + 120)
    }
}
