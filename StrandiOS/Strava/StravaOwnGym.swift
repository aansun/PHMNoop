import Foundation
import WhoopStore
import StrandAnalytics

/// Which strength sessions may go to Strava: only the ones logged in PHMN's own gym session.
///
/// Gym data that came from somewhere else must never be sent on: Hevy brings its sessions in with ids that start with `hevy:`, and
/// Apple Health or a Hevy CSV / Liftosaur file bring workouts with no gym session behind them at all. A PHMN session is the one that has a
/// stored gym session whose id is not an import id, the same start time, and a workout row of its own ("manual").
///
/// The set of such sessions is read from the gym tables (`refresh`) and topped up the moment a session is saved (`add`), so the check
/// that decides whether an Upload button shows can stay a plain, immediate call.
@MainActor
enum StravaOwnGym {
    private static var keys: Set<String> = []
    private static weak var repo: Repository?

    static func isOwn(_ row: WorkoutRow) -> Bool {
        row.source == "manual" && StravaActivityType.value(for: row.sport) == "WeightTraining"
            && keys.contains(StravaSettingsModel.workoutKey(for: row))
    }

    static func add(startTs: Int, sport: String) { keys.insert("\(startTs)|\(sport)") }

    static func refresh(repo: Repository) async {
        self.repo = repo
        guard let store = await repo.storeHandle() else { return }
        let sessions = (try? await store.liftSessions(deviceId: repo.deviceId, fromTs: 0, toTs: Int(Date().timeIntervalSince1970) + 86_400)) ?? []
        keys = Set(sessions.filter { !$0.id.hasPrefix(HevyImporter.idPrefix) }.map { "\($0.startTs)|\($0.sport)" })
    }
}

/// The one rule for "can this workout be uploaded": a GPS route, a treadmill session, or a gym session logged in PHMN.
enum StravaEligibility {
    @MainActor static func canUpload(_ row: WorkoutRow) -> Bool {
        if StravaActivityType.isTreadmill(row.sport) { return true }
        if let route = RouteStore.load(startTs: row.startTs, sport: row.sport), RouteMath.decode(route.polyline).count >= 2 { return true }
        return StravaOwnGym.isOwn(row)
    }
}


extension StravaOwnGym {
    /// What Strava shows for a gym session: the program's name, and under it every exercise with its sets, as Hevy sends them. Nil when the
    /// session cannot be found (its sets are what the description is made of).
    static func summary(for row: WorkoutRow) async -> (name: String, description: String)? {
        guard let repo, let store = await repo.storeHandle() else { return nil }
        let sessions = (try? await store.liftSessions(deviceId: repo.deviceId, fromTs: row.startTs - 60, toTs: row.startTs + 60)) ?? []
        guard let session = sessions.first(where: { $0.startTs == row.startTs && !$0.id.hasPrefix(HevyImporter.idPrefix) }) else { return nil }
        let sets = ((try? await store.liftSets(sessionId: session.id)) ?? []).sorted { $0.ord < $1.ord }
        guard !sets.isEmpty else { return nil }
        let system = UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        var order: [String] = []
        var byExercise: [String: [LiftSetRow]] = [:]
        for s in sets { if byExercise[s.exercise] == nil { order.append(s.exercise) }; byExercise[s.exercise, default: []].append(s) }
        var lines: [String] = []
        for name in order {
            let kind = NunaExerciseKind.of(name)
            lines.append(name)
            for (i, s) in (byExercise[name] ?? []).sorted(by: { $0.setIndex < $1.setIndex }).enumerated() {
                let text = kind.setText(weightKg: s.weightKg, reps: s.reps, system: system)
                lines.append("\(s.isWarmup ? "W" : String(i + 1)). \(text)")
            }
            lines.append("")
        }
        let working = sets.filter { !$0.isWarmup }
        let volume = LiftMetrics.volumeLoadKg(sets) ?? 0
        var footer = "\(working.count) sets"
        if volume > 0 { footer += " · " + LiftFormat.weight(volume, system: system) }
        lines.append(footer)
        lines.append("Logged with PHMN")
        let name = (session.programName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? WorkoutSource.displaySport(row.sport)
        return (name, String(lines.joined(separator: "\n").prefix(3000)))
    }
}
