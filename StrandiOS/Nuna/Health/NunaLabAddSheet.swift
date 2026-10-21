#if os(iOS)
import SwiftUI
import Foundation
import UniformTypeIdentifiers
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

/// Add a result to the Lab Book: type one in (pick the marker, the number, the date, the range from the report) or bring in a markers file. The two sit
/// in one sheet, so the Lab Book page itself stays a page of readings. Blood pressure is entered as a pair and kept as two markers; markers that are
/// reported in two units (lipids, glucose) can be typed in either and are stored in the usual one.
struct NunaLabAddSheet: View {
    /// The marker to start on (adding from its own page): its key, its name and its unit when it is not in the catalog.
    var preselect: String?
    var preselectName: String?
    var preselectUnit: String?
    let onSave: (_ drafts: [LabMarkerRow]) async -> Void

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @Environment(\.dismiss) private var dismiss

    private enum Mode: Hashable { case type, file }
    @State private var mode: Mode = .type

    @State private var selection: MarkerDefinition?
    @State private var customName = ""
    @State private var customUnit = ""
    @State private var customKeyOverride: String?
    @State private var addingCustom = false
    @State private var search = ""
    @State private var categoryFilter: LabMarkerCategory?

    @State private var valueText = ""
    @State private var diastolicText = ""
    @State private var unitChoice = 0
    @State private var takenAt = Date()
    @State private var note = ""
    @State private var referenceText = ""
    @State private var saving = false

    @State private var importing = false
    @State private var importSummary: String?
    @State private var importFailed = false

    private enum Field: Hashable { case value, diastolic, note, reference, customName, customUnit, search }
    @FocusState private var focused: Field?

