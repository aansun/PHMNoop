#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

/// What an import did, in numbers the screen turns into a sentence.
struct StravaImportSummary: Equatable {
    var added = 0          // workouts brought in
    var alreadyHere = 0    // overlaps a workout PHMN already has: logged here, or uploaded from here
    var noHeartRate = 0    // the strap recorded no heart rate in the window, so there is no honest Effort to show
    var skipped = 0        // an activity Strava sent without a usable time or length
}

/// Brings workouts from Strava into PHMN's own list: the ones done with another app (Hevy, a bike computer, a watch) and shared to Strava.
///
/// Strava gives the activity (what, when, how long, how far); it never gives the numbers PHMN shows. A row comes in as a manual workout with
/// no strain, and the same pass that scores a gym session logged here fills the average and peak heart rate, the zones and the Effort from the
/// heart rate the strap recorded in that window. So an activity only comes in when the strap has heart rate for it; without it there would be
/// nothing honest to score, and no Effort is made up from Strava's own figures.
///
/// Read-only towards Strava: nothing is sent back, and an activity PHMN uploaded itself is recognised and left out.
@MainActor
enum StravaImporter {
    /// About a minute of heart rate: the same gate the heart-rate reconcile uses, so a workout comes in only if it will also be scored.
    static let minSamples = 60

    /// One rule for whether a Strava activity may come in, shared by the import and by the suggestion in Today, so the two cannot disagree.
    enum Verdict {
        case candidate(activity: StravaActivitySummary, startTs: Int, endTs: Int, avgHr: Int, peakHr: Int)
        case alreadyHere      // overlaps a workout PHMN has, was uploaded from PHMN, or was handled before
        case noHeartRate      // the strap recorded no heart rate in the window
        case skipped          // no usable time or length
    }

    private static let parser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func judge(_ activity: StravaActivitySummary, now: Int, existing: [WorkoutRow], hrIds: [String], store: WhoopStore, honourHandled: Bool) async -> Verdict {
        if let external = activity.externalId, external.hasPrefix("noop-") { return .alreadyHere }
        if honourHandled, let id = activity.id, StravaHandled.contains(id) { return .alreadyHere }
        guard let startText = activity.startDate, let start = parser.date(from: startText),
              let elapsed = activity.elapsedTime, elapsed > 0 else { return .skipped }
        let startTs = Int(start.timeIntervalSince1970), endTs = startTs + elapsed
        guard endTs <= now, elapsed >= WorkoutSource.minManualSpanSeconds, elapsed <= WorkoutSource.maxManualSpanSeconds else { return .skipped }
        if existing.contains(where: { $0.startTs < endTs && $0.endTs > startTs }) { return .alreadyHere }
        let stats = try? await store.hrWindowStats(primaryId: hrIds[0], secondaryId: hrIds.count > 1 ? hrIds[1] : hrIds[0], from: startTs, to: endTs)
        guard let stats, stats.n >= minSamples, let avg = stats.avg, let peak = stats.max else { return .noHeartRate }
        return .candidate(activity: activity, startTs: startTs, endTs: endTs, avgHr: Int(avg.rounded()), peakHr: Int(peak))
    }

    static func run(days: Int, repo: Repository, client: StravaAPIClient) async throws -> StravaImportSummary {
        var summary = StravaImportSummary()
        guard let store = await repo.storeHandle() else { throw StravaError.network("no store") }
        let now = Int(Date().timeIntervalSince1970)
        let remote = try await client.recentActivities(after: now - days * 86_400, before: now + 86_400)
        // A little wider than the window: a workout that started before it can still overlap one at its edge.
        var existing = await repo.workoutRows(days: days + 2)
        let hrIds = Repository.workoutHrDeviceIds(source: "manual", activeStrapId: repo.deviceId, importedIds: repo.importedReadIds)

        for activity in remote.sorted(by: { ($0.startDate ?? "") < ($1.startDate ?? "") }) {
            // An import the person asks for brings back an activity they dismissed or deleted before: the handled list only quietens the automatic suggestion.
            switch await judge(activity, now: now, existing: existing, hrIds: hrIds, store: store, honourHandled: false) {
            case .alreadyHere: summary.alreadyHere += 1
            case .noHeartRate: summary.noHeartRate += 1
            case .skipped: summary.skipped += 1
            case .candidate(let activity, let startTs, let endTs, _, _):
                let distance = activity.distance.flatMap { $0 > 0 ? $0 : nil }
                guard let row = row(for: activity, startTs: startTs, endTs: endTs, sport: sport(for: activity.sportType), distanceM: distance) else { summary.skipped += 1; continue }
                await repo.saveManualWorkout(row)
                if let id = activity.id { StravaHandled.add(id) }
                existing.append(row)
                summary.added += 1
            }
        }
        if summary.added > 0 { await repo.refresh() }
        return summary
    }

