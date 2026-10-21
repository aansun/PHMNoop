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
}
