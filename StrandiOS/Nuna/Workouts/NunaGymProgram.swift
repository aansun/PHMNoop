#if os(iOS)
import SwiftUI
import Charts
import UniformTypeIdentifiers
import StrandDesign
import StrandAnalytics
import StrandImport
import WhoopStore

private func nunaPill(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(verbatim: title).font(.nuna(size: 13.5, weight: .bold))
            .foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
            .padding(.horizontal, 14).frame(height: 38)
            .background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: on ? 0 : 1))
    }.buttonStyle(.plain)
}

extension LiftProgramItemRow: Identifiable {}

private struct NunaItemTarget: Identifiable { let id: String; let item: LiftProgramItemRow? }

// MARK: - Program editor (WorkoutProgram.dc)

/// Name, note and ordered exercise lines of one program. `programId == "new"` creates one. The lines are drafted locally
/// and written together on Save, the same way the Default editor does, so history is never rewritten.
struct NunaProgramEditor: View {
    let programId: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @State private var program: LiftProgramRow?
    @State private var name = ""
    @State private var note = ""
    @State private var items: [LiftProgramItemRow] = []
    @State private var loaded = false
    @State private var saving = false
    @State private var editing: NunaItemTarget?
    @State private var replacing: LiftProgramItemRow?
    @State private var picking = false
    @State private var demo: NunaLibraryExercise?
    @State private var video: String?
    @State private var noteFor: String?
    @State private var noteDraft = ""
    @State private var confirmDelete = false

