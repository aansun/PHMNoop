#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The six muscle groups the Gym screens roll the stored muscles up into (Set per otot, Beban otot).
enum NunaMuscleGroup: String, CaseIterable {
    case legs, chest, back, shoulders, arms, core

    static func of(_ m: LiftMuscle) -> NunaMuscleGroup {
        switch m {
        case .quads, .hamstrings, .glutes, .adductors, .abductors, .calves: return .legs
        case .chest: return .chest
        case .lats, .upperBack, .traps, .lowerBack: return .back
        case .frontDelts, .sideDelts, .rearDelts, .neck: return .shoulders
        case .biceps, .triceps, .forearms: return .arms
        case .abs, .obliques: return .core
        }
    }

    var name: String {
        switch self {
        case .legs: return String(localized: "Legs"); case .chest: return String(localized: "Chest"); case .back: return String(localized: "Back")
        case .shoulders: return String(localized: "Shoulders"); case .arms: return String(localized: "Arms"); case .core: return String(localized: "Core")
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .legs: return "Legs"; case .chest: return "Chest"; case .back: return "Back"
        case .shoulders: return "Shoulders"; case .arms: return "Arms"; case .core: return "Core"
        }
    }
}

// MARK: - Form pieces shared by the program screens

/// A labelled input box in the Nuna style.
struct NunaFormField<Content: View>: View {
    let label: LocalizedStringKey
    let content: Content
    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.label = label; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(0.9).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            content
                .font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .padding(.horizontal, 14).frame(minHeight: 48, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

extension View {
    /// A "Done" button above the keyboard, for the numeric fields that have no return key.
    func nunaKeyboardDone() -> some View {
        toolbar { ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        } }
    }
}

/// Shared by the hub and the summary: reads and writes of programs, kept out of the views.
@MainActor
enum NunaGymStore {
    /// Flatten a program into the plan the session runs. The plan is a snapshot taken at start, the same as the Lift Log.
    static func start(program: LiftProgramRow, repo: Repository, session: LiftSessionController) async {
        guard !session.isActive else { session.isPresented = true; return }
        guard let store = await repo.storeHandle() else { return }
        let items = (try? await store.liftProgramItems(programId: program.id)) ?? []
        guard !items.isEmpty else { return }
        let vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        let plan = items.map { item -> LiftPlanItem in
            let known = vocabulary.first { $0.name == item.exercise }
            return LiftPlanItem(exercise: item.exercise, primaryMuscle: known?.primaryMuscle, secondaryMuscles: known?.secondaryMuscles ?? [],
                                targetSets: item.targetSets, restSec: item.restSec, targetRepsLow: item.targetRepsLow,
                                targetRepsHigh: item.targetRepsHigh, targetRpe: item.targetRpe, targetWeightKg: item.targetWeightKg,
                                note: item.note, programItemId: item.id)
        }
        session.start(plan: plan, programId: program.id, programName: program.name)
    }

    /// Start with exercises chosen on the spot and no program behind them.
    static func startFreehand(_ names: [String], repo: Repository, session: LiftSessionController) async {
        guard !session.isActive else { session.isPresented = true; return }
        let vocabulary: [LiftExerciseRow]
        if let store = await repo.storeHandle() { vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? [] } else { vocabulary = [] }
        let plan = names.map { n -> LiftPlanItem in
            let known = vocabulary.first { $0.name == n }
            return LiftPlanItem(exercise: n, primaryMuscle: known?.primaryMuscle, secondaryMuscles: known?.secondaryMuscles ?? [], targetSets: 3)
        }
        guard !plan.isEmpty else { return }
        session.start(plan: plan, programId: nil, programName: nil)
    }
}

// MARK: - Gym hub (WorkoutGym.dc)

/// Gym: start an empty session, run or edit a saved program, the sets each muscle group got this week and the latest
/// sessions. Reads and writes the same Lift Log tables as the Default screens, so programs and sessions are shared.
struct NunaGymView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var session: LiftSessionController
    @State private var programs: [LiftProgramRow] = []
    @State private var itemCounts: [String: (exercises: Int, sets: Int)] = [:]
    @State private var lastUsed: [String: Int] = [:]
    @State private var history: [LiftSessionRow] = []
    @State private var weekCounts: [LiftMuscle: Double] = [:]
    @State private var volumes: [String: Double] = [:]
    @State private var loaded = false
    @State private var picking = false

    private static let setsBarSpan = 20.0

