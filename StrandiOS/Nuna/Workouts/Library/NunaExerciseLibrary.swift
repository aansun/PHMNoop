#if os(iOS)
import SwiftUI
import UIKit
import MuscleMap
import WhoopStore

/// One exercise of the bundled library: its muscles, equipment and instructions, and two photos (the start and the end of the
/// movement). Everything is read from the app bundle, so it works offline and needs no server.
///
/// The data and photos are from free-exercise-db (https://github.com/yuhonas/free-exercise-db, The Unlicense, public domain).
/// `Tools/build-exercise-library.py` builds the bundle; today it holds a sample of the library.
struct NunaLibraryExercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let level: String?
    let mechanic: String?
    let force: String?
    let equipment: String?
    let category: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let frames: [String]
    let aliases: [String]

    /// The muscles of the body map for the primary and the secondary ones.
    var primaryMap: [Muscle] { Self.map(primaryMuscles) }
    var secondaryMap: [Muscle] { Self.map(secondaryMuscles).filter { !primaryMap.contains($0) } }

    /// free-exercise-db names its muscles in its own words; the body map has its own set.
    static func map(_ names: [String]) -> [Muscle] {
        var out: [Muscle] = []
        for n in names {
            let m: Muscle?
            switch n {
            case "abdominals": m = .abs
            case "abductors": m = .gluteal
            case "adductors": m = .adductors
            case "biceps": m = .biceps
            case "calves": m = .calves
            case "chest": m = .chest
            case "forearms": m = .forearm
            case "glutes": m = .gluteal
            case "hamstrings": m = .hamstring
            case "lats", "middle back": m = .upperBack
            case "lower back": m = .lowerBack
            case "neck": m = .neck
            case "quadriceps": m = .quadriceps
            case "shoulders": m = .deltoids
            case "traps": m = .trapezius
            case "triceps": m = .triceps
            default: m = nil
            }
            if let m, !out.contains(m) { out.append(m) }
        }
        return out
    }

    /// Plain names for display, in the order given.
    static func title(_ muscle: String) -> String {
        switch muscle {
        case "abdominals": return String(localized: "Abs")
        case "abductors": return String(localized: "Abductors")
        case "adductors": return String(localized: "Adductors")
        case "biceps": return String(localized: "Biceps")
        case "calves": return String(localized: "Calves")
        case "chest": return String(localized: "Chest")
        case "forearms": return String(localized: "Forearms")
        case "glutes": return String(localized: "Glutes")
        case "hamstrings": return String(localized: "Hamstrings")
        case "lats": return String(localized: "Lats")
        case "lower back": return String(localized: "Lower back")
        case "middle back": return String(localized: "Middle back")
        case "neck": return String(localized: "Neck")
        case "quadriceps": return String(localized: "Quads")
        case "shoulders": return String(localized: "Shoulders")
        case "traps": return String(localized: "Traps")
        case "triceps": return String(localized: "Triceps")
        default: return muscle.capitalized
        }
    }

    var equipmentTitle: String? {
        guard let e = equipment, !e.isEmpty else { return nil }
        switch e {
        case "body only": return String(localized: "Body weight")
        case "barbell": return String(localized: "Barbell")
        case "dumbbell": return String(localized: "Dumbbell")
        case "cable": return String(localized: "Cable")
        case "machine": return String(localized: "Machine")
        case "kettlebells": return String(localized: "Kettlebell")
        case "bands": return String(localized: "Bands")
        default: return e.capitalized
        }
    }

    var levelTitle: String? {
        switch level {
        case "beginner": return String(localized: "Beginner")
        case "intermediate": return String(localized: "Intermediate")
        case "expert": return String(localized: "Expert")
        default: return nil
        }
    }
}

enum NunaExerciseLibrary {
    private static let folder = "ExerciseLibrary"

