#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Add a workout tracked elsewhere, or edit one already logged (the Nuna version of `ManualWorkoutSheet`). The same six inputs
/// and the same honest-row rules (`WorkoutSource.buildManualRowFromSpan`): sport, start, end, distance, average heart rate and
/// calories. On save the caller persists it; when editing, the original row is passed as `replacing`.
struct NunaManualWorkoutSheet: View {
    let editing: WorkoutRow?
    /// A distance worked out from steps and height, offered while the session has none (a treadmill).
    var suggestedDistanceM: Double? = nil
    let onSave: (_ row: WorkoutRow, _ replacing: WorkoutRow?) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @State private var sport: String
    @State private var start: Date
    @State private var end: Date
    @State private var avgHrText: String
    @State private var kcalText: String
    @State private var distanceText: String
    /// The text the estimate filled in; the note below stays while it is still there.
    @State private var suggestedText: String?
    @State private var showSport = false

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    private enum NumberField: Hashable { case distance, avgHr, calories }
    @FocusState private var focus: NumberField?

    private var distanceUnitSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw)
    }
    private var distanceUnit: String { UnitFormatter.distanceUnit(distanceUnitSystem) }

    init(editing: WorkoutRow? = nil, suggestedDistanceM: Double? = nil, onSave: @escaping (_ row: WorkoutRow, _ replacing: WorkoutRow?) -> Void) {
        self.editing = editing; self.onSave = onSave; self.suggestedDistanceM = suggestedDistanceM
        let e = editing
        _sport = State(initialValue: e.map { WorkoutSource.editableSport($0.sport) } ?? "")
        let defaultEnd = Date()
        _start = State(initialValue: e.map { Date(timeIntervalSince1970: TimeInterval($0.startTs)) } ?? defaultEnd.addingTimeInterval(-45 * 60))
        _end = State(initialValue: e.map { Date(timeIntervalSince1970: TimeInterval($0.endTs)) } ?? defaultEnd)
        _avgHrText = State(initialValue: e?.avgHr.map(String.init) ?? "")
        _kcalText = State(initialValue: e?.energyKcal.map { String(Int($0.rounded())) } ?? "")
        let body = UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        let sys = UnitPrefs.resolveDistance(system: body, override: UserDefaults.standard.string(forKey: UnitPrefs.distanceSystemKey) ?? "")
        let given = e?.distanceM.flatMap { $0 > 0 ? $0 : nil }
        let initial = given ?? (e == nil ? nil : suggestedDistanceM)
        _distanceText = State(initialValue: initial.map { Self.distanceString($0, system: sys) } ?? "")
        _suggestedText = State(initialValue: given == nil ? initial.map { Self.distanceString($0, system: sys) } : nil)
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

    /// A nap or a night picked on the Rest tab: it is added as sleep, with only the two times to give.
    private var isRest: Bool { editing == nil && NunaActivityKind.isRest(sport) }
    private var restValid: Bool { end.timeIntervalSince(start) >= 5 * 60 && end <= Date() && start <= Date() }
    private var canSave: Bool { isRest ? restValid : builtRow != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if editing == nil {
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: "sparkle").font(.nuna(size: 17, weight: .regular)).foregroundStyle(Self.info).frame(width: 26)
                            Text("Adding a past activity helps PHMN recognize and classify your future workouts more accurately.")
                                .font(.nuna(size: 14, weight: .regular)).foregroundStyle(Self.info).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Self.info.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button { showSport = true } label: {
                        HStack(spacing: 16) {
                            NunaActivityGlyph(name: sport.isEmpty ? "Select" : sport, size: 28)
                                .foregroundStyle(NunaPalette.textSecondary).frame(width: 34, height: 34)
                            Text(verbatim: sport.isEmpty ? String(localized: "Select activity") : sport).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel + 1)
                                .textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                        }
                        .padding(.horizontal, 12).frame(height: 56).frame(maxWidth: .infinity)
                        .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 10) {
                        nunaRuledHeader("Time")
                        dateRow("Start Time", selection: startBinding)
                        dateRow("End Time", selection: $end)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        nunaRuledHeader("Location")
                        Text("Where did you wear your strap?").font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).padding(.horizontal, 16)
                        Text("Wrist band").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel + 1.2).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).padding(.horizontal, 16)
                    }

                    if !isRest {
                        VStack(alignment: .leading, spacing: 4) {
                            nunaRuledHeader("Optional details")
                            numberRow("Distance", text: $distanceText, unit: distanceUnit, field: .distance)
                            numberRow("Avg HR", text: $avgHrText, unit: "bpm", field: .avgHr)
                            numberRow("Calories", text: $kcalText, unit: "kcal", field: .calories)
                        }
                        if let suggestedText, distanceText == suggestedText {
                            Text("Distance estimated from your steps and height. Replace it with the treadmill's reading if you have it.")
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        }
                    } else {
                        Text("This is added as sleep, staged from your strap's heart rate and movement when it has data for that time.")
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }

                    if let note = validationNote {
                        Text(verbatim: note).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                    if avgHrEditedNote {
                        Text("Avg HR is shown as typed. The HR graph, zones and Effort stay from the recorded session.")
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 16).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            Button { save() } label: {
                Text(editing == nil ? "Save" : "Save changes").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel + 1.4).textCase(.uppercase)
                    .foregroundStyle(canSave ? NunaPalette.onAccent : NunaPalette.textMuted)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(canSave ? NunaPalette.accent : NunaPalette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain).disabled(!canSave)
            .padding(.horizontal, 24).padding(.vertical, 12)
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .preferredColorScheme(NunaTheme.colorScheme)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focus = nil } } }
        .sheet(isPresented: $showSport) {
            NunaSportPicker(selection: $sport, allowsCustom: true, includesRest: editing == nil) { showSport = false }.nunaSheetChrome(detents: [.large])
        }
    }

    private static let info = Color(hex: "#6FB1E0")

    private var header: some View {
        ZStack {
            Text(editing == nil ? "Add activity" : "Edit activity").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel + 1.2)
                .textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 52, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Close"))
                Spacer()
            }
        }
        .padding(.horizontal, 8).padding(.top, 14).frame(height: 62)
    }

    /// "Start Time" at the left and, at the right, one dark pill with the day and the time ("31 Oct at 8:52 AM"); touching it opens the picker.
    private func dateRow(_ title: LocalizedStringKey, selection: Binding<Date>) -> some View {
        HStack {
            Text(title).font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Spacer()
            ZStack {
                Text(verbatim: Self.stamp(selection.wrappedValue)).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    .padding(.horizontal, 16).frame(minWidth: 168, minHeight: 40)
                    .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                DatePicker("", selection: selection, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().colorMultiply(.clear).colorScheme(NunaTheme.mode == .light ? .light : .dark)
            }
            .fixedSize()
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }

    private static func stamp(_ d: Date) -> String {
        let day = DateFormatter(); day.locale = AppLanguage.activeLocale; day.setLocalizedDateFormatFromTemplate("d MMM")
        let time = DateFormatter(); time.locale = AppLanguage.activeLocale; time.setLocalizedDateFormatFromTemplate("jmm")
        return day.string(from: d) + " " + String(localized: "at") + " " + time.string(from: d)
    }

    private func numberRow(_ title: LocalizedStringKey, text: Binding<String>, unit: String, field: NumberField) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Spacer()
            TextField("", text: text, prompt: Text("optional").foregroundStyle(NunaPalette.textMuted))
                .font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .multilineTextAlignment(.trailing).keyboardType(.decimalPad).focused($focus, equals: field)
                .frame(maxWidth: 120)
            Text(verbatim: unit).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(minWidth: 30, alignment: .leading)
        }
        .padding(.horizontal, 16).frame(minHeight: 48)
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
        if isRest {
            if restValid { return nil }
            if start > Date() || end > Date() { return String(localized: "A nap can't be in the future.") }
            return String(localized: "A nap must be at least 5 minutes.")
        }
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
        if isRest {
            guard restValid else { return }
            let s = Int(start.timeIntervalSince1970), e = Int(end.timeIntervalSince1970)
            Task { await repo.addManualNap(startTs: s, endTs: e) }
            dismiss()
            return
        }
        guard let row = builtRow else { return }
        RecentSportsPrefs.recordSelection(row.sport)
        onSave(row, editing)
        dismiss()
    }
}
#endif