    init(preselect: String? = nil, preselectName: String? = nil, preselectUnit: String? = nil, onSave: @escaping (_ drafts: [LabMarkerRow]) async -> Void) {
        self.preselect = preselect; self.preselectName = preselectName; self.preselectUnit = preselectUnit; self.onSave = onSave
        let key = preselect == LabBookProjection.bpDiastolicKey ? LabBookProjection.bpSystolicKey : preselect
        if let key, let def = MarkerCatalog.definition(for: key) {
            _selection = State(initialValue: def)
        } else if let key {
            _addingCustom = State(initialValue: true)
            _customKeyOverride = State(initialValue: key)
            _customName = State(initialValue: preselectName ?? key)
            _customUnit = State(initialValue: preselectUnit ?? "")
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                NunaSegmented([(value: Mode.type, title: "Type it in"), (value: Mode.file, title: "Import a file")], selection: $mode)
                if mode == .type { typeContent } else { fileContent }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 14).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil } } }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
            }.buttonStyle(.plain).accessibilityLabel(Text("Close"))
            Spacer()
            Text("Add a result").font(.nuna(size: 16, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: Type it in

    @ViewBuilder private var typeContent: some View {
        nunaTrendsCap("Marker")
        NunaCard(small: true) { markerPicker }
        if selection != nil || addingCustom {
            nunaTrendsCap("Reading")
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 16) {
                    if isPressure { pressureFields } else { valueField }
                    NunaDivider()
                    HStack {
                        Text("Date taken").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        DatePicker("", selection: $takenAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                    }
                }
            }
            nunaTrendsCap("Range and note")
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 14) {
                    NunaFormField("Reference range from my report (optional)") {
                        TextField("", text: $referenceText, prompt: Text("e.g. 2.0-5.0").foregroundStyle(NunaPalette.textMuted)).focused($focused, equals: .reference)
                    }
                    Text("NOOP never fills this in. It only shows back exactly what you type from your own report, and a reading is placed against it.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    NunaFormField("Note (optional)") {
                        TextField("", text: $note, prompt: Text("e.g. fasting, morning draw").foregroundStyle(NunaPalette.textMuted)).focused($focused, equals: .note)
                    }
                }
            }
            Button { save() } label: {
                Text("Save").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                    .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(drafts.isEmpty || saving).opacity(drafts.isEmpty || saving ? 0.4 : 1)
        }
        Text("Lab Book keeps your own numbers. It doesn't test, read, or judge them, and it's not medical advice. Everything stays on this iPhone.")
            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
    }

    private var markerPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            if addingCustom {
                NunaFormField("Name") {
                    TextField("", text: $customName, prompt: Text("e.g. Magnesium").foregroundStyle(NunaPalette.textMuted)).focused($focused, equals: .customName)
                }
                NunaFormField("Unit") {
                    TextField("", text: $customUnit, prompt: Text("e.g. mmol/L").foregroundStyle(NunaPalette.textMuted)).focused($focused, equals: .customUnit)
                }
                if customKeyOverride == nil {
                    Button("Back to the marker list") { addingCustom = false }.font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).buttonStyle(.plain)
                }
            } else if let selection {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: selection.key == LabBookProjection.bpSystolicKey ? String(localized: "Blood pressure") : selection.displayName).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: selection.category.displayName).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    if preselect == nil {
                        Button("Change") { reset() }.font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(NunaPalette.textMuted)
                    TextField("", text: $search, prompt: Text("Search markers (e.g. LDL, ferritin)").foregroundStyle(NunaPalette.textMuted))
                        .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .search)
                }
                .padding(.horizontal, 14).frame(height: 44).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryChip(nil, "All")
                        ForEach([LabMarkerCategory.bloodPanel, .bloodPressure, .bodyMeasurement], id: \.self) { categoryChip($0, LocalizedStringKey($0.displayName)) }
                    }
                }
                ForEach(Array(catalog.enumerated()), id: \.element.key) { i, def in
                    if i > 0 { NunaDivider() }
                    Button { choose(def) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: def.key == LabBookProjection.bpSystolicKey ? String(localized: "Blood pressure") : def.displayName).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: def.category.displayName).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                            Spacer()
                            Text(verbatim: def.canonicalUnit).font(.nuna(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }.padding(.vertical, 7).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if catalog.isEmpty {
                    Text("No match. Add it as a custom marker below.").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                NunaDivider()
                Button { addingCustom = true; focused = .customName } label: {
                    Label("Add a custom marker", systemImage: "plus").font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                }.buttonStyle(.plain)
            }
        }
    }

    private func categoryChip(_ c: LabMarkerCategory?, _ title: LocalizedStringKey) -> some View {
        let on = categoryFilter == c
        return Button { categoryFilter = c } label: {
            Text(title).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .padding(.horizontal, 14).frame(height: 32)
                .background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    /// The catalog without the diastolic half (it is entered with the systolic one), narrowed by the search.
    private var catalog: [MarkerDefinition] {
        let all = MarkerCatalog.builtIn.filter { $0.key != LabBookProjection.bpDiastolicKey && (categoryFilter == nil || $0.category == categoryFilter) }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.displayName.lowercased().contains(q) || $0.key.contains(q) }
    }

    private var valueField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                nunaTrendsCap("Value")
                Spacer()
                if unitOptions.count > 1 {
                    NunaSegmented(unitOptions.indices.map { (value: $0, title: LocalizedStringKey(unitOptions[$0])) }, selection: $unitChoice, compact: true)
                }
            }
            numberBox(placeholder: "e.g. 3.1", text: $valueText, unit: activeUnit, field: .value)
            if unitOptions.count > 1 {
                Text(verbatim: String(localized: "Stored as \(MarkerUnits.canonicalUnit(for: markerKey, fallback: baseUnit)). \(conversionNote)"))
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
        }
    }

    private var pressureFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) { nunaTrendsCap("Systolic"); numberBox(placeholder: "e.g. 120", text: $valueText, unit: "mmHg", field: .value) }
                VStack(alignment: .leading, spacing: 8) { nunaTrendsCap("Diastolic"); numberBox(placeholder: "e.g. 80", text: $diastolicText, unit: "mmHg", field: .diastolic) }
            }
            Text("Entered together; stored as two markers so each lines up cleanly against your signals.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
    }

    private func numberBox(placeholder: LocalizedStringKey, text: Binding<String>, unit: String, field: Field) -> some View {
        HStack(spacing: 8) {
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(NunaPalette.textMuted))
                .font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).keyboardType(.decimalPad).focused($focused, equals: field)
            Text(verbatim: unit).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
        }
        .padding(.horizontal, 14).frame(height: 50).frame(maxWidth: .infinity)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }

    // MARK: Import a file

    @ViewBuilder private var fileContent: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "tablecells").font(.nuna(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 40, height: 40).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                    Text("Import readings").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                }
                Text("Fill in the template, or bring a CSV or a FHIR file (.json) from your lab. Names that match the catalog fold onto your existing markers; anything else comes in as a custom marker. Rows that can't be read are skipped and counted, never guessed. Everything you import stays on this iPhone.")
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                VStack(alignment: .leading, spacing: 8) {
                    nunaTrendsCap("Template")
                    Text(verbatim: "date,marker,value,unit,range,note\n2026-10-07,LDL cholesterol,3.1,mmol/L,<3.4,\n2026-10-07,Weight,75,kg,,").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(NunaPalette.textPrimary)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
                    Text("date as yyyy-MM-dd · range and note are optional · copy the range from your own report. Blood pressure goes on two lines, systolic and diastolic.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                if let template = NunaLabStore.templateFile() {
                    ShareLink(item: template, subject: Text("Lab Book template"), message: Text("Lab Book template")) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc").font(.nuna(size: 15, weight: .bold))
                            Text("Download template").font(.nuna(size: 17, weight: .bold))
                        }
                        .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 54)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Button { Task { await chooseFile() } } label: {
                    HStack(spacing: 8) {
                        if importing { ProgressView().tint(NunaPalette.onAccent) } else { Image(systemName: "square.and.arrow.down").font(.nuna(size: 15, weight: .bold)) }
                        Text("Choose file…").font(.nuna(size: 17, weight: .bold))
                    }
                    .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                    .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(importing)
                if let importSummary {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: importFailed ? "exclamationmark.circle.fill" : "checkmark.circle.fill").foregroundStyle(importFailed ? NunaPalette.warning : NunaPalette.charge)
                        Text(verbatim: importSummary).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
            }
        }
    }

    private func chooseFile() async {
        guard let url = await DocumentPicker.importFile([.commaSeparatedText, .plainText, .json]) else { return }
        importing = true; importSummary = nil
        let result = await NunaLabStore.importCsv(url: url, repo: repo) { line in
            live.append(log: "[\(AppModel.logTimeFormatter.string(from: Date()))] Import \(line)")
        }
        importSummary = result.summary; importFailed = result.failed
        importing = false
    }

    // MARK: Selection and units

    private func choose(_ def: MarkerDefinition) {
        selection = def; unitChoice = 0; focused = .value
    }

    private func reset() {
        selection = nil; valueText = ""; diastolicText = ""; unitChoice = 0; search = ""
    }

    private var markerKey: String {
        if let customKeyOverride { return customKeyOverride }
        if let selection { return selection.key }
        return MarkerUnits.slug(customName)
    }

    private var category: LabMarkerCategory { selection?.category ?? .other }
    private var isPressure: Bool { markerKey == LabBookProjection.bpSystolicKey }
    private var baseUnit: String { selection?.canonicalUnit ?? customUnit }
    private var unitOptions: [String] { addingCustom ? [customUnit] : MarkerUnits.options(for: markerKey, canonical: baseUnit) }
    private var activeUnit: String { unitOptions.indices.contains(unitChoice) ? unitOptions[unitChoice] : baseUnit }

    private var conversionNote: String {
        guard unitOptions.count > 1, activeUnit != MarkerUnits.canonicalUnit(for: markerKey, fallback: baseUnit),
              let factor = MarkerUnits.factorToCanonical(markerKey: markerKey, from: activeUnit) else { return "" }
        return String(localized: "× \(MarkerUnits.factorLabel(factor)) on save.")
    }

    // MARK: Build the rows

    private var drafts: [LabMarkerRow] {
        if addingCustom {
            guard !customName.trimmingCharacters(in: .whitespaces).isEmpty, !customUnit.trimmingCharacters(in: .whitespaces).isEmpty, let v = parsed(valueText) else { return [] }
            return [row(key: markerKey, category: .other, value: v, unit: customUnit)]
        }
        guard selection != nil else { return [] }
        if isPressure {
            guard let sys = parsed(valueText), let dia = parsed(diastolicText) else { return [] }
            return [row(key: LabBookProjection.bpSystolicKey, category: .bloodPressure, value: sys, unit: "mmHg"),
                    row(key: LabBookProjection.bpDiastolicKey, category: .bloodPressure, value: dia, unit: "mmHg")]
        }
        guard let raw = parsed(valueText) else { return [] }
        let canonical = MarkerUnits.canonicalUnit(for: markerKey, fallback: baseUnit)
        return [row(key: markerKey, category: category, value: MarkerUnits.toCanonical(markerKey: markerKey, value: raw, from: activeUnit), unit: canonical)]
    }

    private func row(key: String, category: LabMarkerCategory, value: Double, unit: String) -> LabMarkerRow {
        let n = note.trimmingCharacters(in: .whitespaces), ref = referenceText.trimmingCharacters(in: .whitespaces)
        let epoch = Int(takenAt.timeIntervalSince1970)
        return LabMarkerRow(id: "\(key)-\(epoch)-\(UUID().uuidString.prefix(8))", deviceId: repo.deviceId, markerKey: key, category: category.rawValue,
                            day: LabBookFormat.dayKey(takenAt), takenAt: epoch, value: value, valueText: nil, unit: unit, source: "manual",
                            note: n.isEmpty ? nil : n, referenceText: ref.isEmpty ? nil : ref)
    }

    private func parsed(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }

    private func save() {
        let rows = drafts
        guard !rows.isEmpty else { return }
        saving = true
        Task { await onSave(rows); dismiss() }
    }
}
#endif
