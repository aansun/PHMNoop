#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// A pushable handle for one saved workout (WorkoutRow itself is not Hashable).
struct NunaWorkoutKey: Hashable {
    let startTs: Int
    let sport: String
    let source: String
}

enum NunaWorkoutRoute: Hashable {
    case start(String?)
    case summary(NunaWorkoutKey)
    case history, calendar
    case load, loadCardio, loadMuscle
    case autoDetect
    case settings
    case gym
    case program(String)
    case programImport
    case gymSession(String)
}

enum NunaWorkoutKind {
    /// Strength work: lifting sessions and anything the catalogue names as strength training.
    static func isStrengthName(_ sport: String) -> Bool {
        let s = sport.lowercased()
        return s.contains("strength") || s.contains("lift") || s.contains("weight") || s.contains("gym") || s.contains("crossfit") || s.contains("bodybuilding")
    }

    static func isStrength(_ r: WorkoutRow) -> Bool {
        if WorkoutSource.classify(r.source) == .lifting { return true }
        let s = r.sport.lowercased()
        return s.contains("strength") || s.contains("lift") || s.contains("weight") || s.contains("gym") || s.contains("crossfit")
    }
}

/// Everything the Latihan screens read: saved workouts, daily Effort, lifting sessions. One load, shared by the hub and
/// its sub-screens. Nothing is filled in; a week with no session simply has none.
@MainActor
final class NunaWorkoutsModel: ObservableObject {
    @Published private(set) var rows: [WorkoutRow] = []          // newest first
    @Published private(set) var liftSessions: [LiftSessionRow] = []
    @Published private(set) var liftSets: [String: [LiftSetRow]] = [:]   // by session id
    @Published private(set) var loaded = false

    let todayKey = Repository.localDayKey(Date())
    private let cal = Calendar.current

    func load(repo: Repository) async {
        rows = (await repo.workoutRows()).sorted { $0.startTs > $1.startTs }
        if let store = await repo.storeHandle() {
            let from = Int(Date().addingTimeInterval(-120 * 86_400).timeIntervalSince1970)
            let to = Int(Date().timeIntervalSince1970) + 86_400
            let sessions = (try? await store.liftSessions(deviceId: repo.deviceId, fromTs: from, toTs: to)) ?? []
            var sets: [String: [LiftSetRow]] = [:]
            for s in sessions { sets[s.id] = (try? await store.liftSets(sessionId: s.id)) ?? [] }
            liftSessions = sessions; liftSets = sets
        }
        loaded = true
    }

    func key(_ r: WorkoutRow) -> NunaWorkoutKey { .init(startTs: r.startTs, sport: r.sport, source: r.source) }
    func row(_ k: NunaWorkoutKey) -> WorkoutRow? { rows.first { $0.startTs == k.startTs && $0.sport == k.sport } }

    func dayKey(_ ts: Int) -> String { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(ts))) }

    /// Workouts that started in the last `days` days (today included), newest first.
    func recent(days: Int, back: Int = 0) -> [WorkoutRow] {
        let end = cal.startOfDay(for: Date()).addingTimeInterval(Double(1 - back) * 86_400)
        let start = end.addingTimeInterval(-Double(days) * 86_400)
        return rows.filter { Double($0.startTs) >= start.timeIntervalSince1970 && Double($0.startTs) < end.timeIntervalSince1970 }
    }

    func effort(_ rs: [WorkoutRow]) -> Double { rs.compactMap(\.strain).reduce(0, +) }
    func minutes(_ rs: [WorkoutRow]) -> Double { rs.reduce(0) { $0 + ($1.durationS ?? Double($1.endTs - $1.startTs)) } / 60 }

    /// Total workout Effort in each of the last `weeks` 7-day blocks, oldest first (the last block ends today).
    func weeklyEffort(weeks: Int) -> [Double] {
        (0..<weeks).reversed().map { w in effort(recent(days: 7, back: w * 7)) }
    }

    /// Volume (kg) lifted in each of the last `weeks` 7-day blocks, oldest first.
    func weeklyVolume(weeks: Int) -> [Double] {
        let now = Date()
        return (0..<weeks).reversed().map { w in
            let hi = cal.startOfDay(for: now).addingTimeInterval(Double(1 - w * 7) * 86_400).timeIntervalSince1970
            let lo = hi - 7 * 86_400
            return liftSessions.filter { Double($0.startTs) >= lo && Double($0.startTs) < hi }
                .reduce(0) { $0 + (LiftMetrics.volumeLoadKg(liftSets[$1.id] ?? []) ?? 0) }
        }
    }

    func sportTitle(_ r: WorkoutRow) -> String { WorkoutSource.displaySport(r.sport) }
}

// MARK: - Shared formatting

enum NunaWorkoutFormat {
    static func duration(_ seconds: Double?) -> String {
        guard let s = seconds, s > 0 else { return "–" }
        let m = Int((s / 60).rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min"
    }

    static func distance(_ meters: Double?, _ system: UnitSystem) -> String? {
        guard let m = meters, m > 50 else { return nil }
        return system == .imperial ? String(format: "%.1f mi", locale: AppLanguage.activeLocale, m / 1609.344)
                                   : String(format: "%.1f km", locale: AppLanguage.activeLocale, m / 1000)
    }

    /// Minutes:seconds per km (or per mile).
    static func pace(distanceM: Double?, seconds: Double?, _ system: UnitSystem) -> String? {
        guard let d = distanceM, d > 200, let s = seconds, s > 0 else { return nil }
        let per = system == .imperial ? 1609.344 : 1000
        let sec = Int((s / (d / per)).rounded())
        return String(format: "%d:%02d /%@", sec / 60, sec % 60, system == .imperial ? "mi" : "km")
    }

    static func day(_ ts: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ts)), cal = Calendar.current
        if cal.isDateInToday(d) { return String(localized: "Today") }
        if cal.isDateInYesterday(d) { return String(localized: "Yesterday") }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; // An older year needs the year as well, now that the history reaches back five years.
        f.setLocalizedDateFormatFromTemplate(cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "EEE d MMM" : "d MMM yyyy"); return f.string(from: d)
    }

    static func clock(_ ts: Int) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("jj:mm")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}

/// One tappable session row used by the hub, history and calendar.
struct NunaWorkoutRow: View {
    let row: WorkoutRow
    let system: UnitSystem
    let effortScale: EffortScale

    var body: some View {
        let subtitle = [NunaWorkoutFormat.day(row.startTs), NunaWorkoutFormat.distance(row.distanceM, system), NunaWorkoutFormat.duration(row.durationS)]
            .compactMap { $0 }.joined(separator: " · ")
        NunaListRow(LocalizedStringKey(WorkoutSource.displaySport(row.sport)), subtitle: LocalizedStringKey(subtitle),
                    systemImage: NunaWorkoutKind.isStrength(row) ? "dumbbell" : sportSymbol(row.sport)) {
            if let s = row.strain { NunaChip(verbatim: "+" + UnitFormatter.effortDisplay(s, scale: effortScale), color: NunaPalette.effortText) }
        }
    }
}
#endif
