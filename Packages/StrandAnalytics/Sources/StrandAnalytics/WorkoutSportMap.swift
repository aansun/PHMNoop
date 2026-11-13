import Foundation

// WorkoutSportMap.swift — the name a person gave a workout, read as the coarse class the shape classifier knows.
//
// The classifier (`WorkoutTypeClassifier`) knows walk / run / strength / cycle / ski and `other`. The workouts a person saves carry a sport NAME
// ("Treadmill run", "Indoor cycle", "Hiking"). To compare the two, or one day to learn from them, a name has to become a class.
//
// Pure and deterministic. It is deliberately strict:
//   • A generic placeholder ("Workout", "Other", "detected") is not a label at all: `nil`.
//   • A name that matches exactly one of the five classes gives that class.
//   • A name that names two ("Run and bike") is ambiguous: `nil`, not a guess.
//   • Any other real sport ("Yoga", "Boxing", "Tennis") is `.other`: a true label of "none of the five".
//   • Matching is on whole words, never on a prefix, so "Bikram yoga" is not cycling and "Basketball" is not skiing.
public enum WorkoutSportMap {

    /// Names that say nothing about the sport. A saved row with one of these has no usable label.
    public static let genericNames: Set<String> = ["", "workout", "other", "detected", "activity", "exercise", "training", "session"]

    private static let walkWords: Set<String> = ["walk", "walking", "hike", "hiking", "ruck", "rucking", "trekking"]
    private static let runWords: Set<String> = ["run", "running", "jog", "jogging"]
    private static let cycleWords: Set<String> = ["cycling", "cycle", "bike", "biking", "spinning", "spin"]
    private static let strengthWords: Set<String> = ["strength", "weightlifting", "powerlifting", "bodybuilding", "weights", "lifting"]
    private static let skiWords: Set<String> = ["ski", "skiing", "snowboard", "snowboarding"]
    /// Cross-country and Nordic skiing are steady and gait-like, nothing like the stop-start of downhill the ski prototype describes, so they are `.other`.
    private static let notDownhillWords: Set<String> = ["cross", "country", "nordic", "touring"]

    /// The whole lowercase words of a name, split on anything that is not a letter or a digit.
    static func words(_ sport: String) -> [String] {
        sport.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// True when the name carries no sport at all.
    public static func isGeneric(_ sport: String) -> Bool {
        genericNames.contains(sport.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// The class a saved sport name stands for, or nil when it cannot be used as a label (generic, or ambiguous between classes).
    public static func coarseClass(forSport sport: String) -> CoarseWorkoutClass? {
        if isGeneric(sport) { return nil }
        let w = Set(words(sport))
        var hits: Set<CoarseWorkoutClass> = []
        if !w.isDisjoint(with: walkWords) { hits.insert(.walk) }
        if !w.isDisjoint(with: runWords) { hits.insert(.run) }
        if !w.isDisjoint(with: cycleWords) { hits.insert(.cycle) }
        if !w.isDisjoint(with: strengthWords) { hits.insert(.strength) }
        if !w.isDisjoint(with: skiWords), w.isDisjoint(with: notDownhillWords) { hits.insert(.ski) }
        switch hits.count {
        case 0: return .other
        case 1: return hits.first
        default: return nil
        }
    }
}
