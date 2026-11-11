#if os(iOS)
import Foundation
import WhoopStore

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

    static func run(days: Int, repo: Repository, client: StravaAPIClient) async throws -> StravaImportSummary {
        var summary = StravaImportSummary()
        guard let store = await repo.storeHandle() else { throw StravaError.network("no store") }
        let now = Int(Date().timeIntervalSince1970)
        let remote = try await client.recentActivities(after: now - days * 86_400, before: now + 86_400)
        // A little wider than the window: a workout that started before it can still overlap one at its edge.
        var existing = await repo.workoutRows(days: days + 2)
        let hrIds = Repository.workoutHrDeviceIds(source: "manual", activeStrapId: repo.deviceId, importedIds: repo.importedReadIds)

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        for activity in remote.sorted(by: { ($0.startDate ?? "") < ($1.startDate ?? "") }) {
            if let external = activity.externalId, external.hasPrefix("noop-") { summary.alreadyHere += 1; continue }
            guard let startText = activity.startDate, let start = parser.date(from: startText),
                  let elapsed = activity.elapsedTime, elapsed > 0 else { summary.skipped += 1; continue }
            let startTs = Int(start.timeIntervalSince1970), endTs = startTs + elapsed
            guard endTs <= now else { summary.skipped += 1; continue }
            if existing.contains(where: { $0.startTs < endTs && $0.endTs > startTs }) { summary.alreadyHere += 1; continue }

            let stats = try? await store.hrWindowStats(primaryId: hrIds[0], secondaryId: hrIds.count > 1 ? hrIds[1] : hrIds[0], from: startTs, to: endTs)
            guard let stats, stats.n >= minSamples else { summary.noHeartRate += 1; continue }

            let distance = activity.distance.flatMap { $0 > 0 ? $0 : nil }
            guard let built = WorkoutSource.buildManualRowFromSpan(start: start, end: Date(timeIntervalSince1970: TimeInterval(endTs)), sport: sport(for: activity.sportType),
                                                                   avgHr: nil, energyKcal: nil, distanceM: distance) else { summary.skipped += 1; continue }
            let title = (activity.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let row = WorkoutRow(startTs: built.startTs, endTs: built.endTs, sport: built.sport, source: built.source, durationS: built.durationS,
                                 energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: built.distanceM, zonesJSON: nil,
                                 notes: title.isEmpty ? "Strava" : "Strava · " + title, steps: nil)
            await repo.saveManualWorkout(row)
            existing.append(row)
            summary.added += 1
        }
        if summary.added > 0 { await repo.refresh() }
        return summary
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
#endif