    /// The workout as stored: a manual row with no strain (the strap's heart rate fills it), titled after the Strava activity.
    static func row(for activity: StravaActivitySummary, startTs: Int, endTs: Int, sport: String, distanceM: Double?) -> WorkoutRow? {
        guard let built = WorkoutSource.buildManualRowFromSpan(start: Date(timeIntervalSince1970: TimeInterval(startTs)), end: Date(timeIntervalSince1970: TimeInterval(endTs)),
                                                               sport: sport, avgHr: nil, energyKcal: nil, distanceM: distanceM) else { return nil }
        let title = (activity.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkoutRow(startTs: built.startTs, endTs: built.endTs, sport: built.sport, source: built.source, durationS: built.durationS,
                          energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: built.distanceM, zonesJSON: nil,
                          notes: title.isEmpty ? "Strava" : "Strava · " + title, steps: nil)
    }

    /// PHMN's name for a Strava `sport_type`; one PHMN has no name for keeps Strava's own, spaced out ("Kitesurf", "Ice Skate").
    static func sport(for stravaType: String?) -> String {
        switch stravaType ?? "" {
        case "Run", "VirtualRun": return "Running"
        case "TrailRun": return "Trail Run"
        case "Walk": return "Walking"
        case "Hike": return "Hiking"
        case "Ride", "EBikeRide", "GravelRide", "Handcycle", "Velomobile": return "Cycling"
        case "MountainBikeRide", "EMountainBikeRide": return "Mountain Biking"
        case "VirtualRide": return "Indoor Cycle"
        case "Swim": return "Swimming"
        case "Rowing": return "Rowing"
        case "Elliptical": return "Elliptical"
        case "StairStepper": return "Stair Climber"
        case "WeightTraining": return LiftSessionView.sport
        case "Crossfit": return "CrossFit"
        case "Yoga": return "Yoga"
        case "Pilates": return "Pilates"
        case "Boxing": return "Boxing"
        case "Basketball": return "Basketball"
        case "Soccer": return "Soccer"
        case "Tennis": return "Tennis"
        case "Badminton": return "Badminton"
        case "Squash": return "Squash"
        case "TableTennis": return "Table Tennis"
        case "Volleyball": return "Volleyball"
        case "MartialArts": return "Martial Arts"
        case "Dance": return "Dancing"
        case "Golf": return "Golf"
        case "RockClimbing", "Climbing": return "Climbing"
        case "AlpineSki", "BackcountrySki", "NordicSki": return "Skiing"
        case "Snowboard": return "Snowboarding"
        case "Kayaking", "Canoeing": return "Kayaking"
        case "Sail": return "Sailing"
        case "Surfing": return "Surfing"
        case "Pickleball": return "Pickleball"
        case "Workout", "HighIntensityIntervalTraining", "": return "Workout"
        default:
            var out = ""
            for ch in stravaType ?? "" {
                if ch.isUppercase, !out.isEmpty { out.append(" ") }
                out.append(ch)
            }
            return out
        }
    }
}

/// The Strava activities the person has dealt with (saved from a suggestion, imported, or dismissed), so one they later delete in PHMN is not suggested again.
enum StravaHandled {
    private static let key = "noop.experiment.strava.handled.v1"
    private static var ids: [Int] { UserDefaults.standard.array(forKey: key) as? [Int] ?? [] }
    static func contains(_ id: Int) -> Bool { ids.contains(id) }
    static func add(_ id: Int) {
        var all = ids
        guard !all.contains(id) else { return }
        all.append(id)
        if all.count > 400 { all.removeFirst(all.count - 400) }
        UserDefaults.standard.set(all, forKey: key)
    }
}

/// The workout Today offers when Strava has one PHMN does not: shown as a detected activity, saved only when the person processes it.
///
/// Duplicates are kept out three ways: an activity that overlaps any workout PHMN already has is left alone (a gym session logged here and sent to Strava,
/// a manual entry, a file), one PHMN uploaded is recognised by its external id, and one the person saved or dismissed is remembered by its Strava id. The
/// answer is cached for ten minutes so opening Today does not ask Strava every time.
@MainActor
enum StravaDetector {
    private static var cached: [StravaActivitySummary] = []
    private static var fetchedAt: Date?
    private static let cacheSeconds: TimeInterval = 600

    static func suggestion(repo: Repository) async -> AutoWorkoutSuggestion? {
        guard StravaExperiment.isEnabled, StravaExperiment.isAutoDetectEnabled, StravaTokenStore.isConnected,
              let credentials = StravaCredentials.current, let store = await repo.storeHandle() else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        if fetchedAt.map({ Date().timeIntervalSince($0) > cacheSeconds }) ?? true {
            // The time is stamped before the call, so a failure (offline, rate limit) is not retried on every refresh.
            fetchedAt = Date()
            if let list = try? await StravaAPIClient(credentials: credentials).recentActivities(after: now - 2 * 86_400, before: now + 86_400) { cached = list }
        }
        let existing = await repo.workoutRows(days: 4)
        let hrIds = Repository.workoutHrDeviceIds(source: "manual", activeStrapId: repo.deviceId, importedIds: repo.importedReadIds)
        var best: AutoWorkoutSuggestion?
        for activity in cached {
            guard case .candidate(let a, let startTs, let endTs, let avg, let peak) = await StravaImporter.judge(activity, now: now, existing: existing, hrIds: hrIds, store: store, honourHandled: true) else { continue }
            let w = DetectedWorkout(startSec: startTs, endSec: endTs, avgBpm: avg, peakBpm: peak, durationMin: max(1, (endTs - startTs) / 60))
            let s = AutoWorkoutSuggestion(workout: w, sport: StravaImporter.sport(for: a.sportType), confidence: 1,
                                          stravaId: a.id, stravaName: a.name, distanceM: a.distance.flatMap { $0 > 0 ? $0 : nil })
            if repo.isAutoDetectDismissed(s) { continue }
            if best == nil || s.startSec > best!.startSec { best = s }
        }
        return best
    }

    /// Forget what was fetched, so the next look asks Strava again (after a save or a dismissal the answer is not stale, but a manual import changes what is here).
    static func reset() { fetchedAt = nil }
}
#endif
