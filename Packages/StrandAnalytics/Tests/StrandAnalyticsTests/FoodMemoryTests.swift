import XCTest
@testable import StrandAnalytics

final class FoodMemoryTests: XCTestCase {
    private func learned(_ name: String, _ amount: String?, _ kcal: Double, at: Int = 1) -> LearnedFood {
        LearnedFood(name: name, amount: amount, kcal: kcal, proteinG: 10, carbsG: 8, fatG: 6, updatedAt: at)
    }
    private func item(_ name: String, _ amount: String?) -> AnyaFoodItem { AnyaFoodItem(name: name, amount: amount, kcal: 999, proteinG: 1, carbsG: 1, fatG: 1) }

    func testAPortionIsACountAndAUnit() {
        XCTAssertEqual(FoodMemory.portion("150 gram")?.count, 150)
        XCTAssertEqual(FoodMemory.portion("150 gram")?.unit, "g")
        XCTAssertEqual(FoodMemory.portion("±150g (perkiraan)")?.unit, "g")
        XCTAssertEqual(FoodMemory.portion("1/2 piring")?.count, 0.5)
        XCTAssertEqual(FoodMemory.portion("1,5 gelas")?.count, 1.5)
        XCTAssertNil(FoodMemory.portion("semangkuk"))
        XCTAssertNil(FoodMemory.portion(nil))
        XCTAssertNil(FoodMemory.portion("0 potong"))
        XCTAssertNil(FoodMemory.portion("1/0 potong"))
    }

    func testTheSamePortionTakesThePersonsFigures() {
        let list = [learned("Tempe goreng", "2 potong", 200)]
        let got = FoodMemory.figures(for: item("tempe  Goreng", "2 potong"), in: list)
        XCTAssertEqual(got?.kcal, 200)
        XCTAssertEqual(got?.proteinG, 10)
        XCTAssertEqual(got?.name, "tempe  Goreng", "the new item keeps its own name and portion")
    }

    func testAnotherCountOfTheSameUnitIsScaled() {
        let list = [learned("Nasi putih", "150 g", 270)]
        XCTAssertEqual(FoodMemory.figures(for: item("Nasi putih", "300 gram"), in: list)?.kcal, 540)
        XCTAssertEqual(FoodMemory.figures(for: item("Nasi putih", "100 g"), in: list)?.carbsG, 5.3)
    }

    func testNothingIsReusedWhenTheyCannotBeCompared() {
        let list = [learned("Tempe goreng", "2 potong", 200), learned("Soto ayam", nil, 300)]
        XCTAssertNil(FoodMemory.figures(for: item("Tempe goreng", "100 g"), in: list), "another unit")
        XCTAssertNil(FoodMemory.figures(for: item("Tempe goreng", nil), in: list))
        XCTAssertNil(FoodMemory.figures(for: item("Tempe mendoan", "2 potong"), in: list), "another food")
        XCTAssertNil(FoodMemory.figures(for: item("Tempe goreng", "40 potong"), in: list), "stretched too far")
        XCTAssertNil(FoodMemory.figures(for: item("Soto ayam", "1 mangkuk"), in: list))
        XCTAssertEqual(FoodMemory.figures(for: item("Soto ayam", nil), in: list)?.kcal, 300)
    }

    func testOneFigurePerFoodAndUnit() {
        var list: [LearnedFood] = []
        list = FoodMemory.remember(learned("Tempe goreng", "2 potong", 200, at: 1), in: list)
        list = FoodMemory.remember(learned("Tempe goreng", "100 g", 270, at: 2), in: list)
        list = FoodMemory.remember(learned("tempe goreng", "1 potong", 90, at: 3), in: list)
        XCTAssertEqual(list.map(\.kcal), [90, 270], "the newer count of the same unit replaced the older")
        XCTAssertEqual(FoodMemory.remember(learned(" - ", "1", 100), in: list), list, "a name with no words is not kept")
        for i in 0..<(FoodMemory.limit + 5) { list = FoodMemory.remember(learned("food \(i)", nil, 100), in: list) }
        XCTAssertEqual(list.count, FoodMemory.limit)
    }
}
