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
