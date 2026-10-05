#if os(iOS)
import SwiftUI
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

private struct NunaItemTarget: Identifiable { let id: String; let item: LiftProgramItemRow? }

// MARK: - Program editor (WorkoutProgram.dc)

/// Name, note and ordered exercise lines of one program. `programId == "new"` creates one. The lines are drafted locally
/// and written together on Save, the same way the Default editor does, so history is never rewritten.
struct NunaProgramEditor: View {
    let programId: String
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
        NunaDetailScreen(isNew ? "New program" : "Edit program", trailing: AnyView(saveButton)) {
            NunaFormField("Name") { TextField("", text: $name, prompt: Text("Push · chest, shoulders, triceps").foregroundStyle(NunaPalette.textMuted)) }
            NunaFormField("Note") {
                TextField("", text: $note, prompt: Text("Anything you want to remember").foregroundStyle(NunaPalette.textMuted), axis: .vertical).lineLimit(1...4)
                    .onChange(of: note) { new in if new.count > WhoopStore.maxProgramNoteLength { note = String(new.prefix(WhoopStore.maxProgramNoteLength)) } }
            }
            NunaTitleRow(title: "Exercises") { EmptyView() }
            exercises
            summaryCard
            Text("Every target is optional: this is the plan, not the record. What you lift is entered during the session. Sessions already logged from this program are kept.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true)
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
        .confirmationDialog("Delete this program?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteProgram() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Sessions you already logged from it are kept.") }
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            Text("Save").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                .padding(.horizontal, 20).frame(height: 44).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain).disabled(!canSave).opacity(canSave ? 1 : 0.4)
    }

    @ViewBuilder private var exercises: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text("No exercises yet. Add the first one below.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { NunaDivider() }
                    HStack(spacing: 10) {
                        Button { editing = NunaItemTarget(id: item.id, item: item) } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: item.exercise).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2)
                                    if !detail(item).isEmpty { Text(verbatim: detail(item)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                                }
                                Spacer(minLength: 6)
                                if let s = item.targetSets {
                                    Text(verbatim: item.targetRepsLow.map { "\(s) × \($0)" } ?? "\(s)").font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Menu {
                            Button { move(i, -1) } label: { Label("Move up", systemImage: "arrow.up") }.disabled(i == 0)
                            Button { move(i, 1) } label: { Label("Move down", systemImage: "arrow.down") }.disabled(i == items.count - 1)
                            Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: { Label("Remove exercise", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 32, height: 40)
                        }
                    }.padding(.vertical, 12)
                }
            }
        }
        Button { editing = NunaItemTarget(id: "new", item: nil) } label: {
            HStack(spacing: 8) { Image(systemName: "plus").font(.nuna(size: 14, weight: .bold)); Text("Add exercise").font(.nuna(size: 15, weight: .bold)) }
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NunaPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
        }.buttonStyle(.plain)
    }

    private var summaryCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Program summary")
                HStack {
                    tile("Exercises", "\(items.count)", nil)
                    tile("Sets", "\(totalSets)", nil)
                    tile("Estimated", "\(estimatedMinutes)", "min")
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
        if let kg = item.targetWeightKg { parts.append(LiftFormat.weight(kg, system: system)) }
        if let rest = item.restSec { parts.append(String(localized: "rest \(rest) s")) }
        if parts.isEmpty, item.targetSets == nil { parts.append(String(localized: "No targets set")) }
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
    @State private var weightText = ""
    @State private var restText = ""
    @State private var note = ""
    @State private var vocabulary: [LiftExerciseRow] = []
    @State private var loaded = false
    @State private var forgetting: LiftExerciseRow?
    @State private var vocabularyFull = false

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var trimmed: String { exercise.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty }
    private var suggestions: [LiftExerciseRow] {
        let q = trimmed.lowercased()
        guard !q.isEmpty else { return Array(vocabulary.prefix(8)) }
        return vocabulary.filter { $0.name.lowercased().contains(q) && $0.name.lowercased() != q }.prefix(8).map { $0 }
    }

    var body: some View {
        NavigationStack {
            NunaDetailScreen("Exercise", trailing: AnyView(saveButton)) {
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
        }
        .preferredColorScheme(NunaTheme.colorScheme)
        .task { await loadIfNeeded() }
        .confirmationDialog(forgetting.map { Text(verbatim: String(localized: "Forget \($0.name)?")) } ?? Text(verbatim: ""), isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), titleVisibility: .visible) {
            Button("Forget", role: .destructive) { Task { await forget() } }
            Button("Cancel", role: .cancel) { forgetting = nil }
        } message: { Text("It stops being offered here. Sessions you already logged with it are kept exactly as they are.") }
        .alert("You've saved the most exercises NOOP remembers", isPresented: $vocabularyFull) {
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
                        Menu {
                            ForEach(LiftMuscle.Region.allCases, id: \.self) { region in
                                Section(region.displayName) {
                                    ForEach(LiftMuscle.inRegion(region).filter { $0 != primary && !secondaries.contains($0) }, id: \.self) { mu in
                                        Button(mu.displayName) { secondaries.insert(mu) }
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
                    NunaFormField("Reps") { TextField("", text: $repsText, prompt: Text("8").foregroundStyle(NunaPalette.textMuted)).keyboardType(.numberPad) }
                }
                HStack(spacing: 12) {
                    NunaFormField(system == .imperial ? "Weight (lb)" : "Weight (kg)") { TextField("", text: $weightText, prompt: Text("70").foregroundStyle(NunaPalette.textMuted)).keyboardType(.decimalPad) }
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
                                  targetSets: Int(setsText.trimmingCharacters(in: .whitespaces)), targetRepsLow: Int(repsText.trimmingCharacters(in: .whitespaces)),
                                  targetRepsHigh: nil, targetRpe: nil,
                                  targetWeightKg: LiftFormat.number(weightText).map { LiftFormat.kilograms(fromDisplay: $0, system: system) },
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
                    step(1, "Download the template from the NOOP repository")
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
            Text(verbatim: "\(n)").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(width: 30, height: 30).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
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
            let exercises = program.lines.map { l in
                LiftExerciseRow(id: UUID().uuidString, deviceId: repo.deviceId, name: l.exercise, primaryMuscle: l.primaryMuscle, secondaryMuscles: l.secondaryMuscles, createdAt: now, lastUsedTs: nil)
            }
            _ = try? await store.upsertLiftExercises(exercises)
        }
        await repo.refresh()
        dismiss()
    }
}
#endif
