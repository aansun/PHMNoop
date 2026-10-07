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

    static let all: [NunaLibraryExercise] = {
        guard let url = url("library", "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([NunaLibraryExercise].self, from: data) else { return [] }
        return list
    }()

    static func exercise(id: String) -> NunaLibraryExercise? { all.first { $0.id == id } }

    /// A name reduced to its words, so "Pull-up", "pull up" and "Pull Ups" read the same.
    static func normalized(_ name: String) -> String {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return words.joined(separator: " ")
    }

    private static let index: [String: NunaLibraryExercise] = {
        var out: [String: NunaLibraryExercise] = [:]
        for e in all {
            for n in [e.name] + e.aliases { out[normalized(n)] = out[normalized(n)] ?? e }
        }
        return out
    }()

    /// The library entry for an exercise the person logged under their own name, if one has the same name or a known alias.
    static func match(_ name: String) -> NunaLibraryExercise? { index[normalized(name)] }

    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ file: String) -> UIImage? {
        if let hit = cache.object(forKey: file as NSString) { return hit }
        let base = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
        guard let url = url(base, ext), let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: file as NSString)
        return img
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
