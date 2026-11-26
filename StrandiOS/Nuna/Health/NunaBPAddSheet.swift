#if os(iOS)
import SwiftUI
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

// Typing in one blood pressure reading: the two figures and when, and, for anyone who wants them, how the person sat and where the cuff was.

/// How the person was while measuring. The raw words are what is kept in the reading's note.
enum NunaBPPosition: String, CaseIterable, Identifiable {
    case sitting = "Sitting", standing = "Standing", lying = "Lying down", reclining = "Reclining"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sitting: return String(localized: "bp.position.sitting", defaultValue: "Sitting")
        case .standing: return String(localized: "bp.position.standing", defaultValue: "Standing")
        case .lying: return String(localized: "bp.position.lying", defaultValue: "Lying down")
        case .reclining: return String(localized: "bp.position.reclining", defaultValue: "Reclining")
        }
    }
}

/// Where the cuff was.
enum NunaBPSite: String, CaseIterable, Identifiable {
    case leftUpperArm = "Left upper arm", rightUpperArm = "Right upper arm", leftWrist = "Left wrist", rightWrist = "Right wrist"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .leftUpperArm: return String(localized: "bp.site.leftUpperArm", defaultValue: "Left upper arm")
        case .rightUpperArm: return String(localized: "bp.site.rightUpperArm", defaultValue: "Right upper arm")
        case .leftWrist: return String(localized: "bp.site.leftWrist", defaultValue: "Left wrist")
        case .rightWrist: return String(localized: "bp.site.rightWrist", defaultValue: "Right wrist")
        }
    }
}

