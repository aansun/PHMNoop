import XCTest
@testable import StrandAnalytics

final class NutritionMathTests: XCTestCase {
    private func days(_ from: String, _ n: Int) -> [String] { let s = NutritionMath.dayIndex(from)!; return (0..<n).map { NutritionMath.ymd(s + $0) } }

    func testDayIndexAndBack() {
        XCTAssertEqual(NutritionMath.dayIndex("1970-01-01"), 0)
        XCTAssertEqual(NutritionMath.dayIndex("2026-10-21"), 20747)
        XCTAssertEqual(NutritionMath.ymd(20747), "2026-10-21")
        XCTAssertEqual(NutritionMath.ymd(NutritionMath.dayIndex("2024-02-29")! + 1), "2024-03-01")
        XCTAssertNil(NutritionMath.dayIndex("yesterday"))
    }

    func testTrendSmoothsAndKeepsTheFirstWeighIn() {
        let t = NutritionMath.trend([.init(day: "2026-10-01", kg: 80), .init(day: "2026-10-02", kg: 82), .init(day: "2026-10-02", kg: 82), .init(day: "2026-10-04", kg: 80)])
        XCTAssertEqual(t.count, 3)
        XCTAssertEqual(t[0].kg, 80, accuracy: 1e-9)
        XCTAssertEqual(t[1].kg, 80.2, accuracy: 1e-9)                      // alpha 0.1 on one day
        XCTAssertEqual(t[2].kg, 80.2 + (1 - 0.81) * (80 - 80.2), accuracy: 1e-9) // two-day gap widens alpha
        XCTAssertTrue(NutritionMath.trend([.init(day: "bad", kg: 80), .init(day: "2026-10-01", kg: -3)]).isEmpty)
    }

    func testExpenditureFromIntakeAndAFallingTrend() throws {
        let d = days("2026-10-01", 14)
        let weights = d.enumerated().map { NutritionMath.WeightPoint(day: $0.element, kg: 80 - 0.05 * Double($0.offset)) } // -0.05 kg/day
        let intake = Dictionary(uniqueKeysWithValues: d.map { ($0, 2000.0) })
        let trend = weights // already smooth: use as the trend directly
        let e = try XCTUnwrap(NutritionMath.expenditure(intake: intake, trend: trend, endDay: d.last!))
        // eaten 2000, lost 0.05 kg/day over 13 days -> spends 2000 + 0.05*7700 = 2385
        XCTAssertEqual(e, 2385, accuracy: 1)
    }

    func testExpenditureNeedsEnoughDaysAndTrend() {
        let d = days("2026-10-01", 14)
        let trend = d.map { NutritionMath.WeightPoint(day: $0, kg: 80) }
        let few = Dictionary(uniqueKeysWithValues: d.prefix(5).map { ($0, 2000.0) })
        XCTAssertNil(NutritionMath.expenditure(intake: few, trend: trend, endDay: d.last!))
        let all = Dictionary(uniqueKeysWithValues: d.map { ($0, 2000.0) })
        XCTAssertNil(NutritionMath.expenditure(intake: all, trend: [.init(day: d[10], kg: 80), .init(day: d[13], kg: 80)], endDay: d.last!))
    }

    func testTargetAndMacros() {
        XCTAssertEqual(NutritionMath.dailyTarget(maintenanceKcal: 2600, weeklyChangeKg: -0.4), 2160)   // 2600 - 440
        XCTAssertEqual(NutritionMath.dailyTarget(maintenanceKcal: 1300, weeklyChangeKg: -1), 1200)      // floor
        XCTAssertEqual(NutritionMath.dailyTarget(maintenanceKcal: 2600, weeklyChangeKg: 0.25), 2875)
        let m = NutritionMath.macroTargets(kcal: 2500, weightKg: 75, proteinPerKg: 1.8, fatShare: 0.28)
        XCTAssertEqual(m.proteinG, 135); XCTAssertEqual(m.fatG, 78); XCTAssertEqual(m.carbsG, 315)
        XCTAssertEqual(NutritionMath.kcal(proteinG: 42, carbsG: 78, fatG: 16), 624)
    }

    func testProfileMaintenance() throws {
        let m = try XCTUnwrap(NutritionMath.profileMaintenance(sex: "male", ageYears: 30, weightKg: 75, heightCm: 178))
        XCTAssertEqual(m, (10 * 75 + 6.25 * 178 - 5 * 30 + 5) * 1.4, accuracy: 1e-9)
        XCTAssertNil(NutritionMath.profileMaintenance(sex: "male", ageYears: 30, weightKg: 0, heightCm: 178))
    }

