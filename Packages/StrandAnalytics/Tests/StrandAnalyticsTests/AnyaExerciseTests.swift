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
}
