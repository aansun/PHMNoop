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
