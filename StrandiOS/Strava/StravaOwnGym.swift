import Foundation
import WhoopStore

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

    static func isOwn(_ row: WorkoutRow) -> Bool {
        row.source == "manual" && StravaActivityType.value(for: row.sport) == "WeightTraining"
            && keys.contains(StravaSettingsModel.workoutKey(for: row))
    }

    static func add(startTs: Int, sport: String) { keys.insert("\(startTs)|\(sport)") }

    static func refresh(repo: Repository) async {
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