    private var isNew: Bool { programId == "new" }
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving }
    private var totalSets: Int { items.reduce(0) { $0 + ($1.targetSets ?? 1) } }
    /// A rough length: each set takes about 45 seconds plus the planned rest.
    private var estimatedMinutes: Int {
        let secs = items.reduce(0) { $0 + ($1.targetSets ?? 1) * (45 + ($1.restSec ?? LiftPlanItem.defaultRestSec)) }
        return Int((Double(secs) / 60).rounded())
    }

    var body: some View {
        NunaDetailScreen(isNew ? "New program" : "Edit program", trailing: AnyView(saveButton), centersTitle: true) {
            summaryCard
            // What the person wrote keeps its own capitals, in a look that sets labels in capitals.
            NunaFormField("Name") { TextField("", text: $name, prompt: Text("Push · chest, shoulders, triceps").foregroundStyle(NunaPalette.textMuted)).textCase(nil) }
            NunaFormField("Note") {
                TextField("", text: $note, prompt: Text("Anything you want to remember").foregroundStyle(NunaPalette.textMuted), axis: .vertical).lineLimit(1...4)
                    .onChange(of: note) { new in if new.count > WhoopStore.maxProgramNoteLength { note = String(new.prefix(WhoopStore.maxProgramNoteLength)) } }
                    .textCase(nil)
            }
            NunaTitleRow(title: "Exercises") { EmptyView() }
            exercises
            Text("Every target is optional: this is the plan, not the record. What you lift is entered during the session. Sessions already logged from this program are kept.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
            if !isNew {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Text("Delete program").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                        .frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .nunaKeyboardDone()
        .task { await loadIfNeeded() }
        .sheet(item: $editing) { t in
            NunaProgramItemView(item: t.item) { saved in apply(saved, replacing: t.item) }
        }
        .sheet(isPresented: $picking) {
            NunaExercisePicker(confirm: { $0 == 1 ? String(localized: "Add 1 exercise") : String(localized: "Add \($0) exercises") }, title: "Add exercise") { picked in addPicked(picked) }
        }
        .sheet(item: $demo) { e in
            NavigationStack { NunaExerciseDetailView(exerciseId: e.id) }.preferredColorScheme(NunaTheme.colorScheme).presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(get: { video.map { NunaVideoTarget(name: $0) } }, set: { video = $0?.name })) { t in NunaExerciseVideoSheet(name: t.name) }
        .alert("Note for this exercise", isPresented: Binding(get: { noteFor != nil }, set: { if !$0 { noteFor = nil } })) {
            TextField("Technique, grip, cues", text: $noteDraft)
            Button("Save") { if let id = noteFor { let t = String(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(WhoopStore.maxExerciseNoteLength)); update(id) { $0.note = t.isEmpty ? nil : t } }; noteFor = nil }
            Button("Cancel", role: .cancel) { noteFor = nil }
        }
        .sheet(item: $replacing) { old in
            NunaExercisePicker(title: "Replace exercise", single: true, suggestingFor: old.exercise) { picked in
                guard let p = picked.first, let i = items.firstIndex(where: { $0.id == old.id }) else { return }
                var next = items[i]
                next.exercise = p.name
                items[i] = next
            }
        }
        .nunaDialog("Delete this program?", isPresented: $confirmDelete) {
            NunaDialogButton("Delete", role: .destructive) { Task { await deleteProgram() } }
            NunaDialogButton("Cancel", role: .cancel) {}
        } message: { Text("Sessions you already logged from it are kept.") }
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            Text("Save").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                .padding(.horizontal, 20).frame(height: 44).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain).disabled(!canSave).opacity(canSave ? 1 : 0.4)
    }

    /// The exercises as cards, the way an exercise reads in a finished session: its picture and name with the menu at the top right, the rest
    /// and a note as chips, and the target. Adding opens the library to choose from, and a new exercise lands here with a starting target.
    @ViewBuilder private var exercises: some View {
        if items.isEmpty {
            NunaCard(small: true) {
                Text("No exercises yet. Add the first one below.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        ForEach(items) { item in exerciseCard(item) }
        Button { picking = true } label: {
            HStack(spacing: 8) { Image(systemName: "plus").font(.nuna(size: 14, weight: .bold)); Text("Add exercise").font(.nuna(size: 15, weight: .bold)) }
                .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 52)
                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func index(of id: String) -> Int? { items.firstIndex { $0.id == id } }

    private func exerciseCard(_ item: LiftProgramItemRow) -> some View {
        let kind = NunaExerciseKind.of(item.exercise)
        let lib = NunaExerciseLibrary.match(item.exercise)
        let i = index(of: item.id) ?? 0
        let known = lib?.liftPrimary.map { LiftMuscleSummary.line(primary: $0, secondaries: lib?.liftSecondary ?? []) }
        return NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Button { if let lib { demo = lib } else { video = item.exercise } } label: { NunaExerciseThumb(lib, width: 58, height: 44) }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: item.exercise).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).multilineTextAlignment(.leading).textCase(nil)
                        if let known { Text(verbatim: known).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1) }
                        else { Text("Choose its muscles in the menu").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).textCase(nil) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    exerciseMenu(item, index: i, lib: lib)
                }
                HStack(spacing: 8) {
                    NunaMenu {
                        ForEach([30, 45, 60, 90, 120, 150, 180, 240], id: \.self) { secs in
                            NunaMenuItem(verbatim: LiftFormat.duration(secs), selected: secs == (item.restSec ?? LiftPlanItem.defaultRestSec)) { setRest(item.id, secs) }
                        }
                    } label: { chip("timer", String(localized: "Rest: \(LiftFormat.duration(item.restSec ?? LiftPlanItem.defaultRestSec))")) }
                    Button { noteDraft = item.note ?? ""; noteFor = item.id } label: { chip("note.text", item.note.flatMap { $0.isEmpty ? nil : String(localized: "Note") } ?? String(localized: "Add note")) }
                        .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                let pinned = NunaExerciseNotes.note(forName: item.exercise)
                if let note = item.note, !note.isEmpty {
                    Text(verbatim: note).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(3)
                }
                if !pinned.isEmpty {
                    Label { Text(verbatim: pinned).textCase(nil) } icon: { Image(systemName: "pin.fill") }
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).lineLimit(2)
                }
                NunaDivider()
                targetRow(item.id, kind: kind)
            }
        }
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.nuna(size: 13, weight: .semibold))
            Text(verbatim: text).font(.nuna(size: 13.5, weight: .bold)).textCase(nil)
        }
        .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 12).frame(height: 34)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
    }

    private func exerciseMenu(_ item: LiftProgramItemRow, index i: Int, lib: NunaLibraryExercise?) -> some View {
        NunaMenu {
            if let lib { NunaMenuItem("Show the demo", icon: "play.rectangle") { demo = lib } }
            else { NunaMenuItem("Watch a video", icon: "play.rectangle") { video = item.exercise } }
            NunaMenuItem("Replace exercise", icon: "arrow.triangle.2.circlepath") { replacing = item }
            if NunaExerciseKind.natural(item.exercise) == .bodyweight {
                let tracks = NunaExerciseKind.weightOverrides.contains(item.exercise)
                NunaMenuItem(tracks ? "Bodyweight only" : "Add weight", icon: tracks ? "figure.stand" : "scalemass") { NunaExerciseKind.setTracksWeight(!tracks, for: item.exercise); items = items }
            }
            NunaMenuItem("Muscles and technique", icon: "figure.strengthtraining.traditional") { editing = NunaItemTarget(id: item.id, item: item) }
            NunaMenuGap()
            NunaMenuItem("Move up", icon: "arrow.up") { move(i, -1) }.disabled(i == 0)
            NunaMenuItem("Move down", icon: "arrow.down") { move(i, 1) }.disabled(i == items.count - 1)
            NunaMenuItem("Remove exercise", icon: "trash", role: .destructive) { items.removeAll { $0.id == item.id } }
        } label: {
            Image(systemName: "ellipsis").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 36, height: 34).contentShape(Rectangle())
        }
        .accessibilityLabel(Text("More"))
    }

    /// The target of the exercise: how many sets, and weight and a rep range, reps alone, or a time, by how the exercise is logged. It is one
    /// target for every set of the exercise.
    private func targetRow(_ id: String, kind: NunaExerciseKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    heading("Sets")
                    HStack(spacing: 0) {
                        stepper("minus") { changeSets(id, -1) }
                        Text(verbatim: "\(items.first { $0.id == id }?.targetSets ?? 0)").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(maxWidth: .infinity)
                        stepper("plus") { changeSets(id, 1) }
                    }
                    .frame(height: 44).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.frame(maxWidth: .infinity)
                if kind.usesWeight {
                    VStack(alignment: .leading, spacing: 6) {
                        heading(system == .imperial ? "Weight (lb)" : "Weight (kg)")
                        NunaTargetField(prompt: "70", keyboard: .decimalPad,
                                        get: { items.first { $0.id == id }?.targetWeightKg.map { LiftFormat.trim(LiftFormat.display(fromKilograms: $0, system: system)) } ?? "" },
                                        set: { t in update(id) { $0.targetWeightKg = LiftFormat.number(t).map { LiftFormat.kilograms(fromDisplay: $0, system: system) } } })
                    }.frame(maxWidth: .infinity)
                }
            }
            if kind == .timed {
                VStack(alignment: .leading, spacing: 6) {
                    heading("Time (mm:ss)")
                    NunaTargetField(prompt: "00:30", keyboard: .numbersAndPunctuation,
                                    get: { items.first { $0.id == id }?.targetRepsLow.map(NunaExerciseKind.clock) ?? "" },
                                    set: { t in update(id) { $0.targetRepsLow = NunaExerciseKind.seconds(from: t); $0.targetRepsHigh = nil } })
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    heading("Rep range")
                    HStack(spacing: 8) {
                        NunaTargetField(prompt: "8", keyboard: .numberPad,
                                        get: { items.first { $0.id == id }?.targetRepsLow.map(String.init) ?? "" },
                                        set: { t in update(id) { $0.targetRepsLow = Int(t.trimmingCharacters(in: .whitespaces)) } })
                        Text("to").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        NunaTargetField(prompt: "12", keyboard: .numberPad,
                                        get: { items.first { $0.id == id }?.targetRepsHigh.map(String.init) ?? "" },
                                        set: { t in update(id) { $0.targetRepsHigh = Int(t.trimmingCharacters(in: .whitespaces)) } })
                    }
                }
            }
        }
    }

    private func heading(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
    }

    private func stepper(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func update(_ id: String, _ change: (inout LiftProgramItemRow) -> Void) {
        guard let i = index(of: id) else { return }
        var row = items[i]; change(&row); items[i] = row
    }

    private func changeSets(_ id: String, _ by: Int) {
        update(id) { $0.targetSets = min(LiftSessionEngine.maxSetsPerExercise, max(1, ($0.targetSets ?? 1) + by)) }
    }

    private func setRest(_ id: String, _ secs: Int) { update(id) { $0.restSec = secs } }

    /// Exercises chosen in the library come in with a starting target: three sets, ten reps (a hold of 30 seconds), 90 seconds of rest.
    private func addPicked(_ picked: [NunaPickedExercise]) {
        for p in picked where !p.name.isEmpty {
            let kind = NunaExerciseKind.of(p.name)
            items.append(LiftProgramItemRow(id: UUID().uuidString, deviceId: repo.deviceId, programId: "", ord: items.count, exercise: p.name, targetSets: 3,
                                            targetRepsLow: kind == .timed ? 30 : 10, targetRepsHigh: nil, targetRpe: nil, targetWeightKg: nil, restSec: 90, note: nil))
        }
        // The muscles of the exercises that came with them are remembered, so the weekly sets per muscle count them.
        Task {
            guard let store = await repo.storeHandle() else { return }
            let now = Int(Date().timeIntervalSince1970)
            let known = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
            for p in picked where p.primary != nil && !known.contains(where: { $0.name == p.name }) {
                let row = LiftExerciseRow(id: UUID().uuidString, deviceId: repo.deviceId, name: p.name, primaryMuscle: p.primary,
                                          secondaryMuscles: p.secondary.filter { $0 != p.primary }, createdAt: now, lastUsedTs: now)
                _ = try? await store.upsertLiftExercises([row])
            }
            // An exercise of the person's own gets a page and a history like any library exercise, and Anya fills in its muscles if it has none.
            await NunaCustomExercises.remember(picked, repo: repo, coach: model.coach)
        }
    }

    private var summaryCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Program summary")
                HStack {
                    tile("Exercises", "\(items.count)", nil)
                    tile("Sets", "\(totalSets)", nil)
                    tile("Estimated", "\(estimatedMinutes)", String(localized: "min"))
                }
            }
        }
    }

    private func tile(_ l: LocalizedStringKey, _ v: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: v).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                if let unit { Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "70 kg · rest 90 s": only what was filled in.
    private func detail(_ item: LiftProgramItemRow) -> String {
        var parts: [String] = []
        if NunaExerciseKind.of(item.exercise).usesWeight, let kg = item.targetWeightKg { parts.append(LiftFormat.weight(kg, system: system)) }
        if let rest = item.restSec { parts.append(String(localized: "rest \(rest) s")) }
        if parts.isEmpty, item.targetSets == nil { parts.append(String(localized: "No targets set")) }
        let pinned = NunaExerciseNotes.note(forName: item.exercise)
        if !pinned.isEmpty { parts.append("📌 " + pinned) }
        return parts.joined(separator: " · ")
    }

    private func move(_ i: Int, _ by: Int) {
        let j = i + by
        guard items.indices.contains(i), items.indices.contains(j) else { return }
        withAnimation { items.swapAt(i, j) }
    }

    private func apply(_ saved: LiftProgramItemRow, replacing old: LiftProgramItemRow?) {
        guard let old, let i = items.firstIndex(where: { $0.id == old.id }) else { items.append(saved); return }
        items[i] = saved
    }

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        guard !isNew, let store = await repo.storeHandle() else { return }
        program = ((try? await store.liftPrograms(deviceId: repo.deviceId)) ?? []).first { $0.id == programId }
        name = program?.name ?? ""; note = program?.note ?? ""
        items = (try? await store.liftProgramItems(programId: programId)) ?? []
    }

    private func save() async {
        guard canSave, let store = await repo.storeHandle() else { return }
        saving = true; defer { saving = false }
        let now = Int(Date().timeIntervalSince1970)
        let id = isNew ? UUID().uuidString : programId
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try? await store.upsertLiftPrograms([LiftProgramRow(id: id, deviceId: repo.deviceId, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                note: trimmed.isEmpty ? nil : trimmed, createdAt: program?.createdAt ?? now, updatedAt: now, archived: program?.archived ?? false)])
        let ordered = items.enumerated().map { i, it in
            LiftProgramItemRow(id: it.id, deviceId: repo.deviceId, programId: id, ord: i, exercise: it.exercise, targetSets: it.targetSets,
                               targetRepsLow: it.targetRepsLow, targetRepsHigh: it.targetRepsHigh, targetRpe: it.targetRpe,
                               targetWeightKg: it.targetWeightKg, restSec: it.restSec, note: it.note)
        }
        _ = try? await store.replaceLiftProgramItems(programId: id, items: ordered)
        if isNew { NunaProgramGroupsModel.shared.placeNew(id) }
        await repo.refresh()
        dismiss()
    }

    private func deleteProgram() async {
        guard !isNew, let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLiftProgram(id: programId)
        await repo.refresh()
        dismiss()
    }
}

