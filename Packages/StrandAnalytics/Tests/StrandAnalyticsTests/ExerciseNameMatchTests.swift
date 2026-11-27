import XCTest
@testable import StrandAnalytics

final class ExerciseNameMatchTests: XCTestCase {
    /// The swaps a generated dumbbell program was given before equipment and variation were checked.
    func testADumbbellExerciseIsNeverSwappedForOtherEquipment() {
        let wrong: [(String, String, String)] = [
            ("Dumbbell Bent Over Row", "Bent Over Barbell Row", "barbell"),
            ("Dumbbell Single Arm Row", "Kneeling Single-Arm High Pulley Row", "cable"),
            ("Dumbbell Triceps Extension", "Cable Lying Triceps Extension", "cable"),
            ("Dumbbell Incline Bench Press", "Smith Machine Incline Bench Press", "machine"),
            ("Dumbbell Romanian Deadlift", "Romanian Deadlift", "barbell"),
        ]
        for (asked, entry, equipment) in wrong {
            XCTAssertFalse(ExerciseNameMatch.sameEquipment(asked: asked, entryName: entry, entryEquipment: equipment), "\(asked) -> \(entry)")
        }
    }

    func testTheSameEquipmentPasses() {
        XCTAssertTrue(ExerciseNameMatch.sameEquipment(asked: "Dumbbell Incline Bench Press", entryName: "Incline Dumbbell Press", entryEquipment: "dumbbell"))
        XCTAssertTrue(ExerciseNameMatch.sameEquipment(asked: "Smith Machine Squat", entryName: "Smith Machine Squat", entryEquipment: "machine"))
        XCTAssertFalse(ExerciseNameMatch.sameEquipment(asked: "Machine Bench Press", entryName: "Smith Machine Bench Press", entryEquipment: "machine"))
        XCTAssertTrue(ExerciseNameMatch.sameEquipment(asked: "Goblet Squat", entryName: "Goblet Squat", entryEquipment: "kettlebells"), "a name that states none")
        XCTAssertFalse(ExerciseNameMatch.sameEquipment(asked: "Dumbbell Goblet Squat", entryName: "Goblet Squat", entryEquipment: "kettlebells"))
        XCTAssertFalse(ExerciseNameMatch.sameEquipment(asked: "Bench Press (Dumbbell)", entryName: "Barbell Bench Press - Medium Grip", entryEquipment: "barbell"))
        XCTAssertTrue(ExerciseNameMatch.sameEquipment(asked: "EZ Bar Curl", entryName: "EZ-Bar Curl", entryEquipment: "e-z curl bar"))
    }

    func testAnAliasToOtherEquipmentIsNotFollowed() {
        XCTAssertTrue(ExerciseNameMatch.contradicts(asked: "Dumbbell Romanian Deadlift", entryEquipment: "barbell"))
        XCTAssertFalse(ExerciseNameMatch.contradicts(asked: "Romanian Deadlift", entryEquipment: "barbell"))
        XCTAssertFalse(ExerciseNameMatch.contradicts(asked: "Dumbbell Carry", entryEquipment: "other"))
        XCTAssertFalse(ExerciseNameMatch.contradicts(asked: "Smith Machine Squat", entryEquipment: "machine"))
    }

    func testAVariationIsNotAnotherExercise() {
        XCTAssertFalse(ExerciseNameMatch.sameVariation(asked: "Dumbbell Triceps Extension", entryName: "Lying Dumbbell Tricep Extension"))
        XCTAssertFalse(ExerciseNameMatch.sameVariation(asked: "Dumbbell Triceps Extension", entryName: "Decline Dumbbell Triceps Extension"))
        XCTAssertFalse(ExerciseNameMatch.sameVariation(asked: "Dumbbell Lateral Raise", entryName: "Dumbbell Lying Rear Lateral Raise"))
        XCTAssertTrue(ExerciseNameMatch.sameVariation(asked: "Dumbbell Single Arm Row", entryName: "One-Arm Dumbbell Row"))
        XCTAssertTrue(ExerciseNameMatch.sameVariation(asked: "Dumbbell Bent Over Row", entryName: "Bent Over Two-Dumbbell Row"))
        XCTAssertFalse(ExerciseNameMatch.sameVariation(asked: "Dumbbell Deadlift", entryName: "Stiff-Legged Dumbbell Deadlift"))
    }
}
