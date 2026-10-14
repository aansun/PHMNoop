import XCTest
@testable import StrandAnalytics

final class SessionLoadSplitTests: XCTestCase {
    private let usualHeart = [0.30, 0.35, 0.40, 0.45, 0.50]
    private let usualMuscle = [100.0, 120, 140, 160, 180]

    func testUnusuallyHeavyForTheMusclesReadsMostlyMuscular() {
        let r = SessionLoadSplit.split(cardio: 0.40, muscular: 400, cardioHistory: usualHeart, muscularHistory: usualMuscle)!
        XCTAssertGreaterThan(r.muscularPct, 50)
        XCTAssertEqual(r.cardioPct + r.muscularPct, 100)
        XCTAssertEqual(r.sessions, 5)
    }

    func testUnusuallyHardForTheHeartReadsMostlyCardio() {
        let r = SessionLoadSplit.split(cardio: 0.90, muscular: 100, cardioHistory: usualHeart, muscularHistory: usualMuscle)!
        XCTAssertGreaterThan(r.cardioPct, 50)
    }

    func testAnOrdinarySessionIsRoughlyEven() {
        let r = SessionLoadSplit.split(cardio: 0.40, muscular: 140, cardioHistory: usualHeart, muscularHistory: usualMuscle)!
        XCTAssertEqual(r.cardioPct, 50)
    }

    func testTooLittleHistoryShowsNothing() {
        XCTAssertNil(SessionLoadSplit.split(cardio: 0.4, muscular: 140, cardioHistory: [0.3, 0.4], muscularHistory: usualMuscle))
        XCTAssertNil(SessionLoadSplit.split(cardio: 0.4, muscular: 140, cardioHistory: usualHeart, muscularHistory: [100, 120]))
    }

    func testMissingFigureShowsNothing() {
        XCTAssertNil(SessionLoadSplit.split(cardio: nil, muscular: 140, cardioHistory: usualHeart, muscularHistory: usualMuscle))
        XCTAssertNil(SessionLoadSplit.split(cardio: 0.4, muscular: nil, cardioHistory: usualHeart, muscularHistory: usualMuscle))
        XCTAssertNil(SessionLoadSplit.split(cardio: 0, muscular: 140, cardioHistory: usualHeart, muscularHistory: usualMuscle))
    }

    func testARecordOnOneSideDoesNotZeroTheOther() {
        // The heaviest session ever for the muscles, the lightest for the heart: still a share on both sides.
        let r = SessionLoadSplit.split(cardio: 0.05, muscular: 900, cardioHistory: usualHeart, muscularHistory: usualMuscle)!
        XCTAssertGreaterThan(r.cardioPct, 0)
        XCTAssertGreaterThan(r.muscularPct, 0)
    }
}