/// One finished run of a program, for its progress chart.
struct NunaProgramRun { let date: Date; let volumeKg: Double; let reps: Int; let minutes: Double }

// MARK: - Program page

/// A program as it is opened from the Gym list or a shortcut, laid out like a workout in Explore: the photo with its name and numbers, then how the runs of it
/// have gone (volume or duration, over a week or six months), what it works and its exercises, with Start at the bottom and the menu at the top right for
/// editing or deleting. Editing is its own screen, reached from the menu.
struct NunaProgramDetailView: View {
    let programId: String
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var session: LiftSessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nunaPushWorkout) private var pushWorkout
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @State private var program: LiftProgramRow?
    @State private var items: [LiftProgramItemRow] = []
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var starting = false
    @State private var runs: [NunaProgramRun] = []
    /// 7 days or 30 days a bar each, or 180 days a bar for each week.
    @State private var span = 7
    /// The bar that is touched: its figure replaces the total at the top and the other bars step back.
    @State private var picked: Date?
    @State private var touchBeganOnPicked: Bool?
    /// The exercise whose movement is open in a sheet, so it can be seen before the session starts.
    @State private var preview: String?

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    /// The program as an Explore workout, which gives the numbers, the muscles, the equipment and a photo that fits what it works. A program saved from
    /// Explore keeps the photo it was saved with.
    private var asWorkout: NunaExploreWorkout? {
        guard let program else { return nil }
        let moves = items.map { NunaStarterProgram.Move(name: $0.exercise, sets: $0.targetSets ?? 1, reps: $0.targetRepsLow, rest: $0.restSec ?? LiftPlanItem.defaultRestSec) }
        let probe = NunaStarterProgram(id: programId, name: program.name, level: .medium, goal: .muscle, equipment: .gym, routines: [.init(name: program.name, moves: moves)])
        let equipment: NunaStarterProgram.Equipment = NunaExploreWorkout(program: probe, routine: probe.routines[0]).equipmentText == String(localized: "Body weight") ? .none : .gym
        let real = NunaStarterProgram(id: programId, name: program.name, level: .medium, goal: .muscle, equipment: equipment, routines: probe.routines)
        return NunaExploreWorkout(program: real, routine: real.routines[0])
    }

    private var image: String {
        if let program, let match = NunaExploreWorkout.all(of: NunaStarterPrograms.all).first(where: { $0.title == program.name }) { return match.image }
        return asWorkout?.image ?? "ExplorePlates"
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let program, let w = asWorkout {
                        NunaWorkoutHero(image: image, title: dayName(program.name), byline: planName(program.name).map { Text(verbatim: $0) } ?? Text("My program"),
                                        stats: [("\(w.minutes)", "min", "Est duration"), ("\(items.count)", nil, "Exercises"), ("\(w.totalSets)", nil, "Total sets")])
                        VStack(alignment: .leading, spacing: NunaSpacing.section) {
                            if !items.isEmpty { aboutCard(equipment: w.equipmentText, muscles: w.groupsText) }
                            if let note = program.note, !note.isEmpty { noteCard(note) }
                            progressCard
                            exerciseList.padding(.top, 8)
                        }
                        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 130)
                    } else if loaded {
                        Text("This program is no longer there.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 120)
                    }
                }
            }
            .scrollIndicators(.hidden).ignoresSafeArea(edges: .top)
            topBar
        }
        .background(NunaBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: repo.refreshSeq) { await load() }
        .sheet(item: Binding(get: { preview.map { NunaVideoTarget(name: $0) } }, set: { preview = $0?.name })) { t in NunaExercisePreviewSheet(name: t.name) }
        .safeAreaInset(edge: .bottom, spacing: 0) { startBar }
        .nunaDialog("Delete this program?", isPresented: $confirmDelete) {
            NunaDialogButton("Delete", role: .destructive) { Task { await deleteProgram() } }
            NunaDialogButton("Cancel", role: .cancel) {}
        } message: { Text("Sessions you already logged from it are kept.") }
    }

    private var topBar: some View {
        ZStack {
            HStack {
                Button { dismiss() } label: {
                    // The whole 48 pt square takes the touch, not only the thin strokes of the arrow.
                    Image(systemName: "chevron.left").font(.nuna(size: 22, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 48, height: 48).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(Text("Back"))
                Spacer()
                menu
            }
            Text("Program gym").font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                .accessibilityAddTraits(.isHeader).allowsHitTesting(false)
        }
        .padding(.horizontal, NunaSpacing.screenH - 8).padding(.top, 8)
        .zIndex(1)
    }

    private var menu: some View {
        NunaMenu {
            NunaMenuItem("Share routine", icon: "square.and.arrow.up") { Task { if let program { NunaGymStore.presentShare(await NunaGymStore.shareText(program, repo: repo, system: system)) } } }
            NunaMenuItem("Duplicate routine", icon: "plus.square.on.square") { Task { if let program { _ = await NunaGymStore.duplicate(program, repo: repo); dismiss() } } }
            NunaMenuItem("Edit program", icon: "pencil") { pushWorkout(.programEdit(programId)) }
            NunaMenuItem("Delete program", icon: "trash", role: .destructive) { confirmDelete = true }
        } label: { Image(systemName: "ellipsis").font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44).contentShape(Rectangle()) }
        .accessibilityLabel(Text("Program menu"))
    }

    /// A program Anya saved is named "plan · day". The day is what tells it from its siblings, so it is the title and the plan goes under it.
    private func dayName(_ name: String) -> String {
        let parts = name.components(separatedBy: " · ")
        return parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : name
    }

    private func planName(_ name: String) -> String? {
        let parts = name.components(separatedBy: " · ")
        return parts.count > 1 ? parts[0] : nil
    }

    /// What the program needs and works, as the rows under a score are drawn.
    private func aboutCard(equipment: String, muscles: String) -> some View {
        NunaCard {
            VStack(spacing: 0) {
                about("dumbbell", "Equipment", equipment)
                NunaDivider()
                about("figure.strengthtraining.traditional", "Muscle groups", muscles)
            }
        }
    }

    private func about(_ icon: String, _ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: value).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func noteCard(_ note: String) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Note").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: note).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
    }

    // MARK: Progress

    /// One bar of the chart: a day in the week view, a week in the six-month view.
    private struct Bucket { let date: Date; let value: Double }

    private func volume(_ r: NunaProgramRun) -> Double { LiftFormat.display(fromKilograms: r.volumeKg, system: system) }

    private var unit: Calendar.Component { span == 180 ? .weekOfYear : .day }

    /// Where the chart starts and ends, and the bars with something in them.
    private func buckets() -> (start: Date, end: Date, bars: [Bucket]) {
        let cal = Calendar.current
        let today = Date()
        let thisBucket = cal.dateInterval(of: unit, for: today)?.start ?? cal.startOfDay(for: today)
        let start: Date
        switch span {
        case 7: start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: today)) ?? thisBucket
        case 30: start = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: today)) ?? thisBucket
        default: start = cal.date(byAdding: .weekOfYear, value: -25, to: thisBucket) ?? thisBucket
        }
        let end = cal.date(byAdding: unit, value: 1, to: thisBucket) ?? today
        var sums: [Date: Double] = [:]
        for r in runs where r.date >= start && r.date < end {
            guard let key = cal.dateInterval(of: unit, for: r.date)?.start else { continue }
            sums[key, default: 0] += volume(r)
        }
        return (start, end, sums.filter { $0.value > 0 }.map { Bucket(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date })
    }

    @ViewBuilder private var progressCard: some View {
        if runs.isEmpty {
            // Nothing to draw yet: a line, not an empty chart with its switch.
            if loaded {
                NunaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        NunaWeeklyTitle(title: "Progress", opens: false)
                        Text("Run this routine a couple of times and its progress shows here.").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
            }
        } else { NunaCard { chartCard } }
    }

    /// The volume the runs of this routine added up to, a bar a day over a week or a month and a bar a week over six months, as the heart rate variability page draws
    /// its days: the total at the top until a bar is touched, then that bar's day and figure, with the others stepping back.
    private var chartCard: some View {
        let cal = Calendar.current
        let b = buckets()
        let total = b.bars.map(\.value).reduce(0, +)
        let touched = picked.flatMap { p in b.bars.first { cal.isDate($0.date, equalTo: p, toGranularity: unit) } }
        let shown = touched?.value ?? total
        let color = NunaPalette.effortModerate
        let caption: String = {
            guard let t = touched else { return String(localized: "Total") }
            let df = DateFormatter(); df.locale = AppLanguage.activeLocale
            df.setLocalizedDateFormatFromTemplate(span == 180 ? "MMM d" : "EEE, MMM d")
            return span == 180 ? String(localized: "Week of \(df.string(from: t.date))") : df.string(from: t.date)
        }()
        let top = b.bars.map(\.value).max() ?? 0
        func nearest(_ x: CGFloat, _ proxy: ChartProxy, _ frame: CGRect) -> Date? {
            guard let at: Date = proxy.value(atX: x - frame.minX) else { return nil }
            return b.bars.min { abs($0.date.timeIntervalSince(at)) < abs($1.date.timeIntervalSince(at)) }?.date
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: caption).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(touched == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: b.bars.isEmpty ? "–" : NunaTrendsFormat.num(shown)).font(.nuna(size: 40, weight: .semibold, design: NunaType.design))
                            .foregroundStyle(touched == nil ? NunaPalette.textPrimary : color)
                        if !b.bars.isEmpty {
                            Text(verbatim: UnitFormatter.massUnit(system)).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(touched == nil ? NunaPalette.textPrimary : color).textCase(nil)
                        }
                    }
                }
                Spacer(minLength: 0)
                NunaRangeSwitch(range: $span) { picked = nil }
            }
            Chart {
                ForEach(b.bars, id: \.date) { bar in
                    BarMark(x: .value("Date", bar.date, unit: unit), y: .value("Volume", bar.value), width: .ratio(span == 7 ? 0.5 : (span == 30 ? 0.6 : 0.7)))
                        .foregroundStyle(color).cornerRadius(3).opacity(touched == nil || touched?.date == bar.date ? 1 : 0.3)
                }
                if let t = touched {
                    RuleMark(x: .value("Picked", t.date, unit: unit)).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            .chartXScale(domain: b.start...b.end)
            .chartYScale(domain: 0...max(top * 1.15, 1))
            .chartXAxis {
                switch span {
                case 7: AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true).foregroundStyle(NunaPalette.textMuted) }
                case 30: AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(NunaPalette.textMuted) }
                default: AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(NunaPalette.textMuted) }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(NunaPalette.textMuted.opacity(0.25))
                    AxisValueLabel().foregroundStyle(NunaPalette.textMuted)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let frame = proxy.plotFrame.map({ geo[$0] }) {
                        Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { g in
                                    let hit = nearest(g.location.x, proxy, frame)
                                    if touchBeganOnPicked == nil { touchBeganOnPicked = picked != nil && hit.map { cal.isDate($0, equalTo: picked!, toGranularity: unit) } == true }
                                    if let hit { picked = hit }
                                }
                                .onEnded { g in
                                    if touchBeganOnPicked == true, abs(g.translation.width) < 6 { picked = nil }
                                    touchBeganOnPicked = nil
                                })
                    }
                }
            }
            .frame(height: 200)
            .accessibilityLabel(Text("Volume"))
            if b.bars.isEmpty {
                Text("No runs of this routine in this period.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Exercises

    @ViewBuilder private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Exercises").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Rectangle().fill(NunaPalette.hairlineSoft).frame(height: 1)
            }
            if items.isEmpty {
                Text("No exercises yet. Choose Edit program to add some.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            ForEach(items, id: \.id) { item in
                Button { preview = item.exercise } label: {
                    HStack(spacing: 14) {
                        NunaExerciseThumb(name: item.exercise, width: 70, height: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: item.exercise).font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(2).multilineTextAlignment(.leading)
                            if !detail(item).isEmpty { Text(verbatim: detail(item)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                        }
                        Spacer(minLength: 8)
                        if let s = item.targetSets {
                            Text(verbatim: NunaExerciseKind.of(item.exercise).targetText(sets: s, reps: item.targetRepsLow, upTo: item.targetRepsHigh) ?? "\(s)").font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6).padding(.trailing, 8)
                    .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityHint(Text("Shows how the exercise is done"))
            }
        }
    }

    private func detail(_ item: LiftProgramItemRow) -> String {
        var parts: [String] = []
        if NunaExerciseKind.of(item.exercise).usesWeight, let kg = item.targetWeightKg { parts.append(LiftFormat.weight(kg, system: system)) }
        if let rest = item.restSec { parts.append(String(localized: "rest \(rest) s")) }
        return parts.joined(separator: " · ")
    }

    private var startBar: some View {
        let running = session.isActive
        let off = program == nil || (items.isEmpty && !running) || starting
        return Button { Task { await start() } } label: {
            HStack(spacing: 8) {
                Image(systemName: running ? "arrow.up.forward" : "play.fill").font(.nuna(size: 14, weight: .bold))
                Text(running ? "Open the running session" : "Start").font(.nuna(size: 17, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
            }
            .foregroundStyle(NunaPalette.accent).frame(maxWidth: .infinity).frame(height: 58)
            .background(NunaPalette.canvas, in: Capsule())
            .overlay(Capsule().strokeBorder(NunaPalette.accent, lineWidth: 2))
        }
        .buttonStyle(.plain).disabled(off).opacity(off ? 0.4 : 1)
        .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 10)
        .background(LinearGradient(colors: [NunaPalette.canvas.opacity(0), NunaPalette.canvas], startPoint: .top, endPoint: .init(x: 0.5, y: 0.4)))
    }

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        program = ((try? await store.liftPrograms(deviceId: repo.deviceId)) ?? []).first { $0.id == programId }
        items = (try? await store.liftProgramItems(programId: programId)) ?? []
        // Every finished run of this program, oldest first, with what it added up to.
        let now = Int(Date().timeIntervalSince1970)
        let sessions = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: 0, toTs: now + 86_400)) ?? [])
            .filter { $0.programId == programId && $0.endTs != nil }.sorted { $0.startTs < $1.startTs }
        var out: [NunaProgramRun] = []
        for s in sessions {
            let sets = ((try? await store.liftSets(sessionId: s.id)) ?? [])
            let working = sets.filter { !$0.isWarmup }
            out.append(NunaProgramRun(date: Date(timeIntervalSince1970: TimeInterval(s.startTs)), volumeKg: LiftMetrics.volumeLoadKg(sets) ?? 0,
                                      reps: working.compactMap(\.reps).reduce(0, +), minutes: Double(max(0, (s.endTs ?? s.startTs) - s.startTs)) / 60))
        }
        runs = out
        loaded = true
    }

    private func start() async {
        guard let program else { return }
        starting = true; defer { starting = false }
        await NunaGymStore.start(program: program, repo: repo, session: session)
    }

    private func deleteProgram() async {
        guard let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLiftProgram(id: programId)
        await repo.refresh()
        dismiss()
    }
}

