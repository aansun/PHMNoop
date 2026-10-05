import XCTest
@testable import StrandAnalytics

final class AnyaNoteStoreTests: XCTestCase {
    private func store() -> AnyaNoteStore {
        let suite = "anya.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return AnyaNoteStore(defaults: d)
    }

    func testModulesAreIsolated() {
        let s = store()
        s.remember("breathing", "Breathing session: box, 5 min")
        s.remember("sleep", "Rest 82%")
        XCTAssertEqual(s.notes("breathing").map(\.text), ["Breathing session: box, 5 min"])
        XCTAssertEqual(s.notes("sleep").map(\.text), ["Rest 82%"])
        XCTAssertTrue(s.notes("today").isEmpty)
        XCTAssertNil(s.summary("health"))
        XCTAssertFalse(s.summary("sleep")!.contains("Breathing"))
    }

    func testClearingOneModuleKeepsTheOthers() {
        let s = store()
        s.remember("a", "one"); s.remember("b", "two")
        s.clear("a")
        XCTAssertTrue(s.notes("a").isEmpty)
        XCTAssertEqual(s.notes("b").count, 1)
    }

    func testTaggedNoteReplacesItself() {
        let s = store()
        s.remember("today", "Charge 60%", tag: "2026-10-05", values: ["charge": 60])
        s.remember("today", "Charge 64%", tag: "2026-10-05", values: ["charge": 64])
        s.remember("today", "Charge 70%", tag: "2026-10-06", values: ["charge": 70])
        XCTAssertEqual(s.notes("today").map(\.text), ["Charge 64%", "Charge 70%"])
        XCTAssertEqual(s.previousSnapshot("today", excluding: "2026-10-06")?.values?["charge"], 64)
    }

    func testCapAndBlankNotes() {
        let s = store()
        for i in 0..<60 { s.remember("m", "note \(i)") }
        s.remember("m", "   ")
        XCTAssertEqual(s.notes("m").count, AnyaNoteStore.maxNotes)
        XCTAssertEqual(s.notes("m").last?.text, "note 59")
    }

    func testChangesPickTheBiggestMovesAndSkipSmallOnes() {
        let c = AnyaNoteMath.changes(previous: ["charge": 50, "hrv": 80, "rhr": 56, "rest": 90],
                                     current: ["charge": 70, "hrv": 82, "rhr": 50, "rest": 91, "new": 3])
        XCTAssertEqual(c.map(\.key), ["charge", "rhr"])
        XCTAssertEqual(c[0].relative, 0.4, accuracy: 1e-9)
    }

    func testChangesLimitAndMissingKeys() {
        let prev = ["a": 10.0, "b": 10, "c": 10, "d": 10]
        let cur = ["a": 20.0, "b": 30, "c": 5, "d": 40, "e": 1]
        XCTAssertEqual(AnyaNoteMath.changes(previous: prev, current: cur).map(\.key), ["d", "b", "a"])
        XCTAssertTrue(AnyaNoteMath.changes(previous: [:], current: cur).isEmpty)
    }

    func testDaysBetween() {
        XCTAssertEqual(AnyaNoteMath.daysBetween(0, 3 * 86_400 + 10), 3)
        XCTAssertEqual(AnyaNoteMath.daysBetween(100, 50), 0)
    }
}
