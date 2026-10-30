import XCTest
@testable import StrandAnalytics

final class AlarmRingingTests: XCTestCase {
    private let t0 = 1_800_000_000.0

    func testNotRingingBeforeTheAlarmTime() {
        XCTAssertFalse(AlarmRinging.isRinging(now: t0 - 5, armedFor: t0, firedAt: nil, dismissedAt: nil))
    }

    func testRingingFromTheArmedTimeForTheWindow() {
        XCTAssertTrue(AlarmRinging.isRinging(now: t0, armedFor: t0, firedAt: nil, dismissedAt: nil))
        XCTAssertTrue(AlarmRinging.isRinging(now: t0 + 90, armedFor: t0, firedAt: nil, dismissedAt: nil))
        XCTAssertTrue(AlarmRinging.isRinging(now: t0 + AlarmRinging.window, armedFor: t0, firedAt: nil, dismissedAt: nil))
        XCTAssertFalse(AlarmRinging.isRinging(now: t0 + AlarmRinging.window + 1, armedFor: t0, firedAt: nil, dismissedAt: nil))
    }

    /// The strap reports a fire a little after the armed instant, or the app re-arms the next day in between: the report alone is enough.
    func testAFireReportAloneIsEnough() {
        XCTAssertTrue(AlarmRinging.isRinging(now: t0 + 40, armedFor: t0 + 86_400, firedAt: t0 + 2, dismissedAt: nil))
        XCTAssertFalse(AlarmRinging.isRinging(now: t0 + 400, armedFor: t0 + 86_400, firedAt: t0 + 2, dismissedAt: nil))
    }

    func testADismissalEndsThatRingOnly() {
        // Tapped at +10 s: that ring is over.
        XCTAssertFalse(AlarmRinging.isRinging(now: t0 + 20, armedFor: t0, firedAt: t0 + 1, dismissedAt: t0 + 10))
        // A dismissal from the day before does not silence today's ring.
        XCTAssertTrue(AlarmRinging.isRinging(now: t0 + 20, armedFor: t0, firedAt: t0 + 1, dismissedAt: t0 - 86_400))
    }

    func testNothingKnownIsNotRinging() {
        XCTAssertFalse(AlarmRinging.isRinging(now: t0, armedFor: nil, firedAt: nil, dismissedAt: nil))
    }
}
