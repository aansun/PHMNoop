#if os(iOS)
import SwiftUI
import MuscleMap
import Charts
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

    /// The body part to draw for the group: the side it is seen from, and how far down the figure to look.
    var picture: (side: BodySide, focus: CGFloat, zoom: CGFloat) {
        switch self {
        case .chest: return (.front, 0.27, 2.3); case .shoulders: return (.front, 0.23, 2.3); case .arms: return (.front, 0.34, 2.0)
        case .core: return (.front, 0.40, 2.3); case .legs: return (.front, 0.72, 1.7); case .back: return (.back, 0.30, 2.3)
        }
    }

    /// The muscles of the figure that belong to the group.
    var bodyMuscles: [Muscle] { LiftMuscle.allCases.filter { NunaMuscleGroup.of($0) == self }.map(\.bodyMap) }
}

/// A small tile with the figure and the muscles of one group lit, like the pictures of a muscle list.
struct NunaMuscleGroupThumb: View {
    let group: NunaMuscleGroup
    var body: some View {
        let pic = group.picture
        // The rest of the body is dimmed so only the group is lit; the figure is enlarged and moved so the group sits in the middle of the tile.
        let dim = BodyViewStyle(defaultFillColor: NunaPalette.textMuted.opacity(0.4), headColor: NunaPalette.textMuted.opacity(0.4), hairColor: NunaPalette.textMuted.opacity(0.3))
        ZStack {
            BodyView(gender: .male, side: pic.side).bodyStyle(dim).highlight(group.bodyMuscles, color: NunaPalette.textPrimary)
                .frame(width: 46, height: 96)
                .scaleEffect(pic.zoom)
                .offset(y: (0.5 - pic.focus) * 96 * pic.zoom)
        }
        .frame(width: 46, height: 46).background(NunaPalette.field).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
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
            let lib = NunaExerciseLibrary.match(item.exercise)
            return LiftPlanItem(exercise: item.exercise, primaryMuscle: known?.primaryMuscle ?? lib?.liftPrimary,
                                secondaryMuscles: known?.secondaryMuscles ?? lib?.liftSecondary ?? [],
                                targetSets: item.targetSets, restSec: item.restSec, targetRepsLow: item.targetRepsLow,
                                targetRepsHigh: item.targetRepsHigh, targetRpe: item.targetRpe, targetWeightKg: item.targetWeightKg,
                                note: mergedNote(item.note, pinned: NunaExerciseNotes.note(forName: item.exercise)), programItemId: item.id)
        }
        session.start(plan: plan, programId: program.id, programName: program.name)
    }

    /// The program's own note for the exercise, then the note pinned to the exercise itself.
    static func mergedNote(_ own: String?, pinned: String) -> String? {
        let parts = [own, pinned.isEmpty ? nil : pinned].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// A copy of a program with the same exercises and targets, named "<name> copy".
    @discardableResult
    static func duplicate(_ program: LiftProgramRow, repo: Repository) async -> String? {
        guard let store = await repo.storeHandle() else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let id = UUID().uuidString
        let name = String((program.name + " " + String(localized: "copy")).prefix(60))
        _ = try? await store.upsertLiftPrograms([LiftProgramRow(id: id, deviceId: repo.deviceId, name: name, note: program.note, createdAt: now, updatedAt: now, archived: false)])
        let items = ((try? await store.liftProgramItems(programId: program.id)) ?? []).map {
            LiftProgramItemRow(id: UUID().uuidString, deviceId: repo.deviceId, programId: id, ord: $0.ord, exercise: $0.exercise, targetSets: $0.targetSets,
                               targetRepsLow: $0.targetRepsLow, targetRepsHigh: $0.targetRepsHigh, targetRpe: $0.targetRpe, targetWeightKg: $0.targetWeightKg,
                               restSec: $0.restSec, note: $0.note)
        }
        _ = try? await store.replaceLiftProgramItems(programId: id, items: items)
        if let g = NunaProgramGroupsModel.shared.group(of: program.id) { NunaProgramGroupsModel.shared.move(id, to: g) }
        await repo.refresh()
        return id
    }

    /// The program as plain text, for the share sheet: the name, the note and one line per exercise.
    static func shareText(_ program: LiftProgramRow, repo: Repository, system: UnitSystem) async -> String {
        var items: [LiftProgramItemRow] = []
        if let store = await repo.storeHandle() { items = (try? await store.liftProgramItems(programId: program.id)) ?? [] }
        var lines = [program.name]
        if let n = program.note, !n.isEmpty { lines.append(n) }
        lines.append("")
        for (i, it) in items.enumerated() {
            var line = "\(i + 1). \(it.exercise)"
            let kind = NunaExerciseKind.of(it.exercise)
            if let t = kind.targetText(sets: it.targetSets, reps: it.targetRepsLow) { line += " · " + t }
            if kind.usesWeight, let w = it.targetWeightKg { line += " · " + LiftFormat.weight(w, system: system) }
            lines.append(line)
        }
        lines.append(""); lines.append("PHMN")
        return lines.joined(separator: "\n")
    }

    /// Opens the iOS share sheet over whatever is on top.
    static func presentShare(_ text: String) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        top.present(UIActivityViewController(activityItems: [text], applicationActivities: nil), animated: true)
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
                                secondaryMuscles: p.primary == nil ? (known?.secondaryMuscles ?? []) : p.secondary, targetSets: 3,
                                note: mergedNote(nil, pinned: NunaExerciseNotes.note(forName: p.name)))
        }
        guard !plan.isEmpty else { return }
        session.start(plan: plan, programId: nil, programName: nil)
    }
}

