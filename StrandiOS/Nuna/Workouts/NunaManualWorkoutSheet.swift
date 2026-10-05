#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Add a workout tracked elsewhere, or edit one already logged (the Nuna version of `ManualWorkoutSheet`). The same six inputs
/// and the same honest-row rules (`WorkoutSource.buildManualRowFromSpan`): sport, start, end, distance, average heart rate and
/// calories. On save the caller persists it; when editing, the original row is passed as `replacing`.
struct NunaManualWorkoutSheet: View {
    let editing: WorkoutRow?
    let onSave: (_ row: WorkoutRow, _ replacing: WorkoutRow?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sport: String
    @State private var start: Date
    @State private var end: Date
    @State private var avgHrText: String
    @State private var kcalText: String
    @State private var distanceText: String
    @State private var showSport = false

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    private enum NumberField: Hashable { case distance, avgHr, calories }
    @FocusState private var focus: NumberField?

    private var distanceUnitSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw)
    }
    private var distanceUnit: String { UnitFormatter.distanceUnit(distanceUnitSystem) }

    init(editing: WorkoutRow? = nil, onSave: @escaping (_ row: WorkoutRow, _ replacing: WorkoutRow?) -> Void) {
        self.editing = editing; self.onSave = onSave
        let e = editing
        _sport = State(initialValue: e.map { WorkoutSource.editableSport($0.sport) } ?? "")
        let defaultEnd = Date()
        _start = State(initialValue: e.map { Date(timeIntervalSince1970: TimeInterval($0.startTs)) } ?? defaultEnd.addingTimeInterval(-45 * 60))
        _end = State(initialValue: e.map { Date(timeIntervalSince1970: TimeInterval($0.endTs)) } ?? defaultEnd)
        _avgHrText = State(initialValue: e?.avgHr.map(String.init) ?? "")
        _kcalText = State(initialValue: e?.energyKcal.map { String(Int($0.rounded())) } ?? "")
        let body = UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        let sys = UnitPrefs.resolveDistance(system: body, override: UserDefaults.standard.string(forKey: UnitPrefs.distanceSystemKey) ?? "")
        _distanceText = State(initialValue: e?.distanceM.map { Self.distanceString($0, system: sys) } ?? "")
    }

    private static func distanceString(_ meters: Double, system: UnitSystem) -> String {
        let km = meters / 1000.0
        let v = system == .imperial ? km * UnitFormatter.milesPerKilometer : km
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(editing == nil ? "Add Workout" : "Edit Workout")
                            .font(.nuna(size: NunaTypeSize.h2, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text(editing == nil ? "Log a session you tracked elsewhere." : "Adjust this session's details.")
                            .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Cancel").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Button { showSport = true } label: {
                    NunaCard(small: true) {
                        NunaListRow("Sport", subtitle: sport.isEmpty ? "Choose a sport" : LocalizedStringKey(sport),
                                    systemImage: NunaSportPicker.symbol(for: sport), showsChevron: true)
                    }
                }.buttonStyle(.plain)

                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                    VStack(spacing: 0) {
                        dateRow("Start", selection: startBinding)
                        NunaDivider()
                        dateRow("End", selection: $end)
                        NunaDivider()
                        HStack {
                            Text("Duration").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            Text(verbatim: durationLabel).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.effortText)
                            Stepper("", value: durationBinding, in: 1...(24 * 60), step: 5).labelsHidden().fixedSize()
                        }
                        .padding(.vertical, 10).accessibilityElement(children: .combine)
                    }
                }

                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                    VStack(spacing: 0) {
                        numberRow("Distance", text: $distanceText, unit: distanceUnit, field: .distance)
                        NunaDivider()
                        numberRow("Avg HR", text: $avgHrText, unit: "bpm", field: .avgHr)
                        NunaDivider()
                        numberRow("Calories", text: $kcalText, unit: "kcal", field: .calories)
                    }
                }
                Text("Distance, Avg HR and Calories are optional.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)

                if let note = validationNote {
                    Text(verbatim: note).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                if avgHrEditedNote {
                    Text("Avg HR is shown as typed. The HR graph, zones and Effort stay from the recorded session.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).fixedSize(horizontal: false, vertical: true)
                }
                Button { save() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark").font(.nuna(size: 15, weight: .bold))
                        Text(editing == nil ? "Add" : "Save").font(.nuna(size: 17, weight: .bold))
                    }
                    .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                    .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                }
                .buttonStyle(.plain).disabled(builtRow == nil).opacity(builtRow == nil ? 0.4 : 1)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 22).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .preferredColorScheme(NunaTheme.colorScheme)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focus = nil } } }
        .sheet(isPresented: $showSport) {
            NunaSportPicker(selection: $sport, allowsCustom: true) { showSport = false }.nunaSheetChrome(detents: [.large])
        }
    }

    private func dateRow(_ title: LocalizedStringKey, selection: Binding<Date>) -> some View {
        HStack {
            Text(title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            DatePicker("", selection: selection, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden().colorScheme(NunaTheme.mode == .light ? .light : .dark)
        }
        .padding(.vertical, 6)
    }

    private func numberRow(_ title: LocalizedStringKey, text: Binding<String>, unit: String, field: NumberField) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            TextField("", text: text, prompt: Text("optional").foregroundStyle(NunaPalette.textMuted))
                .font(.nuna(size: 16, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                .multilineTextAlignment(.trailing).keyboardType(.decimalPad).focused($focus, equals: field)
                .frame(maxWidth: 120)
            Text(verbatim: unit).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(minWidth: 30, alignment: .leading)
        }
        .padding(.vertical, 12)
    }

    // MARK: Values

    private var startBinding: Binding<Date> {
        Binding(get: { start }, set: { picked in
            let span = end.timeIntervalSince(start)
            let newStart = min(picked, Date().addingTimeInterval(-span))
            end = WorkoutSource.endAfterStartMove(oldStart: start, oldEnd: end, newStart: newStart)
            start = newStart
        })
    }

    private var durationBinding: Binding<Int> {
        Binding(get: { min(24 * 60, max(1, WorkoutSource.spanDurationMin(start: start, end: end))) },
                set: { end = WorkoutSource.endForDuration(start: start, durationMin: $0) })
    }

    private var durationLabel: String {
        let d = durationBinding.wrappedValue
        let h = d / 60, m = d % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        return h > 0 ? "\(h)h" : "\(m)m"
    }

    private var avgHr: Int? { Int(avgHrText.trimmingCharacters(in: .whitespaces)) }
    private var kcal: Double? { Double(kcalText.trimmingCharacters(in: .whitespaces)) }
    private var distanceMeters: Double? {
        let t = distanceText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let v = Double(t), v >= 0 else { return nil }
        let km = distanceUnitSystem == .imperial ? v / UnitFormatter.milesPerKilometer : v
        return km * 1000.0
    }

    private var builtRow: WorkoutRow? {
        if !avgHrText.trimmingCharacters(in: .whitespaces).isEmpty && avgHr == nil { return nil }
        if !kcalText.trimmingCharacters(in: .whitespaces).isEmpty && kcal == nil { return nil }
        if !distanceText.trimmingCharacters(in: .whitespaces).isEmpty && distanceMeters == nil { return nil }
        guard let base = WorkoutSource.buildManualRowFromSpan(start: start, end: end, sport: sport, avgHr: avgHr, energyKcal: kcal, distanceM: distanceMeters) else { return nil }
        return WorkoutSource.preservingCaptured(base, from: editing)
    }

    private var avgHrEditedNote: Bool {
        guard let editing, let built = builtRow else { return false }
        return (editing.strain != nil || editing.zonesJSON != nil) && built.avgHr != editing.avgHr
    }

    private var validationNote: String? {
        guard builtRow == nil else { return nil }
        if sport.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Enter a sport.") }
        if start > Date() { return String(localized: "Start can't be in the future.") }
        if end <= start { return String(localized: "End must be after the start.") }
        if end > Date() { return String(localized: "End can't be in the future.") }
        if Int(end.timeIntervalSince1970) - Int(start.timeIntervalSince1970) < WorkoutSource.minManualSpanSeconds { return String(localized: "A workout must be at least 1 minute.") }
        if !avgHrText.trimmingCharacters(in: .whitespaces).isEmpty, avgHr == nil || !(25...250).contains(avgHr ?? -1) { return String(localized: "Average HR must be 25-250 bpm.") }
        if !kcalText.trimmingCharacters(in: .whitespaces).isEmpty, kcal == nil || (kcal ?? -1) < 0 || (kcal ?? 0) > 20_000 { return String(localized: "Calories must be 0-20,000.") }
        if !distanceText.trimmingCharacters(in: .whitespaces).isEmpty, distanceMeters == nil || (distanceMeters ?? -1) < 0 || (distanceMeters ?? 0) > 1_000_000 {
            return distanceUnitSystem == .imperial ? String(localized: "Distance must be 0–621 mi.") : String(localized: "Distance must be 0–1,000 km.")
        }
        return String(localized: "Check the values and try again.")
    }

    private func save() {
        guard let row = builtRow else { return }
        RecentSportsPrefs.recordSelection(row.sport)
        onSave(row, editing)
        dismiss()
    }
}
#endif