    var body: some View {
        NunaDetailScreen("Gym") {
            emptyCard
            programsSection
            weekSection
            sessionsSection
            NavigationLink(value: NunaWorkoutRoute.loadMuscle) {
                NunaCard(small: true) { NunaListRow("Muscle load", subtitle: "Volume, recovery and personal records", systemImage: "chart.bar", showsChevron: true) }
            }.buttonStyle(.plain)
        }
        .nunaWorkoutDestinations()
        .task(id: "\(repo.refreshSeq)-\(session.savedSessions)") { await load() }
        .sheet(isPresented: $picking) { NunaExercisePicker { names in
            picking = false
            Task { await NunaGymStore.startFreehand(names, repo: repo, session: session) }
        } }
    }

    // MARK: Empty session

    private var emptyCard: some View {
        NunaCard(highlight: true) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.isActive ? "Session in progress" : "Start an empty session").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text(session.isActive ? "Open it to keep logging sets" : "Pick the exercises you want to do").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                Spacer(minLength: 8)
                Button { if session.isActive { session.isPresented = true } else { picking = true } } label: {
                    Text(session.isActive ? "Open" : "Start").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                        .padding(.horizontal, 22).frame(height: 44).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: Programs

    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Programs") { EmptyView() }
            if loaded, programs.isEmpty {
                NunaCard(small: true) {
                    Text("No programs yet. A program is a named list of exercises with your targets for each.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(programs, id: \.id) { p in programRow(p) }
            HStack(spacing: 10) {
                NavigationLink(value: NunaWorkoutRoute.program("new")) { programButton("New program", "plus") }.buttonStyle(.plain)
                NavigationLink(value: NunaWorkoutRoute.programImport) { programButton("Import", "tablecells") }.buttonStyle(.plain)
            }
        }
    }

    private func programButton(_ title: LocalizedStringKey, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.nuna(size: 14, weight: .bold))
            Text(title).font(.nuna(size: 14.5, weight: .bold))
        }
        .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 48).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
    }

    private func programRow(_ p: LiftProgramRow) -> some View {
        let c = itemCounts[p.id]
        return NunaCard(small: true) {
            HStack(spacing: 12) {
                NavigationLink(value: NunaWorkoutRoute.program(p.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: p.name).font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2)
                        Text(verbatim: String(localized: "\(c?.exercises ?? 0) exercises") + " · " + String(localized: "\(c?.sets ?? 0) sets")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: lastUsed[p.id].map { String(localized: "Last \(NunaWorkoutFormat.day($0))") } ?? String(localized: "Never run"))
                            .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                        Text("Tap to edit").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button { Task { await NunaGymStore.start(program: p, repo: repo, session: session) } } label: {
                    Text(session.isActive ? "Open" : "Start").font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                        .padding(.horizontal, 20).frame(height: 42).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled((c?.exercises ?? 0) == 0).opacity((c?.exercises ?? 0) == 0 ? 0.4 : 1)
            }
        }
    }

    // MARK: Sets per muscle group

    private var weekSection: some View {
        let floorSets = LiftMetrics.ReferenceDose.hypertrophyMinimumSetsPerWeek
        var sums: [NunaMuscleGroup: Double] = [:]
        for (mu, n) in weekCounts { sums[NunaMuscleGroup.of(mu), default: 0] += n }
        let ordered = NunaMuscleGroup.allCases.filter { (sums[$0] ?? 0) > 0 }.sorted { (sums[$0] ?? 0) > (sums[$1] ?? 0) }
        let under = NunaMuscleGroup.allCases.filter { (sums[$0] ?? 0) < floorSets && (sums[$0] ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Sets per muscle") { Text(verbatim: String(localized: "Tick = \(LiftFormat.trim(floorSets)) sets")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    if ordered.isEmpty {
                        Text("Once you log a session, this shows how many sets each muscle group got in the last 7 days.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(ordered, id: \.self) { g in
                        let n = sums[g] ?? 0
                        VStack(spacing: 6) {
                            HStack { Text(g.title).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary); Spacer()
                                Text(verbatim: LiftFormat.trim(n)).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary) }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.ink.opacity(0.09))
                                    RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.accent.opacity(n >= floorSets ? 1 : 0.5)).frame(width: max(6, geo.size.width * min(1, n / Self.setsBarSpan)))
                                    RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(n >= floorSets ? NunaPalette.onAccent.opacity(0.7) : NunaPalette.accent.opacity(0.55)).frame(width: 2, height: 12).offset(x: geo.size.width * min(1, floorSets / Self.setsBarSpan) - 1)
                                }
                            }.frame(height: 8)
                        }
                    }
                    if !ordered.isEmpty {
                        Text("Direct sets count one, indirect sets count half.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                        if !under.isEmpty {
                            let names = under.map(\.name).joined(separator: ", ")
                            Text(verbatim: String(localized: "\(names) are still under \(LiftFormat.trim(floorSets)) sets.")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Last sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Last sessions") {
                NavigationLink(value: NunaWorkoutRoute.history) { Text("All").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }
            }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    if history.isEmpty {
                        NunaListRow("No gym sessions yet", subtitle: "Finished sessions land here with every set", systemImage: "dumbbell")
                    }
                    ForEach(Array(history.prefix(3).enumerated()), id: \.element.id) { i, s in
                        if i > 0 { NunaDivider() }
                        NavigationLink(value: NunaWorkoutRoute.gymSession(s.id)) {
                            NunaListRow(LocalizedStringKey(s.programName ?? String(localized: "Gym")),
                                        subtitle: LocalizedStringKey(sessionLine(s)), systemImage: "dumbbell", showsChevron: true)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sessionLine(_ s: LiftSessionRow) -> String {
        var parts = [NunaWorkoutFormat.day(s.startTs)]
        if let e = s.endTs { parts.append("\(max(1, (e - s.startTs) / 60)) min") }
        if let v = volumes[s.id], v > 0 { parts.append(NunaTrendsFormat.num(v) + " kg") }
        return parts.joined(separator: " · ")
    }

    // MARK: Load

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        let ps = (try? await store.liftPrograms(deviceId: repo.deviceId)) ?? []
        var counts: [String: (exercises: Int, sets: Int)] = [:]
        for p in ps {
            let items = (try? await store.liftProgramItems(programId: p.id)) ?? []
            counts[p.id] = (items.count, items.reduce(0) { $0 + ($1.targetSets ?? 1) })
        }
        let now = Int(Date().timeIntervalSince1970)
        let all = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: now - 180 * 86_400, toTs: now + 86_400)) ?? [])
            .filter { $0.endTs != nil }.sorted { $0.startTs > $1.startTs }
        var last: [String: Int] = [:]
        for s in all { if let id = s.programId, last[id] == nil { last[id] = s.startTs } }
        var vols: [String: Double] = [:]
        for s in all.prefix(3) { vols[s.id] = LiftMetrics.volumeLoadKg((try? await store.liftSets(sessionId: s.id)) ?? []) }
        weekCounts = (try? await store.liftSetCounts(deviceId: repo.deviceId, fromTs: now - 7 * 86_400, toTs: now).fractional) ?? [:]
        programs = ps; itemCounts = counts; lastUsed = last; history = all; volumes = vols; loaded = true
    }
}