// MARK: - One exercise line (WorkoutProgramItem.dc)

/// Which exercise and the targets for it, plus the muscles it counts towards. Opens as a sheet from the program editor.
struct NunaProgramItemView: View {
    let item: LiftProgramItemRow?
    let onSave: (LiftProgramItemRow) -> Void
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @State private var exercise = ""
    @State private var primary: LiftMuscle?
    @State private var primaryGroup: NunaMuscleGroup?
    @State private var secondaries: Set<LiftMuscle> = []
    @State private var setsText = ""
    @State private var repsText = ""
    @State private var timeText = ""
    @State private var weightText = ""
    @State private var restText = ""
    @State private var note = ""
    @State private var vocabulary: [LiftExerciseRow] = []
    @State private var loaded = false
    @State private var forgetting: LiftExerciseRow?
    @State private var vocabularyFull = false
    @State private var choosingFromLibrary = false

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var trimmed: String { exercise.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty }
    /// How the exercise is logged: weight and reps, reps alone, or a time. The target fields follow it.
    private var kind: NunaExerciseKind { NunaExerciseKind.of(trimmed) }
    private var suggestions: [LiftExerciseRow] {
        let q = trimmed.lowercased()
        guard !q.isEmpty else { return Array(vocabulary.prefix(8)) }
        return vocabulary.filter { $0.name.lowercased().contains(q) && $0.name.lowercased() != q }.prefix(8).map { $0 }
    }

