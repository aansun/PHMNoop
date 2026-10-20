#if os(iOS)
import SwiftUI
import WhoopStore

/// One past session of an exercise, with the sets that were logged for it.
struct NunaExerciseSession: Identifiable {
    let id: String
    let startTs: Int
    let program: String?
    let sets: [LiftSetRow]

    var working: [LiftSetRow] { sets.filter { !$0.isWarmup } }
    var heaviest: Double? { working.compactMap(\.weightKg).max() }
    var volume: Double { working.reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) } }
    var oneRepMax: Double? { working.compactMap { NunaExerciseHistory.oneRepMax($0) }.max() }
    var bestSetVolume: Double? { working.compactMap { s in s.weightKg.flatMap { w in s.reps.map { w * Double($0) } } }.max() }
}

enum NunaExerciseHistory {
    /// The Epley estimate, `weight × (1 + reps / 30)`, for a set of 1 to 12 reps with a weight; a heavier count of reps says little about a max.
    static func oneRepMax(_ s: LiftSetRow) -> Double? {
        guard let w = s.weightKg, w > 0, let r = s.reps, (1...12).contains(r) else { return nil }
        return r == 1 ? w : w * (1 + Double(r) / 30)
    }

    /// The records of an exercise over every session logged: the best of each, and the session it was set in.
    struct Records {
        var heaviest: Double?, oneRepMax: Double?, bestSetVolume: Double?, bestSessionVolume: Double?, mostReps: Int?
    }

    /// For each number of reps you have done, the heaviest weight you did it with, fewest reps first.
    static func setRecords(_ sessions: [NunaExerciseSession]) -> [(reps: Int, kg: Double)] {
        var best: [Int: Double] = [:]
        for s in sessions { for set in s.working { if let w = set.weightKg, w > 0, let r = set.reps, r > 0 { best[r] = max(best[r] ?? 0, w) } } }
        return best.keys.sorted().map { (reps: $0, kg: best[$0] ?? 0) }
    }

    /// Which sets were a record when they were done: a heavier weight than any set before it, or a higher estimated one rep max. Walks the
    /// sessions oldest first, so a later session never takes a record from an earlier one. Keyed by set id, with the words to show.
    static func records(inSets sessions: [NunaExerciseSession]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        var bestWeight = 0.0, bestMax = 0.0
        for s in sessions.sorted(by: { $0.startTs < $1.startTs }) {
            for set in s.sets where !set.isWarmup {
                var labels: [String] = []
                if let w = set.weightKg, w > bestWeight { if bestWeight > 0 { labels.append(String(localized: "Weight")) }; bestWeight = w }
                if let m = oneRepMax(set), m > bestMax { if bestMax > 0 { labels.append("1RM") }; bestMax = m }
                if !labels.isEmpty { out[set.id] = labels }
            }
        }
        return out
    }

    static func records(_ sessions: [NunaExerciseSession]) -> Records {
        var r = Records()
        for s in sessions {
            if let h = s.heaviest { r.heaviest = max(r.heaviest ?? 0, h) }
            if let o = s.oneRepMax { r.oneRepMax = max(r.oneRepMax ?? 0, o) }
            if let b = s.bestSetVolume { r.bestSetVolume = max(r.bestSetVolume ?? 0, b) }
            if s.volume > 0 { r.bestSessionVolume = max(r.bestSessionVolume ?? 0, s.volume) }
            if let m = s.working.compactMap(\.reps).max() { r.mostReps = max(r.mostReps ?? 0, m) }
        }
        return r
    }
}

/// Every logged session of one library exercise, newest first. A set belongs to it when its name matches the library entry (the same
/// words, or a known alias), so "Bench press" and "Barbell bench press" are one exercise.
@MainActor
final class NunaExerciseHistoryModel: ObservableObject {
    @Published private(set) var sessions: [NunaExerciseSession] = []
    @Published private(set) var loaded = false

    func load(libraryId: String, repo: Repository) async {
        guard let store = await repo.storeHandle() else { loaded = true; return }
        let now = Int(Date().timeIntervalSince1970)
        let all = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: 0, toTs: now + 86_400)) ?? [])
            .filter { $0.endTs != nil }.sorted { $0.startTs > $1.startTs }
        var out: [NunaExerciseSession] = []
        for s in all {
            let sets = ((try? await store.liftSets(sessionId: s.id)) ?? [])
                .filter { NunaExerciseLibrary.match($0.exercise)?.id == libraryId }.sorted { $0.ord < $1.ord }
            if !sets.isEmpty { out.append(NunaExerciseSession(id: s.id, startTs: s.startTs, program: s.programName, sets: sets)) }
        }
        sessions = out; loaded = true
    }
}
#endif

#if os(iOS)
/// The note pinned to an exercise, by library id. It lives on this iPhone, beside the exercise's own history.
enum NunaExerciseNotes {
    private static let key = "nuna.gym.exerciseNotes"
    private static var all: [String: String] { (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:] }

    static func note(for libraryId: String) -> String { all[libraryId] ?? "" }

    static func set(_ text: String, for libraryId: String) {
        var a = all
        let t = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        if t.isEmpty { a.removeValue(forKey: libraryId) } else { a[libraryId] = t }
        UserDefaults.standard.set(a, forKey: key)
    }

    /// The pinned note of the library exercise a logged name stands for, or "".
    static func note(forName name: String) -> String { NunaExerciseLibrary.match(name).map { note(for: $0.id) } ?? "" }
}
#endif
