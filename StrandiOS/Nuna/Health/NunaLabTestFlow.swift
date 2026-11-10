#if os(iOS)
import SwiftUI
import Foundation
import UniformTypeIdentifiers
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

/// Adding a set of results to the Lab Book, in steps: what to know and where the results come from (a file, or by hand), then for a test by hand its
/// name and when it was collected, which markers it covers, and the numbers. A file's results are read as they are, a typed test is stored with the
/// name in the note of each reading, all at the same moment, so they list together as one test. Nothing is sent anywhere.
struct NunaLabTestFlow: View {
    let onDone: () async -> Void

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @Environment(\.dismiss) private var dismiss

    private enum Step { case intro, details, pick, values }
    @State private var step: Step = .intro

    @State private var name = ""
    @State private var date = Date()

    @State private var picked: [String] = []
    @State private var customs: [Custom] = []
    @State private var search = ""
    @State private var addingCustom = false
    @State private var customName = ""
    @State private var customUnit = ""

    @State private var entries: [String: Entry] = [:]
    @State private var saving = false

    @State private var importing = false
    @State private var importMessage: String?

    private struct Custom: Identifiable, Equatable { let id: String; let name: String; let unit: String }
    private struct Entry { var value = ""; var diastolic = ""; var unit = 0; var range = "" }

