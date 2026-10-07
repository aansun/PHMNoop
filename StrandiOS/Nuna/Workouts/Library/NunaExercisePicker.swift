#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// An exercise chosen in the picker, with the muscles it counts towards.
struct NunaPickedExercise: Identifiable, Hashable {
    let name: String
    let primary: LiftMuscle?
    let secondary: [LiftMuscle]
    var id: String { name }
}

/// Choose exercises: search the library, narrow to a part of the body, or type a name that is not in it. The exercises done before come
/// first while nothing is typed. An exercise the person already logs under their own name keeps that name, so its history stays whole.
struct NunaExercisePicker: View {
    /// The button's words once something is chosen, for example "Start with 3 exercises".
    var confirm: (Int) -> String = { $0 == 1 ? String(localized: "Start with 1 exercise") : String(localized: "Start with \($0) exercises") }
    var title: LocalizedStringKey = "Choose exercises"
    /// One exercise only: a tap picks it and closes the sheet.
    var single = false
    let onPick: ([NunaPickedExercise]) -> Void

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var vocabulary: [LiftExerciseRow] = []
    @State private var query = ""
    @State private var group: Group?
    @State private var chosen: [NunaPickedExercise] = []
    @FocusState private var focused: Bool

    /// The parts of the body to filter by, in the library's own muscle names.
    enum Group: String, CaseIterable, Identifiable {
        case chest, back, shoulders, arms, legs, core
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self { case .chest: "Chest"; case .back: "Back"; case .shoulders: "Shoulders"; case .arms: "Arms"; case .legs: "Legs"; case .core: "Core" }
        }
        var muscles: Set<String> {
            switch self {
            case .chest: ["chest"]
            case .back: ["lats", "middle back", "lower back", "traps"]
            case .shoulders: ["shoulders"]
            case .arms: ["biceps", "triceps", "forearms"]
            case .legs: ["quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors"]
            case .core: ["abdominals"]
            }
        }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var results: [NunaLibraryExercise] { NunaExerciseLibrary.search(trimmed, muscles: group?.muscles ?? []) }
    private var recents: [LiftExerciseRow] {
        guard trimmed.isEmpty, group == nil else { return [] }
        return vocabulary.filter { $0.lastUsedTs != nil }.sorted { ($0.lastUsedTs ?? 0) > ($1.lastUsedTs ?? 0) }.prefix(8).map { $0 }
    }
    private var canCreate: Bool {
        !trimmed.isEmpty && NunaExerciseLibrary.match(trimmed) == nil && !chosen.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(title).font(.nuna(size: 24, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        Button { dismiss() } label: {
                            Text("Cancel").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                .padding(.horizontal, 16).frame(height: 38).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(NunaPalette.textMuted)
                        TextField("", text: $query, prompt: Text("Search exercises").foregroundStyle(NunaPalette.textMuted))
                            .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textInputAutocapitalization(.never).autocorrectionDisabled().textCase(nil)
                            .focused($focused).submitLabel(.search)
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(NunaPalette.textMuted) }.buttonStyle(.plain) }
                    }
                    .padding(.horizontal, 16).frame(height: 46).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
                    filters
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 18).padding(.bottom, 10)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !recents.isEmpty {
                            sectionTitle("Recent")
                            ForEach(recents, id: \.id) { r in recentRow(r) }
                            sectionTitle("All exercises")
                        }
                        ForEach(results) { e in libraryRow(e) }
                        if canCreate { createRow.padding(.top, results.isEmpty ? 0 : 10) }
                        if results.isEmpty && !canCreate {
                            Text("No exercise matches").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).padding(.vertical, 24).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(NunaPalette.canvas.ignoresSafeArea())
            .overlay(alignment: .bottom) { confirmBar }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(NunaTheme.colorScheme)
        .task { if let s = await repo.storeHandle() { vocabulary = (try? await s.liftExercises(deviceId: repo.deviceId)) ?? [] } }
    }

    // MARK: Parts

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", on: group == nil) { group = nil }
                ForEach(Group.allCases) { g in chip(g.title, on: group == g) { group = group == g ? nil : g } }
            }
        }
    }

    private func chip(_ title: LocalizedStringKey, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .padding(.horizontal, 16).frame(height: 34).background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func sectionTitle(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).padding(.top, 14).padding(.bottom, 4)
    }

    private var createRow: some View {
        Button { toggle(NunaPickedExercise(name: trimmed, primary: nil, secondary: [])) } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(width: 56, height: 42).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: String(localized: "Add \"\(trimmed)\" as typed")).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text("Your own name, not from the library").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Spacer(minLength: 8)
            }.padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func recentRow(_ r: LiftExerciseRow) -> some View {
        let pick = NunaPickedExercise(name: r.name, primary: r.primaryMuscle, secondary: r.secondaryMuscles)
        return row(thumb: NunaExerciseThumb(name: r.name), name: r.name,
                   detail: r.primaryMuscle?.displayName ?? String(localized: "Not classified"), selected: isChosen(r.name)) { toggle(pick) }
    }

    private func libraryRow(_ e: NunaLibraryExercise) -> some View {
        // The person's own name for it, when they already log this exercise.
        let own = vocabulary.first { NunaExerciseLibrary.match($0.name)?.id == e.id }
        let pick = own.map { NunaPickedExercise(name: $0.name, primary: $0.primaryMuscle ?? e.liftPrimary, secondary: $0.secondaryMuscles.isEmpty ? e.liftSecondary : $0.secondaryMuscles) }
            ?? NunaPickedExercise(name: e.name, primary: e.liftPrimary, secondary: e.liftSecondary)
        let detail = e.primaryMuscles.map(NunaLibraryExercise.title).joined(separator: ", ") + (e.equipmentTitle.map { " · " + $0 } ?? "")
        return row(thumb: NunaExerciseThumb(e), name: e.name, detail: detail, selected: isChosen(pick.name)) { toggle(pick) }
    }

    private func row(thumb: NunaExerciseThumb, name: String, detail: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                thumb
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).multilineTextAlignment(.leading)
                    Text(verbatim: detail).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.nuna(size: 22)).foregroundStyle(selected ? NunaPalette.accent : NunaPalette.textMuted)
            }
            .padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var confirmBar: some View {
        if !chosen.isEmpty && !single {
            Button { onPick(chosen); dismiss() } label: {
                Text(verbatim: confirm(chosen.count)).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                    .frame(maxWidth: .infinity).frame(height: 54).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }
            .buttonStyle(.plain).padding(.horizontal, NunaSpacing.screenH).padding(.top, 10).padding(.bottom, 14)
            .background(.ultraThinMaterial)
        }
    }

    private func isChosen(_ name: String) -> Bool { chosen.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
    private func toggle(_ p: NunaPickedExercise) {
        if single { onPick([p]); dismiss(); return }
        if let i = chosen.firstIndex(where: { $0.name.caseInsensitiveCompare(p.name) == .orderedSame }) { chosen.remove(at: i) } else { chosen.append(p) }
        if canCreate == false && !trimmed.isEmpty && chosen.contains(where: { $0.name == trimmed }) { query = "" }
    }
}
#endif
