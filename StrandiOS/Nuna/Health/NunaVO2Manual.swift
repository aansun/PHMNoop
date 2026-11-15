#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

extension Notification.Name {
    /// A VO₂ max typed in by hand was added or removed: the pages that show it read their series again.
    static let nunaManualVO2Changed = Notification.Name("nuna.manualVO2Changed")
}

/// A VO₂ max the wearer typed in (a lab test, another device or app). It is kept under the manual source, away from the weekly estimate, and read next to it:
/// `Repository.exploreSeries` lays it over the estimate for its day, so the trend page, Fitness Age and the Today tile all see it.
enum NunaVO2Manual {
    static let key = "vo2max_est"
    /// Where the value came from, kept beside it under this key as the case number.
    static let sourceKey = "vo2max_manual_src"
    static let range: ClosedRange<Double> = 10...90

    enum Source: Int, CaseIterable, Identifiable {
        case lab = 1, device, other
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .lab: return String(localized: "VO₂ Max Lab Assessment")
            case .device: return String(localized: "Another Device or App")
            case .other: return String(localized: "Other")
            }
        }
    }

    struct Entry: Identifiable, Equatable {
        let day: String
        let value: Double
        let source: Source?
        var id: String { day }
    }

    @MainActor static func entries(repo: Repository) async -> [Entry] {
        let values = await repo.exploreSeries(key: key, source: nunaManualSource, days: 4000)
        let sources = Dictionary(uniqueKeysWithValues: await repo.exploreSeries(key: sourceKey, source: nunaManualSource, days: 4000).map { ($0.day, Int($0.value)) })
        return values.map { Entry(day: $0.day, value: $0.value, source: sources[$0.day].flatMap(Source.init(rawValue:))) }.sorted { $0.day > $1.day }
    }

    @MainActor static func save(repo: Repository, date: Date, value: Double, source: Source) async {
        guard let store = await repo.storeHandle() else { return }
        let day = Repository.localDayKey(date)
        _ = try? await store.upsertMetricSeries([MetricPoint(day: day, key: key, value: value), MetricPoint(day: day, key: sourceKey, value: Double(source.rawValue))], deviceId: nunaManualSource)
        NotificationCenter.default.post(name: .nunaManualVO2Changed, object: nil)
    }

    @MainActor static func delete(repo: Repository, day: String) async {
        guard let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteMetricSeriesPoint(deviceId: nunaManualSource, day: day, key: key)
        _ = try? await store.deleteMetricSeriesPoint(deviceId: nunaManualSource, day: day, key: sourceKey)
        NotificationCenter.default.post(name: .nunaManualVO2Changed, object: nil)
    }
}

