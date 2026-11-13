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

    // MARK: Strava

    // A workout brought in from Strava is saved under PHMN's own sport name, and PHMN's names are coarser than Strava's: `StravaImporter.sport(for:)`
    // folds AlpineSki, BackcountrySki and NordicSki into one "Skiing", and Handcycle into "Cycling". Read as a name, a cross-country ski would
    // count as downhill. So the original Strava type is kept in the row's notes ("Strava · NordicSki · Evening ski") and read back from there.

    /// Strava's own sport types, the only words accepted as a type in a row's notes. A free-text title that happens to follow "Strava · " is not one.
    static let stravaTypes: Set<String> = [
        "AlpineSki", "BackcountrySki", "Badminton", "Canoeing", "Crossfit", "EBikeRide", "Elliptical", "EMountainBikeRide", "Golf", "GravelRide",
        "Handcycle", "HighIntensityIntervalTraining", "Hike", "IceSkate", "InlineSkate", "Kayaking", "Kitesurf", "MountainBikeRide", "NordicSki",
        "Pickleball", "Pilates", "Racquetball", "Ride", "RockClimbing", "RollerSki", "Rowing", "Run", "Sail", "Skateboard", "Snowboard", "Snowshoe",
        "Soccer", "Squash", "StairStepper", "StandUpPaddling", "Surfing", "Swim", "TableTennis", "Tennis", "TrailRun", "Velomobile", "VirtualRide",
        "VirtualRow", "VirtualRun", "Walk", "WeightTraining", "Wheelchair", "Windsurf", "Workout", "Yoga",
    ]

    private static let stravaPrefix = "Strava"
    private static let stravaSeparator = " · "

    /// The notes of a workout brought in from Strava: "Strava", then its type when it is a known one, then the title when there is one.
    public static func stravaNotes(title: String?, stravaType: String?) -> String {
        var parts = [stravaPrefix]
        if let t = stravaType?.trimmingCharacters(in: .whitespacesAndNewlines), stravaTypes.contains(t) { parts.append(t) }
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { parts.append(title) }
        return parts.joined(separator: stravaSeparator)
    }

    /// True when the notes mark the workout as one brought in from Strava.
    public static func isStravaNotes(_ notes: String?) -> Bool {
        guard let n = notes else { return false }
        return n == stravaPrefix || n.hasPrefix(stravaPrefix + stravaSeparator)
    }

    /// The Strava type kept in the notes, or nil for a row made before it was kept (its second part is then a title) or one that is not from Strava.
    public static func stravaType(fromNotes notes: String?) -> String? {
        guard isStravaNotes(notes), let n = notes else { return nil }
        let parts = n.components(separatedBy: stravaSeparator)
        guard parts.count >= 2, stravaTypes.contains(parts[1]) else { return nil }
        return parts[1]
    }

    /// The class a Strava sport type stands for. nil for the generic ones (Workout, HIIT) and for a type that is not a Strava one.
    public static func coarseClass(forStravaType type: String) -> CoarseWorkoutClass? {
        guard stravaTypes.contains(type) else { return nil }
        switch type {
        case "Run", "VirtualRun", "TrailRun": return .run
        case "Walk", "Hike": return .walk
        case "Ride", "EBikeRide", "GravelRide", "MountainBikeRide", "EMountainBikeRide", "VirtualRide", "Velomobile": return .cycle
        case "WeightTraining": return .strength
        case "AlpineSki", "Snowboard": return .ski
        case "Workout", "HighIntensityIntervalTraining": return nil
        default: return .other
        }
    }

    /// The name PHMN's importer gives a Strava type when that name is LOSSY: it hides what the type says. Used to tell "the importer's own name"
    /// from "a name the person chose".
    static func lossyImporterName(forStravaType type: String) -> String? {
        switch type {
        case "NordicSki", "BackcountrySki": return "Skiing"
        case "Handcycle": return "Cycling"
        default: return nil
        }
    }

    /// The class of a saved workout's sport, using the Strava type when there is one.
    /// The sport name wins when the person has changed it (it then no longer matches what the type implies). The Strava type wins only where the importer's
    /// own name hid it, which is exactly when the name is the importer's and not the person's.
    public static func labelClass(sport: String, stravaType: String?) -> CoarseWorkoutClass? {
        let fromName = coarseClass(forSport: sport)
        guard let type = stravaType, let fromType = coarseClass(forStravaType: type) else { return fromName }
        guard let fromName else { return fromType }
        if fromName == fromType { return fromName }
        if let lossy = lossyImporterName(forStravaType: type),
           sport.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lossy.lowercased() { return fromType }
        return fromName
    }
}
