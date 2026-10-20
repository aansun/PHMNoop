#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Proposal

/// A session Anya puts together for today: the program that is due, or exercises the person already does for the muscles that are rested.
/// The numbers are the usual ones; how much lighter today should be is applied on top, to the session only, never to the program.
struct NunaGymProposal {
    struct Row: Identifiable {
        let id = UUID().uuidString
        let exercise: String
        let primary: LiftMuscle?
        let secondary: [LiftMuscle]
        var sets: Int
        var repsLow: Int?
        var repsHigh: Int?
        var weightKg: Double?
        var restSec: Int?
        var note: String?
        var programItemId: String?

        var kind: NunaExerciseKind { NunaExerciseKind.of(exercise) }
    }

    var title: String
    var programId: String?
    var rows: [Row]
    /// The program is the person's own (so a lighter day starts it as it is, only lighter); false for a session built from their history.
    var fromProgram: Bool

    /// What a row reads like after the lighter day: weight, reps or a hold. Nil where the row has nothing to lower.
    func adjusted(_ row: Row, _ a: GymCoach.LoadAdjust) -> (weightKg: Double?, reps: Int?) {
        let w = row.kind.usesWeight ? row.weightKg.map { GymCoach.adjustedWeight($0, a) } : nil
        let r: Int? = row.repsLow.map { row.kind == .timed ? GymCoach.adjustedSeconds($0, a) : GymCoach.adjustedReps($0, a) }
        return (w, r)
    }
}

/// Programs Anya made, kept apart so the Gym tab can show them under "Anya special".
enum NunaAnyaPrograms {
    private static let key = "nuna.gym.anyaPrograms"
    static var ids: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func add(_ id: String) { var s = ids; s.insert(id); UserDefaults.standard.set(Array(s), forKey: key) }
}

// MARK: - What Anya read

@MainActor
final class NunaGymAnyaModel: ObservableObject {
    struct Reading {
        var habit: GymCoach.Habit?
        var trend: GymCoach.Trend?
        var condition: GymCoach.Condition?
        var charge: Double?
        var programName: String?
        var proposal: NunaGymProposal?
        var sessionCount: Int
    }

    @Published private(set) var reading: Reading?