/// "Add manual value": the day of the assessment, the figure, and where it came from.
struct NunaVO2ManualSheet: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var showDate = false
    @State private var text = ""
    @State private var sourceIndex = 0
    @State private var showSource = false
    @FocusState private var focused: Bool

    private var value: Double? {
        Double(text.replacingOccurrences(of: ",", with: ".")).flatMap { NunaVO2Manual.range.contains($0) ? $0 : nil }
    }
    private var source: NunaVO2Manual.Source? { NunaVO2Manual.Source(rawValue: sourceIndex) }
    private var canAdd: Bool { value != nil && source != nil }

    private var dateTitle: String {
        if Calendar.current.isDateInToday(date) { return String(localized: "Today") }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return f.string(from: date)
    }

    var body: some View {
        ZStack {
            NunaBackdrop()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        nunaRuledHeader("When")
                        HStack(spacing: 12) {
                            Text("When was your VO₂ Max assessment?").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button { withAnimation(.easeInOut(duration: 0.2)) { showDate.toggle(); showSource = false; focused = false } } label: {
                                Text(verbatim: dateTitle).font(.nuna(size: 14, weight: .semibold)).textCase(nil)
                                    .foregroundStyle(showDate ? Color(red: 0.03, green: 0.04, blue: 0.07) : NunaPalette.textPrimary)
                                    .padding(.horizontal, 16).frame(height: 38)
                                    .background(showDate ? AnyShapeStyle(NunaPalette.recoveryBlue) : AnyShapeStyle(NunaPalette.glassStrong), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                        if showDate {
                            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).datePickerStyle(.wheel).labelsHidden()
                                .frame(maxWidth: .infinity).environment(\.locale, AppLanguage.activeLocale)
                        }
                        nunaRuledHeader("Value").padding(.top, 8)
                        Text("VO₂ max").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        HStack(spacing: 8) {
                            TextField("40", text: $text).keyboardType(.decimalPad).focused($focused)
                                .font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: "mL/kg/min").font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        .padding(.horizontal, 16).frame(height: 52)
                        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
                        Text("Source").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).padding(.top, 6)
                        Button { withAnimation(.easeInOut(duration: 0.2)) { showSource.toggle(); showDate = false; focused = false } } label: {
                            Text(verbatim: source?.title ?? "---").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }.buttonStyle(.plain)
                        if showSource {
                            Picker("", selection: $sourceIndex) {
                                Text(verbatim: "---").tag(0)
                                ForEach(NunaVO2Manual.Source.allCases) { Text(verbatim: $0.title).textCase(nil).tag($0.rawValue) }
                            }
                            .pickerStyle(.wheel).labelsHidden().frame(height: 150)
                        }
                        Text("We recommend only entering values from a lab that performs standard VO₂ Max assessments.")
                            .font(.nuna(size: 13, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.top, 14)
                    }
                    .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                addButton
            }
        }
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    private var header: some View {
        ZStack {
            Text("Add manual value").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel(Text("Close"))
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
    }

    private var addButton: some View {
        Button {
            guard let v = value, let s = source else { return }
            Task { await NunaVO2Manual.save(repo: repo, date: date, value: v, source: s); dismiss() }
        } label: {
            Text("Add value").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(NunaPalette.recoveryBlue)
                .frame(maxWidth: .infinity).frame(height: 56)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NunaPalette.recoveryBlue, lineWidth: 2))
        }
        .buttonStyle(.plain).disabled(!canAdd).opacity(canAdd ? 1 : 0.4)
        .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 14).padding(.top, 8)
    }
}

/// Every VO₂ max entered by hand, newest first, with where it came from. A row is removed with its bin.
struct NunaVO2ManualRecordingsView: View {
    @EnvironmentObject private var repo: Repository
    @State private var entries: [NunaVO2Manual.Entry] = []
    @State private var showAdd = false