// MARK: - Gym page

/// Gym as a page of its own, apart from the Workouts hub: three tabs (Progress, My Program, Explore) under its own header, with the banner of a running session.
struct NunaGymPage: View {
    @Environment(\.dismiss) private var dismiss
    @State private var openLive = false
    @State private var tab = 1

    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                HStack(spacing: 10) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.nuna(size: 23, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(Text("Back"))
                    Text("Gym").font(.nuna(size: 24, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    Spacer()
                }
                NunaPageTabs([(value: 0, title: "Progress"), (value: 1, title: "My Program"), (value: 2, title: "Explore")], selection: $tab)
                NunaActiveWorkoutBanner { openLive = true }
                NunaGymView(tab: $tab)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
        .background(NunaBackdrop())
        .textCase(nil)
        .toolbar(.hidden, for: .navigationBar)
        .nunaWorkoutDestinations()
        .nunaTodayDestinations()
        .navigationDestination(isPresented: $openLive) { NunaWorkoutStartView(sport: nil, resume: true) }
        .environment(\.nunaAnyaCardContext, "workouts")
    }
}

// MARK: - Gym hub (WorkoutGym.dc)

/// Gym, the middle tab of Workouts (header and scroll view come from the hub): start an empty session, run or edit a saved program, the sets each muscle group got this week and the latest
/// sessions. Reads and writes the same Lift Log tables as the Default screens, so programs and sessions are shared.
struct NunaGymView: View {
    /// The tab of the Gym page this shows: 0 Progress, 1 My Program, 2 Explore.
    @Binding var tab: Int
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var session: LiftSessionController
    @State private var programs: [LiftProgramRow] = []
    @State private var itemCounts: [String: (exercises: Int, sets: Int)] = [:]
    @State private var previews: [String: [String]] = [:]
    @EnvironmentObject private var profile: ProfileStore
    @StateObject private var anyaModel = NunaGymAnyaModel()
    @StateObject private var anyaDay = NunaTodayModel()
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @State private var deletingProgram: LiftProgramRow?
    @State private var lastUsed: [String: Int] = [:]
    @State private var history: [LiftSessionRow] = []
    @State private var weekCounts: [LiftMuscle: Double] = [:]
    @State private var readiness: [LiftMuscle: Double] = [:]
    @State private var volumes: [String: Double] = [:]
    /// Volume load (kg) of each day that had a session, by the start of the day, for the Progress chart.
    @State private var dayVolumes: [Date: Double] = [:]
    /// The heaviest set of each exercise with the day it was lifted, newest first.
    @State private var records: [(exercise: String, kg: Double, ts: Int)] = []
    @State private var volRange = 30
    @State private var volPage = 0
    /// The day whose bar is touched: its figure replaces the average at the top and the other bars step back.
    @State private var volPicked: Date?
    @State private var volTouchBeganOnPicked: Bool?
    @State private var loaded = false
    @State private var picking = false
    @State private var choosingStart = false
    @State private var buildingWithAnya = false
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
        switch tab {
        case 0:
            volumeSection
            NunaMuscleReadinessCard(readings: readiness)
            weekSection
            recordsSection
        case 1:
            NunaGymAnyaCard(model: anyaModel)
            topActions
            NunaDivider()
            programsSection
        default:
            NunaGymExploreView(embedded: true)
        }
    }

