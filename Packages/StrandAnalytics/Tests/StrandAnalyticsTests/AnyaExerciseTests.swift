import XCTest
@testable import StrandAnalytics

final class AnyaExerciseTests: XCTestCase {
    func testParsesAFencedBlockAndKeepsOnlyKnownNames() {
        let reply = "Here:\n```anya-exercise\n{\"primary\":[\"Chest\",\"pecs\"],\"secondary\":[\"triceps\",\"chest\",\"shoulders\"],\"equipment\":\"Machine\",\"kind\":\"weighted\"}\n```"
        let spec = AnyaActions.parseExercise(from: reply)
        XCTAssertEqual(spec, AnyaExerciseSpec(primary: ["chest"], secondary: ["triceps", "shoulders"], equipment: "machine", kind: "weighted"))
    }

    func testRejectsUnknownAndInvalid() {
        XCTAssertNil(AnyaActions.parseExercise(from: "{\"unknown\":true}"))
        XCTAssertNil(AnyaActions.parseExercise(from: "{\"primary\":[\"pecs\"]}"))
        XCTAssertNil(AnyaActions.parseExercise(from: "I am not sure what that is."))
    }

    func testDropsAnInvalidEquipmentAndKind() {
        let spec = AnyaActions.parseExercise(from: "{\"primary\":\"lats\",\"equipment\":\"jetpack\",\"kind\":\"floaty\"}")
        XCTAssertEqual(spec, AnyaExerciseSpec(primary: ["lats"], secondary: [], equipment: nil, kind: nil))
    }

    func testParsesAProgramFromABlockOrBareJSON() {
        let json = "{\"name\":\"Upper lower\",\"days\":[{\"title\":\"A\",\"items\":[{\"exercise\":\"Lat Pulldown\",\"sets\":3,\"repsLow\":12,\"repsHigh\":8,\"restSec\":90}]}]}"
        let fenced = AnyaActions.parseProgram(from: "Split.\n```anya-program\n\(json)\n```")
        XCTAssertEqual(fenced?.days.first?.items.first?.repsLow, 8)   // a reversed range is put right
        XCTAssertEqual(fenced?.days.first?.items.first?.repsHigh, 12)
        XCTAssertEqual(AnyaActions.parseProgram(from: "Here you go: \(json)")?.name, "Upper lower")
        XCTAssertNil(AnyaActions.parseProgram(from: "I need to know which equipment you have."))
    }

    func testABreathingExerciseIsBoundedAndNeedsBothPhases() {
        let ok = AnyaActions.parseBreath(from: "```anya-breath\n{\"title\":\"Box\",\"goal\":\"focus\",\"minutes\":99,\"stages\":[{\"phase\":\"inhale\",\"seconds\":4},{\"phase\":\"hold\",\"seconds\":30},{\"phase\":\"exhale\",\"seconds\":4}]}\n```")
        XCTAssertEqual(ok?.minutes, 30)
        XCTAssertEqual(ok?.stages.map(\.seconds), [4, 8, 4])   // a hold is capped at 8 s
        XCTAssertNil(AnyaActions.parseBreath(from: "{\"title\":\"Only in\",\"stages\":[{\"phase\":\"inhale\",\"seconds\":4},{\"phase\":\"hold\",\"seconds\":4}]}"))
        XCTAssertEqual(AnyaActions.parseBreath(from: "{\"title\":\"x\",\"goal\":\"party\",\"stages\":[{\"phase\":\"inhale\",\"seconds\":4},{\"phase\":\"exhale\",\"seconds\":4}]}")?.goal, "calm")
    }

    func testAFastCycleIsSlowedDownNotRefused() {
        let spec = AnyaActions.parseBreath(from: "{\"title\":\"Fast\",\"stages\":[{\"phase\":\"inhale\",\"seconds\":1.5},{\"phase\":\"exhale\",\"seconds\":2}]}")
        XCTAssertNotNil(spec)
        XCTAssertGreaterThanOrEqual(spec?.cycleSeconds ?? 0, 6)
    }

    func testACustomBreathProtocolCanBeRegisteredAndFound() {
        let p = BreathProtocol(id: "custom-test", title: "Mine", subtitle: "", edu: "", mode: .playable, category: .ans, recommendedDurationMs: 60_000,
                               stages: [BreathStage(type: .inhale, durationMs: 4_000), BreathStage(type: .exhale, durationMs: 6_000)])
        XCTAssertNil(BreathProtocolCatalog.protocolById("custom-test"))
        BreathProtocolCatalog.registerCustom(p)
        XCTAssertEqual(BreathProtocolCatalog.protocolById("custom-test")?.title, "Mine")
        BreathProtocolCatalog.unregisterCustom(id: "custom-test")
        XCTAssertNil(BreathProtocolCatalog.protocolById("custom-test"))
    }
}