    var body: some View {
        NunaDetailScreen("Manual VO₂ max recordings", centersTitle: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Manual Data").font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).tracking(0)
                Text("If you have VO₂ Max assessment results, enter them here to keep them next to your estimates.")
                    .font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
            Button { showAdd = true } label: { NunaVO2Row(symbol: "plus", title: "Add manual VO₂ max value") }.buttonStyle(.plain)
            ForEach(entries) { e in entryRow(e) }
            if entries.isEmpty { Text("No values yet").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
        }
        .environment(\.nunaDetailSwitch, nil)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .nunaManualVO2Changed)) { _ in Task { await load() } }
        .sheet(isPresented: $showAdd) { NunaVO2ManualSheet() }
    }

    private func entryRow(_ e: NunaVO2Manual.Entry) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "pencil").font(.system(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                .frame(width: 44, height: 44).background(NunaPalette.textMuted.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, e.value)).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: "mL/kg/min").font(.nuna(size: 13, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                }
                Text(verbatim: [e.source?.title, e.day].compactMap { $0 }.joined(separator: " · ")).font(.nuna(size: 13, weight: .regular))
                    .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 0)
            Button { Task { await NunaVO2Manual.delete(repo: repo, day: e.day) } } label: {
                Image(systemName: "trash").font(.system(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(Text("Delete"))
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }

    private func load() async { entries = await NunaVO2Manual.entries(repo: repo) }
}

/// A row of the VO₂ max footer: an icon, a title, and the card behind it.
struct NunaVO2Row: View {
    let symbol: String
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(NunaPalette.textSecondary).frame(width: 34)
            Text(title).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(height: 56).frame(maxWidth: .infinity)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Under the VO₂ max trend page: the wait for the first estimate, the way to enter a value by hand, the waist, and what VO₂ max is.
struct NunaVO2MaxFooter: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var hasData = true
    @State private var latest: Double?
    @State private var showAdd = false
    @State private var showWaist = false

    var body: some View {
        VStack(spacing: NunaSpacing.section) {
            if !hasData { waiting }
            if let latest {
                hint
                NunaVO2LevelCard(value: latest, age: profile.age)
            }
            VStack(spacing: 12) {
                Button { showAdd = true } label: { NunaVO2Row(symbol: "plus", title: "Add manual VO₂ max value") }.buttonStyle(.plain)
                NavigationLink { NunaVO2ManualRecordingsView() } label: { NunaVO2Row(symbol: "list.bullet", title: "See all manual recordings") }.buttonStyle(.plain)
                Button { showWaist = true } label: { NunaVO2Row(symbol: "plus", title: profile.waistCm > 0 ? "Update waist" : "Add waist") }.buttonStyle(.plain)
                Text("A waist measurement sharpens your VO₂ max. Without it the estimate uses only your age and resting heart rate, and it is used the next time the weekly estimate is worked out.")
                    .font(.nuna(size: 12.5, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
            }
            NunaVO2MaxInfo()
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .nunaManualVO2Changed)) { _ in Task { await load() } }
        .sheet(isPresented: $showAdd) { NunaVO2ManualSheet() }
        .sheet(isPresented: $showWaist) {
            NunaNumberSheet(title: "Waist", unit: "cm", initial: profile.waistCm > 0 ? profile.waistCm : 85, range: 40...200, step: 0.5, decimals: 1) { profile.waistCm = $0 }
        }
    }

    /// The blue note above the level card: what the figure rests on, and what would sharpen it.
    private var hint: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "info").font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.insightBlue).frame(width: 22)
            Text(profile.waistCm > 0
                 ? "Your VO₂ max is worked out once a week from your resting heart rate, your waist and your profile, so it moves slowly."
                 : "Your VO₂ max is worked out once a week from your resting heart rate and your profile. Adding your waist makes it sharper.")
                .font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.insightBlue).textCase(nil).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.insightBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }

    private var waiting: some View {
        VStack(spacing: 12) {
            Image(systemName: "applewatch").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(NunaPalette.textSecondary).padding(.top, 8)
            Text("Keep wearing your strap").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).tracking(0)
            Text("VO₂ max is first estimated after four nights of resting heart rate, then once a week. Check back soon to see how it moves.")
                .font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24).frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
    }

    private func load() async {
        let series = await repo.exploreSeries(key: NunaVO2Manual.key, source: "my-whoop", days: 400)
        hasData = !series.isEmpty
        latest = series.last?.value
    }
}

/// Where a VO₂ max sits among people of the same age: five levels with their lower limits, the level the reading falls in, and about what share of
/// people it is above. The spread is taken from the same age curves as the chart in "What is VO₂ max?" (5th, 50th and 95th percentile), read as a normal
/// distribution, so the figures are close, not exact.
enum NunaVO2Level {
    struct Result { let bounds: [Int]; let tier: Int; let percent: Int }
    static let names: [LocalizedStringKey] = ["Below Average", "Average", "Above Average", "Excellent", "Superior"]
    /// The lowest figure the bar starts at.
    static let floorValue = 15

    private static func at(_ points: [(Double, Double)], _ age: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if age <= first.0 { return first.1 }
        if age >= last.0 { return last.1 }
        for i in 1..<points.count where age <= points[i].0 {
            let (x0, y0) = points[i - 1], (x1, y1) = points[i]
            return y0 + (y1 - y0) * (age - x0) / (x1 - x0)
        }
        return last.1
    }

    /// The VO₂ max an average person of this age has (the middle of the normative curve), the reference the Body Age reads a wearer's figure against.
    static func expected(age: Int) -> Double { at(NunaVO2MaxInfo.average, Double(age)) }