// MARK: - Exercise picker for an empty session

/// Choose exercises for a session with no program: the ones remembered from earlier, plus any name typed in.
struct NunaExercisePicker: View {
    let onStart: ([String]) -> Void
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var vocabulary: [LiftExerciseRow] = []
    @State private var chosen: [String] = []
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            NunaDetailScreen("Choose exercises") {
                NunaFormField("Exercise name") {
                    HStack {
                        TextField("", text: $typed, prompt: Text("Bench press").foregroundStyle(NunaPalette.textMuted)).focused($focused).submitLabel(.done).onSubmit(add)
                        Button(action: add) { Image(systemName: "plus.circle.fill").font(.nuna(size: 22)).foregroundStyle(NunaPalette.textPrimary) }.buttonStyle(.plain)
                            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if !vocabulary.isEmpty {
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                        VStack(spacing: 0) {
                            ForEach(Array(vocabulary.prefix(30).enumerated()), id: \.element.id) { i, e in
                                if i > 0 { NunaDivider() }
                                Button { toggle(e.name) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(verbatim: e.name).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                            Text(verbatim: LiftMuscleSummary.line(primary: e.primaryMuscle, secondaries: e.secondaryMuscles)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: chosen.contains(e.name) ? "checkmark.circle.fill" : "circle").font(.nuna(size: 20)).foregroundStyle(chosen.contains(e.name) ? NunaPalette.textPrimary : NunaPalette.textMuted)
                                    }.padding(.vertical, 12).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                Button { onStart(chosen) } label: {
                    Text(verbatim: chosen.isEmpty ? String(localized: "Pick at least one exercise") : String(localized: "Start with \(chosen.count) exercises"))
                        .font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(chosen.isEmpty).opacity(chosen.isEmpty ? 0.4 : 1)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .nunaKeyboardDone()
        }
        .preferredColorScheme(NunaTheme.colorScheme)
        .task { if let s = await repo.storeHandle() { vocabulary = ((try? await s.liftExercises(deviceId: repo.deviceId)) ?? []).sorted { ($0.lastUsedTs ?? 0) > ($1.lastUsedTs ?? 0) } } }
    }

    private func toggle(_ n: String) { if let i = chosen.firstIndex(of: n) { chosen.remove(at: i) } else { chosen.append(n) } }
    private func add() {
        let n = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        if !chosen.contains(n) { chosen.append(n) }
        typed = ""
    }
}
#endif
