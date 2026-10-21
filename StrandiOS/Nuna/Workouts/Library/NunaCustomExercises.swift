#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

/// The exercises a person made up (typed in the picker, or brought in from Hevy) made to look like the ones in the library, so everything the
/// library gives an exercise works for them too: its page with the muscles, the history of every set logged under the name, the records, the
/// how-to video, the picture on a card. Each one is a `NunaLibraryExercise` with no photos, built from the muscle vocabulary the store already
/// keeps (`LiftExerciseRow`) plus what is known about how it is done. Nothing about a set changes: weight and reps, or a time, by its kind.
///
/// A custom exercise often arrives with no muscles at all. They are filled in without being asked: first by the closest exercise of the bundled
/// library (offline), then by Anya, who is given only the exercise's name. What the person classified by hand is never touched.
enum NunaCustomExercises {
    /// Posted on the main queue whenever the registry changed, so a page showing an exercise can read it again.
    static let didChange = Notification.Name("nuna.customExercises.didChange")

    // MARK: What is known besides the muscles

    /// How a custom exercise is done and where its muscles came from, kept on this phone beside the vocabulary.
    struct Extra: Codable, Equatable {
        var equipment: String?
        /// weighted | bodyweight | timed
        var kind: String?
        /// "you" when the person classified it, "library" or "anya" when it was filled in.
        var source: String
        var checkedAt: Int
        var tries: Int
    }

    private static let extrasKey = "nuna.gym.customExercises.v1"
    private static let lock = NSLock()
    private static var entries: [String: NunaLibraryExercise] = [:]
    private static var extras: [String: Extra] = {
        guard let data = UserDefaults.standard.data(forKey: extrasKey),
              let decoded = try? JSONDecoder().decode([String: Extra].self, from: data) else { return [:] }
        return decoded
    }()

    private static func key(_ name: String) -> String { NunaExerciseLibrary.normalized(name) }

    private static func saveExtras() {
        if let data = try? JSONEncoder().encode(extras) { UserDefaults.standard.set(data, forKey: extrasKey) }
    }

    // MARK: Lookups (the library asks these for a name it has no entry for)

    static func entry(forName name: String) -> NunaLibraryExercise? {
        lock.lock(); defer { lock.unlock() }
        return entries[key(name)]
    }

    static func entry(id: String) -> NunaLibraryExercise? {
        guard id.hasPrefix("custom-") else { return nil }
        lock.lock(); defer { lock.unlock() }
        return entries.values.first { $0.id == id }
    }

    /// weighted | bodyweight | timed, when it is known for this name.
    static func kind(forName name: String) -> NunaExerciseKind? {
        lock.lock(); defer { lock.unlock() }
        switch extras[key(name)]?.kind {
        case "weighted": return .weighted
        case "bodyweight": return .bodyweight
        case "timed": return .timed
        default: return nil
        }
    }

    /// Where the muscles of this exercise came from ("you", "library", "anya"), nil when it is not a custom one or nothing was filled in.
    static func source(forName name: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return extras[key(name)]?.source
    }

    // MARK: Building the registry

    /// A stable id from the name: the same name is the same exercise from one launch to the next (FNV-1a over the words).
    static func id(forName name: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for u in key(name).utf16 { h = (h ^ UInt64(u)) &* 0x100000001b3 }
        return "custom-" + String(h, radix: 16)
    }

    private static func libraryNames(_ muscles: [LiftMuscle]) -> [String] {
        var out: [String] = []
        for m in muscles { let n = m.libraryName; if !out.contains(n) { out.append(n) } }
        return out
    }

    private static func build(_ row: LiftExerciseRow, extra: Extra?) -> NunaLibraryExercise {
        NunaLibraryExercise(id: id(forName: row.name), name: row.name, level: nil, mechanic: nil, force: nil,
                            // "other" reads as an unknown tool, the same as before this registry existed: weighted unless the words say otherwise.
                            equipment: extra?.equipment ?? "other", category: extra?.kind == "timed" ? "stretching" : "strength",
                            primaryMuscles: row.primaryMuscle.map { libraryNames([$0]) } ?? [],
                            secondaryMuscles: libraryNames(row.secondaryMuscles).filter { !(row.primaryMuscle.map { libraryNames([$0]) } ?? []).contains($0) },
                            instructions: [], frames: [], aliases: [])
    }

