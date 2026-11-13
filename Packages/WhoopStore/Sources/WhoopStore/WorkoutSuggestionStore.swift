import Foundation
import GRDB

// MARK: - v48 store: what the workout auto-detector offered, and what the person did with it
//
// WorkoutSuggestionStore.swift — GRDB access to the `workoutSuggestion` table (migration v48-workout-suggestion-log).
//
// It is INSTRUMENTATION. Nothing reads it to decide what to show. It exists so that a later learner can tell a person's own
// label from the detector's guess saved with one tap, can measure how often the offered sport was right, and keeps the
// "Not a workout" decisions that the UserDefaults list forgets after ~30 days.
//
// One row per workout, keyed by where it STARTS. The detector offers the same workout again and again while it is still going on, each time with a
// later end, so the end cannot be part of the key. While a row is `pending` the latest offer refreshes its prediction fields (that is what the person
// is looking at). The moment the person decides, the row is frozen: the prediction they decided on is evidence and is never rewritten, and the
// outcome never changes again.

/// What happened to an offered window.
public enum WorkoutSuggestionOutcome: String, Sendable, CaseIterable {
    case pending
    case saved
    case dismissed
}

/// One window the auto-detector offered. Times are unix seconds.
public struct WorkoutSuggestionRow: Equatable, Codable, Sendable {
    public var id: String
    public var deviceId: String
    public var startSec: Int
    public var endSec: Int
    public var createdAt: Int
    public var predictedSport: String
    public var predictedClass: String?
    public var confidence: Double
    public var scoresJSON: String?
    public var featuresJSON: String?
    public var outcome: String
    public var outcomeAt: Int?
    public var savedSport: String?

    public init(id: String, deviceId: String, startSec: Int, endSec: Int, createdAt: Int, predictedSport: String,
                predictedClass: String?, confidence: Double, scoresJSON: String?, featuresJSON: String?,
                outcome: String, outcomeAt: Int?, savedSport: String?) {
        self.id = id; self.deviceId = deviceId; self.startSec = startSec; self.endSec = endSec; self.createdAt = createdAt
        self.predictedSport = predictedSport; self.predictedClass = predictedClass; self.confidence = confidence
        self.scoresJSON = scoresJSON; self.featuresJSON = featuresJSON
        self.outcome = outcome; self.outcomeAt = outcomeAt; self.savedSport = savedSport
    }

    /// The key of a workout: the same start always maps to the same row, so offering it again never makes a second one.
    public static func key(deviceId: String, startSec: Int) -> String { "\(deviceId):\(startSec)" }

    static func decode(_ row: Row) -> WorkoutSuggestionRow {
        WorkoutSuggestionRow(
            id: row["id"], deviceId: row["deviceId"], startSec: row["startSec"], endSec: row["endSec"],
            createdAt: row["createdAt"], predictedSport: row["predictedSport"], predictedClass: row["predictedClass"],
            confidence: row["confidence"], scoresJSON: row["scoresJSON"], featuresJSON: row["featuresJSON"],
            outcome: row["outcome"], outcomeAt: row["outcomeAt"], savedSport: row["savedSport"])
    }
}

extension WhoopStore {

    /// Record a window the detector offered. A new start writes a new row. The same start again refreshes the prediction while the row is still
    /// `pending` (the detector offers a running workout again with a later end), and changes nothing once the person has decided, so a decision
    /// and the prediction it was made on are never overwritten. Returns true when a row was written or refreshed.
    @discardableResult
    public func recordWorkoutSuggestion(_ row: WorkoutSuggestionRow) async throws -> Bool {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO workoutSuggestion
                    (id, deviceId, startSec, endSec, createdAt, predictedSport, predictedClass, confidence,
                     scoresJSON, featuresJSON, outcome, outcomeAt, savedSport)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    endSec = excluded.endSec,
                    predictedSport = excluded.predictedSport,
                    predictedClass = excluded.predictedClass,
                    confidence = excluded.confidence,
                    scoresJSON = excluded.scoresJSON,
                    featuresJSON = excluded.featuresJSON
                WHERE workoutSuggestion.outcome = 'pending'
                """, arguments: [
                    row.id, row.deviceId, row.startSec, row.endSec, row.createdAt, row.predictedSport, row.predictedClass,
                    row.confidence, row.scoresJSON, row.featuresJSON, row.outcome, row.outcomeAt, row.savedSport,
                ])
            return db.changesCount > 0
        }
    }

    /// Settle a pending workout as saved or dismissed. Only a `pending` row moves: a decision already taken is kept, so tapping twice, or a
    /// later duplicate, cannot flip it. Returns true when the row changed.
    @discardableResult
    public func settleWorkoutSuggestion(deviceId: String, startSec: Int,
                                        outcome: WorkoutSuggestionOutcome, at ts: Int, savedSport: String?) async throws -> Bool {
        guard outcome != .pending else { return false }
        return try syncWrite { db in
            try db.execute(sql: """
                UPDATE workoutSuggestion
                SET outcome = ?, outcomeAt = ?, savedSport = ?
                WHERE id = ? AND outcome = 'pending'
                """, arguments: [
                    outcome.rawValue, ts, outcome == .saved ? savedSport : nil,
                    WorkoutSuggestionRow.key(deviceId: deviceId, startSec: startSec),
                ])
            return db.changesCount > 0
        }
    }

    /// Offered windows for a device that started at or after `since` (unix seconds), oldest first. Served by `idx_workoutSuggestion_device_start`.
    public func workoutSuggestions(deviceId: String, since: Int = 0) async throws -> [WorkoutSuggestionRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM workoutSuggestion
                WHERE deviceId = ? AND startSec >= ?
                ORDER BY startSec ASC
                """, arguments: [deviceId, since]).map(WorkoutSuggestionRow.decode)
        }
    }
}