    /// The bundle build puts the files at the top level; a folder reference would keep them under `ExerciseLibrary`. Both are read.
    private static func url(_ base: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: base, withExtension: ext) ?? Bundle.main.url(forResource: base, withExtension: ext, subdirectory: folder)
    }

    /// Every exercise, by name.
    static let all: [NunaLibraryExercise] = {
        guard let url = url("library", "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([NunaLibraryExercise].self, from: data) else { return [] }
        return list
    }()

    private static let byId: [String: NunaLibraryExercise] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    static func exercise(id: String) -> NunaLibraryExercise? { byId[id] }

    // MARK: Matching a logged name to the library

    /// The words of a name, lower case, with a plural "s" dropped ("Pull-ups", "pull up" and "Pullups" all read "pull up"/"pullup"), so
    /// spelling and punctuation do not matter. "Bench Press (Barbell)" and "Barbell Bench Press" have the same words.
    static func words(_ name: String) -> [String] {
        name.lowercased().split { !$0.isLetter && !$0.isNumber }.map { w in
            let s = String(w)
            return s.count > 3 && s.hasSuffix("s") && !s.hasSuffix("ss") ? String(s.dropLast()) : s
        }
    }

    static func normalized(_ name: String) -> String { words(name).joined(separator: " ") }
    private static func wordSet(_ name: String) -> String { words(name).sorted().joined(separator: " ") }

    private static let ordered: [String: NunaLibraryExercise] = index(by: normalized)
    private static let unordered: [String: NunaLibraryExercise] = index(by: wordSet)

    /// Aliases first, so the name a person actually uses wins over a near-identical library name.
    private static func index(by key: (String) -> String) -> [String: NunaLibraryExercise] {
        var out: [String: NunaLibraryExercise] = [:]
        for e in all { for a in e.aliases { let k = key(a); if out[k] == nil { out[k] = e } } }
        for e in all { let k = key(e.name); if out[k] == nil { out[k] = e } }
        return out
    }

    /// The library entry for an exercise logged under a person's own name: the same words, or the same words in another order, or a
    /// known alias. Nil when the library has nothing by that name.
    static func match(_ name: String) -> NunaLibraryExercise? {
        ordered[normalized(name)] ?? unordered[wordSet(name)]
    }

    // MARK: Searching

    /// Exercises whose name (or alias) has every word of the query, the ones that start with it first. Empty query: everything.
    static func search(_ query: String, muscles: Set<String> = [], limit: Int = 2000) -> [NunaLibraryExercise] {
        let q = words(query)
        var pool = all
        if !muscles.isEmpty { pool = pool.filter { e in e.primaryMuscles.contains { muscles.contains($0) } } }
        guard !q.isEmpty else { return Array(pool.prefix(limit)) }
        var starts: [NunaLibraryExercise] = [], contains: [NunaLibraryExercise] = []
        for e in pool {
            let names = [e.name] + e.aliases
            let hit = names.contains { n in let w = words(n); return q.allSatisfy { qw in w.contains { $0.hasPrefix(qw) } } }
            guard hit else { continue }
            if names.contains(where: { words($0).first.map { f in f.hasPrefix(q[0]) } ?? false }) { starts.append(e) } else { contains.append(e) }
        }
        return Array((starts + contains).prefix(limit))
    }

    // MARK: Photos

    private static let cache = NSCache<NSString, UIImage>()
    private static let thumbs = NSCache<NSString, UIImage>()

    static func image(_ file: String) -> UIImage? {
        if let hit = cache.object(forKey: file as NSString) { return hit }
        let base = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
        guard let url = url(base, ext), let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: file as NSString)
        return img
    }

    /// A small version of the first photo for lists, drawn once.
    static func thumbnail(_ e: NunaLibraryExercise) -> UIImage? {
        guard let f = e.frames.first else { return nil }
        if let hit = thumbs.object(forKey: f as NSString) { return hit }
        guard let img = image(f) else { return nil }
        let t = img.preparingThumbnail(of: CGSize(width: 180, height: 180 * img.size.height / max(img.size.width, 1))) ?? img
        thumbs.setObject(t, forKey: f as NSString)
        return t
    }
}

extension NunaLibraryExercise {
    /// The app's own muscle for the first main muscle, for an exercise added from the library. A shoulder is told apart by the name
    /// (a press works the front, a fly or a face pull the rear, a raise the side); that is a guess, and the muscle map treats the
    /// three heads as one part of the body anyway.
    var liftPrimary: LiftMuscle? { primaryMuscles.first.flatMap { lift($0) } }

    var liftSecondary: [LiftMuscle] {
        var out: [LiftMuscle] = []
        for m in secondaryMuscles { if let l = lift(m), l != liftPrimary, !out.contains(l) { out.append(l) } }
        return out
    }

    private func lift(_ muscle: String) -> LiftMuscle? {
        let n = name.lowercased()
        switch muscle {
        case "abdominals": return n.contains("twist") || n.contains("oblique") || n.contains("side bend") ? .obliques : .abs
        case "abductors": return .abductors
        case "adductors": return .adductors
        case "biceps": return .biceps
        case "calves": return .calves
        case "chest": return .chest
        case "forearms": return .forearms
        case "glutes": return .glutes
        case "hamstrings": return .hamstrings
        case "lats": return .lats
        case "lower back": return .lowerBack
        case "middle back": return .upperBack
        case "neck": return .neck
        case "quadriceps": return .quads
        case "shoulders":
            if n.contains("rear") || n.contains("reverse") || n.contains("face pull") || n.contains("bent over") { return .rearDelts }
            if n.contains("lateral") || n.contains("side raise") || n.contains("upright") { return .sideDelts }
            return .frontDelts
        case "traps": return .traps
        case "triceps": return .triceps
        default: return nil
        }
    }
}

extension LiftMuscle {
    /// The part of the body map this muscle is drawn on.
    var bodyMap: Muscle {
        switch self {
        case .chest: return .chest
        case .frontDelts, .sideDelts, .rearDelts: return .deltoids
        case .triceps: return .triceps
        case .lats, .upperBack: return .upperBack
        case .traps: return .trapezius
        case .biceps: return .biceps
        case .forearms: return .forearm
        case .quads: return .quadriceps
        case .hamstrings: return .hamstring
        case .glutes, .abductors: return .gluteal
        case .adductors: return .adductors
        case .calves: return .calves
        case .abs: return .abs
        case .obliques: return .obliques
        case .lowerBack: return .lowerBack
        case .neck: return .neck
        }
    }
}
#endif
