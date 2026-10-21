import Foundation
import GRDB

// MARK: - v47 store: the nutrition diary
//
// FoodLogStore.swift — GRDB CRUD over `foodEntry` and `savedFood` (migration v47). One `foodEntry` is one thing eaten on one
// day in one meal; the day's intake is the sum of its entries, derived on read. Calories and macros are stored exactly as
// entered. There is no food catalogue and nothing here reads the network.

public struct FoodEntryRow: Equatable, Codable, Sendable {
    public var id: String
    public var deviceId: String
    /// yyyy-MM-dd
    public var day: String
    /// breakfast | lunch | dinner | snack
    public var meal: String
    public var name: String
    public var kcal: Double
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    /// manual | anya | saved
    public var source: String
    public var createdAt: Int

    public init(id: String, deviceId: String, day: String, meal: String, name: String, kcal: Double,
                proteinG: Double?, carbsG: Double?, fatG: Double?, source: String, createdAt: Int) {
        self.id = id; self.deviceId = deviceId; self.day = day; self.meal = meal; self.name = name; self.kcal = kcal
        self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG; self.source = source; self.createdAt = createdAt
    }

    static func decode(_ row: Row) -> FoodEntryRow {
        FoodEntryRow(id: row["id"], deviceId: row["deviceId"], day: row["day"], meal: row["meal"], name: row["name"], kcal: row["kcal"],
                     proteinG: row["proteinG"], carbsG: row["carbsG"], fatG: row["fatG"], source: row["source"], createdAt: row["createdAt"])
    }
}

public struct SavedFoodRow: Equatable, Codable, Sendable {
    public var id: String
    public var deviceId: String
    public var name: String
    public var kcal: Double
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public var useCount: Int
    public var updatedAt: Int

    public init(id: String, deviceId: String, name: String, kcal: Double, proteinG: Double?, carbsG: Double?, fatG: Double?,
                useCount: Int, updatedAt: Int) {
        self.id = id; self.deviceId = deviceId; self.name = name; self.kcal = kcal
        self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG; self.useCount = useCount; self.updatedAt = updatedAt
    }

    static func decode(_ row: Row) -> SavedFoodRow {
        SavedFoodRow(id: row["id"], deviceId: row["deviceId"], name: row["name"], kcal: row["kcal"], proteinG: row["proteinG"],
                     carbsG: row["carbsG"], fatG: row["fatG"], useCount: row["useCount"], updatedAt: row["updatedAt"])
    }
}

extension WhoopStore {

    // MARK: Entries

    /// Adds entries (an entry with an id already stored is replaced, so an edit is an upsert). Returns how many were written.
    @discardableResult
    public func upsertFoodEntries(_ rows: [FoodEntryRow]) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        return try syncWrite { db in
            var written = 0
            for r in rows {
                try db.execute(sql: """
                    INSERT INTO foodEntry (id, deviceId, day, meal, name, kcal, proteinG, carbsG, fatG, source, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        day = excluded.day, meal = excluded.meal, name = excluded.name, kcal = excluded.kcal,
                        proteinG = excluded.proteinG, carbsG = excluded.carbsG, fatG = excluded.fatG, source = excluded.source
                    """, arguments: [r.id, r.deviceId, r.day, r.meal, r.name, r.kcal, r.proteinG, r.carbsG, r.fatG, r.source, r.createdAt])
                written += db.changesCount
            }
            return written
        }
    }

    /// Entries from `fromDay` to `toDay` inclusive (yyyy-MM-dd), oldest first, then in the order they were added.
    public func foodEntries(deviceId: String, fromDay: String, toDay: String) async throws -> [FoodEntryRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM foodEntry WHERE deviceId = ? AND day >= ? AND day <= ?
                ORDER BY day ASC, createdAt ASC, id ASC
                """, arguments: [deviceId, fromDay, toDay]).map(FoodEntryRow.decode)
        }
    }

    @discardableResult
    public func deleteFoodEntry(id: String) async throws -> Bool {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM foodEntry WHERE id = ?", arguments: [id])
            return db.changesCount > 0
        }
    }

    /// The latest distinct foods eaten (by name), newest first, for the Recent list.
    public func recentFoods(deviceId: String, limit: Int) async throws -> [FoodEntryRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT e.* FROM foodEntry e
                WHERE e.deviceId = ? AND e.id = (
                    SELECT e2.id FROM foodEntry e2 WHERE e2.deviceId = e.deviceId AND e2.name = e.name
                    ORDER BY e2.createdAt DESC, e2.id DESC LIMIT 1)
                ORDER BY e.createdAt DESC, e.id DESC LIMIT ?
                """, arguments: [deviceId, max(0, limit)]).map(FoodEntryRow.decode)
        }
    }

    // MARK: Saved foods

    /// Keeps a food to add again. One per name per device: saving a name again updates its numbers and keeps its use count.
    public func upsertSavedFood(_ row: SavedFoodRow) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO savedFood (id, deviceId, name, kcal, proteinG, carbsG, fatG, useCount, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(deviceId, name) DO UPDATE SET
                    kcal = excluded.kcal, proteinG = excluded.proteinG, carbsG = excluded.carbsG, fatG = excluded.fatG,
                    updatedAt = excluded.updatedAt
                """, arguments: [row.id, row.deviceId, row.name, row.kcal, row.proteinG, row.carbsG, row.fatG, row.useCount, row.updatedAt])
        }
    }

    /// Most used first, then most recently updated.
    public func savedFoods(deviceId: String) async throws -> [SavedFoodRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM savedFood WHERE deviceId = ? ORDER BY useCount DESC, updatedAt DESC, name ASC",
                             arguments: [deviceId]).map(SavedFoodRow.decode)
        }
    }

    /// Counts one more use of a saved food (adding it to the diary).
    public func bumpSavedFood(id: String, at ts: Int) async throws {
        try syncWrite { db in
            try db.execute(sql: "UPDATE savedFood SET useCount = useCount + 1, updatedAt = ? WHERE id = ?", arguments: [ts, id])
        }
    }

    @discardableResult
    public func deleteSavedFood(id: String) async throws -> Bool {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM savedFood WHERE id = ?", arguments: [id])
            return db.changesCount > 0
        }
    }
}