    func load(repo: Repository, profile: ProfileStore, day: NunaTodayModel) async {
        guard let store = await repo.storeHandle() else { return }
        let now = Date()
        let nowTs = Int(now.timeIntervalSince1970)
        let all = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: nowTs - 90 * 86_400, toTs: nowTs + 86_400)) ?? [])
            .filter { $0.endTs != nil }.sorted { $0.startTs > $1.startTs }
        var facts: [GymCoach.Session] = []
        var setsBySession: [String: [LiftSetRow]] = [:]
        for s in all {
            let sets = (try? await store.liftSets(sessionId: s.id)) ?? []
            setsBySession[s.id] = sets
            facts.append(GymCoach.Session(startTs: s.startTs, programId: s.programId, volumeKg: LiftMetrics.volumeLoadKg(sets) ?? 0,
                                          workingSets: sets.filter { !$0.isWarmup }.count))
        }
        await day.load(repo: repo, profile: profile)
        let charge = day.charge.pct
        let condition = GymCoach.condition(charge: charge, readiness: day.readiness?.level)
        let habit = GymCoach.habit(sessions: facts, now: now)
        let trend = GymCoach.trend(sessions: facts, now: now)

        // The program that is due: its exercises as they are in it.
        var proposal: NunaGymProposal?
        var programName: String?
        let programs = (try? await store.liftPrograms(deviceId: repo.deviceId)) ?? []
        if let id = GymCoach.scheduledProgram(sessions: facts, now: now), let program = programs.first(where: { $0.id == id }) {
            let items = (try? await store.liftProgramItems(programId: id)) ?? []
            if !items.isEmpty {
                programName = program.name
                var rows: [NunaGymProposal.Row] = []
                for it in items {
                    let lib = NunaExerciseLibrary.match(it.exercise)
                    let last = ((try? await store.lastLiftSets(deviceId: repo.deviceId, exercise: it.exercise, before: nowTs)) ?? []).filter { !$0.isWarmup }
                    let best = last.max { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }
                    rows.append(.init(exercise: it.exercise, primary: lib?.liftPrimary, secondary: lib?.liftSecondary ?? [], sets: it.targetSets ?? 3,
                                      repsLow: it.targetRepsLow ?? best?.reps, repsHigh: it.targetRepsHigh, weightKg: it.targetWeightKg ?? best?.weightKg,
                                      restSec: it.restSec, note: it.note, programItemId: it.id))
                }
                proposal = NunaGymProposal(title: program.name, programId: id, rows: rows, fromProgram: true)
            }
        }
        // No program for the day: exercises done in the last 30 days, for the muscle groups that are most rested.
        if proposal == nil {
            let last30 = all.filter { $0.startTs >= nowTs - 30 * 86_400 }
            var perExercise: [String: (group: NunaMuscleGroup, primary: LiftMuscle?, secondary: [LiftMuscle], sessions: Int, sets: Int, weight: Double?, reps: Int?, ts: Int)] = [:]
            for s in last30 {
                var seen: Set<String> = []
                for set in setsBySession[s.id] ?? [] where !set.isWarmup {
                    guard let p = set.primaryMuscle else { continue }
                    var e = perExercise[set.exercise] ?? (NunaMuscleGroup.of(p), p, set.secondaryMuscles, 0, 0, nil, nil, 0)
                    if !seen.contains(set.exercise) { e.sessions += 1; seen.insert(set.exercise) }
                    e.sets += 1
                    if s.startTs >= e.ts, let w = set.weightKg, w >= (e.weight ?? 0) || s.startTs > e.ts { e.weight = w; e.reps = set.reps; e.ts = s.startTs }
                    else if s.startTs >= e.ts, set.weightKg == nil { e.reps = set.reps; e.ts = s.startTs }
                    perExercise[set.exercise] = e
                }
            }
            var dated: [(set: LiftSetRow, at: Int)] = []
            for s in all where s.startTs >= nowTs - NunaMuscleReadiness.horizonDays * 86_400 {
                for set in setsBySession[s.id] ?? [] { dated.append((set, set.endTs ?? set.startTs ?? (s.endTs ?? s.startTs))) }
            }
            var fatigue: [String: Double] = [:]
            for (muscle, load) in NunaMuscleReadiness.readings(sets: dated, now: nowTs) {
                let g = NunaMuscleGroup.of(muscle).rawValue
                fatigue[g] = max(fatigue[g] ?? 0, load)
            }
            let candidates = perExercise.map { name, e in
                GymCoach.Candidate(name: name, group: e.group.rawValue, sets: max(2, min(4, Int((Double(e.sets) / Double(max(1, e.sessions))).rounded()))))
            }
            let picked = GymCoach.pick(candidates: candidates, fatigue: fatigue, timesDone: perExercise.mapValues(\.sessions))
            if !picked.isEmpty {
                let rows = picked.map { c -> NunaGymProposal.Row in
                    let e = perExercise[c.name]!
                    return .init(exercise: c.name, primary: e.primary, secondary: e.secondary, sets: c.sets, repsLow: e.reps, repsHigh: nil, weightKg: e.weight,
                                 restSec: nil, note: nil, programItemId: nil)
                }
                proposal = NunaGymProposal(title: String(localized: "Anya's session"), programId: nil, rows: rows, fromProgram: false)
            }
        }
        reading = Reading(habit: habit, trend: trend, condition: condition, charge: charge, programName: programName, proposal: proposal, sessionCount: facts.count)
    }
}

// MARK: - The card on the Gym tab

/// Anya at the top of the Gym tab. She reads when the wearer usually trains and how the last 30 days went, weighs today's Charge and
/// readiness, and says whether to go as planned or lighter. A lighter day changes only the session that is started, never the program.
struct NunaGymAnyaCard: View {
    @EnvironmentObject private var session: LiftSessionController
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    /// Read by the Gym tab (a task on a card that starts out empty would never run).
    @ObservedObject var model: NunaGymAnyaModel
    @State private var sheet = false

    var body: some View {
        Group {
            if coachEnabled, !session.isActive, let r = model.reading {
                NunaAnyaCard(verbatim: headline(r), detail: detail(r), buttonTitle: r.proposal == nil ? nil : buttonTitle(r),
                             onButton: { sheet = true }, action: { sheet = true })
                    // The card opens the plan, not the general sheet.
                    .environment(\.nunaAnyaCardContext, nil)
            }
        }
        .sheet(isPresented: $sheet) {
            if let r = model.reading, let p = r.proposal { NunaGymAnyaSheet(reading: r, proposal: p, text: headline(r)).nunaSheetChrome(detents: [.large]) }
        }
    }

