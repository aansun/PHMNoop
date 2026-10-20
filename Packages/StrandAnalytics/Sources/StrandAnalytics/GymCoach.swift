import Foundation

// GymCoach.swift - what Anya says on the Gym tab: when the wearer usually trains, how the last 30 days went, whether today's body can
// take the usual load, and which exercises to put in a session when there is no program for the day.
//
// Pure and DB-free so the rules run in tests against fixed figures. It never changes a program: it only says how a session that starts
// today could be lighter, and the app applies that to the session's own copy of the plan. Rules of thumb for a healthy adult, not
// medical advice.

public enum GymCoach {

    // MARK: Habit

    /// One finished gym session, reduced to what the habit reads.
    public struct Session: Equatable, Sendable {
        public let startTs: Int
        public let programId: String?
        public let volumeKg: Double
        public let workingSets: Int
        public init(startTs: Int, programId: String?, volumeKg: Double, workingSets: Int) {
            self.startTs = startTs; self.programId = programId; self.volumeKg = volumeKg; self.workingSets = workingSets
        }
    }

    public struct Habit: Equatable, Sendable {
        /// Weekdays (1 = Sunday ... 7 = Saturday) the wearer trained on at least twice in the last eight weeks.
        public let usualWeekdays: [Int]
        /// The usual hour of day (0...23) on those days.
        public let usualHour: Int?
        public let sessionsPerWeek: Double
        public let isUsualDay: Bool
        public let trainedToday: Bool
        public let daysSinceLast: Int?
    }

    public static let habitWindowDays = 56
    public static let minSessionsForHabit = 4