    static func assess(vo2: Double, age: Int) -> Result {
        let a = Double(age)
        let low = at(NunaVO2MaxInfo.low, a), mid = at(NunaVO2MaxInfo.average, a), high = at(NunaVO2MaxInfo.high, a)
        let sd = max((high - low) / (2 * 1.645), 1)
        // Lower limits of the four upper levels: the 40th, 60th, 80th and 95th percentile.
        var bounds = [-0.2533, 0.2533, 0.8416, 1.6449].map { Int((mid + $0 * sd).rounded()) }
        for i in 1..<bounds.count { bounds[i] = max(bounds[i], bounds[i - 1] + 1) }
        bounds[0] = max(bounds[0], floorValue + 1)
        let z = (vo2 - mid) / sd
        let percent = min(max(Int((50 * (1 + erf(z / 2.0.squareRoot()))).rounded()), 1), 99)
        return Result(bounds: bounds, tier: bounds.filter { vo2 >= Double($0) }.count, percent: percent)
    }
}

/// "Your cardio fitness level": the five levels as a bar with the reading above it, the level it falls in, and what that says.
struct NunaVO2LevelCard: View {
    let value: Double
    let age: Int

    private static let share: [CGFloat] = [0.38, 0.18, 0.18, 0.13, 0.13]
    private var tints: [Color] { [NunaPalette.textMuted, NunaPalette.rangeSteel, NunaPalette.insightBlue, NunaPalette.insightFrom.opacity(0.7), NunaPalette.insightFrom] }

    var body: some View {
        let r = NunaVO2Level.assess(vo2: value, age: age)
        NunaCard(small: true, padding: EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16)) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your cardio fitness level").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary).padding(.bottom, 22)
                bar(r).frame(height: 62)
                (Text(NunaVO2Level.names[r.tier]).foregroundColor(NunaPalette.textPrimary)
                 + Text(verbatim: " (\(range(r)) ml/kg/min)").foregroundColor(NunaPalette.textSecondary))
                    .font(.nuna(size: 17, weight: .regular)).textCase(nil).padding(.top, 16)
                Text(verbatim: String(localized: "Your latest VO₂ max is higher than about \(r.percent)% of people your age."))
                    .font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func range(_ r: NunaVO2Level.Result) -> String {
        switch r.tier {
        case 0: return "\(NunaVO2Level.floorValue)-\(r.bounds[0] - 1)"
        case 4: return "\(r.bounds[3])+"
        default: return "\(r.bounds[r.tier - 1])-\(r.bounds[r.tier] - 1)"
        }
    }

    private func bar(_ r: NunaVO2Level.Result) -> some View {
        GeometryReader { geo in
            let gap: CGFloat = 1.5
            let usable = geo.size.width - gap * 4
            let widths = Self.share.map { $0 * usable }
            let starts = widths.indices.map { i in widths[..<i].reduce(0, +) + gap * CGFloat(i) }
            let lows = [Double(NunaVO2Level.floorValue)] + r.bounds.map(Double.init)
            let tier = r.tier
            let span = tier < 4 ? lows[tier + 1] - lows[tier] : 10
            let f = CGFloat(min(max((value - lows[tier]) / span, 0), 1))
            let x = starts[tier] + f * widths[tier]
            ZStack(alignment: .topLeading) {
                HStack(spacing: gap) {
                    ForEach(0..<5, id: \.self) { i in
                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(tints[i].opacity(0.22))
                            Rectangle().fill(tints[i]).frame(height: 3)
                            Text(verbatim: i == 4 ? "\(r.bounds[3])+" : "\(Int(lows[i]))")
                                .font(.nunaBoldFigure(size: 14)).foregroundStyle(tints[i]).textCase(nil).lineLimit(1)
                                .padding(.leading, 9).frame(maxHeight: .infinity, alignment: .center).padding(.top, 3)
                        }
                        .frame(width: widths[i], height: 22)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: i == 0 ? 5 : 0, bottomLeadingRadius: i == 0 ? 5 : 0,
                                                          bottomTrailingRadius: i == 4 ? 5 : 0, topTrailingRadius: i == 4 ? 5 : 0, style: .continuous))
                    }
                }
                .offset(y: 40)
                Text(verbatim: String(format: "%.0f", value)).font(.nunaBoldFigure(size: 18)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    .position(x: x, y: 10)
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 11)).foregroundStyle(NunaPalette.textPrimary)
                    .position(x: x, y: 31)
            }
        }
    }
}
#endif
