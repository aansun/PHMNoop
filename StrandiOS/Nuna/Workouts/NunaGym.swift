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
        guard !session.isActive else { session.present(); return }
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
    static func startFreehand(_ picked: [NunaPickedExercise], repo: Repository, session: LiftSessionController) async {
        guard !session.isActive else { session.present(); return }
        let vocabulary: [LiftExerciseRow]
        if let store = await repo.storeHandle() { vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? [] } else { vocabulary = [] }
        // A name typed by hand takes its muscles from the exercises remembered from earlier, when it is one of them.
        let plan = picked.map { p -> LiftPlanItem in
            let known = p.primary == nil ? vocabulary.first { $0.name == p.name } : nil
            return LiftPlanItem(exercise: p.name, primaryMuscle: p.primary ?? known?.primaryMuscle,
                                secondaryMuscles: p.primary == nil ? (known?.secondaryMuscles ?? []) : p.secondary, targetSets: 3)
        }
        guard !plan.isEmpty else { return }
        session.start(plan: plan, programId: nil, programName: nil)
    }
}

// MARK: - Gym hub (WorkoutGym.dc)

/// Gym: start an empty session, run or edit a saved program, the sets each muscle group got this week and the latest
/// sessions. Reads and writes the same Lift Log tables as the Default screens, so programs and sessions are shared.
struct NunaGymView: View {
    /// True when shown as the Gym tab of Workouts, which already has its own header and scroll view.
    var embedded = false
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var session: LiftSessionController
    @State private var programs: [LiftProgramRow] = []
    @State private var itemCounts: [String: (exercises: Int, sets: Int)] = [:]
    @State private var lastUsed: [String: Int] = [:]
    @State private var history: [LiftSessionRow] = []
    @State private var weekCounts: [LiftMuscle: Double] = [:]
    @State private var readiness: [LiftMuscle: Double] = [:]
    @State private var volumes: [String: Double] = [:]
    @State private var loaded = false
    @State private var picking = false
    @ObservedObject private var groupsModel = NunaProgramGroupsModel.shared
    @State private var groupDialog: GroupDialog?
    @State private var groupName = ""
    @State private var deletingGroup: NunaProgramGroup?

    /// What the name box is for: a new group (and the program to put in it, if it came from a program's menu), or a rename.
    private enum GroupDialog: Identifiable {
        case new(programId: String?)
        case rename(NunaProgramGroup)
        var id: String { switch self { case .new(let p): "new-\(p ?? "")"; case .rename(let g): "rename-\(g.id)" } }
    }

    private static let setsBarSpan = 20.0

    @ViewBuilder private var content: some View {
        emptyCard
        programsSection
        NunaMuscleReadinessCard(readings: readiness)
        weekSection
        sessionsSection
        NavigationLink(value: NunaWorkoutRoute.loadMuscle) {
            NunaCard(small: true) { NunaListRow("Muscle load", subtitle: "Volume, recovery and personal records", systemImage: "chart.bar", showsChevron: true) }
        }.buttonStyle(.plain)
        NavigationLink(value: NunaWorkoutRoute.exerciseLibrary) {
            NunaCard(small: true) { NunaListRow("Exercise library", subtitle: "Animated demos and the muscles each one works", systemImage: "figure.strengthtraining.traditional", showsChevron: true) }
        }.buttonStyle(.plain)
    }

