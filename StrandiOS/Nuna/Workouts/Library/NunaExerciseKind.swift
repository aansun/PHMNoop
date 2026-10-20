#if os(iOS)
import Foundation
import WhoopStore

/// How an exercise is logged. A barbell or a machine takes a weight and reps; a push-up or a pull-up only reps (the body is the load); a plank
/// or a stretch a time. Read from the library entry when there is one, and from the words of the name when the exercise is the person's own.
///
/// For a timed exercise the hold, in seconds, is kept in the set's `reps` field. The Lift Log has no field for a duration and adding one
/// would change the stored schema (and the Android twin), so the number is kept where a count would be and every screen that shows a set of
/// a timed exercise reads it as time. Its volume is zero, since there is no weight.
enum NunaExerciseKind: Equatable {
    case weighted, bodyweight, timed

    private static let overridesKey = "nuna.gym.trackWeight"

    /// Exercises whose weight the person asked to track although the body is the usual load (weighted pull-ups, weighted dips).
    static var weightOverrides: Set<String> { Set(UserDefaults.standard.stringArray(forKey: overridesKey) ?? []) }

    static func setTracksWeight(_ on: Bool, for name: String) {
        var s = weightOverrides
        if on { s.insert(name) } else { s.remove(name) }
        UserDefaults.standard.set(Array(s).sorted(), forKey: overridesKey)
    }

    static func of(_ name: String) -> NunaExerciseKind {
        let kind = natural(name)
        return kind == .bodyweight && weightOverrides.contains(name) ? .weighted : kind
    }

    /// The kind without the person's override.
    static func natural(_ name: String) -> NunaExerciseKind {
        let n = name.lowercased()
        let lib = NunaExerciseLibrary.match(name)
        if isTimed(n, lib) { return .timed }
        if let lib {
            if lib.equipment == nil || lib.equipment == "body only" { return .bodyweight }
        }
        let bodyweightWords = ["push-up", "pushup", "push up", "pull-up", "pullup", "pull up", "chin-up", "chinup", "chin up", "dip", "muscle-up",
                               "sit-up", "situp", "crunch", "burpee", "bodyweight", "body weight", "inverted row", "hanging leg raise", "mountain climber",
                               "jumping jack", "leg raise", "glute bridge", "superman", "lunge sprint"]
        if lib == nil || lib?.equipment == "other", bodyweightWords.contains(where: { n.contains($0) }) { return .bodyweight }
        return .weighted
    }

    private static func isTimed(_ n: String, _ lib: NunaLibraryExercise?) -> Bool {
        if lib?.category == "stretching" { return true }
        if n.contains("push up to") || n.contains("push-up to") { return false }
        return ["plank", "wall sit", "isometric", "l-sit", "stretch", "dead hang", " hold", "hollow body"].contains { n.contains($0) }
    }

    var usesWeight: Bool { self == .weighted }

    // MARK: Time

    /// 45 seconds as "00:45".
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "45", "0:45", "00:45" and "1:05" to seconds. A bare number is seconds. Nil for anything else.
    static func seconds(from text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1: return Int(parts[0])
        case 2:
            guard let m = Int(parts[0].isEmpty ? "0" : parts[0]), let s = Int(parts[1].isEmpty ? "0" : parts[1]), s < 60 else { return nil }
            return m * 60 + s
        default: return nil
        }
    }

    // MARK: Showing a set or a target

    /// One set as text: "60 kg × 8", "12 reps" or "00:45".
    func setText(weightKg: Double?, reps: Int?, system: UnitSystem) -> String {
        switch self {
        case .timed: return reps.map(Self.clock) ?? "–"
        case .bodyweight:
            return reps.map { String(localized: "\($0) reps") } ?? "–"
        case .weighted:
            switch (weightKg, reps) {
            case let (w?, r?): return "\(LiftFormat.weight(w, system: system)) × \(r)"
            case let (w?, nil): return LiftFormat.weight(w, system: system)
            case let (nil, r?): return "× \(r)"
            default: return "–"
            }
        }
    }

    /// A program line's target: "3 × 10", or "3 × 00:45" for a hold.
    func targetText(sets: Int?, reps: Int?) -> String? {
        guard let sets else { return nil }
        guard let reps else { return "\(sets)" }
        return self == .timed ? "\(sets) × \(Self.clock(reps))" : "\(sets) × \(reps)"
    }
}
#endif