    /// Rebuilds the registry from the vocabulary: every name the bundled library does not know.
    static func reload(vocabulary rows: [LiftExerciseRow]) {
        var built: [String: NunaLibraryExercise] = [:]
        lock.lock()
        for r in rows where !r.name.trimmingCharacters(in: .whitespaces).isEmpty && NunaExerciseLibrary.matchBundled(r.name) == nil {
            built[key(r.name)] = build(r, extra: extras[key(r.name)])
        }
        entries = built
        lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: didChange, object: nil) }
    }

    // MARK: Remembering and filling in

    /// Exercises picked from the library or typed: a name the library does not know goes into the vocabulary at once, with its muscles if
    /// there are any, so it has a page and a history from its first set. Anya or the closest library exercise fills the rest in the background.
    @MainActor static func remember(_ picks: [NunaPickedExercise], repo: Repository, coach: AICoachEngine?) async {
        guard let store = await repo.storeHandle() else { return }
        let now = Int(Date().timeIntervalSince1970)
        var vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        for p in picks where NunaExerciseLibrary.matchBundled(p.name) == nil {
            guard !p.name.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let known = vocabulary.first(where: { key($0.name) == key(p.name) }) {
                // Muscles the person just gave win over what was there before.
                if p.primary != nil, known.primaryMuscle == nil {
                    let row = LiftExerciseRow(id: known.id, deviceId: known.deviceId, name: known.name, primaryMuscle: p.primary,
                                              secondaryMuscles: p.secondary.filter { $0 != p.primary }, createdAt: known.createdAt, lastUsedTs: now)
                    _ = try? await store.upsertLiftExercises([row])
                    mark(name: known.name, source: "you")
                }
                continue
            }
            let row = LiftExerciseRow(id: UUID().uuidString, deviceId: repo.deviceId, name: p.name, primaryMuscle: p.primary,
                                      secondaryMuscles: p.secondary.filter { $0 != p.primary }, createdAt: now, lastUsedTs: now)
            if (try? await store.upsertLiftExercises([row])) != nil {
                vocabulary.append(row)
                if p.primary != nil { mark(name: p.name, source: "you") }
            }
        }
        reload(vocabulary: (try? await store.liftExercises(deviceId: repo.deviceId)) ?? vocabulary)
        Task { await fillIn(repo: repo, coach: coach) }
    }

    private static func mark(name: String, source: String) {
        lock.lock(); defer { lock.unlock() }
        var e = extras[key(name)] ?? Extra(equipment: nil, kind: nil, source: source, checkedAt: Int(Date().timeIntervalSince1970), tries: 0)
        e.source = source
        extras[key(name)] = e
        saveExtras()
    }

    /// Brings the registry up to date with everything logged: a name in a logged set (a Hevy import, an older session) that the vocabulary
    /// lacks is added to it, then every custom exercise without muscles is filled in. Safe to call often; it only works on what is missing.
    @MainActor static func sync(repo: Repository, coach: AICoachEngine?) async {
        guard let store = await repo.storeHandle() else { return }
        let now = Int(Date().timeIntervalSince1970)
        var vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        var seen = Set(vocabulary.map { key($0.name) })
        let sessions = (try? await store.liftSessions(deviceId: repo.deviceId, fromTs: 0, toTs: now + 86_400)) ?? []
        for s in sessions {
            for set in (try? await store.liftSets(sessionId: s.id)) ?? [] {
                let name = set.exercise.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, NunaExerciseLibrary.matchBundled(name) == nil, !seen.contains(key(name)) else { continue }
                seen.insert(key(name))
                let row = LiftExerciseRow(id: UUID().uuidString, deviceId: repo.deviceId, name: name, primaryMuscle: set.primaryMuscle,
                                          secondaryMuscles: set.secondaryMuscles, createdAt: now, lastUsedTs: set.endTs ?? set.startTs)
                if (try? await store.upsertLiftExercises([row])) != nil { vocabulary.append(row) }
            }
        }
        reload(vocabulary: (try? await store.liftExercises(deviceId: repo.deviceId)) ?? vocabulary)
        await fillIn(repo: repo, coach: coach)
    }

    private static var syncedThisLaunch = false

    /// The Gym tab's own call: the first time in a launch it does the whole sync; later opens do nothing, because every way of adding an
    /// exercise already calls `remember` or `sync` itself.
    @MainActor static func syncOncePerLaunch(repo: Repository, coach: AICoachEngine?) async {
        guard !syncedThisLaunch else { return }
        syncedThisLaunch = true
        await sync(repo: repo, coach: coach)
    }

    private static var filling = false
    /// A name tried this many times without an answer is left alone, so a provider that cannot place it is not asked on every launch.
    private static let maxTries = 2

    /// Gives every custom exercise without muscles a classification, one at a time.
    @MainActor static func fillIn(repo: Repository, coach: AICoachEngine?) async {
        guard !filling, let store = await repo.storeHandle() else { return }
        filling = true; defer { filling = false }
        let vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        let missing = vocabulary.filter { $0.primaryMuscle == nil && NunaExerciseLibrary.matchBundled($0.name) == nil }
        guard !missing.isEmpty else { return }
        for row in missing {
            let k = key(row.name)
            lock.lock(); let tries = extras[k]?.tries ?? 0; lock.unlock()
            guard tries < maxTries else { continue }
            var spec = closestLibraryExercise(to: row.name).map { AnyaExerciseSpec(primary: Array($0.primaryMuscles.prefix(2)), secondary: Array($0.secondaryMuscles.prefix(3)),
                                                                                  equipment: $0.equipment, kind: nil) }
            var source = "library"
            if spec == nil, let coach, let reply = await coach.classifyExercise(row.name) {
                spec = AnyaActions.parseExercise(from: reply); source = "anya"
            }
            lock.lock()
            var extra = extras[k] ?? Extra(equipment: nil, kind: nil, source: source, checkedAt: 0, tries: 0)
            extra.checkedAt = Int(Date().timeIntervalSince1970)
            guard let spec else { extra.tries += 1; extras[k] = extra; saveExtras(); lock.unlock(); continue }
            extra.equipment = spec.equipment; extra.kind = spec.kind; extra.source = source
            extras[k] = extra; saveExtras(); lock.unlock()

            let primary = spec.primary.compactMap(LiftMuscle.init(libraryName:)).first
            let secondary = (spec.primary.dropFirst() + spec.secondary).compactMap(LiftMuscle.init(libraryName:)).filter { $0 != primary }
            let filled = LiftExerciseRow(id: row.id, deviceId: row.deviceId, name: row.name, primaryMuscle: primary, secondaryMuscles: secondary,
                                         createdAt: row.createdAt, lastUsedTs: row.lastUsedTs)
            _ = try? await store.upsertLiftExercises([filled])
        }
        reload(vocabulary: (try? await store.liftExercises(deviceId: repo.deviceId)) ?? vocabulary)
        await repo.refresh()
    }

    // MARK: The closest library exercise

    /// Words that say how or with what, not which movement.
    private static let filler: Set<String> = ["barbell", "dumbbell", "cable", "machine", "kettlebell", "band", "smith", "bodyweight", "weighted", "ez", "bar",
                                              "hevy", "custom", "my", "the", "a", "with", "on", "to", "seated", "standing", "lying"]

    /// The library exercise whose words overlap the name's the most, when they overlap enough to trust: at least two thirds of the smaller
    /// set of words, and two words in common, so "Cable Fly" does not claim "Cable Crossover Fly Machine Pec Deck".
    static func closestLibraryExercise(to name: String) -> NunaLibraryExercise? {
        let target = Set(NunaExerciseLibrary.words(name).filter { !filler.contains($0) })
        guard target.count >= 2 else { return nil }
        var best: (score: Double, entry: NunaLibraryExercise)?
        for e in NunaExerciseLibrary.all {
            let words = Set(NunaExerciseLibrary.words(e.name).filter { !filler.contains($0) })
            let common = target.intersection(words).count
            guard common >= 2 else { continue }
            let score = Double(common) / Double(min(target.count, words.count)) * (Double(common) / Double(max(target.count, words.count)) + 1) / 2
            if Double(common) / Double(min(target.count, words.count)) >= 0.67, score > (best?.score ?? 0) { best = (score, e) }
        }
        return best?.entry
    }
}