    var body: some View {
        VStack(spacing: NunaSpacing.section) { content }
        .nunaWorkoutDestinations()
        .task(id: "\(repo.refreshSeq)-\(session.savedSessions)") { await load(); await anyaModel.load(repo: repo, profile: profile, day: anyaDay) }
        // Custom exercises (typed in a picker, or brought in from Hevy) are given their muscles once per launch, in the background.
        .task { await NunaCustomExercises.syncOncePerLaunch(repo: repo, coach: appModel.coach) }
        .alert(groupDialogTitle, isPresented: Binding(get: { groupDialog != nil }, set: { if !$0 { groupDialog = nil } })) {
            TextField("Group name", text: $groupName)
            Button("Save") { saveGroupDialog() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this routine?", isPresented: Binding(get: { deletingProgram != nil }, set: { if !$0 { deletingProgram = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let p = deletingProgram { Task { await deleteProgram(p) } }; deletingProgram = nil }
            Button("Cancel", role: .cancel) { deletingProgram = nil }
        } message: { Text("Sessions you already logged from it are kept.") }
        .confirmationDialog("Delete this group?", isPresented: Binding(get: { deletingGroup != nil }, set: { if !$0 { deletingGroup = nil } }), titleVisibility: .visible) {
            Button("Delete group", role: .destructive) { if let g = deletingGroup { groupsModel.delete(g) }; deletingGroup = nil }
            Button("Cancel", role: .cancel) { deletingGroup = nil }
        } message: { Text("The programs in it are kept and become ungrouped.") }
        .sheet(isPresented: $picking) { NunaExercisePicker { picked in
            Task { await NunaGymStore.startFreehand(picked, repo: repo, session: session) }
        } }
    }

    // MARK: Start and explore

    /// One white button; what to start is chosen in the sheet it opens: a program with Anya, a ready-made program, or an empty session.
    private var topActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start a Workout").font(.nuna(size: 20, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Text("Jump right into a workout and log exercises as you go.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Button { if session.isActive { session.present() } else { choosingStart = true } } label: {
                Text(session.isActive ? "Open session" : "Quick start").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                    .background(NunaPalette.textPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $choosingStart) { startSheet }
        .sheet(isPresented: $buildingWithAnya) { NunaAnyaProgramBuilder() }
    }

    private var startSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start workout").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).padding(.top, 22).padding(.bottom, 8)
            startOption("Program with Anya", "sparkles", "Describe your goal and Anya builds the program.") {
                choosingStart = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { buildingWithAnya = true }
            }
            startOption("Explore programs", "safari", "Ready-made programs to start from.") {
                choosingStart = false
                tab = 2
            }
            startOption("Empty session", "plus", "Pick exercises as you go.") {
                choosingStart = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { picking = true }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NunaSpacing.screenH)
        .preferredColorScheme(NunaTheme.colorScheme)
        .nunaSheetChrome(detents: [.height(400)])
    }