    var body: some View {
        NavigationStack {
            NunaDetailScreen("Exercise", trailing: AnyView(saveButton)) {
                Button { choosingFromLibrary = true } label: {
                    HStack(spacing: 12) {
                        NunaExerciseThumb(name: trimmed, width: 50, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose from the library").font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.restText)
                            Text("876 exercises with a demo and the muscles each works").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    .padding(12).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(.plain)
                NunaFormField("Exercise name") { TextField("", text: $exercise, prompt: Text("Incline dumbbell press").foregroundStyle(NunaPalette.textMuted)).autocorrectionDisabled() }
                if !suggestions.isEmpty { usedBefore }
                primaryCard
                secondaryCard
                targetsCard
                NunaFormField("Technique note") {
                    TextField("", text: $note, prompt: Text("Slow lowering, pause at the bottom").foregroundStyle(NunaPalette.textMuted), axis: .vertical).lineLimit(1...4)
                        .onChange(of: note) { new in if new.count > WhoopStore.maxExerciseNoteLength { note = String(new.prefix(WhoopStore.maxExerciseNoteLength)) } }
                }
                Text("Every target is optional. Leave out what you do not need and fill it in during the session.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                if let known = vocabulary.first(where: { $0.name == trimmed }) {
                    Button(role: .destructive) { forgetting = known } label: {
                        Text("Forget this exercise").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                            .frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .nunaKeyboardDone()
            .sheet(isPresented: $choosingFromLibrary) {
                NunaExercisePicker(title: "Choose exercise", single: true) { picked in
                    guard let p = picked.first else { return }
                    exercise = p.name
                    primary = p.primary
                    primaryGroup = p.primary.map(NunaMuscleGroup.of)
                    secondaries = Set(p.secondary)
                }
            }
        }
        .preferredColorScheme(NunaTheme.colorScheme)
        .task { await loadIfNeeded() }
        .nunaDialog(forgetting.map { Text(verbatim: String(localized: "Forget \($0.name)?")) } ?? Text(verbatim: ""), isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
            NunaDialogButton("Forget", role: .destructive) { Task { await forget() } }
            NunaDialogButton("Cancel", role: .cancel) { forgetting = nil }
        } message: { Text("It stops being offered here. Sessions you already logged with it are kept exactly as they are.") }
        .alert("You've saved the most exercises PHMN remembers", isPresented: $vocabularyFull) {
            Button("OK", role: .cancel) {}
        } message: { Text("Forget one you no longer use and this one will save. Your logged sessions are never affected.") }
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            Text("Save").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                .padding(.horizontal, 20).frame(height: 44).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain).disabled(!canSave).opacity(canSave ? 1 : 0.4)
    }

    private var usedBefore: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Used before").font(.nuna(size: 11, weight: .heavy)).tracking(0.9).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            NunaFlowChips(items: suggestions.map(\.name)) { n in
                nunaPill(n, on: false) { if let row = vocabulary.first(where: { $0.name == n }) { adopt(row) } }
            }
        }
    }

    private var primaryCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Primary muscle")
                NunaFlowChips(items: NunaMuscleGroup.allCases.map(\.rawValue)) { id in
                    let g = NunaMuscleGroup(rawValue: id)!
                    nunaPill(g.name, on: primaryGroup == g) {
                        primaryGroup = g
                        let ms = muscles(in: g)
                        if ms.count == 1 { select(primary: ms[0], group: g) }
                        else if let p = primary, NunaMuscleGroup.of(p) != g { primary = nil }
                    }
                }
                if let g = primaryGroup, muscles(in: g).count > 1 {
                    NunaFlowChips(items: muscles(in: g).map(\.rawValue)) { id in
                        let mu = LiftMuscle(rawValue: id)!
                        nunaPill(mu.displayName, on: primary == mu) { select(primary: mu, group: g) }
                    }
                }
            }
        }
    }

    private var secondaryCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Also works (counts half a set)")
                NunaFlowChips(items: LiftMuscle.ordered.filter { secondaries.contains($0) && $0 != primary }.map(\.rawValue) + ["+"]) { id in
                    if id == "+" {
                        NunaMenu {
                            ForEach(LiftMuscle.Region.allCases, id: \.self) { region in
                                NunaMenuSub(verbatim: region.displayName) {
                                    ForEach(LiftMuscle.inRegion(region).filter { $0 != primary && !secondaries.contains($0) }, id: \.self) { mu in
                                        NunaMenuItem(verbatim: mu.displayName) { secondaries.insert(mu) }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) { Image(systemName: "plus").font(.nuna(size: 12, weight: .bold)); Text("Add muscle").font(.nuna(size: 13.5, weight: .bold)) }
                                .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 38)
                                .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                        }
                    } else {
                        let mu = LiftMuscle(rawValue: id)!
                        Button { secondaries.remove(mu) } label: {
                            HStack(spacing: 6) { Text(verbatim: mu.displayName).font(.nuna(size: 13.5, weight: .bold)); Image(systemName: "xmark").font(.nuna(size: 10, weight: .bold)) }
                                .foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 14).frame(height: 38).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
                Text("Direct sets count one, indirect sets count half. This is the basis of the weekly sets per muscle.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
    }

    private var targetsCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("Target")
                HStack(spacing: 12) {
                    NunaFormField("Sets") { TextField("", text: $setsText, prompt: Text("4").foregroundStyle(NunaPalette.textMuted)).keyboardType(.numberPad) }
                    if kind == .timed {
                        NunaFormField("Time (mm:ss)") { TextField("", text: $timeText, prompt: Text("00:45").foregroundStyle(NunaPalette.textMuted)).keyboardType(.numbersAndPunctuation) }
                    } else {
                        NunaFormField("Reps") { TextField("", text: $repsText, prompt: Text("8").foregroundStyle(NunaPalette.textMuted)).keyboardType(.numberPad) }
                    }
                }
                HStack(spacing: 12) {
                    if kind.usesWeight { NunaFormField(system == .imperial ? "Weight (lb)" : "Weight (kg)") { TextField("", text: $weightText, prompt: Text("70").foregroundStyle(NunaPalette.textMuted)).keyboardType(.decimalPad) } }
                    NunaFormField("Rest (s)") { TextField("", text: $restText, prompt: Text("90").foregroundStyle(NunaPalette.textMuted)).keyboardType(.numberPad) }
                }
            }
        }
    }

    private func muscles(in g: NunaMuscleGroup) -> [LiftMuscle] { LiftMuscle.ordered.filter { NunaMuscleGroup.of($0) == g } }

    private func select(primary mu: LiftMuscle?, group: NunaMuscleGroup) {
        primary = mu; primaryGroup = group
        if let mu { secondaries.remove(mu) }
    }

    private func adopt(_ row: LiftExerciseRow) {
        exercise = row.name; primary = row.primaryMuscle; primaryGroup = row.primaryMuscle.map(NunaMuscleGroup.of); secondaries = Set(row.secondaryMuscles)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func forget() async {
        guard let row = forgetting, let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLiftExercise(id: row.id)
        vocabulary.removeAll { $0.id == row.id }; forgetting = nil
    }

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        if let item {
            exercise = item.exercise
            setsText = item.targetSets.map(String.init) ?? ""
            repsText = item.targetRepsLow.map(String.init) ?? ""
            if NunaExerciseKind.of(item.exercise) == .timed { timeText = item.targetRepsLow.map(NunaExerciseKind.clock) ?? ""; repsText = "" }
            weightText = item.targetWeightKg.map { LiftFormat.trim(LiftFormat.display(fromKilograms: $0, system: system)) } ?? ""
            restText = item.restSec.map(String.init) ?? ""
            note = item.note ?? ""
        }
        guard let store = await repo.storeHandle() else { return }
        vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        if let item, let known = vocabulary.first(where: { $0.name == item.exercise }) {
            primary = known.primaryMuscle; primaryGroup = known.primaryMuscle.map(NunaMuscleGroup.of); secondaries = Set(known.secondaryMuscles)
        }
    }

    private func save() async {
        guard canSave else { return }
        let name = trimmed
        if let store = await repo.storeHandle() {
            let now = Int(Date().timeIntervalSince1970)
            let existing = vocabulary.first { $0.name == name }
            let row = LiftExerciseRow(id: existing?.id ?? UUID().uuidString, deviceId: repo.deviceId, name: name, primaryMuscle: primary,
                                      secondaryMuscles: LiftMuscle.ordered.filter { secondaries.contains($0) && $0 != primary }, createdAt: existing?.createdAt ?? now, lastUsedTs: now)
            do { _ = try await store.upsertLiftExercises([row]) }
            catch is WhoopStore.LiftExerciseVocabularyFull { vocabularyFull = true; return }
            catch { return }
        }
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(LiftProgramItemRow(id: item?.id ?? UUID().uuidString, deviceId: repo.deviceId, programId: item?.programId ?? "", ord: item?.ord ?? 0, exercise: name,
                                  targetSets: Int(setsText.trimmingCharacters(in: .whitespaces)),
                                  // A hold's time, in seconds, takes the place of the reps.
                                  targetRepsLow: kind == .timed ? NunaExerciseKind.seconds(from: timeText) : Int(repsText.trimmingCharacters(in: .whitespaces)),
                                  targetRepsHigh: nil, targetRpe: nil,
                                  targetWeightKg: kind.usesWeight ? LiftFormat.number(weightText).map { LiftFormat.kilograms(fromDisplay: $0, system: system) } : nil,
                                  restSec: Int(restText.trimmingCharacters(in: .whitespaces)), note: n.isEmpty ? nil : n))
        dismiss()
    }
}

