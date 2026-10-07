#if os(iOS)
import Foundation
import StrandImport
import WhoopStore

/// What an import did, in numbers the screen turns into a sentence.
struct HevyImportSummary: Equatable {
    var added = 0            // new workouts or programs
    var updated = 0          // earlier Hevy imports written again
    var alreadyHere = 0      // a workout PHMN already has at that moment (logged here, or imported from a CSV)
    var skipped = 0          // elements Hevy sent that could not be read
    var sets = 0
    var first: Date?
    var last: Date?
    var groups = 0
    var vocabularyFull = false
}

/// Writes what Hevy sent into PHMN's own gym tables. Every row it writes has an id that starts with `hevy:` and is built from Hevy's own
/// id, so importing again rewrites the same rows instead of adding a second copy, and never touches anything the person logged or typed
/// here. Pure writes into the local database; nothing is sent to Hevy.
@MainActor
enum HevyImporter {
    static let idPrefix = "hevy:"

    // MARK: Names and muscles

    /// The name an exercise goes under: the one the person already uses for the same library exercise (so "Bench press" and Hevy's
    /// "Bench Press (Barbell)" share one history), otherwise Hevy's own title.
    private static func names(from vocabulary: [LiftExerciseRow]) -> [String: String] {
        var out: [String: String] = [:]
        for v in vocabulary { if let id = NunaExerciseLibrary.match(v.name)?.id, out[id] == nil { out[id] = v.name } }
        return out
    }

    private static func name(for title: String, own: [String: String]) -> String {
        NunaExerciseLibrary.match(title).flatMap { own[$0.id] } ?? title
    }

    private static func muscle(_ g: HevyAPI.MuscleGroup) -> LiftMuscle? {
        switch g {
        case .abdominals: return .abs
        case .shoulders: return .frontDelts
        case .biceps: return .biceps
        case .triceps: return .triceps
        case .forearms: return .forearms
        case .quadriceps: return .quads
        case .hamstrings: return .hamstrings
        case .calves: return .calves
        case .glutes: return .glutes
        case .abductors: return .abductors
        case .adductors: return .adductors
        case .lats: return .lats
        case .upperBack: return .upperBack
        case .traps: return .traps
        case .lowerBack: return .lowerBack
        case .chest: return .chest
        case .neck: return .neck
        case .cardio, .fullBody, .other: return nil
        }
    }

    /// Muscles of an exercise: from the library when its name is in it, else from Hevy's own exercise template.
    private struct Classifier {
        var templates: [String: HevyAPI.ExerciseTemplate] = [:]

        func muscles(title: String, templateId: String?) -> (primary: LiftMuscle?, secondary: [LiftMuscle]) {
            if let lib = NunaExerciseLibrary.match(title), lib.liftPrimary != nil { return (lib.liftPrimary, lib.liftSecondary) }
            if let id = templateId, let t = templates[id] {
                let primary = t.primaryMuscleGroup.flatMap(HevyImporter.muscle)
                return (primary, t.secondaryMuscleGroups.compactMap(HevyImporter.muscle).filter { $0 != primary })
            }
            return (nil, [])
        }
    }

