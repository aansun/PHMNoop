#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

extension Notification.Name {
    /// A weight, body fat or lean mass reading was added by hand: the pages that show them read their series again.
    static let nunaBodyMeasurementChanged = Notification.Name("nuna.bodyMeasurementChanged")
}

/// "Add manual measurement": the day, then weight, body fat and lean body mass. Lean mass follows from the other two (and body fat from lean mass and weight),
/// so a typed pair never disagrees with the third. Readings are kept under the manual source, next to the ones Apple Health brings.
struct NunaManualBodySheet: View {
    let initialWeightKg: Double?
    let initialFat: Double?

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nuna.body.useLbs") private var useLbs = false
    @State private var day = Date()
    @State private var weightText = ""
    @State private var fatText = ""
    @State private var leanText = ""
    @FocusState private var focus: Field?
    private enum Field { case weight, fat, lean }

    private static let kgPerLb = 0.45359237

    // MARK: Values

    private func parse(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
    private var weightKg: Double? { parse(weightText).map { useLbs ? $0 * Self.kgPerLb : $0 } }
    private var fat: Double? { parse(fatText) }
    private var leanKg: Double? { parse(leanText).map { useLbs ? $0 * Self.kgPerLb : $0 } }

    private func show(_ kg: Double) -> String { fmt(useLbs ? kg / Self.kgPerLb : kg) }
    private func fmt(_ v: Double) -> String { String(format: "%.1f", locale: AppLanguage.activeLocale, v) }

    private var weightOK: Bool { weightKg.map { (25...250).contains($0) } ?? false }
    private var fatOK: Bool { fat.map { (3...60).contains($0) } ?? false }
    private var leanOK: Bool { leanKg.map { (10...200).contains($0) } ?? false }
    /// Something to keep: a weight, a body fat, or a lean mass; every field that has text must be a sensible figure.
    private var canSave: Bool {
        (weightOK || fatOK || leanOK)
            && (weightText.isEmpty || weightOK) && (fatText.isEmpty || fatOK) && (leanText.isEmpty || leanOK)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var dayLabel: String {
        if isToday { return String(localized: "Today") }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return f.string(from: day)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44, alignment: .leading) }
                    .buttonStyle(.plain).accessibilityLabel(Text("Close"))
                Spacer()
                Text("Add manual measurement").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    nunaRuledHeader("When")
                    line("What day?") { dayPill }
                    nunaRuledHeader("Measurements").padding(.top, 8)
                    VStack(alignment: .leading, spacing: 10) {
                        label("Weight")
                        HStack(spacing: 12) {
                            field($weightText, .weight, unit: nil)
                            unitSwitch
                        }
                    }
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) { label("Body fat"); field($fatText, .fat, unit: "%") }
                        VStack(alignment: .leading, spacing: 10) { label("Lean body mass"); field($leanText, .lean, unit: useLbs ? "lbs" : "kg") }
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 22)
            }
            .scrollIndicators(.hidden)

            Button(action: save) {
                Text("Add measurement").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase)
                    .foregroundStyle(canSave ? NunaPalette.recoveryBlue : NunaPalette.textMuted)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .overlay(Capsule().strokeBorder(canSave ? NunaPalette.recoveryBlue : NunaPalette.textMuted.opacity(0.5), lineWidth: 2))
            }
            .buttonStyle(.plain).disabled(!canSave)
            .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 14).padding(.top, 8)
        }
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
        .presentationDragIndicator(.visible)
        .onAppear(perform: fill)
        .onChange(of: weightText) { _, _ in if focus == .weight { fromWeightOrFat() } }
        .onChange(of: fatText) { _, _ in if focus == .fat { fromWeightOrFat() } }
        .onChange(of: leanText) { _, _ in if focus == .lean { fromLean() } }
        .onChange(of: useLbs) { old, new in convert(from: old, to: new) }
    }

    // MARK: Pieces

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
    }

    private func line<Trailing: View>(_ key: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(key).font(.nunaWords(size: 17)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 8)
            trailing()
        }
    }

    /// The day as a pill; a date picker sits invisibly over it, so a tap opens the system calendar.
    private var dayPill: some View {
        Text(verbatim: dayLabel).font(.nunaWords(size: 16)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textPrimary)
            .padding(.horizontal, 18).frame(height: 44)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                DatePicker("", selection: $day, in: ...Date(), displayedComponents: .date).labelsHidden().blendMode(.destinationOver).opacity(0.015)
            }
    }

    private func field(_ text: Binding<String>, _ which: Field, unit: String?) -> some View {
        HStack(spacing: 6) {
            TextField("", text: text).keyboardType(.decimalPad).focused($focus, equals: which)
                .font(.nunaWords(size: 18)).tracking(0).foregroundStyle(NunaPalette.textPrimary)
            if let unit { Text(verbatim: unit).font(.nunaWords(size: 16)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary) }
        }
        .padding(.horizontal, 18).frame(height: 62).frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focus == which ? NunaPalette.recoveryBlue : NunaPalette.hairline, lineWidth: focus == which ? 2 : 1))
        .contentShape(Rectangle()).onTapGesture { focus = which }
    }

    private var unitSwitch: some View {
        HStack(spacing: 0) {
            ForEach([true, false], id: \.self) { lbs in
                Button { useLbs = lbs } label: {
                    Text(lbs ? "lbs" : "kg").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 50)
                        .background(useLbs == lbs ? NunaPalette.glassStrong : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6).frame(maxWidth: .infinity).frame(height: 62)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Behaviour

    /// Starts from the latest readings, with lean mass worked out from them.
    private func fill() {
        if let w = initialWeightKg { weightText = show(w) }
        if let f = initialFat { fatText = fmt(f) }
        if let w = initialWeightKg, let f = initialFat { leanText = show(w * (1 - f / 100)) }
    }

    private func fromWeightOrFat() {
        guard let w = weightKg, let f = fat, weightOK, fatOK else { return }
        leanText = show(w * (1 - f / 100))
    }

    private func fromLean() {
        guard let w = weightKg, let l = leanKg, weightOK, l > 0, l <= w else { return }
        fatText = fmt((1 - l / w) * 100)
    }

    /// The figures on show change with the unit; what they stand for does not.
    private func convert(from old: Bool, to new: Bool) {
        func swap(_ s: String) -> String {
            guard let v = parse(s) else { return s }
            let kg = old ? v * Self.kgPerLb : v
            return fmt(new ? kg / Self.kgPerLb : kg)
        }
        weightText = swap(weightText)
        leanText = swap(leanText)
    }

    private func save() {
        let key = Repository.localDayKey(day)
        var points: [MetricPoint] = []
        if weightOK, let w = weightKg { points.append(MetricPoint(day: key, key: "weight", value: (w * 10).rounded() / 10)) }
        if fatOK, let f = fat { points.append(MetricPoint(day: key, key: "body_fat", value: f)) }
        if leanOK, let l = leanKg { points.append(MetricPoint(day: key, key: "lean_mass", value: (l * 10).rounded() / 10)) }
        guard !points.isEmpty else { return }
        let weight = weightOK ? weightKg : nil
        let today = isToday
        Task {
            guard let store = await repo.storeHandle() else { return }
            _ = try? await store.upsertMetricSeries(points, deviceId: nunaManualSource)
            if today, let weight { profile.weightKg = weight }
            NotificationCenter.default.post(name: .nunaBodyMeasurementChanged, object: nil)
            dismiss()
        }
    }
}

/// The two rows under the weight and lean body mass pages: add a reading by hand, and the list of everything recorded.
struct NunaBodyRows: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var weightS = NunaSeriesModel()
    @StateObject private var fatS = NunaSeriesModel()
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 12) {
            Button { showAdd = true } label: { row("plus", "Add manual measurement") }.buttonStyle(.plain)
            NavigationLink { NunaBodyRecordingsView() } label: { row("list.bullet", "See all recordings") }.buttonStyle(.plain)
        }
        .sheet(isPresented: $showAdd) {
            NunaManualBodySheet(initialWeightKg: weightS.latest?.value, initialFat: fatS.latest?.value)
        }
        .task(id: repo.refreshSeq) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .nunaBodyMeasurementChanged)) { _ in Task { await load() } }
    }

    private func load() async {
        await weightS.load(repo: repo, key: "weight", source: "apple-health", days: 400, also: nunaManualSource)
        await fatS.load(repo: repo, key: "body_fat", source: "apple-health", days: 400, also: nunaManualSource)
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(NunaPalette.textSecondary).frame(width: 34)
            Text(title).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(height: 64).frame(maxWidth: .infinity)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// What sits under the weight page: the two rows, then what weight is.
struct NunaWeightFooter: View {
    var body: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaBodyRows()
            NunaTrendInfo(kind: .weight)
        }
    }
}
#endif
