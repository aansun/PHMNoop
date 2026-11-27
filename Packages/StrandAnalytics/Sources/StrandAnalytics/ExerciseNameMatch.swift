import Foundation

/// Whether a library exercise can stand in for a name someone wrote. Words alone are not enough: "Dumbbell Triceps Extension" shares most of
/// its words with a cable exercise and with a decline one, and either would send the person to equipment they did not ask for or do not have.
/// A name is only swapped for another when the equipment it names is the same and the two describe the same variation. Pure.
public enum ExerciseNameMatch {
    public enum Equipment: String, Sendable {
        case barbell, ezBar, dumbbell, cable, machine, smith, kettlebell, bands, bodyweight, medicineBall, exerciseBall
    }

    /// Words of a name: lower case, a plural "s" dropped.
    public static func words(_ name: String) -> [String] {
        name.lowercased().split { !$0.isLetter && !$0.isNumber }.map { w in
            let s = String(w)
            return s.count > 3 && s.hasSuffix("s") && !s.hasSuffix("ss") ? String(s.dropLast()) : s
        }
    }

    /// The equipment a name states; empty when it states none ("Goblet Squat", "Lat Pulldown").
    public static func equipment(inName name: String) -> Set<Equipment> {
        let w = words(name), set = Set(w), joined = " " + w.joined(separator: " ") + " "
        var out: Set<Equipment> = []
        if set.contains("barbell") { out.insert(.barbell) }
        if set.contains("ez") || joined.contains(" e z ") { out.insert(.ezBar) }
        if set.contains("dumbbell") { out.insert(.dumbbell) }
        if set.contains("cable") || set.contains("pulley") { out.insert(.cable) }
        if set.contains("smith") { out.insert(.smith) } else if set.contains("machine") || set.contains("lever") || set.contains("leverage") { out.insert(.machine) }
        if set.contains("kettlebell") { out.insert(.kettlebell) }
        if set.contains("band") { out.insert(.bands) }
        if set.contains("bodyweight") || joined.contains(" body weight ") { out.insert(.bodyweight) }
        if joined.contains(" medicine ball ") { out.insert(.medicineBall) }
        if joined.contains(" exercise ball ") || joined.contains(" swiss ball ") || joined.contains(" stability ball ") { out.insert(.exerciseBall) }
        return out
    }

    /// The library's own word for what an exercise is done with, as one of the above; nil for "other" and for none recorded.
    public static func equipment(libraryValue: String?) -> Equipment? {
        switch libraryValue {
        case "barbell": return .barbell
        case "e-z curl bar": return .ezBar
        case "dumbbell": return .dumbbell
        case "cable": return .cable
        case "machine": return .machine
        case "kettlebells": return .kettlebell
        case "bands": return .bands
        case "body only": return .bodyweight
        case "medicine ball": return .medicineBall
        case "exercise ball": return .exerciseBall
        default: return nil
        }
    }

    /// Whether a library entry uses the equipment the asked name states. A name that states none accepts any entry, except a body-weight one whose
    /// own name calls for a tool ("Push-Up off of a Dumbbell"): that is not the plain exercise.
    public static func sameEquipment(asked: String, entryName: String, entryEquipment: String?) -> Bool {
        let wanted = equipment(inName: asked)
        guard !wanted.isEmpty else {
            return equipment(libraryValue: entryEquipment) != .bodyweight || equipment(inName: entryName).subtracting([.bodyweight]).isEmpty
        }
        var has = equipment(inName: entryName)
        if let own = equipment(libraryValue: entryEquipment) {
            // The library files a Smith machine exercise under "machine"; its name is what says which.
            if !(own == .machine && has.contains(.smith)) { has.insert(own) }
        }
        guard !has.isEmpty else { return false }
        return has == wanted
    }

    /// Whether an entry's recorded equipment is plainly not what the asked name states: for names the library already claims (an alias), where
    /// an entry with nothing recorded is left alone.
    public static func contradicts(asked: String, entryEquipment: String?) -> Bool {
        let wanted = equipment(inName: asked)
        guard !wanted.isEmpty, let own = equipment(libraryValue: entryEquipment) else { return false }
        return !wanted.contains(own) && !(own == .machine && wanted.contains(.smith))
    }

    /// Whether an entry needs equipment outside what the person has. An entry with nothing recorded, or body weight, needs none.
    public static func needsOther(entryEquipment: String?, than allowed: Set<Equipment>) -> Bool {
        guard let own = equipment(libraryValue: entryEquipment), own != .bodyweight else { return false }
        return !allowed.contains(own)
    }

    /// Words that make a different exercise of the same movement. "Single" and "one" say the same thing.
    private static let variations: Set<String> = ["incline", "decline", "one", "reverse", "alternate", "alternating", "close", "wide", "rear", "front", "behind",
                                                  "overhead", "stiff", "legged", "sumo", "twist", "preacher", "concentration", "bent", "upright", "romanian",
                                                  "bulgarian", "split", "hack", "sissy", "pistol", "kneeling", "prone", "lying", "cross", "high", "low", "deficit", "pause"]

    public static func variation(of name: String) -> Set<String> {
        Set(words(name).map { $0 == "single" ? "one" : ($0 == "alternating" ? "alternate" : $0) }.filter(variations.contains))
    }

    public static func sameVariation(asked: String, entryName: String) -> Bool { variation(of: asked) == variation(of: entryName) }
}