    func testCheckInSuggestsTheGapAndStaysQuietWhenClose() throws {
        let d = days("2026-10-01", 21)
        // Lost 0.3 kg/week against a plan of 0.4: eat a bit less.
        let trend = d.enumerated().map { NutritionMath.WeightPoint(day: $0.element, kg: 80 - 0.3 / 7 * Double($0.offset)) }
        let intake = Dictionary(uniqueKeysWithValues: d.map { ($0, 2300.0) })
        let c = try XCTUnwrap(NutritionMath.checkIn(trend: trend, intake: intake, endDay: d.last!, plannedKgPerWeek: -0.4, currentTarget: 2500))
        XCTAssertEqual(c.actualKgPerWeek, -0.3, accuracy: 1e-6)
        XCTAssertEqual(c.changeKcal, -110)
        XCTAssertEqual(c.newTarget, 2390)
        // On pace: nothing to suggest.
        let onPace = d.enumerated().map { NutritionMath.WeightPoint(day: $0.element, kg: 80 - 0.4 / 7 * Double($0.offset)) }
        XCTAssertNil(NutritionMath.checkIn(trend: onPace, intake: intake, endDay: d.last!, plannedKgPerWeek: -0.4, currentTarget: 2500))
        // Too few logged days.
        XCTAssertNil(NutritionMath.checkIn(trend: trend, intake: ["2026-10-21": 2000], endDay: d.last!, plannedKgPerWeek: -0.4, currentTarget: 2500))
    }

    func testCheckInIsCappedAt250() throws {
        let d = days("2026-10-01", 21)
        let flat = d.map { NutritionMath.WeightPoint(day: $0, kg: 80) }
        let intake = Dictionary(uniqueKeysWithValues: d.map { ($0, 2300.0) })
        let c = try XCTUnwrap(NutritionMath.checkIn(trend: flat, intake: intake, endDay: d.last!, plannedKgPerWeek: -1, currentTarget: 2500))
        XCTAssertEqual(c.changeKcal, -250)
    }
}

final class AnyaFoodBlockTests: XCTestCase {
    func testFoodBlockParsesAndDropsBadItems() {
        let r = "Estimates below.\n```anya-food\n{\"meal\":\"Lunch\",\"day\":\"2026-10-20\",\"items\":[{\"name\":\"Nasi goreng\",\"amount\":\"1 plate\",\"kcal\":520,\"proteinG\":14,\"carbsG\":68,\"fatG\":21},{\"name\":\"\",\"kcal\":10},{\"name\":\"Rocket\",\"kcal\":99999},{\"name\":\"Tea\",\"kcal\":\"2\",\"proteinG\":-4}]}\n```"
        guard case .food(let f)? = AnyaActions.parse(r).last else { return XCTFail() }
        XCTAssertEqual(f.meal, "lunch"); XCTAssertEqual(f.day, "2026-10-20")
        XCTAssertEqual(f.items.map(\.name), ["Nasi goreng", "Tea"])
        XCTAssertEqual(f.items[0].fatG, 21); XCTAssertEqual(f.items[1].kcal, 2); XCTAssertNil(f.items[1].proteinG)
        XCTAssertEqual(AnyaActions.proseOnly(r), "Estimates below.")
    }

    func testUnknownMealIsDroppedAndEmptyIsNotACard() {
        guard case .food(let f)? = AnyaActions.parse("```anya-food\n{\"meal\":\"brunch\",\"items\":[{\"name\":\"Toast\",\"kcal\":120}]}\n```").first else { return XCTFail() }
        XCTAssertNil(f.meal)
        XCTAssertTrue(AnyaActions.parse("```anya-food\n{\"items\":[]}\n```").isEmpty)
        XCTAssertTrue(AnyaActions.instruction.contains("anya-food")); XCTAssertTrue(AnyaActions.foodInstruction.contains("anya-food"))
    }
}

final class AnyaPlanBlockTests: XCTestCase {
    func testPlanParsesAndIsClamped() {
        let r = "Here is a plan.\n```anya-plan\n{\"targetKcal\":900,\"paceKgPerWeek\":-3,\"proteinPerKg\":5,\"fatShare\":0.9,\"reasons\":[\"Weight 75 kg\",\"\"],\"cautions\":[\"a\",\"b\",\"c\",\"d\"]}\n```"
        guard case .plan(let p)? = AnyaActions.parse(r).last else { return XCTFail() }
        XCTAssertEqual(p.targetKcal, 1200); XCTAssertEqual(p.paceKgPerWeek, -1); XCTAssertEqual(p.proteinPerKg, 2.4); XCTAssertEqual(p.fatShare ?? 0, 0.40, accuracy: 1e-9)
        XCTAssertEqual(p.reasons, ["Weight 75 kg"]); XCTAssertEqual(p.cautions.count, 3)
        XCTAssertEqual(AnyaActions.proseOnly(r), "Here is a plan.")
    }