    /// Nil under four sessions in the last eight weeks: a habit read from two or three sessions would be a guess.
    public static func habit(sessions: [Session], now: Date, calendar: Calendar = .current) -> Habit? {
        let from = now.addingTimeInterval(-Double(habitWindowDays) * 86_400)
        let recent = sessions.filter { Double($0.startTs) >= from.timeIntervalSince1970 && Double($0.startTs) <= now.timeIntervalSince1970 + 86_400 }
        guard recent.count >= minSessionsForHabit else { return nil }
        var perDay: [Int: Int] = [:]
        for s in recent { perDay[calendar.component(.weekday, from: Date(timeIntervalSince1970: TimeInterval(s.startTs))), default: 0] += 1 }
        let usual = perDay.filter { $0.value >= 2 }.keys.sorted()
        let pool = recent.filter { usual.isEmpty || usual.contains(calendar.component(.weekday, from: Date(timeIntervalSince1970: TimeInterval($0.startTs)))) }
        let hours = pool.map { calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval($0.startTs))) }.sorted()
        let today = calendar.component(.weekday, from: now)
        let startOfToday = calendar.startOfDay(for: now).timeIntervalSince1970
        let last = recent.map(\.startTs).max()
        return Habit(usualWeekdays: usual, usualHour: hours.isEmpty ? nil : hours[hours.count / 2],
                     sessionsPerWeek: Double(recent.count) / (Double(habitWindowDays) / 7),
                     isUsualDay: usual.contains(today),
                     trainedToday: recent.contains { Double($0.startTs) >= startOfToday },
                     daysSinceLast: last.map { ts in
                        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(ts)))
                        return max(0, calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day ?? 0)
                     })
    }

    // MARK: The last 30 days

    public struct Trend: Equatable, Sendable {
        public let sessions: Int
        /// Volume of the last 15 days against the 15 before, in percent; nil without a session in both halves.
        public let volumeChangePct: Double?
    }

    public static func trend(sessions: [Session], now: Date) -> Trend? {
        let t = now.timeIntervalSince1970
        let last30 = sessions.filter { Double($0.startTs) > t - 30 * 86_400 && Double($0.startTs) <= t + 86_400 }
        guard !last30.isEmpty else { return nil }
        let recent = last30.filter { Double($0.startTs) > t - 15 * 86_400 }
        let before = last30.filter { Double($0.startTs) <= t - 15 * 86_400 }
        var change: Double?
        let a = recent.map(\.volumeKg).reduce(0, +), b = before.map(\.volumeKg).reduce(0, +)
        if !recent.isEmpty, !before.isEmpty, b > 0 { change = (a - b) / b * 100 }
        return Trend(sessions: last30.count, volumeChangePct: change)
    }

    // MARK: Which program is due

    /// The program the wearer usually runs on this weekday; with none, the one used in the last eight weeks that has waited longest.
    public static func scheduledProgram(sessions: [Session], now: Date, calendar: Calendar = .current) -> String? {
        let from = now.timeIntervalSince1970 - Double(habitWindowDays) * 86_400
        let recent = sessions.filter { Double($0.startTs) >= from && $0.programId != nil }
        guard !recent.isEmpty else { return nil }
        let today = calendar.component(.weekday, from: now)
        var sameDay: [String: Int] = [:]
        for s in recent where calendar.component(.weekday, from: Date(timeIntervalSince1970: TimeInterval(s.startTs))) == today { sameDay[s.programId!, default: 0] += 1 }
        if let best = sameDay.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) { return best.key }
        var lastRun: [String: Int] = [:]
        for s in recent { lastRun[s.programId!] = max(lastRun[s.programId!] ?? 0, s.startTs) }
        return lastRun.min { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }?.key
    }

    // MARK: Today's body

    public enum Condition: Int, Equatable, Sendable { case good, fair, poor }

    /// Charge (0...100) and the readiness word. Nil when neither is known: no verdict is guessed.
    public static func condition(charge: Double?, readiness: ReadinessEngine.Level?) -> Condition? {
        if charge == nil, readiness == nil || readiness == .insufficient { return nil }
        if let c = charge, c < 34 { return .poor }
        if readiness == .rundown { return .poor }
        if let c = charge, c < 50 { return .fair }
        if readiness == .strained { return .fair }
        return .good
    }

    /// How much lighter a session is for one day: weight, reps (or hold time) and nothing else. The number of sets is never touched, so
    /// the program does not read the day as a change to itself.
    public struct LoadAdjust: Equatable, Sendable {
        public let weightFactor: Double
        public let repsDelta: Int
        public let timeFactor: Double
        public var isNeutral: Bool { weightFactor == 1 && repsDelta == 0 && timeFactor == 1 }
        public var weightCutPct: Int { Int(((1 - weightFactor) * 100).rounded()) }
    }

    public static func adjust(for condition: Condition) -> LoadAdjust {
        switch condition {
        case .good: return LoadAdjust(weightFactor: 1, repsDelta: 0, timeFactor: 1)
        case .fair: return LoadAdjust(weightFactor: 0.9, repsDelta: -1, timeFactor: 0.9)
        case .poor: return LoadAdjust(weightFactor: 0.8, repsDelta: -2, timeFactor: 0.8)
        }
    }

    /// Nearest 1.25 kg, the smallest step of the usual plates; never below zero.
    public static func adjustedWeight(_ kg: Double, _ a: LoadAdjust) -> Double {
        guard a.weightFactor != 1 else { return kg }
        return max(0, ((kg * a.weightFactor) / 1.25).rounded() * 1.25)
    }

    /// Reps drop by `repsDelta` but never under 60% of the plan, so a set of 5 is not cut to 3.
    public static func adjustedReps(_ reps: Int, _ a: LoadAdjust) -> Int {
        guard a.repsDelta != 0 else { return reps }
        return max(1, max(Int((Double(reps) * 0.6).rounded(.up)), reps + a.repsDelta))
    }

    /// A hold in seconds, to the nearest five.
    public static func adjustedSeconds(_ seconds: Int, _ a: LoadAdjust) -> Int {
        guard a.timeFactor != 1 else { return seconds }
        return max(5, Int((Double(seconds) * a.timeFactor / 5).rounded()) * 5)
    }

    // MARK: A session with no program behind it

    public struct Candidate: Equatable, Sendable {
        public let name: String
        /// The muscle group it counts under ("legs", "chest", "back", "shoulders", "arms", "core").
        public let group: String
        public let sets: Int
        public init(name: String, group: String, sets: Int) { self.name = name; self.group = group; self.sets = sets }
    }

    /// Exercises the wearer already does, for the muscle groups that are most rested. `fatigue` is 0 (rested) to 1 (still loaded) per group
    /// and `timesDone` how often each exercise appeared in the last 30 days; `maxExercises` is split two to a group at most.
    public static func pick(candidates: [Candidate], fatigue: [String: Double], timesDone: [String: Int], maxExercises: Int = 5) -> [Candidate] {
        let groups = Dictionary(grouping: candidates, by: \.group)
        let ordered = groups.keys.sorted { a, b in
            let fa = fatigue[a] ?? 0, fb = fatigue[b] ?? 0
            return fa == fb ? a < b : fa < fb
        }
        var out: [Candidate] = []
        for g in ordered where (fatigue[g] ?? 0) < 0.55 {
            let best = (groups[g] ?? []).sorted { (timesDone[$0.name] ?? 0, $1.name) > (timesDone[$1.name] ?? 0, $0.name) }
            for c in best.prefix(2) where out.count < maxExercises { out.append(c) }
            if out.count >= maxExercises { break }
        }
        return out
    }
}