// MARK: - Import (WorkoutProgramImport.dc)

/// Programs from a spreadsheet filled in on a computer. The file is read and checked in full before anything is written.
struct NunaProgramImportView: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var parsed: LiftProgramImportResult?
    @State private var fileName: String?
    @State private var failure: String?
    @State private var importing = false

    private static let acceptedTypes: [UTType] = {
        var t: [UTType] = [.spreadsheet, .commaSeparatedText, .plainText, .data]
        if let x = UTType(filenameExtension: "xlsx") { t.insert(x, at: 0) }
        return t
    }()

    var body: some View {
        NunaDetailScreen("Import program") {
            if let parsed { preview(parsed) } else { intro }
            if let failure {
                NunaCard(small: true) { Text(verbatim: failure).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil) }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.acceptedTypes, allowsMultipleSelection: false) { handle($0) }
    }

    private var intro: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Fill it in on a computer").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text("Typing a dozen exercise rows on a phone is tiring. A spreadsheet is much faster.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    step(1, "Download the template from the PHMN repository")
                    step(2, "Fill in one row per exercise")
                    step(3, "Bring the file here (.xlsx or .csv)")
                }
            }
            Text("Only the exercise name is required. The rest can stay empty and be filled in later or during the session.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
            primary("Choose file") { failure = nil; picking = true }
        }
    }

    private func step(_ n: Int, _ t: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(n)").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(width: 30, height: 30)
            Text(t).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
    }

    private func preview(_ r: LiftProgramImportResult) -> some View {
        let lines = r.programs.reduce(0) { $0 + $1.lines.count }
        return VStack(spacing: NunaSpacing.section) {
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text").font(.nuna(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 42, height: 42).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: fileName ?? "").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                        Text(verbatim: String(localized: "\(r.programs.count) programs · \(lines) exercises")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    NunaChip("Read", color: NunaPalette.charge)
                }
            }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(r.programs.enumerated()), id: \.offset) { i, p in
                        if i > 0 { NunaDivider() }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(verbatim: p.name).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary); Spacer()
                                Text(verbatim: String(localized: "\(p.lines.count) exercises")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                            ForEach(Array(p.lines.enumerated()), id: \.offset) { _, l in
                                HStack { Text(verbatim: l.exercise).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil); Spacer()
                                    Text(verbatim: summary(l)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil) }
                            }
                        }.padding(.vertical, 12)
                    }
                }
            }
            if !r.warnings.isEmpty {
                NunaCard(small: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Worth checking").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.warning)
                        ForEach(Array(r.warnings.enumerated()), id: \.offset) { _, w in
                            Text(verbatim: w).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        }
                        Text("These lines still import. Anything unclassified can be set in the app.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    }
                }
            }
            primary(r.programs.count == 1 ? "Import 1 program" : "Import \(r.programs.count) programs") { Task { await performImport(r) } }.disabled(importing)
            Button { failure = nil; parsed = nil; picking = true } label: {
                Text("Choose a different file").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 48)
            }.buttonStyle(.plain)
        }
    }

    private func primary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func summary(_ l: ImportedProgramLine) -> String {
        var parts: [String] = []
        if let s = l.targetSets, let r = l.targetReps { parts.append("\(s) × \(r)") } else if let s = l.targetSets { parts.append("\(s) ×") }
        if let kg = l.targetWeightKg { parts.append(LiftFormat.trim(kg) + " kg") }
        if let rest = l.restSec { parts.append("\(rest)s") }
        return parts.joined(separator: " · ")
    }

    private func handle(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e): failure = e.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard bytes <= LiftProgramSheetImporter.maxFileBytes else { parsed = nil; failure = message(.tooLarge); return }
                parsed = try LiftProgramSheetImporter.parse(data: try Data(contentsOf: url))
                fileName = url.lastPathComponent; failure = nil
            } catch let e as LiftProgramSheetImporter.ImportError { parsed = nil; failure = message(e) }
            catch { parsed = nil; failure = String(localized: "That file could not be read.") }
        }
    }

    private func message(_ e: LiftProgramSheetImporter.ImportError) -> String {
        switch e {
        case .unreadable: return String(localized: "That does not look like a spreadsheet. Use the template, saved as .xlsx or .csv.")
        case .missingColumns: return String(localized: "That sheet has no Exercise column. Use the template — the import matches on the header names.")
        case .empty: return String(localized: "That sheet has no exercises in it yet.")
        case .tooLarge: return String(localized: "That file is too big to be a program sheet.")
        }
    }

    private func performImport(_ result: LiftProgramImportResult) async {
        guard !importing, let store = await repo.storeHandle() else { return }
        importing = true; defer { importing = false }
        let now = Int(Date().timeIntervalSince1970)
        for program in result.programs {
            let pid = UUID().uuidString
            _ = try? await store.upsertLiftPrograms([LiftProgramRow(id: pid, deviceId: repo.deviceId, name: program.name, note: program.note, createdAt: now, updatedAt: now, archived: false)])
            let items = program.lines.enumerated().map { i, l in
                LiftProgramItemRow(id: UUID().uuidString, deviceId: repo.deviceId, programId: pid, ord: i, exercise: l.exercise, targetSets: l.targetSets,
                                   targetRepsLow: l.targetReps, targetRepsHigh: nil, targetRpe: nil, targetWeightKg: l.targetWeightKg, restSec: l.restSec, note: l.note)
            }
            _ = try? await store.replaceLiftProgramItems(programId: pid, items: items)
            NunaProgramGroupsModel.shared.placeNew(pid)
            let exercises = program.lines.map { l in
                LiftExerciseRow(id: UUID().uuidString, deviceId: repo.deviceId, name: l.exercise, primaryMuscle: l.primaryMuscle, secondaryMuscles: l.secondaryMuscles, createdAt: now, lastUsedTs: nil)
            }
            _ = try? await store.upsertLiftExercises(exercises)
        }
        await repo.refresh()
        dismiss()
    }
}