    private enum Field: Hashable { case name, search, customName, customUnit, value(String), diastolic(String), range(String) }
    @FocusState private var focused: Field?

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case .intro: intro
                    case .details: details
                    case .pick: pick
                    case .values: values
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 14).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(NunaBackdrop())
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil } } }
    }

    private var header: some View {
        ZStack {
            Text(stepTitle).font(.nuna(size: 16, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            HStack {
                Button { back() } label: {
                    Image(systemName: step == .intro ? "xmark" : "chevron.left").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(Text(step == .intro ? "Close" : "Back"))
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4)
    }

    private var stepTitle: LocalizedStringKey {
        switch step {
        case .intro, .details: return "Add results"
        case .pick: return "Edit biomarkers"
        case .values: return "Enter results"
        }
    }

    private func back() {
        focused = nil
        switch step {
        case .intro: dismiss()
        case .details: step = .intro
        case .pick: step = .details
        case .values: step = .pick
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        switch step {
        case .intro:
            VStack(spacing: 12) {
                if let importMessage {
                    Text(verbatim: importMessage).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                primary("Choose from files", busy: importing) { Task { await chooseFile() } }.disabled(importing)
                Button { step = .details } label: {
                    Text("Enter by hand").font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(NunaPalette.textPrimary.opacity(0.7), lineWidth: 2))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 12)
        case .details:
            primary("Next") { focused = nil; step = .pick }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 12)
        case .pick:
            let none = picked.isEmpty && customs.isEmpty
            primary("Next") { focused = nil; step = .values }.disabled(none).opacity(none ? 0.4 : 1)
                .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 12)
        case .values:
            let none = drafts.isEmpty || saving
            primary("Save", busy: saving) { save() }.disabled(none).opacity(none ? 0.4 : 1)
                .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 12)
        }
    }

    private func primary(_ title: LocalizedStringKey, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(NunaPalette.onAccent) }
                Text(title).font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
            }
            .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: Step 1 — what to know

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What to know before adding").font(.nuna(size: 28, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            VStack(spacing: 0) {
                tip("lock", "Lab Book keeps your own numbers. It doesn't test, read or judge them. Everything stays on this iPhone.")
                NunaDivider()
                tip("slider.horizontal.3", "A range comes from your own report. Type it in with a result and the page shows which markers sit inside it.")
                NunaDivider()
                tip("tablecells", "A file can be the Lab Book template (CSV), a WHOOP biomarker export or a FHIR file (.json).")
                NunaDivider()
                tip("calendar", "Add one set of results at a time, with the date it was collected.")
                NunaDivider()
                tip("hand.raised", "Rows that can't be read are skipped and counted, never guessed.")
            }
            .padding(.horizontal, 18).background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
            if let template = NunaLabStore.templateFile() {
                ShareLink(item: template, subject: Text("Lab Book template"), message: Text("Lab Book template")) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc").font(.nuna(size: 15, weight: .bold))
                        Text("Download template").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    }.foregroundStyle(NunaPalette.textSecondary)
                }.buttonStyle(.plain)
            }
        }
    }

    private func tip(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol).font(.nuna(size: 22, weight: .regular)).foregroundStyle(NunaPalette.effortModerate).frame(width: 34)
            Text(text).font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            Spacer(minLength: 0)
        }.padding(.vertical, 16)
    }

    private func chooseFile() async {
        guard let url = await DocumentPicker.importFile([.commaSeparatedText, .plainText, .json]) else { return }
        importing = true; importMessage = nil
        let result = await NunaLabStore.importCsv(url: url, repo: repo) { line in
            live.append(log: "[\(AppModel.logTimeFormatter.string(from: Date()))] Import \(line)")
        }
        importing = false
        if result.failed { importMessage = result.summary } else { await onDone(); dismiss() }
    }

    // MARK: Step 2 — test details

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "list.clipboard").font(.nuna(size: 54, weight: .light)).foregroundStyle(NunaPalette.textMuted).padding(.top, 10)
            VStack(alignment: .leading, spacing: 8) {
                Text("Add test details").font(.nuna(size: 28, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text("Name the test and say when the sample was collected.").font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            fieldLabel("Test name")
            TextField("", text: $name, prompt: Text("e.g. Annual check-up").foregroundStyle(NunaPalette.textMuted))
                .font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).focused($focused, equals: .name)
                .padding(.horizontal, 16).frame(height: 54).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
            fieldLabel("Date collected")
            HStack {
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: [.date]).labelsHidden()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 54).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
            fieldLabel("Time collected")
            HStack {
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: [.hourAndMinute]).labelsHidden()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 54).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
        }
    }

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).padding(.top, 6)
    }

    // MARK: Step 3 — which markers

    /// The catalog without the diastolic half (entered with the systolic one) and without body measurements (those have their own pages), A to Z.
    private var catalog: [MarkerDefinition] {
        let all = MarkerCatalog.builtIn.filter { $0.key != LabBookProjection.bpDiastolicKey && $0.category != .bodyMeasurement }
            .sorted { Self.title($0).localizedCaseInsensitiveCompare(Self.title($1)) == .orderedAscending }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { Self.title($0).lowercased().contains(q) || $0.key.contains(q) }
    }

    private static func title(_ d: MarkerDefinition) -> String { d.key == LabBookProjection.bpSystolicKey ? String(localized: "Blood pressure") : d.displayName }

    private var pick: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Confirm the biomarkers tested").font(.nuna(size: 26, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                TextField("", text: $search, prompt: Text("Search for Vitamin D, Cortisol, etc.").foregroundStyle(NunaPalette.textMuted))
                    .font(.nunaWords(size: 16)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).focused($focused, equals: .search)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 16).frame(height: 54).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 22) {
                ForEach(customs) { c in
                    box(c.name, on: true) { customs.removeAll { $0.id == c.id }; entries[c.id] = nil }
                }
                ForEach(catalog, id: \.key) { d in
                    box(Self.title(d), on: picked.contains(d.key)) {
                        if let i = picked.firstIndex(of: d.key) { picked.remove(at: i) } else { picked.append(d.key) }
                    }
                }
                if catalog.isEmpty && !search.isEmpty {
                    Text("No match. Add it as a custom marker below.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                customAdder
            }
            .padding(.top, 4)
        }
    }

    private func box(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? NunaPalette.accent : NunaPalette.textPrimary, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? NunaPalette.accent : Color.clear))
                    .frame(width: 34, height: 34)
                    .overlay { if on { Image(systemName: "checkmark").font(.nuna(size: 16, weight: .heavy)).foregroundStyle(NunaPalette.onAccent) } }
                Text(verbatim: title).font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var customAdder: some View {
        if addingCustom {
            VStack(alignment: .leading, spacing: 12) {
                NunaFormField("Name") {
                    TextField("", text: $customName, prompt: Text("e.g. Magnesium").foregroundStyle(NunaPalette.textMuted)).focused($focused, equals: .customName)
                }
                NunaFormField("Unit") {
                    TextField("", text: $customUnit, prompt: Text("e.g. mmol/L").foregroundStyle(NunaPalette.textMuted)).focused($focused, equals: .customUnit)
                }
                HStack(spacing: 12) {
                    Button("Cancel") { addingCustom = false; customName = ""; customUnit = "" }
                        .font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).buttonStyle(.plain)
                    Spacer()
                    let ok = !customName.trimmingCharacters(in: .whitespaces).isEmpty && !customUnit.trimmingCharacters(in: .whitespaces).isEmpty
                    Button("Add") {
                        let n = customName.trimmingCharacters(in: .whitespaces), u = customUnit.trimmingCharacters(in: .whitespaces)
                        customs.append(Custom(id: MarkerUnits.slug(n), name: n, unit: u))
                        addingCustom = false; customName = ""; customUnit = ""
                    }
                    .font(.nuna(size: 14, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).buttonStyle(.plain).disabled(!ok).opacity(ok ? 1 : 0.4)
                }
            }
            .padding(16).background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
        } else {
            Button { addingCustom = true; focused = .customName } label: {
                Label("Add a custom marker", systemImage: "plus").font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            }.buttonStyle(.plain)
        }
    }

    // MARK: Step 4 — the numbers

    private var selectedDefinitions: [MarkerDefinition] { picked.compactMap { MarkerCatalog.definition(for: $0) } }

    private var values: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: name.trimmingCharacters(in: .whitespaces)).font(.nuna(size: 28, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text("Type the results you have. A marker left empty is skipped.").font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            ForEach(selectedDefinitions, id: \.key) { d in entryCard(key: d.key, title: Self.title(d), base: d.canonicalUnit, pressure: d.key == LabBookProjection.bpSystolicKey, custom: false) }
            ForEach(customs) { c in entryCard(key: c.id, title: c.name, base: c.unit, pressure: false, custom: true) }
            Text("NOOP never fills the range in. It only shows back what you type from your own report.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
    }

    private func binding(_ key: String) -> Binding<Entry> {
        Binding(get: { entries[key] ?? Entry() }, set: { entries[key] = $0 })
    }

    private func entryCard(key: String, title: String, base: String, pressure: Bool, custom: Bool) -> some View {
        let options = custom ? [base] : MarkerUnits.options(for: key, canonical: base)
        let e = binding(key)
        let active = options.indices.contains(e.wrappedValue.unit) ? options[e.wrappedValue.unit] : base
        return NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(verbatim: title).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    Spacer(minLength: 6)
                    if options.count > 1 {
                        NunaSegmented(options.indices.map { (value: $0, title: LocalizedStringKey(options[$0])) }, selection: e.unit, compact: true)
                    }
                }
                if pressure {
                    HStack(spacing: 12) {
                        numberBox("e.g. 120", text: e.value, unit: "mmHg", field: .value(key))
                        numberBox("e.g. 80", text: e.diastolic, unit: "mmHg", field: .diastolic(key))
                    }
                } else {
                    numberBox("e.g. 3.1", text: e.value, unit: active, field: .value(key))
                }
                NunaFormField("Range from my report (optional)") {
                    TextField("", text: e.range, prompt: Text("e.g. 2.0-5.0").foregroundStyle(NunaPalette.textMuted)).textCase(nil).focused($focused, equals: .range(key))
                }
            }
        }
    }

    private func numberBox(_ placeholder: LocalizedStringKey, text: Binding<String>, unit: String, field: Field) -> some View {
        HStack(spacing: 8) {
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(NunaPalette.textMuted))
                .font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).keyboardType(.decimalPad).focused($focused, equals: field)
            Text(verbatim: unit).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
        }
        .padding(.horizontal, 14).frame(height: 50).frame(maxWidth: .infinity)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }

    // MARK: Build and save

    private func parsed(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }

    private var drafts: [LabMarkerRow] {
        let testName = name.trimmingCharacters(in: .whitespaces)
        let epoch = Int(date.timeIntervalSince1970)
        let day = LabBookFormat.dayKey(date)
        func row(_ key: String, _ category: LabMarkerCategory, _ value: Double, _ unit: String, _ range: String) -> LabMarkerRow {
            let ref = range.trimmingCharacters(in: .whitespaces)
            return LabMarkerRow(id: "\(key)-\(epoch)-\(UUID().uuidString.prefix(8))", deviceId: repo.deviceId, markerKey: key, category: category.rawValue, day: day, takenAt: epoch,
                                value: value, valueText: nil, unit: unit, source: "manual", note: testName.isEmpty ? nil : testName, referenceText: ref.isEmpty ? nil : ref)
        }
        var out: [LabMarkerRow] = []
        for d in selectedDefinitions {
            let e = entries[d.key] ?? Entry()
            if d.key == LabBookProjection.bpSystolicKey {
                guard let sys = parsed(e.value), let dia = parsed(e.diastolic) else { continue }
                out.append(row(LabBookProjection.bpSystolicKey, .bloodPressure, sys, "mmHg", e.range))
                out.append(row(LabBookProjection.bpDiastolicKey, .bloodPressure, dia, "mmHg", ""))
                continue
            }
            guard let raw = parsed(e.value) else { continue }
            let options = MarkerUnits.options(for: d.key, canonical: d.canonicalUnit)
            let from = options.indices.contains(e.unit) ? options[e.unit] : d.canonicalUnit
            let canonical = MarkerUnits.canonicalUnit(for: d.key, fallback: d.canonicalUnit)
            out.append(row(d.key, d.category, MarkerUnits.toCanonical(markerKey: d.key, value: raw, from: from), canonical, e.range))
        }
        for c in customs {
            guard let v = parsed((entries[c.id] ?? Entry()).value) else { continue }
            out.append(row(c.id, .other, v, c.unit, (entries[c.id] ?? Entry()).range))
        }
        return out
    }

    private func save() {
        let rows = drafts
        guard !rows.isEmpty else { return }
        saving = true
        Task { await NunaLabStore.save(rows, repo: repo); await onDone(); dismiss() }
    }
}
#endif
