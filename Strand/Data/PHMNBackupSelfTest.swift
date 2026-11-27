#if DEBUG
import Foundation
import WhoopStore

/// A check of the whole backup path with the extras, run by a debug build when launched with `--backup-selftest` (the result goes to the log as `PHMNBACKUP`).
/// It writes a backup from a scratch set of defaults and files, restores it into a second scratch set and compares: what must come back does, and what must not,
/// does not. Nothing of the real app's data is read or changed.
enum PHMNBackupSelfTest {
    static func run() async -> [String] {
        var out: [String] = []
        func check(_ ok: Bool, _ what: String) { out.append((ok ? "PASS " : "FAIL ") + what) }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("phmn-backup-selftest-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let suiteA = "phmn.selftest.a.\(UUID().uuidString)", suiteB = "phmn.selftest.b.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteA); UserDefaults().removePersistentDomain(forName: suiteB) }
        guard let a = UserDefaults(suiteName: suiteA), let b = UserDefaults(suiteName: suiteB) else { return ["FAIL no scratch defaults"] }
        do {
            let supportA = root.appendingPathComponent("supportA", isDirectory: true), supportB = root.appendingPathComponent("supportB", isDirectory: true)
            try fm.createDirectory(at: supportA.appendingPathComponent("WorkoutReviews/1700000000-Run"), withIntermediateDirectories: true)
            try fm.createDirectory(at: supportA.appendingPathComponent("OpenWhoop"), withIntermediateDirectories: true)
            try fm.createDirectory(at: supportB, withIntermediateDirectories: true)
            let photo = Data((0..<2048).map { UInt8($0 % 251) })
            try Data("{\"note\":\"felt strong\"}".utf8).write(to: supportA.appendingPathComponent("WorkoutReviews/1700000000-Run/review.json"))
            try photo.write(to: supportA.appendingPathComponent("WorkoutReviews/1700000000-Run/photo.jpg"))
            try Data("{}".utf8).write(to: supportA.appendingPathComponent("stress-waking-days.json"))
            try Data("not for a backup".utf8).write(to: supportA.appendingPathComponent("OpenWhoop/bg-1.jpg"))

            // Kept: user content and choices. Left out: state of a device or an install, and what would be a secret.
            let blob = Data("groups-blob".utf8)
            a.set(blob, forKey: "nuna.gym.programGroups")
            a.set(Data("routes".utf8), forKey: "noop.workoutRoutes")
            a.set(Data("memory".utf8), forKey: "coach.memories.v1")
            a.set(Data("about".utf8), forKey: "coach.aboutYou.v1")
            a.set(Data("catalog".utf8), forKey: "journal.catalog.v2")
            a.set(["250", "300"], forKey: "noop.hydrationEntries.2026-11-11")
            a.set(9000, forKey: "nuna.goal.steps")
            a.set(true, forKey: "noop.experiment.strava.autoDetect")
            a.set("lift", forKey: "nuna.gym.openGroup")
            for key in ["alarm.lastFiredAt", "ble.lastConnectedPeripheralUUID", "ai.customConnected", "ai.keyProvider", "noop.pendingCoachQuestion",
                        "behavior.batteryLowAlerted", "coach.composerDraft", "noop.environment.lastLocation", "backup.lastRestoreAt", "profile.stepsCalibrationCoefficient"] {
                a.set("device-state", forKey: key)
            }

            // A real, empty store for the database half (the file must pass the app's own integrity checks).
            let dbA = root.appendingPathComponent("a.sqlite"), dbLive = root.appendingPathComponent("live.sqlite")
            do { _ = try await WhoopStore(path: dbA.path); _ = try await WhoopStore(path: dbLive.path) }
            try? await Task.sleep(nanoseconds: 300_000_000)
            for url in [dbA, dbLive] {
                for suffix in ["-wal", "-shm"] { try? fm.removeItem(atPath: url.path + suffix) }
            }
            // Fold any WAL content in before copying: open, checkpoint, close.
            for url in [dbA, dbLive] { let s = try await WhoopStore(path: url.path); try await s.checkpointWAL() }
            try? await Task.sleep(nanoseconds: 300_000_000)

            let snap = PHMNBackupExtras.collect(defaults: a, supportDirectory: supportA)
            check(snap.defaultsPlist != nil, "extras: a defaults entry was made")
            check(Set(snap.files.map(\.entry)) == ["phmn-files/WorkoutReviews/1700000000-Run/review.json", "phmn-files/WorkoutReviews/1700000000-Run/photo.jpg", "phmn-files/stress-waking-days.json"],
                  "extras: exactly the review files and the stress days are collected (got \(snap.files.map(\.entry).sorted()))")

            let zip = root.appendingPathComponent("test.noopbak")
            try DataBackup.writeBackupForTesting(databaseAt: dbA, to: zip, settings: ["profile.age": 41], extras: snap)
            check(DataBackup.writtenBackupIsIntact(at: zip), "the written backup reads back intact")

            let result = DataBackup.restore(from: zip, toDatabaseAt: dbLive.path, settingsDefaults: b, restoreSupportDirectory: supportB)
            if case .imported = result { check(true, "restore finished") } else { check(false, "restore finished (got \(result))") }

            check(b.data(forKey: "nuna.gym.programGroups") == blob, "restored: program groups, byte for byte")
            check(b.data(forKey: "noop.workoutRoutes") == Data("routes".utf8), "restored: GPS routes")
            check(b.data(forKey: "coach.memories.v1") == Data("memory".utf8), "restored: Anya's memory")
            check(b.data(forKey: "coach.aboutYou.v1") == Data("about".utf8), "restored: About you")
            check(b.data(forKey: "journal.catalog.v2") == Data("catalog".utf8), "restored: the full journal catalogue (kept over the bridged names)")
            check((b.array(forKey: "noop.hydrationEntries.2026-11-11") as? [String]) == ["250", "300"], "restored: a day of hydration entries")
            check(b.integer(forKey: "nuna.goal.steps") == 9000, "restored: a goal")
            check(b.bool(forKey: "noop.experiment.strava.autoDetect"), "restored: a Strava switch")
            check(b.integer(forKey: "profile.age") == 41, "restored: profile age through settings.json as before")
            for key in ["alarm.lastFiredAt", "ble.lastConnectedPeripheralUUID", "ai.customConnected", "ai.keyProvider", "noop.pendingCoachQuestion",
                        "behavior.batteryLowAlerted", "coach.composerDraft", "noop.environment.lastLocation", "profile.stepsCalibrationCoefficient"] {
                check(b.object(forKey: key) == nil, "not restored: \(key)")
            }
            check((try? Data(contentsOf: supportB.appendingPathComponent("WorkoutReviews/1700000000-Run/photo.jpg"))) == photo, "restored: a workout photo, byte for byte")
            check(fm.fileExists(atPath: supportB.appendingPathComponent("WorkoutReviews/1700000000-Run/review.json").path), "restored: the workout review notes")
            check(fm.fileExists(atPath: supportB.appendingPathComponent("stress-waking-days.json").path), "restored: the stress days")
            check(!fm.fileExists(atPath: supportB.appendingPathComponent("OpenWhoop").path), "not restored: the background pictures folder")

            // A name that tries to leave the folder, or is not one of the roots, is refused.
            check(PHMNBackupExtras.relativePath(forEntry: "phmn-files/../x") == nil, "refused: a path with ..")
            check(PHMNBackupExtras.relativePath(forEntry: "phmn-files//etc/passwd") == nil, "refused: an absolute-looking path")
            check(PHMNBackupExtras.relativePath(forEntry: "phmn-files/OpenWhoop/whoop.sqlite") == nil, "refused: a root that is not listed")
        } catch {
            check(false, "self-test threw: \(error)")
        }
        return out
    }
}
#endif
