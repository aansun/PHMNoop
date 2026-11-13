import XCTest
import GRDB
@testable import WhoopStore

final class WorkoutSuggestionStoreTests: XCTestCase {

    private func row(_ start: Int = 1_000, _ end: Int = 2_800, device: String = "dev-a",
                     sport: String = "Running", outcome: String = "pending") -> WorkoutSuggestionRow {
        WorkoutSuggestionRow(
            id: WorkoutSuggestionRow.key(deviceId: device, startSec: start), deviceId: device,
            startSec: start, endSec: end, createdAt: end + 60, predictedSport: sport, predictedClass: "run", confidence: 0.7,
            scoresJSON: "{\"run\":0.9,\"walk\":0.2}", featuresJSON: "{\"meanHR\":150}", outcome: outcome, outcomeAt: nil, savedSport: nil)
    }

    // MARK: Migration (additive)

    func testV48CreatesTableAndIndex() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("workoutSuggestion"))
        let pk = try await store.primaryKeyColumns("workoutSuggestion")
        XCTAssertEqual(pk, ["id"])
        let cols = try await store.columnNamesForTest(table: "workoutSuggestion")
        XCTAssertEqual(cols, ["id", "deviceId", "startSec", "endSec", "createdAt", "predictedSport", "predictedClass", "confidence",
                              "scoresJSON", "featuresJSON", "outcome", "outcomeAt", "savedSport"])
        let idx = try await store.indexNamesForTest(table: "workoutSuggestion")
        XCTAssertTrue(idx.contains("idx_workoutSuggestion_device_start"))
    }

    func testV48IsAdditive() async throws {
        let tables = try await WhoopStore.inMemory().tableNames()
        for t in ["hrSample", "gravitySample", "stepSample", "workout", "sleepSession", "foodEntry", "labMarker", "dailyMetric"] {
            XCTAssertTrue(tables.contains(t), "v48 must not drop \(t)")
        }
    }

    // MARK: Record

    func testSameStartIsOneRowAndAPendingOneIsRefreshed() async throws {
        let store = try await WhoopStore.inMemory()
        let first = try await store.recordWorkoutSuggestion(row())
        XCTAssertTrue(first)
        // The workout is still going on: offered again with a later end and a changed prediction. Still one row, now showing the latest.
        var again = row(1_000, 3_600); again.predictedSport = "Cycling"; again.confidence = 0.2
        let second = try await store.recordWorkoutSuggestion(again)
        XCTAssertTrue(second)
        let rows = try await store.workoutSuggestions(deviceId: "dev-a")
        XCTAssertEqual(rows.count, 1, "the same start must never become a second row")
        XCTAssertEqual(rows[0].endSec, 3_600)
        XCTAssertEqual(rows[0].predictedSport, "Cycling")
        XCTAssertEqual(rows[0].confidence, 0.2, accuracy: 1e-9)
        XCTAssertEqual(rows[0].createdAt, 2_860, "createdAt stays the first time it was offered")
    }

    func testADecidedRowIsFrozenAgainstALaterOffer() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.recordWorkoutSuggestion(row())
        _ = try await store.settleWorkoutSuggestion(deviceId: "dev-a", startSec: 1_000, outcome: .saved, at: 3_000, savedSport: "Running")
        var late = row(1_000, 4_000); late.predictedSport = "Cycling"; late.confidence = 0.1
        let changed = try await store.recordWorkoutSuggestion(late)
        XCTAssertFalse(changed, "what the person decided on must not be rewritten")
        let r = try await store.workoutSuggestions(deviceId: "dev-a")[0]
        XCTAssertEqual(r.predictedSport, "Running")
        XCTAssertEqual(r.endSec, 2_800)
        XCTAssertEqual(r.outcome, "saved")
    }

    func testDifferentWindowsAreDifferentRows() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.recordWorkoutSuggestion(row(1_000, 2_800))
        _ = try await store.recordWorkoutSuggestion(row(5_000, 6_800))
        let rows = try await store.workoutSuggestions(deviceId: "dev-a")
        XCTAssertEqual(rows.map(\.startSec), [1_000, 5_000])
    }

    func testRowsAreScopedByDeviceAndSince() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.recordWorkoutSuggestion(row(1_000, 2_800, device: "dev-a"))
        _ = try await store.recordWorkoutSuggestion(row(1_000, 2_800, device: "dev-b"))
        _ = try await store.recordWorkoutSuggestion(row(9_000, 9_900, device: "dev-a"))
        let all = try await store.workoutSuggestions(deviceId: "dev-a")
        XCTAssertEqual(all.count, 2)
        let late = try await store.workoutSuggestions(deviceId: "dev-a", since: 5_000)
        XCTAssertEqual(late.map(\.startSec), [9_000])
        let other = try await store.workoutSuggestions(deviceId: "dev-b")
        XCTAssertEqual(other.count, 1)
    }

    // MARK: Settle

    func testSavedRecordsTheSportAndOutcomeTime() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.recordWorkoutSuggestion(row())
        let changed = try await store.settleWorkoutSuggestion(deviceId: "dev-a", startSec: 1_000,
                                                              outcome: .saved, at: 3_000, savedSport: "Running")
        XCTAssertTrue(changed)
        let r = try await store.workoutSuggestions(deviceId: "dev-a")[0]
        XCTAssertEqual(r.outcome, "saved")
        XCTAssertEqual(r.outcomeAt, 3_000)
        XCTAssertEqual(r.savedSport, "Running")
    }

    func testDismissedKeepsNoSavedSport() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.recordWorkoutSuggestion(row())
        _ = try await store.settleWorkoutSuggestion(deviceId: "dev-a", startSec: 1_000,
                                                    outcome: .dismissed, at: 3_100, savedSport: "ignored")
        let r = try await store.workoutSuggestions(deviceId: "dev-a")[0]
        XCTAssertEqual(r.outcome, "dismissed")
        XCTAssertNil(r.savedSport, "a dismissed window has no saved sport")
    }

    func testADecisionAlreadyTakenIsNeverFlipped() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.recordWorkoutSuggestion(row())
        _ = try await store.settleWorkoutSuggestion(deviceId: "dev-a", startSec: 1_000, outcome: .saved, at: 3_000, savedSport: "Running")
        let flipped = try await store.settleWorkoutSuggestion(deviceId: "dev-a", startSec: 1_000, outcome: .dismissed, at: 4_000, savedSport: nil)
        XCTAssertFalse(flipped)
        let r = try await store.workoutSuggestions(deviceId: "dev-a")[0]
        XCTAssertEqual(r.outcome, "saved")
        XCTAssertEqual(r.outcomeAt, 3_000)
    }

    func testSettlingAnUnknownWindowChangesNothing() async throws {
        let store = try await WhoopStore.inMemory()
        let changed = try await store.settleWorkoutSuggestion(deviceId: "dev-a", startSec: 1, outcome: .saved, at: 3, savedSport: "Running")
        XCTAssertFalse(changed)
        let rows = try await store.workoutSuggestions(deviceId: "dev-a")
        XCTAssertTrue(rows.isEmpty)
    }

    func testSettleToPendingIsRefused() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.recordWorkoutSuggestion(row())
        let changed = try await store.settleWorkoutSuggestion(deviceId: "dev-a", startSec: 1_000, outcome: .pending, at: 3_000, savedSport: nil)
        XCTAssertFalse(changed)
    }
}