    /// Fetches Hevy's exercise templates only when something in the import is not in the library.
    private static func classifier(needing items: [(title: String, templateId: String?)], client: HevyClient) async throws -> Classifier {
        var c = Classifier()
        let unmatched = items.contains { NunaExerciseLibrary.match($0.title) == nil && $0.templateId != nil }
        guard unmatched else { return c }
        c.templates = Dictionary(try await client.exerciseTemplates().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return c
    }

    // MARK: History

    static func importHistory(client: HevyClient, repo: Repository, progress: @escaping @Sendable (String) -> Void) async throws -> HevyImportSummary {
        guard let store = await repo.storeHandle() else { throw HevyClient.Failure.network("no store") }
        progress(String(localized: "Reading your workouts…"))
        let fetched = try await client.workouts(progress: { page, count in
            progress(String(localized: "Reading your workouts… page \(page) of \(count)"))
        })
        var summary = HevyImportSummary(skipped: fetched.skipped)
        guard !fetched.items.isEmpty else { return summary }

        let vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        let own = names(from: vocabulary)
        progress(String(localized: "Matching exercises…"))
        let titles = fetched.items.flatMap { $0.exercises.map { (title: $0.title, templateId: $0.templateId) } }
        let classifier = try await classifier(needing: titles, client: client)

        // Sessions already in the store, by start: the ones from an earlier Hevy import are replaced, anything else is left alone.
        let now = Int(Date().timeIntervalSince1970)
        let existing = (try? await store.liftSessions(deviceId: repo.deviceId, fromTs: 0, toTs: now + 86_400)) ?? []
        let byStart = Dictionary(existing.map { ($0.startTs, $0) }, uniquingKeysWith: { a, _ in a })
        let lifting = await repo.workoutRows().filter { WorkoutSource.classify($0.source) == .lifting }.map(\.startTs)

        var sessions: [LiftSessionRow] = [], sets: [LiftSetRow] = [], workouts: [WorkoutRow] = []
        for w in fetched.items {
            let startTs = Int(w.start.timeIntervalSince1970), endTs = max(Int(w.end.timeIntervalSince1970), startTs)
            let id = idPrefix + w.id
            if let e = byStart[startTs] {
                if e.id == id { _ = try? await store.deleteLiftSession(id: id); summary.updated += 1 }
                else { summary.alreadyHere += 1; continue }
            } else { summary.added += 1 }

            sessions.append(LiftSessionRow(id: id, deviceId: repo.deviceId, startTs: startTs, endTs: endTs, sport: LiftSessionView.sport,
                                           programId: nil, programName: w.title, sessionRpe: nil, note: w.title))
            var ord = 0
            for ex in w.exercises {
                let m = classifier.muscles(title: ex.title, templateId: ex.templateId)
                let exercise = name(for: ex.title, own: own)
                for (i, s) in ex.sets.enumerated() {
                    var note: [String] = []
                    if let d = s.durationSeconds { note.append("\(Int(d.rounded())) s") }
                    if let d = s.distanceMeters { note.append("\(Int(d.rounded())) m") }
                    sets.append(LiftSetRow(id: "\(id):\(ord)", deviceId: repo.deviceId, sessionId: id, ord: ord, exercise: exercise,
                                           primaryMuscle: m.primary, secondaryMuscles: m.secondary, setIndex: i + 1,
                                           weightKg: s.weightKg, reps: s.reps, rpe: s.rpe, isWarmup: s.isWarmup,
                                           startTs: nil, endTs: nil, restSec: nil, note: note.isEmpty ? nil : note.joined(separator: " · ")))
                    ord += 1
                }
            }
            summary.sets += ord
            summary.first = min(summary.first ?? w.start, w.start); summary.last = max(summary.last ?? w.start, w.start)
            // A workout row beside the session, so it shows in Workouts like one logged here; skipped when a Hevy CSV import already made one.
            if !lifting.contains(where: { abs($0 - startTs) <= 120 }) {
                workouts.append(WorkoutRow(startTs: startTs, endTs: endTs, sport: LiftSessionView.sport, source: "manual",
                                           durationS: Double(max(0, endTs - startTs)), energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
                                           distanceM: nil, zonesJSON: nil, notes: w.title, steps: nil))
            }
        }
        progress(String(localized: "Saving…"))
        _ = try? await store.upsertLiftSessions(sessions)
        for chunk in stride(from: 0, to: sets.count, by: 500) { _ = try? await store.upsertLiftSets(Array(sets[chunk..<min(chunk + 500, sets.count)])) }
        if !workouts.isEmpty { _ = try? await store.upsertWorkouts(workouts, deviceId: repo.deviceId) }
        await repo.refresh()
        return summary
    }

    // MARK: Routines

    static func importRoutines(client: HevyClient, repo: Repository, progress: @escaping @Sendable (String) -> Void) async throws -> HevyImportSummary {
        guard let store = await repo.storeHandle() else { throw HevyClient.Failure.network("no store") }
        progress(String(localized: "Reading your routines…"))
        let fetched = try await client.routines(progress: { page, count in
            progress(String(localized: "Reading your routines… page \(page) of \(count)"))
        })
        var summary = HevyImportSummary(skipped: fetched.skipped)
        guard !fetched.items.isEmpty else { return summary }

        // Folders are a convenience: if they cannot be read the routines still come in, just ungrouped.
        let folders: [HevyAPI.RoutineFolder]
        do { folders = try await client.routineFolders() }
        catch HevyClient.Failure.unauthorized { throw HevyClient.Failure.unauthorized }
        catch { folders = [] }
        let folderTitle = Dictionary(folders.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })

        let vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        let own = names(from: vocabulary)
        progress(String(localized: "Matching exercises…"))
        let classifier = try await classifier(needing: fetched.items.flatMap { $0.exercises.map { (title: $0.title, templateId: $0.templateId) } }, client: client)
        let existing = Set(((try? await store.liftPrograms(deviceId: repo.deviceId)) ?? []).map(\.id))
        let now = Int(Date().timeIntervalSince1970)
        let groups = NunaProgramGroupsModel.shared
        let groupsBefore = groups.groups.count
        var remembered: [String: LiftExerciseRow] = [:]

        for r in fetched.items {
            let programId = idPrefix + r.id
            if existing.contains(programId) { summary.updated += 1 } else { summary.added += 1 }
            _ = try? await store.upsertLiftPrograms([LiftProgramRow(id: programId, deviceId: repo.deviceId, name: r.title, note: r.notes,
                                                                    createdAt: now, updatedAt: now, archived: false)])
            var items: [LiftProgramItemRow] = []
            for (i, ex) in r.exercises.enumerated() {
                let working = ex.sets.filter { !$0.isWarmup }
                let first = working.first ?? ex.sets.first
                let exercise = name(for: ex.title, own: own)
                let timed = first?.reps == nil && first?.repRangeStart == nil ? first?.durationSeconds.map { "\(Int($0.rounded())) s" } : nil
                let note = [ex.notes, timed].compactMap { $0 }.joined(separator: " · ")
                items.append(LiftProgramItemRow(id: "\(programId):\(i)", deviceId: repo.deviceId, programId: programId, ord: i, exercise: exercise,
                                                targetSets: max(1, working.count),
                                                targetRepsLow: first?.repRangeStart ?? first?.reps, targetRepsHigh: first?.repRangeEnd,
                                                targetRpe: nil, targetWeightKg: first?.weightKg, restSec: ex.restSeconds,
                                                note: note.isEmpty ? nil : String(note.prefix(WhoopStore.maxExerciseNoteLength))))
                let m = classifier.muscles(title: ex.title, templateId: ex.templateId)
                if m.primary != nil, remembered[exercise] == nil {
                    remembered[exercise] = LiftExerciseRow(id: UUID().uuidString, deviceId: repo.deviceId, name: exercise, primaryMuscle: m.primary,
                                                       secondaryMuscles: m.secondary, createdAt: now, lastUsedTs: nil)
                }
            }
            _ = try? await store.replaceLiftProgramItems(programId: programId, items: items)
            // A folder from Hevy becomes a group, unless the person already put this program somewhere themselves.
            if let fid = r.folderId, let title = folderTitle[fid], groups.group(of: programId) == nil, let g = groups.add(name: title) {
                groups.move(programId, to: g)
            }
        }
        // The exercises' muscles, so the program lines are classified like any others. The vocabulary has a cap; past it, the rest stay unclassified.
        for row in remembered.values {
            do { _ = try await store.upsertLiftExercises([row]) }
            catch { summary.vocabularyFull = true; break }
        }
        summary.groups = groups.groups.count - groupsBefore
        await repo.refresh()
        return summary
    }
}
#endif
