import XCTest
@testable import StrandAnalytics

final class NutritionPlannerTests: XCTestCase {
    private func input(_ kg: Double, goal: Double?, burn: Double = 2464, height: Double = 175, kidney: Bool = false) -> NutritionPlanner.Input {
        .init(maintenanceKcal: burn, weightKg: kg, heightCm: height, goalKg: goal, kidneyResultOutOfRange: kidney)
    }

    func testAGoalAwayGivesAPaceAndNumbersThatAgree() {
        let p = NutritionPlanner.make(input(79.3, goal: 68))
        XCTAssertEqual(p.paceKgPerWeek, -0.5)
        XCTAssertEqual(p.targetKcal, 1914)
        XCTAssertEqual(p.proteinPerKg, 1.8)
        XCTAssertEqual(p.weeksToGoal, 23)
        XCTAssertEqual(p.macros.proteinG, 143)
        XCTAssertLessThanOrEqual(abs(p.proteinPercent + p.fatPercent + p.carbsPercent - 100), 1)
        XCTAssertEqual(p.targetKcal, NutritionMath.dailyTarget(maintenanceKcal: 2464, weeklyChangeKg: p.paceKgPerWeek), "the screen reaches the same figure")
        XCTAssertEqual(NutritionPlanner.make(input(79.3, goal: 68)), p, "asked twice, answered the same")
    }

    func testNearNoOrReachedGoal() {
        XCTAssertEqual(NutritionPlanner.make(input(70, goal: 68)).paceKgPerWeek, -0.25)
        XCTAssertEqual(NutritionPlanner.make(input(68.4, goal: 68)).paceKgPerWeek, 0)
        let none = NutritionPlanner.make(input(79.3, goal: nil))
        XCTAssertEqual(none.targetKcal, 2464)
        XCTAssertEqual(none.proteinPerKg, 1.6)
        XCTAssertNil(none.weeksToGoal)
        XCTAssertEqual(NutritionPlanner.make(input(60, goal: 66)).paceKgPerWeek, 0.25)
    }

    func testTheGuards() {
        let under = NutritionPlanner.make(input(52, goal: 48, height: 172))
        XCTAssertTrue(under.heldBecauseUnderweight)
        XCTAssertEqual(under.paceKgPerWeek, 0)
        let small = NutritionPlanner.make(input(55, goal: 50, burn: 1500, height: 155))
        XCTAssertGreaterThanOrEqual(small.targetKcal, NutritionMath.floorKcal)
        XCTAssertEqual(small.paceKgPerWeek, -0.25)
        let floor = NutritionPlanner.make(input(90, goal: 70, burn: 1600))
        XCTAssertTrue(floor.easedForFloor)
        XCTAssertEqual(floor.paceKgPerWeek, -0.25)
        XCTAssertEqual(NutritionPlanner.make(input(79, goal: 68, kidney: true)).proteinPerKg, 1.0)
    }

    func testAnInventedFigureIsCaught() {
        let facts = "Daily burn 2464 kcal, target 1914 kcal, weight 79.3 kg, carbohydrate 47 percent, range 55 to 75."
        XCTAssertEqual(FigureGuard.unknownFigures(in: "Targetmu 1.914 kcal dari 2.464 kcal, berat 79,3 kg, karbo 47% (rentang 55-75%). Cek lagi 2 minggu.", facts: facts), [])
        XCTAssertEqual(FigureGuard.unknownFigures(in: "Target 2250 kcal dan karbo 55%", facts: facts), [2250])
        XCTAssertEqual(FigureGuard.figures(in: "0,500 dan 1,200 dan 12.5"), [0.5, 1200, 12.5])
    }

    func testDecimalsFollowTheCard() {
        let words = "Turun 0.5 kg dari 79.3 kg, target 1.915 kcal, WHO 0.83 g. Selesai."
        XCTAssertEqual(FigureGuard.localised(words, decimalSeparator: ","), "Turun 0,5 kg dari 79,3 kg, target 1.915 kcal, WHO 0,83 g. Selesai.")
        XCTAssertEqual(FigureGuard.localised(words, decimalSeparator: "."), words)
    }
}