    func testRoundingAndMissingFields() {
        guard case .plan(let p)? = AnyaActions.parse("```anya-plan\n{\"targetKcal\":\"2153.4\",\"paceKgPerWeek\":-0.43,\"proteinPerKg\":1.84}\n```").first else { return XCTFail() }
        XCTAssertEqual(p.targetKcal, 2153); XCTAssertEqual(p.paceKgPerWeek ?? 0, -0.45, accuracy: 1e-9); XCTAssertEqual(p.proteinPerKg ?? 0, 1.8, accuracy: 1e-9)
        XCTAssertNil(p.fatShare)
        XCTAssertTrue(AnyaActions.parse("```anya-plan\n{\"paceKgPerWeek\":-0.4}\n```").isEmpty)   // no target, no card
        XCTAssertTrue(AnyaActions.instruction.contains("anya-plan")); XCTAssertTrue(AnyaActions.planInstruction.contains("anya-plan"))
    }
}

final class NutritionNudgeTests: XCTestCase {
    private func n(_ eaten: Double, hour: Int, today: Bool = true, p: Double? = nil, pt: Double? = 135) -> NutritionMath.Nudge? {
        NutritionMath.nudge(eaten: eaten, target: 2000, proteinEaten: p, proteinTarget: pt, hour: hour, isToday: today)
    }

    func testQuietEarlyInTheDay() {
        XCTAssertNil(n(0, hour: 8)); XCTAssertNil(n(300, hour: 9))
    }

    func testNothingLoggedByNoon() { XCTAssertEqual(n(0, hour: 13), .nothingLogged); XCTAssertNil(n(0, hour: 13, today: false)) }

    func testOverTheTarget() {
        XCTAssertEqual(n(2300, hour: 20), .over(kcal: 300))
        XCTAssertNil(n(2080, hour: 12))            // 4% over is still fine
        XCTAssertEqual(n(2300, hour: 12), .over(kcal: 300))   // over is over, even at noon
        XCTAssertEqual(NutritionMath.nudge(eaten: 2150, target: 2000, proteinEaten: nil, proteinTarget: nil, hour: 9, isToday: false), .onTrack)   // 7.5% over a past day is still on track
        XCTAssertEqual(NutritionMath.nudge(eaten: 2300, target: 2000, proteinEaten: nil, proteinTarget: nil, hour: 9, isToday: false), .over(kcal: 300))
    }

    func testBehindFollowsTheClock() {
        XCTAssertNil(n(500, hour: 12))
        XCTAssertEqual(n(300, hour: 15), .behind(kcal: 1700))
        XCTAssertNil(n(700, hour: 15))
        XCTAssertEqual(n(900, hour: 19), .behind(kcal: 1100))
        XCTAssertEqual(n(1300, hour: 22), .behind(kcal: 700))
        XCTAssertEqual(n(1500, hour: 9, today: false), .behind(kcal: 500))
        XCTAssertNil(n(1700, hour: 9, today: false))
    }

    func testProteinThenOnTrack() {
        XCTAssertEqual(n(1500, hour: 18, p: 40), .proteinLow(grams: 95))
        XCTAssertNil(n(1500, hour: 18, p: 100))
        XCTAssertNil(n(1500, hour: 16, p: 40))     // too early to worry about protein
        XCTAssertEqual(n(1950, hour: 20, p: 130), .onTrack)
        XCTAssertNil(n(1950, hour: 15, p: 130))
        XCTAssertNil(NutritionMath.nudge(eaten: 1000, target: 0, proteinEaten: nil, proteinTarget: nil, hour: 20, isToday: true))
    }
}

final class AnyaFoodFallbackTests: XCTestCase {
    func testFencedAndBareJsonBothReadAsFood() {
        let items = "{\"meal\":\"lunch\",\"items\":[{\"name\":\"Rice\",\"kcal\":200,\"carbsG\":45}]}"
        XCTAssertEqual(AnyaActions.parseFood(from: "About 200 kcal.\n```anya-food\n\(items)\n```")?.items.first?.name, "Rice")
        XCTAssertEqual(AnyaActions.parseFood(from: "Here you go:\n```json\n\(items)\n```")?.items.first?.name, "Rice")
        XCTAssertEqual(AnyaActions.parseFood(from: "Estimate: \(items) done")?.meal, "lunch")
        XCTAssertNil(AnyaActions.parseFood(from: "I can't tell what that is."))
        XCTAssertNil(AnyaActions.parseFood(from: "{\"other\":1}"))
    }
}