    private func startOption(_ title: LocalizedStringKey, _ icon: String, _ detail: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.nuna(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Text(detail).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).frame(height: 76)
            .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            // The new group opens, so a program just moved into it, or the empty group just made, is the one in view.
            if let g = groupsModel.add(name: groupName) {
                if let programId { groupsModel.move(programId, to: g) }
                groupsModel.openGroupId = g.id
            }
        case .rename(let g):
            groupsModel.rename(g, to: groupName)
        }
        groupDialog = nil
    }

    private func askForGroup(_ dialog: GroupDialog) {
        if case .rename(let g) = dialog { groupName = g.name } else { groupName = "" }
        groupDialog = dialog
    }

    /// Every program is in a group: one the person made, or Ungrouped. One group shows at a time, picked from a drop-down, and the Gym tab
    /// comes back to the one that was open last.
    private var programsSection: some View {
        let open = groupsModel.openGroup
        let inGroup = open.map { groupsModel.programs(in: $0, from: programs) } ?? groupsModel.ungrouped(programs)
        let suggestion = open == nil ? groupsModel.suggestions(for: programs).first : nil
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "My Workouts") {
                HStack(spacing: 6) {
                    NavigationLink(value: NunaWorkoutRoute.program("new")) { programIcon("plus") }.buttonStyle(.plain).accessibilityLabel(Text("New program"))
                    Button { askForGroup(.new(programId: nil)) } label: { programIcon("folder.badge.plus") }.buttonStyle(.plain).accessibilityLabel(Text("New group"))
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                groupPicker(open, count: inGroup.count)
                if let suggestion { suggestionCard(suggestion) }
                if inGroup.isEmpty {
                    Text(loaded && programs.isEmpty ? "No programs yet. A program is a named list of exercises with your targets for each."
                         : open == nil ? "Every program is in a group. The ones you have not moved are here." : "Empty. Use the menu of a program to move it here.")
                        .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                ForEach(inGroup, id: \.id) { p in programRow(p) }
            }
        }
    }

    /// A bare icon at the right end of the My Program title.
    private func programIcon(_ name: String) -> some View {
        Image(systemName: name).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 40, height: 36).contentShape(Rectangle())
    }

    /// The drop-down that names the group on show, with the options of that group beside it.
    private func groupPicker(_ open: NunaProgramGroup?, count: Int) -> some View {
        HStack(spacing: 8) {
            Menu {
                Button { withAnimation(.easeInOut(duration: 0.2)) { groupsModel.openGroupId = "" } } label: {
                    if open == nil { Label(String(localized: "Ungrouped") + " (\(groupsModel.ungrouped(programs).count))", systemImage: "checkmark") }
                    else { Text(verbatim: String(localized: "Ungrouped") + " (\(groupsModel.ungrouped(programs).count))") }
                }
                ForEach(groupsModel.groups) { g in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { groupsModel.openGroupId = g.id } } label: {
                        let n = groupsModel.programs(in: g, from: programs).count
                        if open?.id == g.id { Label(g.name + " (\(n))", systemImage: "checkmark") } else { Text(verbatim: g.name + " (\(n))") }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(verbatim: open?.name ?? String(localized: "Ungrouped")).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).lineLimit(1)
                    Text(verbatim: "\(count)").font(.nuna(size: 13, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.nuna(size: 14, weight: .bold))
                }
                .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 4).frame(maxWidth: .infinity).frame(height: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Group"))
            if let open {
                Menu {
                    Button { askForGroup(.rename(open)) } label: { Label("Rename group", systemImage: "pencil") }
                    Button(role: .destructive) { deletingGroup = open } label: { Label("Delete group", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 34, height: 36).contentShape(Rectangle())
                }
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
            Button { Task { await NunaGymStore.start(program: p, repo: repo, session: session) } } label: {
                Label(session.isActive ? "Open session" : "Start", systemImage: session.isActive ? "arrow.up.forward" : "play.fill")
            }
            .disabled((itemCounts[p.id]?.exercises ?? 0) == 0)
            Divider()
            Menu {
                ForEach(groupsModel.groups) { g in
                    Button { groupsModel.move(p.id, to: g) } label: {
                        if groupsModel.group(of: p.id)?.id == g.id { Label(g.name, systemImage: "checkmark") } else { Text(verbatim: g.name) }
                    }
                }
                if groupsModel.group(of: p.id) != nil { Button { groupsModel.move(p.id, to: nil) } label: { Label("Ungrouped", systemImage: "tray") } }
                Button { askForGroup(.new(programId: p.id)) } label: { Label("New group", systemImage: "folder.badge.plus") }
            } label: { Label("Move to group", systemImage: "folder") }
            Divider()
            Button { Task { await shareProgram(p) } } label: { Label("Share routine", systemImage: "square.and.arrow.up") }
            Button { Task { _ = await NunaGymStore.duplicate(p, repo: repo) } } label: { Label("Duplicate routine", systemImage: "plus.square.on.square") }
            NavigationLink(value: NunaWorkoutRoute.programEdit(p.id)) { Label("Edit routine", systemImage: "pencil") }
            Button(role: .destructive) { deletingProgram = p } label: { Label("Delete routine", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Program options"))
    }

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    private func shareProgram(_ p: LiftProgramRow) async {
        NunaGymStore.presentShare(await NunaGymStore.shareText(p, repo: repo, system: system))
    }

    private func deleteProgram(_ p: LiftProgramRow) async {
        guard let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLiftProgram(id: p.id)
        await repo.refresh()
    }

    /// One program as a plain row inside the Programs card: its name and its menu. Tapping it opens the program; Start is in the menu.
    private func programRow(_ p: LiftProgramRow) -> some View {
        HStack(spacing: 8) {
            NavigationLink(value: NunaWorkoutRoute.program(p.id)) {
                Text(verbatim: p.name).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).frame(height: 62).contentShape(Rectangle())
            }.buttonStyle(.plain)
            programMenu(p)
        }
        .padding(.leading, 18).padding(.trailing, 8)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
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
                        HStack(alignment: .center, spacing: 12) {
                        NunaMuscleGroupThumb(group: g)
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

    // MARK: Total volume load

    private var volWindow: NunaTrendWindow { NunaTrendWindow(range: volRange, page: volPage, endingDaysAgo: 0) }

    private var volumeSection: some View {
        let w = volWindow, cal = Calendar.current
        let days: [(date: Date, kg: Double)] = (0..<volRange).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: w.start), let kg = dayVolumes[cal.startOfDay(for: d)], kg > 0 else { return nil }
            return (w.noon(d), kg)
        }
        let average: Double? = days.isEmpty ? nil : days.map(\.kg).reduce(0, +) / Double(days.count)
        let most = days.map(\.kg).max() ?? 0
        // Steps of a round size, so the axis never has more than five labels: 0 to 3,000 by 1,000 until a day goes past it.
        let step = [1000.0, 2000, 2500, 5000, 10000, 20000].first { ceil(max(most, 3000) / $0) <= 4 } ?? 20000
        let top = step * max(3, ceil(most / step))
        let ticks = stride(from: 0.0, through: top, by: step).map { $0 }
        let oldest = dayVolumes.keys.min()
        let pickedKg: Double? = volPicked.flatMap { p in days.first { cal.isDate($0.date, inSameDayAs: p) }?.kg }
        let shown = pickedKg ?? average
        let pickedTitle: String = {
            guard let p = volPicked else { return "" }
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE, MMM d")
            return f.string(from: p)
        }()
        func nearest(_ x: CGFloat, _ proxy: ChartProxy, _ frame: CGRect) -> Date? {
            guard let touched: Date = proxy.value(atX: x - frame.minX) else { return nil }
            return days.min { abs($0.date.timeIntervalSince(touched)) < abs($1.date.timeIntervalSince(touched)) }?.date
        }
        func lit(_ d: Date) -> Bool { volPicked == nil || cal.isDate(d, inSameDayAs: volPicked!) }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Total Volume Load").font(.nuna(size: 20, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: pickedKg == nil ? String(localized: "Avg. volume load") : pickedTitle).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(pickedKg == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: shown.map { nunaThousands($0) } ?? "–").font(.nuna(size: 32, weight: .semibold, design: NunaType.design))
                            .foregroundStyle(pickedKg == nil ? NunaPalette.textPrimary : NunaPalette.effortModerate)
                        if shown != nil { Text("kg").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(pickedKg == nil ? NunaPalette.textPrimary : NunaPalette.effortModerate).textCase(nil) }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 14) {
                    NunaRangeSwitch(choices: [(30, "M"), (180, "6M")], range: $volRange) { volPage = 0; volPicked = nil }
                    NunaDateStepper(label: w.label, canGoBack: oldest.map { w.start > cal.startOfDay(for: $0) } ?? false, canGoForward: volPage > 0,
                                    back: { volPage += 1; volPicked = nil }, forward: { volPage = max(0, volPage - 1); volPicked = nil })
                }
            }
            Chart {
                ForEach(days, id: \.date) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("kg", d.kg), width: .fixed(volRange == 30 ? 8 : 3))
                        .foregroundStyle(NunaPalette.effortModerate).cornerRadius(1.5).opacity(lit(d.date) ? 1 : 0.3)
                }
                if let p = volPicked, days.contains(where: { cal.isDate($0.date, inSameDayAs: p) }) {
                    RuleMark(x: .value("Picked", w.noon(p))).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            .chartYScale(domain: 0...top)
            .chartXScale(domain: w.domain)
            .chartYAxis {
                AxisMarks(position: .leading, values: ticks) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.white.opacity(0.09))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: nunaThousands(d)).font(.nuna(size: 11.5, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textMuted) } }
                }
            }
            .chartXAxis(.hidden)
            .chartPlotStyle { $0.padding(.bottom, 46) }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let frame = proxy.plotFrame.map({ geo[$0] }) {
                        ZStack {
                            ForEach(w.axisDates, id: \.self) { d in
                                if let x = proxy.position(forX: d) { w.axisLabel(d).position(x: frame.minX + x, y: frame.maxY + 25).allowsHitTesting(false) }
                            }
                            Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { g in
                                        let hit = nearest(g.location.x, proxy, frame)
                                        if volTouchBeganOnPicked == nil { volTouchBeganOnPicked = volPicked != nil && hit.map { cal.isDate($0, inSameDayAs: volPicked!) } == true }
                                        if let hit { volPicked = hit }
                                    }
                                    .onEnded { g in
                                        if volTouchBeganOnPicked == true, abs(g.translation.width) < 6 { volPicked = nil }
                                        volTouchBeganOnPicked = nil
                                    })
                        }
                    }
                }
            }
            .frame(height: 260)
            .accessibilityLabel(Text("Total Volume Load"))
        }
    }

    // MARK: Personal records

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Personal Records") { EmptyView() }
            if records.isEmpty {
                Text("Your heaviest set of each exercise shows here once you log a session.").font(.nuna(size: 13.5, weight: .semibold))
                    .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            ForEach(Array(records.prefix(5).enumerated()), id: \.offset) { _, r in
                let match = NunaExerciseLibrary.match(r.exercise)
                let row = NunaCard(small: true, padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 14)) {
                    HStack(spacing: 12) {
                        NunaExerciseThumb(match, width: 72, height: 54).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(verbatim: match?.name ?? r.exercise).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                            .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading).textCase(nil)
                        Spacer(minLength: 8)
                        // The figure and its unit sit in columns of a fixed width, so the numbers of every record end on the same line.
                        Text(verbatim: LiftFormat.trim(r.kg)).font(.nuna(size: 26, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6).frame(width: 64, alignment: .trailing)
                        Text("kg").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).frame(width: 20, alignment: .leading)
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .opacity(match == nil ? 0 : 1)
                    }
                }
                if let match {
                    NavigationLink { NunaExerciseDetailView(exerciseId: match.id, opensOnHistory: true) } label: { row }.buttonStyle(.plain)
                } else { row }
            }
        }
    }

    // MARK: Load

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        let ps = (try? await store.liftPrograms(deviceId: repo.deviceId)) ?? []
        var counts: [String: (exercises: Int, sets: Int)] = [:]
        var names: [String: [String]] = [:]
        for p in ps {
            let items = (try? await store.liftProgramItems(programId: p.id)) ?? []
            counts[p.id] = (items.count, items.reduce(0) { $0 + ($1.targetSets ?? 1) })
            names[p.id] = items.prefix(5).map(\.exercise)
        }
        let now = Int(Date().timeIntervalSince1970)
        let all = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: now - 180 * 86_400, toTs: now + 86_400)) ?? [])
            .filter { $0.endTs != nil }.sorted { $0.startTs > $1.startTs }
        var last: [String: Int] = [:]
        for s in all { if let id = s.programId, last[id] == nil { last[id] = s.startTs } }
        var vols: [String: Double] = [:]
        var perDay: [Date: Double] = [:]
        var best: [String: (kg: Double, ts: Int)] = [:]
        for s in all {
            let sets = (try? await store.liftSets(sessionId: s.id)) ?? []
            let v = LiftMetrics.volumeLoadKg(sets)
            if all.prefix(3).contains(where: { $0.id == s.id }) { vols[s.id] = v }
            if let v { perDay[Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(s.startTs))), default: 0] += v }
            for set in sets where !set.isWarmup {
                guard let w = set.weightKg, w > 0, let r = set.reps, r > 0 else { continue }
                if w > (best[set.exercise]?.kg ?? 0) { best[set.exercise] = (w, s.startTs) }
            }
        }
        dayVolumes = perDay
        records = best.map { (exercise: $0.key, kg: $0.value.kg, ts: $0.value.ts) }.sorted { $0.ts != $1.ts ? $0.ts > $1.ts : $0.exercise < $1.exercise }
        weekCounts = (try? await store.liftSetCounts(deviceId: repo.deviceId, fromTs: now - 7 * 86_400, toTs: now).fractional) ?? [:]
        // The sets of the last days, each with the time of its session, for the muscle map.
        var dated: [(set: LiftSetRow, at: Int)] = []
        for s in all where s.startTs >= now - NunaMuscleReadiness.horizonDays * 86_400 {
            for set in (try? await store.liftSets(sessionId: s.id)) ?? [] { dated.append((set, set.endTs ?? set.startTs ?? (s.endTs ?? s.startTs))) }
        }
        readiness = NunaMuscleReadiness.readings(sets: dated, now: now)
        groupsModel.prune(existing: Set(ps.map(\.id)))
        groupsModel.adoptDefaultGroup(for: ps)
        programs = ps; itemCounts = counts; previews = names; lastUsed = last; history = all; volumes = vols; loaded = true
    }
}
#endif