    var body: some View {
        Group {
            if embedded {
                VStack(spacing: NunaSpacing.section) { content }
            } else {
                NunaDetailScreen("Gym") { content }
            }
        }
        .nunaWorkoutDestinations()
        .task(id: "\(repo.refreshSeq)-\(session.savedSessions)") { await load() }
        .alert(groupDialogTitle, isPresented: Binding(get: { groupDialog != nil }, set: { if !$0 { groupDialog = nil } })) {
            TextField("Group name", text: $groupName)
            Button("Save") { saveGroupDialog() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this group?", isPresented: Binding(get: { deletingGroup != nil }, set: { if !$0 { deletingGroup = nil } }), titleVisibility: .visible) {
            Button("Delete group", role: .destructive) { if let g = deletingGroup { groupsModel.delete(g) }; deletingGroup = nil }
            Button("Cancel", role: .cancel) { deletingGroup = nil }
        } message: { Text("The programs in it are kept and become ungrouped.") }
        .sheet(isPresented: $picking) { NunaExercisePicker { picked in
            Task { await NunaGymStore.startFreehand(picked, repo: repo, session: session) }
        } }
    }

    // MARK: Empty session

    private var emptyCard: some View {
        NunaCard(highlight: true) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.isActive ? "Session in progress" : "Start an empty session").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text(session.isActive ? "Open it to keep logging sets" : "Pick the exercises you want to do").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Spacer(minLength: 8)
                Button { if session.isActive { session.present() } else { picking = true } } label: {
                    Text(session.isActive ? "Open" : "Start").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                        .padding(.horizontal, 22).frame(height: 44).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: Programs

    private var groupDialogTitle: LocalizedStringKey {
        if case .rename = groupDialog { return "Rename group" }
        return "New group"
    }

    private func saveGroupDialog() {
        guard let dialog = groupDialog else { return }
        switch dialog {
        case .new(let programId):
            if let g = groupsModel.add(name: groupName), let programId { groupsModel.move(programId, to: g) }
        case .rename(let g):
            groupsModel.rename(g, to: groupName)
        }
        groupDialog = nil
    }

    private func askForGroup(_ dialog: GroupDialog) {
        if case .rename(let g) = dialog { groupName = g.name } else { groupName = "" }
        groupDialog = dialog
    }

    private var programsSection: some View {
        let loose = groupsModel.ungrouped(programs)
        let suggestion = groupsModel.suggestions(for: programs).first
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Programs") {
                Button { askForGroup(.new(programId: nil)) } label: {
                    HStack(spacing: 6) { Image(systemName: "folder.badge.plus").font(.nuna(size: 13, weight: .bold)); Text("New group").font(.nuna(size: 13.5, weight: .bold)) }
                        .foregroundStyle(NunaPalette.textPrimary)
                }.buttonStyle(.plain)
            }
            if loaded, programs.isEmpty {
                NunaCard(small: true) {
                    Text("No programs yet. A program is a named list of exercises with your targets for each.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
            if let suggestion { suggestionCard(suggestion) }
            ForEach(groupsModel.groups) { g in groupSection(g) }
            if !groupsModel.groups.isEmpty, !loose.isEmpty {
                Text("Ungrouped").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).padding(.top, 4)
            }
            ForEach(loose, id: \.id) { p in programRow(p) }
            HStack(spacing: 10) {
                NavigationLink(value: NunaWorkoutRoute.program("new")) { programButton("New program", "plus") }.buttonStyle(.plain)
                NavigationLink(value: NunaWorkoutRoute.programImport) { programButton("Import", "tablecells") }.buttonStyle(.plain)
            }
        }
    }

    /// Programs named "Plan · Day A" and "Plan · Day B" can be put together in one tap.
    private func suggestionCard(_ s: NunaProgramGroupsModel.Suggestion) -> some View {
        NunaCard(small: true) {
            HStack(spacing: 12) {
                Image(systemName: "folder").font(.nuna(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 40, height: 40).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: String(localized: "Group \(s.programIds.count) programs as \"\(s.name)\"?")).font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text("They share the start of their names.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Spacer(minLength: 6)
                Button { withAnimation(.easeInOut(duration: 0.2)) { groupsModel.apply(s) } } label: {
                    Text("Group").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 16).frame(height: 38)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    /// One folder: its name and count (tap to fold it), a menu to rename or delete it, and its programs.
    @ViewBuilder private func groupSection(_ g: NunaProgramGroup) -> some View {
        let inside = groupsModel.programs(in: g, from: programs)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { groupsModel.toggleCollapsed(g) } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: g.collapsed ? "folder.fill" : "folder").font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: g.name).font(.nuna(size: 17, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                        Text(verbatim: "\(inside.count)").font(.nuna(size: 13, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.down").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted).rotationEffect(.degrees(g.collapsed ? -90 : 0))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                Menu {
                    Button { askForGroup(.rename(g)) } label: { Label("Rename group", systemImage: "pencil") }
                    Button(role: .destructive) { deletingGroup = g } label: { Label("Delete group", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 34, height: 36).contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 4)
            if !g.collapsed {
                if inside.isEmpty {
                    NunaCard(small: true) {
                        Text("Empty. Use the menu of a program to move it here.").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(inside, id: \.id) { p in programRow(p) }
            }
        }
        .padding(.top, 4)
    }

    private func programButton(_ title: LocalizedStringKey, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.nuna(size: 14, weight: .bold))
            Text(title).font(.nuna(size: 14.5, weight: .bold))
        }
        .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 48).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
    }

    /// Move a program into a group, out of one, or into a new one.
    private func programMenu(_ p: LiftProgramRow) -> some View {
        Menu {
            Menu {
                ForEach(groupsModel.groups) { g in
                    Button { groupsModel.move(p.id, to: g) } label: {
                        if groupsModel.group(of: p.id)?.id == g.id { Label(g.name, systemImage: "checkmark") } else { Text(verbatim: g.name) }
                    }
                }
                if groupsModel.group(of: p.id) != nil { Button { groupsModel.move(p.id, to: nil) } label: { Label("No group", systemImage: "xmark") } }
                Button { askForGroup(.new(programId: p.id)) } label: { Label("New group", systemImage: "folder.badge.plus") }
            } label: { Label("Move to group", systemImage: "folder") }
        } label: {
            Image(systemName: "ellipsis").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 30, height: 42).contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Program options"))
    }

    private func programRow(_ p: LiftProgramRow) -> some View {
        let c = itemCounts[p.id]
        return NunaCard(small: true) {
            HStack(spacing: 12) {
                NavigationLink(value: NunaWorkoutRoute.program(p.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: p.name).font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2)
                        Text(verbatim: String(localized: "\(c?.exercises ?? 0) exercises") + " · " + String(localized: "\(c?.sets ?? 0) sets")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        Text(verbatim: lastUsed[p.id].map { String(localized: "Last \(NunaWorkoutFormat.day($0))") } ?? String(localized: "Never run"))
                            .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                        Text("Tap to edit").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                programMenu(p)
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
            NunaTitleRow(title: "Sets per muscle") { Text(verbatim: String(localized: "Tick = \(LiftFormat.trim(floorSets)) sets")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    if ordered.isEmpty {
                        Text("Once you log a session, this shows how many sets each muscle group got in the last 7 days.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
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
                        Text("Direct sets count one, indirect sets count half.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                        if !under.isEmpty {
                            let names = under.map(\.name).joined(separator: ", ")
                            Text(verbatim: String(localized: "\(names) are still under \(LiftFormat.trim(floorSets)) sets.")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
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
        // The sets of the last days, each with the time of its session, for the muscle map.
        var dated: [(set: LiftSetRow, at: Int)] = []
        for s in all where s.startTs >= now - NunaMuscleReadiness.horizonDays * 86_400 {
            for set in (try? await store.liftSets(sessionId: s.id)) ?? [] { dated.append((set, set.endTs ?? set.startTs ?? (s.endTs ?? s.startTs))) }
        }
        readiness = NunaMuscleReadiness.readings(sets: dated, now: now)
        groupsModel.prune(existing: Set(ps.map(\.id)))
        programs = ps; itemCounts = counts; lastUsed = last; history = all; volumes = vols; loaded = true
    }
}
#endif
