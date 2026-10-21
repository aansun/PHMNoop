import XCTest
import GRDB
@testable import WhoopStore

final class FoodLogStoreTests: XCTestCase {
    private func entry(_ id: String, day: String = "2026-10-21", meal: String = "lunch", name: String = "Rice", kcal: Double = 300, at: Int = 1_000) -> FoodEntryRow {
        FoodEntryRow(id: id, deviceId: "d1", day: day, meal: meal, name: name, kcal: kcal, proteinG: 8, carbsG: 60, fatG: 2, source: "manual", createdAt: at)
    }

    func testV47CreatesBothTables() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("foodEntry")); XCTAssertTrue(tables.contains("savedFood"))
        let names = try await store.indexNamesForTest(table: "savedFood")
        XCTAssertTrue(names.contains("idx_savedFood_natural"))
    }

    func testEntriesRoundTripInDayOrderAndEditInPlace() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertFoodEntries([entry("a", day: "2026-10-21", at: 2), entry("b", day: "2026-10-20", at: 1), entry("c", day: "2026-10-21", at: 3)])
        var rows = try await store.foodEntries(deviceId: "d1", fromDay: "2026-10-20", toDay: "2026-10-21")
        XCTAssertEqual(rows.map(\.id), ["b", "a", "c"])
        try await store.upsertFoodEntries([entry("a", kcal: 450)])
        rows = try await store.foodEntries(deviceId: "d1", fromDay: "2026-10-21", toDay: "2026-10-21")
        XCTAssertEqual(rows.count, 2); XCTAssertEqual(rows.first { $0.id == "a" }?.kcal, 450)
        let none = try await store.foodEntries(deviceId: "other", fromDay: "2026-10-01", toDay: "2026-10-31")
        XCTAssertTrue(none.isEmpty)
    }

    func testDeleteAndRecentFoodsAreDistinctByNameNewestFirst() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertFoodEntries([entry("a", name: "Rice", at: 1), entry("b", name: "Egg", at: 2), entry("c", name: "Rice", kcal: 320, at: 3)])
        let recent = try await store.recentFoods(deviceId: "d1", limit: 10)
        XCTAssertEqual(recent.map(\.name), ["Rice", "Egg"])
        XCTAssertEqual(recent.first?.kcal, 320)
        let removed = try await store.deleteFoodEntry(id: "c")
        XCTAssertTrue(removed)
        let again = try await store.deleteFoodEntry(id: "c")
        XCTAssertFalse(again)
    }

    func testSavedFoodsAreOnePerNameAndOrderedByUse() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertSavedFood(SavedFoodRow(id: "1", deviceId: "d1", name: "Oats", kcal: 300, proteinG: 10, carbsG: 50, fatG: 6, useCount: 0, updatedAt: 1))
        try await store.upsertSavedFood(SavedFoodRow(id: "2", deviceId: "d1", name: "Egg", kcal: 70, proteinG: 6, carbsG: 0, fatG: 5, useCount: 0, updatedAt: 2))
        try await store.bumpSavedFood(id: "1", at: 3)
        try await store.bumpSavedFood(id: "1", at: 4)
        try await store.upsertSavedFood(SavedFoodRow(id: "x", deviceId: "d1", name: "Oats", kcal: 320, proteinG: 11, carbsG: 52, fatG: 6, useCount: 0, updatedAt: 5))
        let list = try await store.savedFoods(deviceId: "d1")
        XCTAssertEqual(list.map(\.name), ["Oats", "Egg"])
        XCTAssertEqual(list.first?.kcal, 320); XCTAssertEqual(list.first?.useCount, 2); XCTAssertEqual(list.first?.id, "1")
        let removed = try await store.deleteSavedFood(id: "2")
        XCTAssertTrue(removed)
    }
}
