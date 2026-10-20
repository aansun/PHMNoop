#if os(iOS)
import SwiftUI
import MuscleMap
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

// MARK: - Gym hub (WorkoutGym.dc)

/// Gym, the middle tab of Workouts (header and scroll view come from the hub): start an empty session, run or edit a saved program, the sets each muscle group got this week and the latest
/// sessions. Reads and writes the same Lift Log tables as the Default screens, so programs and sessions are shared.
struct NunaGymView: View {
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
    @State private var loaded = false
    /// How many weeks back the history shows; 0 is this week.
    @State private var weekOffset = 0
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
        NunaGymAnyaCard(model: anyaModel)
        topActions
        programsSection
        NunaMuscleReadinessCard(readings: readiness)
        weekSection
        sessionsSection
    }

    var body: some View {
        VStack(spacing: NunaSpacing.section) { content }
        .nunaWorkoutDestinations()
        .task(id: "\(repo.refreshSeq)-\(session.savedSessions)") { await load(); await anyaModel.load(repo: repo, profile: profile, day: anyaDay) }
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

    /// Two buttons side by side under Anya: an empty session, and the ready-made programs.
    private var topActions: some View {
        HStack(spacing: 10) {
            Button { if session.isActive { session.present() } else { picking = true } } label: {
                topActionLabel(session.isActive ? "Open session" : "Empty session", session.isActive ? "arrow.up.forward" : "plus")
            }.buttonStyle(.plain)
            NavigationLink(value: NunaWorkoutRoute.explore) { topActionLabel("Explore Program", "safari") }.buttonStyle(.plain)
        }
    }

    /// Plain words and an icon in the text colour, no fill: the two sit side by side as equals.
    private func topActionLabel(_ title: LocalizedStringKey, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.nuna(size: 14, weight: .bold))
            Text(title).font(.nuna(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 48).contentShape(Rectangle())
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
            NunaTitleRow(title: "Programs") { EmptyView() }
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    groupPicker(open, count: inGroup.count)
                    if let suggestion { suggestionCard(suggestion) }
                    if inGroup.isEmpty {
                        Text(loaded && programs.isEmpty ? "No programs yet. A program is a named list of exercises with your targets for each."
                             : open == nil ? "Every program is in a group. The ones you have not moved are here." : "Empty. Use the menu of a program to move it here.")
                            .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                    ForEach(inGroup, id: \.id) { p in programRow(p) }
                    HStack(spacing: 10) {
                        NavigationLink(value: NunaWorkoutRoute.program("new")) { programButton("New program", "plus") }.buttonStyle(.plain)
                        Button { askForGroup(.new(programId: nil)) } label: { programButton("New group", "folder.badge.plus") }.buttonStyle(.plain)
                    }
                }
            }
        }
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
                HStack(spacing: 10) {
                    Image(systemName: open == nil ? "tray" : "folder").font(.nuna(size: 16, weight: .semibold))
                    Text(verbatim: open?.name ?? String(localized: "Ungrouped")).font(.nuna(size: 17, weight: .heavy)).lineLimit(1)
                    Text(verbatim: "\(count)").font(.nuna(size: 13, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                    Image(systemName: "chevron.up.chevron.down").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(NunaPalette.textPrimary).frame(minHeight: 40).contentShape(Rectangle())
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
            Image(systemName: "ellipsis").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 36, height: 32).contentShape(Rectangle())
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

    /// One program as a tile inside the Programs card: the name with its menu at the top right, what it holds, the exercises as a
    /// muted line, and Start along the bottom. Tapping the card opens the program.
    private func programRow(_ p: LiftProgramRow) -> some View {
        let c = itemCounts[p.id]
        let empty = (c?.exercises ?? 0) == 0
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    NavigationLink(value: NunaWorkoutRoute.program(p.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: p.name).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).multilineTextAlignment(.leading)
                            Text(verbatim: String(localized: "\(c?.exercises ?? 0) exercises") + " · " + String(localized: "\(c?.sets ?? 0) sets") + " · "
                                 + (lastUsed[p.id].map { String(localized: "Last \(NunaWorkoutFormat.day($0))") } ?? String(localized: "Never run")))
                                .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
                            if let names = previews[p.id], !names.isEmpty {
                                Text(verbatim: names.joined(separator: ", ")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    programMenu(p)
                }
                Button { Task { await NunaGymStore.start(program: p, repo: repo, session: session) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: session.isActive ? "arrow.up.forward" : "play.fill").font(.nuna(size: 12, weight: .bold))
                        Text(session.isActive ? "Open" : "Start").font(.nuna(size: 15, weight: .bold))
                    }
                    .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 44)
                    .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(empty).opacity(empty ? 0.4 : 1)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: Week history

    /// Weeks run Monday to Sunday, whatever the region setting says.
    private static var weekCalendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4
        return c
    }

    private var weekStart: Date {
        let cal = Self.weekCalendar
        let monday = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
        return cal.date(byAdding: .weekOfYear, value: weekOffset, to: monday) ?? monday
    }

    private var weekSessions: [LiftSessionRow] {
        let cal = Self.weekCalendar
        let start = Int(weekStart.timeIntervalSince1970)
        let end = Int((cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart).timeIntervalSince1970)
        return history.filter { $0.startTs >= start && $0.startTs < end }
    }

    private var weekTitle: String {
        let cal = Self.weekCalendar
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM")
        let last = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return weekOffset == 0 ? String(localized: "This week") + " · " + f.string(from: weekStart) + " – " + f.string(from: last)
                               : f.string(from: weekStart) + " – " + f.string(from: last)
    }

    /// The week as seven days from Monday, a dot under the days with a session, and the sessions of that week below. The arrows go to the weeks before.
    private var sessionsSection: some View {
        let cal = Self.weekCalendar
        let sessions = weekSessions
        let letter = DateFormatter(); letter.locale = AppLanguage.activeLocale; letter.setLocalizedDateFormatFromTemplate("EEEEE")
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "History") {
                NavigationLink(value: NunaWorkoutRoute.history) { Text("All").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }
            }
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 4) {
                        Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").font(.nuna(size: 13, weight: .bold)).frame(width: 36, height: 34).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityLabel(Text("Previous week"))
                        Text(verbatim: weekTitle).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
                        Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).frame(width: 36, height: 34).contentShape(Rectangle()) }
                            .buttonStyle(.plain).disabled(weekOffset >= 0).opacity(weekOffset >= 0 ? 0.3 : 1).accessibilityLabel(Text("Next week"))
                    }.foregroundStyle(NunaPalette.textPrimary)
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            let day = cal.date(byAdding: .day, value: i, to: weekStart) ?? weekStart
                            let trained = sessions.contains { cal.isDate(Date(timeIntervalSince1970: TimeInterval($0.startTs)), inSameDayAs: day) }
                            let today = cal.isDateInToday(day)
                            VStack(spacing: 6) {
                                Text(verbatim: letter.string(from: day)).font(.nuna(size: 11, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary).textCase(.uppercase)
                                Text(verbatim: "\(cal.component(.day, from: day))").font(.nuna(size: 15, weight: .bold, design: NunaType.design))
                                    .foregroundStyle(today ? NunaPalette.onAccent : NunaPalette.textPrimary)
                                    .frame(width: 32, height: 32).background(today ? NunaPalette.accent : Color.clear, in: Circle())
                                Circle().fill(trained ? NunaPalette.charge : Color.clear).frame(width: 6, height: 6)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                    if sessions.isEmpty {
                        Text("No gym sessions this week").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                        NunaDivider()
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
        for s in all.prefix(3) { vols[s.id] = LiftMetrics.volumeLoadKg((try? await store.liftSets(sessionId: s.id)) ?? []) }
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
