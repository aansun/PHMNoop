import XCTest
@testable import StrandAnalytics

final class BreathAdvisorTests: XCTestCase {
    func testElevatedHeartRatePicksCalmWithLongExhale() {
        let a = BreathAdvisor.advise(.init(bpm: 92, restingHr: 56, hour: 15))
        XCTAssertEqual(a.goal, .calm)
        XCTAssertEqual(a.template.id, "calm_slow")
        XCTAssertTrue(a.reasons.contains(.heartRateHigh(bpm: 92, aboveResting: 36)))
    }

    func testLateEveningPicksSleep() {
        XCTAssertEqual(BreathAdvisor.advise(.init(bpm: 58, restingHr: 56, hour: 23)).goal, .sleep)
        XCTAssertEqual(BreathAdvisor.advise(.init(hour: 2)).goal, .sleep)
    }

    func testLowChargeAndDownTrendPicksRecover() {
        let a = BreathAdvisor.advise(.init(restingHr: 56, hrvDelta: -12, restingHrDelta: 5, charge: 25, hour: 14))
        XCTAssertEqual(a.goal, .recover)
        XCTAssertEqual(a.reasons.count, 3)
    }

    func testGoodMorningChargePicksEnergize() {
        let a = BreathAdvisor.advise(.init(charge: 82, hour: 8))
        XCTAssertEqual(a.goal, .energize)
        XCTAssertTrue(a.template.advisable)
    }

    func testForcefulProtocolIsNeverSuggestedOnItsOwn() {
        for h in 0..<24 {
            for charge in [10.0, 50, 90] {
                XCTAssertTrue(BreathAdvisor.advise(.init(charge: charge, hour: h)).template.advisable)
            }
        }
    }

    func testHighStressBeatsDaytime() {
        XCTAssertEqual(BreathAdvisor.advise(.init(stress: 2.4, hour: 13)).goal, .calm)
    }

    func testWhatWorkedBeforeWinsWithinTheGoal() {
        let a = BreathAdvisor.advise(.init(stress: 2.5, hour: 13, pastEffect: ["calm_coherence": 18, "calm_slow": 4]))
        XCTAssertEqual(a.template.id, "calm_coherence")
        XCTAssertTrue(a.reasons.contains(.workedBefore(pct: 18)))
    }

    func testNoDataFallsBackToTimeOfDayAndSaysSo() {
        let a = BreathAdvisor.advise(.init(hour: 15))
        XCTAssertEqual(a.goal, .focus)
        XCTAssertTrue(a.reasons.contains(.daytime(hour: 15)) || a.reasons.contains(.noLiveData))
    }

    func testPastEffectNeedsTwoSessionsAndSkipsMissingHrv() {
        let e = BreathAdvisor.pastEffect([("a", 40, 50), ("a", 40, 44), ("b", 40, 60), ("c", nil, 50), ("c", 30, nil)])
        XCTAssertEqual(e["a"] ?? 0, 17.5, accuracy: 0.001)
        XCTAssertNil(e["b"]); XCTAssertNil(e["c"])
    }

    func testEveryTemplateReferencesARealProtocol() {
        for t in BreathTemplates.all { XCTAssertNotNil(BreathProtocolCatalog.protocolById(t.protocolId), t.id) }
        for g in BreathGoal.allCases { XCTAssertFalse(BreathTemplates.templates(for: g).isEmpty) }
    }
}