extension LiftMuscle {
    /// The library's own name for this muscle (the three shoulder heads are one "shoulders" there).
    var libraryName: String {
        switch self {
        case .chest: return "chest"
        case .frontDelts, .sideDelts, .rearDelts: return "shoulders"
        case .triceps: return "triceps"
        case .lats: return "lats"
        case .upperBack: return "middle back"
        case .traps: return "traps"
        case .biceps: return "biceps"
        case .forearms: return "forearms"
        case .quads: return "quadriceps"
        case .hamstrings: return "hamstrings"
        case .glutes: return "glutes"
        case .adductors: return "adductors"
        case .abductors: return "abductors"
        case .calves: return "calves"
        case .abs, .obliques: return "abdominals"
        case .lowerBack: return "lower back"
        case .neck: return "neck"
        }
    }

    /// The reverse, for a name the library uses. A shoulder is the front head, which is where most work lands; a muscle the app does not
    /// track gives nil.
    init?(libraryName: String) {
        switch libraryName {
        case "chest": self = .chest
        case "shoulders": self = .frontDelts
        case "triceps": self = .triceps
        case "lats": self = .lats
        case "middle back": self = .upperBack
        case "traps": self = .traps
        case "biceps": self = .biceps
        case "forearms": self = .forearms
        case "quadriceps": self = .quads
        case "hamstrings": self = .hamstrings
        case "glutes": self = .glutes
        case "adductors": self = .adductors
        case "abductors": self = .abductors
        case "calves": self = .calves
        case "abdominals": self = .abs
        case "lower back": self = .lowerBack
        case "neck": self = .neck
        default: return nil
        }
    }
}
#endif