/// The two optional facts of a reading, kept in the note of its Lab Book rows as plain English words ("Position: Sitting; Cuff: Left wrist"), so an
/// export reads without the app, and shown in the person's language.
enum NunaBPContext {
    static func note(position: NunaBPPosition?, site: NunaBPSite?) -> String? {
        let parts = [position.map { "Position: " + $0.rawValue }, site.map { "Cuff: " + $0.rawValue }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    static func parse(_ note: String?) -> (position: NunaBPPosition?, site: NunaBPSite?) {
        var position: NunaBPPosition?, site: NunaBPSite?
        for part in (note ?? "").components(separatedBy: ";") {
            let t = part.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Position: ") { position = NunaBPPosition(rawValue: String(t.dropFirst(10))) }
            if t.hasPrefix("Cuff: ") { site = NunaBPSite(rawValue: String(t.dropFirst(6))) }
        }
        return (position, site)
    }

    /// "Sitting · Left upper arm" in the person's language; nil when the note holds neither.
    static func display(_ note: String?) -> String? {
        let c = parse(note)
        let parts = [c.position?.title, c.site?.title].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The sheet: systolic, diastolic and the date and time are needed; position and cuff place may be left out, and a second tap takes a choice back.
struct NunaBPAddSheet: View {
    let onSave: (_ drafts: [LabMarkerRow]) async -> Void

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var systolicText = ""
    @State private var diastolicText = ""
    @State private var takenAt = Date()
    @State private var position: NunaBPPosition?
    @State private var site: NunaBPSite?
    @State private var saving = false
    @State private var showInfo = false

    private enum Field: Hashable { case systolic, diastolic }
    @FocusState private var focused: Field?

    private var systolic: Int? { Int(systolicText) }
    private var diastolic: Int? { Int(diastolicText) }
    /// A pair that can be a blood pressure: each figure in a believable range and the upper one higher.
    private var valid: (Int, Int)? {
        guard let s = systolic, let d = diastolic, (50...300).contains(s), (30...200).contains(d), s > d else { return nil }
        return (s, d)
    }

    var body: some View {
        // In a navigation stack so the number pad gets its buttons: it has no return key of its own.
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    infoChip
                    figures
                    when
                    choices(title: "Position", options: NunaBPPosition.allCases.map { ($0.id, $0.title) }, selected: position?.id) { id in
                        position = position?.id == id ? nil : NunaBPPosition(rawValue: id)
                    }
                    choices(title: "Where measured", options: NunaBPSite.allCases.map { ($0.id, $0.title) }, selected: site?.id) { id in
                        site = site?.id == id ? nil : NunaBPSite(rawValue: id)
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            // Out of the way while a figure is typed, so it does not float over the choices above the number pad.
            .safeAreaInset(edge: .bottom, spacing: 0) { if focused == nil { saveBar } }
            .background(NunaBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if focused == .systolic { Button("Next") { focused = .diastolic } } else { Button("Done") { focused = nil } }
                }
            }
        }
        .preferredColorScheme(NunaTheme.colorScheme)
        .sheet(isPresented: $showInfo) {
            ScrollView { NunaBPMeasureInfo().padding(NunaSpacing.screenH) }
                .background(NunaBackdrop()).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                .preferredColorScheme(NunaTheme.colorScheme)
        }
        .task {
            // After the sheet has arrived, so the keyboard does not fight its animation.
            try? await Task.sleep(nanoseconds: 450_000_000)
            if systolicText.isEmpty { focused = .systolic }
        }
    }

    private var header: some View {
        ZStack {
            Text("Add reading").font(.nuna(size: 16, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Close"))
                Spacer()
            }
        }
        .padding(.horizontal, NunaSpacing.screenH - 10).padding(.top, 14).padding(.bottom, 8)
        .background(NunaBackdrop(top: true))
    }

    private var infoChip: some View {
        Button { focused = nil; showInfo = true } label: {
            HStack(spacing: 8) {
                Text("How to measure").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                Image(systemName: "info.circle").font(.nuna(size: 15, weight: .regular))
            }
            .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 34)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain).frame(maxWidth: .infinity)
    }

    private var figures: some View {
        NunaCard {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 0) {
                    figure("Systolic", text: $systolicText, prompt: "120", field: .systolic)
                    Text(verbatim: "/").font(.nuna(size: 40, weight: .regular, design: NunaType.design)).foregroundStyle(NunaPalette.textMuted).padding(.top, 30)
                    figure("Diastolic", text: $diastolicText, prompt: "80", field: .diastolic)
                }
                if let (s, d) = valid {
                    let c = NunaBPCategory.of(Double(s), Double(d))
                    Text(verbatim: c.wordText).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(c.color)
                } else if systolicText.count >= 2, diastolicText.count >= 2, focused != .diastolic {
                    Text("Check the figures: systolic 50 to 300, diastolic 30 to 200, and systolic the higher of the two.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).multilineTextAlignment(.center).textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func figure(_ title: LocalizedStringKey, text: Binding<String>, prompt: String, field: Field) -> some View {
        VStack(spacing: 4) {
            nunaTrendsCap(title)
            TextField("", text: text, prompt: Text(verbatim: prompt).foregroundStyle(NunaPalette.textMuted.opacity(0.5)))
                .font(.nuna(size: 52, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                .multilineTextAlignment(.center).keyboardType(.numberPad).focused($focused, equals: field)
                .frame(maxWidth: .infinity).frame(height: 66)
                .accessibilityLabel(Text(title))
                .onChange(of: text.wrappedValue) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(3))
                    if digits != new { text.wrappedValue = digits }
                    // Three figures finish the upper one.
                    if field == .systolic, digits.count == 3, focused == .systolic { focused = .diastolic }
                }
            Text(verbatim: "mmHg").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { focused = field }
    }

    private var when: some View {
        NunaCard(small: true) {
            HStack(spacing: 12) {
                NunaIcon(name: "clock", size: 18, weight: .regular).foregroundStyle(NunaPalette.textSecondary)
                VStack(alignment: .leading, spacing: 8) {
                    nunaTrendsCap("Date and time")
                    DatePicker("", selection: $takenAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func choices(title: LocalizedStringKey, options: [(id: String, title: String)], selected: String?, pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                nunaTrendsCap(title)
                Spacer()
                Text("Optional").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(options, id: \.id) { o in
                    let on = selected == o.id
                    Button { focused = nil; pick(o.id) } label: {
                        Text(verbatim: o.title).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
                            .textCase(nil).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 6)
                            .background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var saveBar: some View {
        Button { save() } label: { Text("Save") }
            .buttonStyle(.nuna(.primary, fullWidth: true))
            .disabled(valid == nil || saving).opacity(valid == nil || saving ? 0.4 : 1)
            .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 12)
            .background(NunaPalette.canvas)
    }

    private func save() {
        guard let (s, d) = valid else { return }
        saving = true
        let epoch = Int(takenAt.timeIntervalSince1970)
        let note = NunaBPContext.note(position: position, site: site)
        let rows = [(LabBookProjection.bpSystolicKey, s), (LabBookProjection.bpDiastolicKey, d)].map { key, value in
            LabMarkerRow(id: "\(key)-\(epoch)-\(UUID().uuidString.prefix(8))", deviceId: repo.deviceId, markerKey: key,
                         category: LabMarkerCategory.bloodPressure.rawValue, day: LabBookFormat.dayKey(takenAt), takenAt: epoch,
                         value: Double(value), valueText: nil, unit: "mmHg", source: "manual", note: note, referenceText: nil)
        }
        // The sheet leaves at once: saving also refreshes the app's data, which takes a few seconds, and the page redraws itself when that is done.
        Task { await onSave(rows) }
        dismiss()
    }
}
#endif