/// A number or time typed into a target. It keeps what is being typed ("62." on the way to "62.5") and hands the program its value as soon as
/// the text reads as one.
private struct NunaTargetField: View {
    let prompt: String
    var keyboard: UIKeyboardType = .numberPad
    let get: () -> String
    let set: (String) -> Void
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        TextField("", text: $text, prompt: Text(verbatim: prompt).foregroundStyle(NunaPalette.textMuted))
            .font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.center)
            .keyboardType(keyboard).frame(height: 44).frame(maxWidth: .infinity)
            .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onAppear { if !loaded { text = get(); loaded = true } }
            .onChange(of: text) { _, new in set(new.replacingOccurrences(of: ",", with: ".")) }
    }
}
#endif


#if os(iOS)
/// How an exercise is done, for looking at before it is started: the library's demo, muscles and history where the exercise is in the
/// library, and the how-to video where it is not (an exercise the person made up).
struct NunaExercisePreviewSheet: View {
    let name: String
    var body: some View {
        if let lib = NunaExerciseLibrary.match(name) {
            NavigationStack { NunaExerciseDetailView(exerciseId: lib.id) }
                .preferredColorScheme(NunaTheme.colorScheme).presentationDragIndicator(.visible)
        } else {
            NunaExerciseVideoSheet(name: name)
        }
    }
}
#endif