    private func weekdays(_ h: GymCoach.Habit) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return h.usualWeekdays.map { symbols[($0 - 1) % 7] }.joined(separator: ", ")
    }

    private func buttonTitle(_ r: NunaGymAnyaModel.Reading) -> LocalizedStringKey {
        if let c = r.condition, c != .good, r.habit?.trainedToday != true { return "Plan a lighter session" }
        return "Plan today's session"
    }

    /// One short paragraph: what day it is for the wearer's habit, and what to do with the body as it is.
    private func headline(_ r: NunaGymAnyaModel.Reading) -> String {
        guard let h = r.habit else {
            return r.sessionCount == 0
                ? String(localized: "Log a few gym sessions and Anya learns your gym days, then helps plan each one.")
                : String(localized: "Anya needs about four sessions to read your gym habit. Until then, here is a session from what you already do.")
        }
        let name = r.programName
        if h.trainedToday { return String(localized: "You trained today. Give those muscles a day before you load them again.") }
        let cond = r.condition
        let c = r.charge.map { Int($0.rounded()) }
        if h.isUsualDay {
            switch cond {
            case .poor?:
                let a = GymCoach.adjust(for: .poor)
                return String(localized: "It is one of your gym days, but Charge is \(c.map(String.init) ?? "low"). Go lighter today: about \(a.weightCutPct)% less weight and \(-a.repsDelta) fewer reps. Resting is a fine choice too.")
            case .fair?:
                let a = GymCoach.adjust(for: .fair)
                return String(localized: "It is one of your gym days, and your body is a little under par. Go a bit lighter: about \(a.weightCutPct)% less weight and \(-a.repsDelta) fewer rep.")
            default:
                if let name { return String(localized: "It is one of your gym days and you are ready. \(name) is due.") }
                return String(localized: "It is one of your gym days and you are ready for a normal session.")
            }
        }
        if cond == .poor { return String(localized: "Not one of your usual gym days, and Charge is low. Rest is a good choice; if you go, keep it light.") }
        return String(localized: "Not one of your usual gym days. If you go, here is a session built from the muscles that are rested.")
    }

    private func detail(_ r: NunaGymAnyaModel.Reading) -> String? {
        var parts: [String] = []
        if let h = r.habit, !h.usualWeekdays.isEmpty {
            var line = String(localized: "You usually train on \(weekdays(h))")
            if let hour = h.usualHour { line += " " + String(format: String(localized: "around %02d:00"), hour) }
            parts.append(line + ".")
        }
        if let t = r.trend {
            var line = String(localized: "Last 30 days: \(t.sessions) sessions")
            if let c = t.volumeChangePct, abs(c) >= 1 { line += c > 0 ? String(localized: ", volume up \(Int(c.rounded()))% on the 15 days before") : String(localized: ", volume down \(Int((-c).rounded()))% on the 15 days before") }
            parts.append(line + ".")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: - Today's session

/// The session Anya proposes for today, with how much lighter it is and what happens to the program (nothing).
struct NunaGymAnyaSheet: View {
    let reading: NunaGymAnyaModel.Reading
    let proposal: NunaGymProposal
    let text: String
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var session: LiftSessionController
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @State private var lighter = true
    @State private var saved = false

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var adjust: GymCoach.LoadAdjust? {
        guard lighter, let c = reading.condition, c != .good, reading.habit?.trainedToday != true else { return nil }
        return GymCoach.adjust(for: c)
    }

    var body: some View {
        NavigationStack {
            NunaDetailScreen("Today's session") {
                Text(verbatim: text).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let c = reading.condition, c != .good {
                    let a = GymCoach.adjust(for: c)
                    NunaCard(small: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            NunaToggleRow("Go lighter today", subtitle: LocalizedStringKey(String(localized: "\(a.weightCutPct)% less weight, \(-a.repsDelta) fewer reps, holds a little shorter. The sets stay.")), systemImage: "arrow.down.right", isOn: $lighter)
                            Text("Only today's session changes. Your program is exactly as it was and next time starts from its own numbers.")
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                NunaTitleRow(title: LocalizedStringKey(proposal.fromProgram ? proposal.title : String(localized: "Built from your last 30 days"))) { EmptyView() }
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        ForEach(Array(proposal.rows.enumerated()), id: \.element.id) { i, row in
                            if i > 0 { NunaDivider() }
                            rowView(row)
                        }
                    }
                }
                Button { Task { await start() } } label: {
                    HStack(spacing: 8) { Image(systemName: "play.fill").font(.nuna(size: 13, weight: .bold)); Text(adjust == nil ? "Start this session" : "Start the lighter session").font(.nuna(size: 17, weight: .bold)) }
                        .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(session.isActive)
                if !proposal.fromProgram {
                    Button { Task { await saveProgram() } } label: {
                        Text(saved ? "Saved in Anya special" : "Save as a program").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(saved)
                }
                nunaFootnote("Anya reads your own sessions, your Charge and your readiness, on this iPhone. A suggestion, not a prescription.")
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    private func rowView(_ row: NunaGymProposal.Row) -> some View {
        let kind = row.kind
        let a = adjust.map { proposal.adjusted(row, $0) }
        func line(weight: Double?, reps: Int?) -> String {
            var parts: [String] = []
            if let t = kind.targetText(sets: row.sets, reps: reps) { parts.append(t) } else { parts.append("\(row.sets)") }
            if kind.usesWeight, let w = weight { parts.append(LiftFormat.weight(w, system: system)) }
            return parts.joined(separator: " · ")
        }
        let normal = line(weight: row.weightKg, reps: row.repsLow)
        let now = a.map { line(weight: $0.weightKg, reps: $0.reps) } ?? normal
        return HStack(spacing: 12) {
            NunaExerciseThumb(name: row.exercise, width: 50, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: row.exercise).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2)
                if now != normal {
                    Text(verbatim: normal).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).strikethrough().textCase(nil)
                }
            }
            Spacer(minLength: 6)
            Text(verbatim: now).font(.nuna(size: 14.5, weight: .bold, design: NunaType.design)).foregroundStyle(now != normal ? NunaPalette.warning : NunaPalette.textPrimary)
                .multilineTextAlignment(.trailing)
        }.padding(.vertical, 10)
    }

    /// The sheet goes first: the session screen opens over the top controller, and cannot while a sheet is still closing.
    private func start() async {
        dismiss()
        try? await Task.sleep(nanoseconds: 450_000_000)
        await NunaGymStore.start(proposal: proposal, adjust: adjust, repo: repo, session: session)
    }

    private func saveProgram() async {
        guard let store = await repo.storeHandle() else { return }
        let now = Int(Date().timeIntervalSince1970)
        let id = UUID().uuidString
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        let name = String((String(localized: "Anya") + " · " + f.string(from: Date())).prefix(60))
        _ = try? await store.upsertLiftPrograms([LiftProgramRow(id: id, deviceId: repo.deviceId, name: name, note: nil, createdAt: now, updatedAt: now, archived: false)])
        // The usual numbers, not today's lighter ones: the program is for every day.
        let items = proposal.rows.enumerated().map { i, r in
            LiftProgramItemRow(id: UUID().uuidString, deviceId: repo.deviceId, programId: id, ord: i, exercise: r.exercise, targetSets: r.sets, targetRepsLow: r.repsLow,
                               targetRepsHigh: r.repsHigh, targetRpe: nil, targetWeightKg: r.kind.usesWeight ? r.weightKg : nil, restSec: r.restSec ?? 90, note: nil)
        }
        _ = try? await store.replaceLiftProgramItems(programId: id, items: items)
        NunaAnyaPrograms.add(id)
        await repo.refresh()
        saved = true
    }
}

// MARK: - Starting a proposal

extension NunaGymStore {
    /// Start Anya's session. The plan carries the usual numbers; a lighter day is written on top of the sets, in this session only, so the
    /// program (and what the next session starts from) is left alone.
    static func start(proposal: NunaGymProposal, adjust: GymCoach.LoadAdjust?, repo: Repository, session: LiftSessionController) async {
        guard !session.isActive else { session.present(); return }
        let plan = proposal.rows.map { r in
            LiftPlanItem(exercise: r.exercise, primaryMuscle: r.primary, secondaryMuscles: r.secondary, targetSets: r.sets, restSec: r.restSec,
                         targetRepsLow: r.repsLow, targetRepsHigh: r.repsHigh, targetRpe: nil, targetWeightKg: r.kind.usesWeight ? r.weightKg : nil,
                         note: mergedNote(r.note, pinned: NunaExerciseNotes.note(forName: r.exercise)), programItemId: r.programItemId)
        }
        guard !plan.isEmpty else { return }
        session.start(plan: plan, programId: proposal.programId, programName: proposal.title)
        guard let adjust, !adjust.isNeutral, let engine = session.engine else { return }
        // What each set would have shown (last session, then the plan), made lighter and typed in.
        if let store = await repo.storeHandle() {
            var last: [String: [Int: LiftSetCarry]] = [:]
            for name in Set(plan.map(\.exercise)) {
                let rows = (try? await store.lastLiftSets(deviceId: repo.deviceId, exercise: name, before: engine.startTs)) ?? []
                var bySet: [Int: LiftSetCarry] = [:]
                for r in rows where !r.isWarmup { bySet[r.setIndex] = LiftSetCarry(weightKg: r.weightKg, reps: r.reps) }
                last[name] = bySet
            }
            session.setLastSession(last)
        }
        for i in plan.indices {
            let kind = NunaExerciseKind.of(plan[i].exercise)
            for slot in engine.slots(forExercise: i) {
                let base = session.carry(for: slot)
                let reps = base.reps.map { kind == .timed ? GymCoach.adjustedSeconds($0, adjust) : GymCoach.adjustedReps($0, adjust) }
                let weight = kind.usesWeight ? base.weightKg.map { GymCoach.adjustedWeight($0, adjust) } : nil
                session.updateSet(slot, weightKg: weight, reps: reps, rpe: nil, isWarmup: false)
            }
        }
    }
}
#endif
