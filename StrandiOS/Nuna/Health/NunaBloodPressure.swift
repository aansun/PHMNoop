#if os(iOS)
import SwiftUI
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

// Blood pressure: readings from a cuff, typed in or copied from Apple Health into the Lab Book (see `PHMBloodPressureImport`). The strap measures
// nothing here. The ranges are general reference ranges for adults, shown as words; they are not a diagnosis.

// MARK: - A reading and where it sits

struct NunaBPReading: Identifiable, Equatable {
    /// The id of the systolic row.
    let id: String
    let diastolicId: String?
    let takenAt: Int
    let systolic: Double
    let diastolic: Double
    let source: String

    var date: Date { Date(timeIntervalSince1970: TimeInterval(takenAt)) }
    var text: String { NunaBP.text(systolic, diastolic) }
    var category: NunaBPCategory { .of(systolic, diastolic) }
}

/// Where a pair sits against general adult reference ranges. The worse of the two figures decides, except that "low" only applies when neither is high.
enum NunaBPCategory: Equatable {
    case low, normal, aboveIdeal, high, veryHigh

    static func of(_ systolic: Double, _ diastolic: Double) -> NunaBPCategory {
        let s = systolic.rounded(), d = diastolic.rounded()
        if s >= 180 || d >= 120 { return .veryHigh }
        if s >= 140 || d >= 90 { return .high }
        if s >= 120 || d >= 80 { return .aboveIdeal }
        if s < 90 || d < 60 { return .low }
        return .normal
    }

    /// Keys of their own: "Low" and "High" elsewhere in the app stay in English in some languages, and these must read in the person's language.
    var wordText: String {
        switch self {
        case .low: return String(localized: "bp.word.low", defaultValue: "Low")
        case .normal: return String(localized: "bp.word.normal", defaultValue: "Normal")
        case .aboveIdeal: return String(localized: "bp.word.aboveIdeal", defaultValue: "Above ideal")
        case .high: return String(localized: "bp.word.high", defaultValue: "High")
        case .veryHigh: return String(localized: "bp.word.veryHigh", defaultValue: "Very high")
        }
    }

    var color: Color {
        switch self {
        case .low: return NunaPalette.restText
        case .normal: return NunaPalette.charge
        case .aboveIdeal: return NunaPalette.caution
        case .high: return NunaPalette.warning
        case .veryHigh: return NunaPalette.alertText
        }
    }

    /// The three bars of the panel rows: lit at the right for normal, in the middle for a little off, at the left for high.
    var level: NunaLevel {
        switch self {
        case .normal: return .optimal
        case .low, .aboveIdeal: return .sufficient
        case .high, .veryHigh: return .poor
        }
    }
}

/// The readings and the figures worked from them. The page, the Health card and the dashboard all take them from here, so they cannot differ.
enum NunaBP {
    static func text(_ systolic: Double, _ diastolic: Double) -> String { "\(Int(systolic.rounded()))/\(Int(diastolic.rounded()))" }

    /// Pairs the Lab Book rows by the moment they were taken, oldest first.
    static func pair(_ rows: [LabMarkerRow]) -> [NunaBPReading] {
        let diastolic = Dictionary(rows.filter { $0.markerKey == LabBookProjection.bpDiastolicKey }.map { ($0.takenAt, $0) }, uniquingKeysWith: { _, l in l })
        return rows.filter { $0.markerKey == LabBookProjection.bpSystolicKey }.compactMap { s in
            guard let sv = s.value, let d = diastolic[s.takenAt], let dv = d.value else { return nil }
            return NunaBPReading(id: s.id, diastolicId: d.id, takenAt: s.takenAt, systolic: sv, diastolic: dv, source: s.source)
        }
        .sorted { $0.takenAt < $1.takenAt }
    }

    @MainActor static func load(_ repo: Repository) async -> [NunaBPReading] {
#if DEBUG
        if CommandLine.arguments.contains("--demo-bp") { return demo }
#endif
        return pair(await NunaLabStore.load(repo))
    }

    static func average(_ list: [NunaBPReading]) -> (systolic: Double, diastolic: Double)? {
        guard !list.isEmpty else { return nil }
        return (list.map(\.systolic).reduce(0, +) / Double(list.count), list.map(\.diastolic).reduce(0, +) / Double(list.count))
    }

    static func within(_ list: [NunaBPReading], days: Int, now: Date = Date()) -> [NunaBPReading] {
        let from = Int(now.timeIntervalSince1970) - days * 86_400
        return list.filter { $0.takenAt >= from }
    }

    struct Day: Equatable { let date: Date; let systolic: Double; let diastolic: Double }

    /// One point a day, the mean of that day's readings, oldest first.
    static func daily(_ list: [NunaBPReading], calendar: Calendar = .current) -> [Day] {
        Dictionary(grouping: list) { calendar.startOfDay(for: $0.date) }
            .compactMap { day, rs in average(rs).map { Day(date: day, systolic: $0.systolic, diastolic: $0.diastolic) } }
            .sorted { $0.date < $1.date }
    }

    /// Morning is 04:00 to 12:00, evening 17:00 to 04:00; the afternoon belongs to neither.
    static func isMorning(_ r: NunaBPReading) -> Bool { (4..<12).contains(Calendar.current.component(.hour, from: r.date)) }
    static func isEvening(_ r: NunaBPReading) -> Bool { let h = Calendar.current.component(.hour, from: r.date); return h >= 17 || h < 4 }

    static func sourceName(_ source: String) -> String {
        source == PHMBloodPressureImport.source ? String(localized: "Apple Health") : (source == "manual" ? String(localized: "Typed in") : String(localized: "Imported"))
    }

    static func when(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale
        // A reading from another year says which, so an old one is not taken for a recent one.
        let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        f.setLocalizedDateFormatFromTemplate(thisYear ? "EEEdMMMjjmm" : "dMMMyyyyjjmm")
        return f.string(from: date)
    }

#if DEBUG
    /// `--demo-bp`: a month of made-up readings, mornings and evenings, so the screens can be looked at. Nothing is read from or written to the store.
    static let demo: [NunaBPReading] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let figures: [(Int, Int)] = [(131, 85), (128, 83), (134, 87), (126, 81), (129, 84), (123, 80), (127, 82), (121, 79), (125, 81), (119, 78), (124, 80), (122, 79)]
        var out: [NunaBPReading] = []
        for back in stride(from: 29, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            for (slot, hour) in [(0, 7), (1, 20)] where slot == 0 || back % 3 == 0 {
                let f = figures[(29 - back + slot * 5) % figures.count]
                guard let at = cal.date(bySettingHour: hour, minute: 12, second: 0, of: day), at <= Date() else { continue }
                let ts = Int(at.timeIntervalSince1970)
                out.append(NunaBPReading(id: "demo-\(ts)", diastolicId: nil, takenAt: ts, systolic: Double(f.0 + slot * 3), diastolic: Double(f.1 + slot * 2),
                                         source: slot == 0 ? PHMBloodPressureImport.source : "manual"))
            }
        }
        return out.sorted { $0.takenAt < $1.takenAt }
    }()
#endif
}

// MARK: - The page

/// Laid out like the Sleep pages: the latest reading in a ring, one panel of averages, the trend, the readings, how to add more, and what the ranges mean.
struct NunaBloodPressureView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var health: HealthKitBridge
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var readings: [NunaBPReading] = []
    @State private var loaded = false
    @State private var days = 30
    @State private var adding = false
    @State private var reading = false

    private var latest: NunaBPReading? { readings.last }

    var body: some View {
        NunaDetailScreen("Blood pressure", centersTitle: true) {
            if !loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
            } else if let latest {
                hero(latest)
                if latest.category == .veryHigh { veryHigh }
                panel
                trend
                recent
            } else {
                empty
            }
            addButton
            appleHealth
            NunaBPMeasureInfo()
            NunaBPRangeInfo()
        }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") {
            readings = await NunaBP.load(repo)
            loaded = true
            // New readings in Health are copied in as the page opens; a change comes back round through `changes`.
            await PHMBloodPressureImport.sync(repo: repo)
        }
        .sheet(isPresented: $adding) {
            // In a navigation stack so the number pad gets its Done button: it has no return key of its own.
            NavigationStack {
                NunaLabAddSheet(preselect: LabBookProjection.bpSystolicKey) { drafts in await NunaLabStore.save(drafts, repo: repo) }
                    .toolbar(.hidden, for: .navigationBar)
            }
            .preferredColorScheme(NunaTheme.colorScheme)
        }
        // Her line is worked out from these figures; nothing is sent anywhere unless she is asked.
        .nunaAnyaFloating(context: "blood pressure", line: anyaLine, detail: anyaDetail, analyses: false)
    }

    // MARK: Anya

    private var week: (systolic: Double, diastolic: Double)? { NunaBP.average(NunaBP.within(readings, days: 7)) }

    private var anyaLine: String? {
        guard loaded else { return nil }
        guard let latest else { return String(localized: "Add a reading and I will follow it with you.") }
        if latest.category == .veryHigh { return String(localized: "Your latest reading is very high. Rest five minutes and measure again.") }
        guard let week else { return String(localized: "No reading this week. A fresh one keeps the picture current.") }
        let word = NunaBPCategory.of(week.systolic, week.diastolic).wordText.lowercased(with: AppLanguage.activeLocale)
        return String(localized: "Your 7-day average is \(NunaBP.text(week.systolic, week.diastolic)), \(word).")
    }

    private var anyaDetail: String? {
        guard let latest else { return nil }
        var bits = [String(localized: "Latest: \(latest.text) mmHg, \(NunaBP.when(latest.date)).")]
        let month = NunaBP.within(readings, days: 30)
        if let a = NunaBP.average(month) { bits.append(String(localized: "30-day average: \(NunaBP.text(a.systolic, a.diastolic)) from \(month.count) readings.")) }
        if let m = NunaBP.average(month.filter(NunaBP.isMorning)) { bits.append(String(localized: "Mornings: \(NunaBP.text(m.systolic, m.diastolic)).")) }
        if let e = NunaBP.average(month.filter(NunaBP.isEvening)) { bits.append(String(localized: "Evenings: \(NunaBP.text(e.systolic, e.diastolic)).")) }
        bits.append(String(localized: "These are general reference ranges, not a diagnosis."))
        return bits.joined(separator: " ")
    }

    // MARK: Hero

    private func hero(_ r: NunaBPReading) -> some View {
        VStack(spacing: 14) {
            // The ring runs with the upper figure, from 80 to 180.
            NunaRingGauge(fraction: (r.systolic - 80) / 100, color: r.category.color, size: 300, lineWidth: 16) {
                VStack(spacing: 6) {
                    nunaTrendsCap("Latest")
                    Text(verbatim: r.text).font(.nuna(size: 62, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(62))
                        .foregroundStyle(NunaPalette.textPrimary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(verbatim: "mmHg").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    Text(verbatim: r.category.wordText).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(r.category.color)
                }
                .padding(.horizontal, 24)
            }
            Text(verbatim: NunaBP.when(r.date) + " · " + NunaBP.sourceName(r.source))
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    private var veryHigh: some View {
        NunaCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(NunaPalette.alertText)
                Text("This reading is very high. Sit quietly for five minutes and measure again. If it stays this high, contact a health professional today. With chest pain, shortness of breath, weakness, trouble speaking or seeing, call your local emergency service now.")
                    .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
    }

    // MARK: Panel

    private var panel: some View {
        let month = NunaBP.within(readings, days: 30)
        return NunaSignalPanel {
            VStack(spacing: 0) {
                row("7-day average", "calendar", NunaBP.average(NunaBP.within(readings, days: 7)))
                NunaDivider()
                row("30-day average", "chart.line.uptrend.xyaxis", NunaBP.average(month))
                NunaDivider()
                row("Mornings", "sun.max", NunaBP.average(month.filter(NunaBP.isMorning)))
                NunaDivider()
                row("Evenings", "moon", NunaBP.average(month.filter(NunaBP.isEvening)))
                NunaDivider()
                NunaFigureRow(title: "Readings (30 days)", icon: "number", value: "\(month.count)")
            }
            NunaBPLegend().padding(.top, 8)
        }
    }

    private func row(_ title: LocalizedStringKey, _ icon: String, _ value: (systolic: Double, diastolic: Double)?) -> some View {
        NunaFigureRow(title: title, icon: icon, value: value.map { NunaBP.text($0.systolic, $0.diastolic) } ?? "–",
                      level: value.map { NunaBPCategory.of($0.systolic, $0.diastolic).level })
    }

    // MARK: Trend

    private var trend: some View {
        let shown = NunaBP.within(readings, days: days)
        let points = NunaBP.daily(shown)
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Trend") {
                Text("Daily average · mmHg").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            NunaSegmented([(value: 7, title: "7 days"), (value: 30, title: "30 days"), (value: 90, title: "90 days")], selection: $days)
            NunaCard {
                if points.isEmpty {
                    Text("No reading in this period.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        NunaBPChart(points: points, days: days).frame(height: 220)
                        HStack(spacing: 14) {
                            key(NunaPalette.textPrimary, "Upper (systolic)")
                            key(NunaPalette.restText, "Lower (diastolic)")
                        }
                        Text("Dashed lines mark 120 and 80.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
            }
        }
    }

    private func key(_ color: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: Readings

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Latest readings") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(readings.suffix(5).reversed().enumerated()), id: \.element.id) { i, r in
                        if i > 0 { NunaDivider() }
                        HStack(spacing: 14) {
                            NunaIcon(name: NunaBP.isMorning(r) ? "sun.max" : (NunaBP.isEvening(r) ? "moon" : "clock"), size: 18, weight: .regular)
                                .foregroundStyle(NunaPalette.textSecondary).frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: NunaBP.when(r.date)).font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: NunaBP.sourceName(r.source)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(verbatim: r.text).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                                Text(verbatim: r.category.wordText).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(r.category.color)
                            }
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            NavigationLink(value: NunaTodayRoute.bloodPressureHistory) {
                NunaCard(small: true) { NunaListRow("All readings", description: "The full history, where a reading can be edited or deleted", systemImage: "list.bullet", showsChevron: true) }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Adding

    private var empty: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 10) {
                NunaIconTile(NunaIcons.bloodPressure, tint: NunaPalette.restText)
                Text("No blood pressure yet").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text("Measure with a cuff, then type the two figures here, or let PHMN read them from Apple Health if your cuff's app saves them there. The strap does not measure blood pressure.")
                    .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var addButton: some View {
        Button { adding = true } label: { Text("Add a reading") }
            .buttonStyle(.nuna(.primary, fullWidth: true))
    }

    @ViewBuilder private var appleHealth: some View {
        switch health.auth {
        case .authorized:
            Button { readHealth() } label: {
                NunaCard(small: true) {
                    NunaListRow("Apple Health", description: reading ? "Reading…" : "Read automatically. Tap to read now", systemImage: "heart.text.square", showsChevron: true)
                }
            }
            .buttonStyle(.plain).disabled(reading)
        case .entitlementMissing, .unavailable:
            NunaCard(small: true) { NunaListRow("Apple Health", description: "Not available in this build. Typed readings work as usual", systemImage: "heart.slash") }
        default:
            Button { readHealth(connect: true) } label: {
                NunaCard(small: true) { NunaListRow("Connect Apple Health", description: "Read blood pressure saved by your cuff's app", systemImage: "heart.text.square", showsChevron: true) }
            }
            .buttonStyle(.plain).disabled(reading)
        }
    }

    /// A full Health pass also asks for any reading permission this version added, blood pressure among them.
    private func readHealth(connect: Bool = false) {
        reading = true
        Task {
            if connect { await health.requestAuthorization() }
            _ = await health.sync(days: 30)
            await PHMBloodPressureImport.sync(repo: repo)
            readings = await NunaBP.load(repo)
            reading = false
        }
    }
}

/// The two figures over the period as two lines, a point for each day with a reading, against dashed lines at 120 and 80. The latest pair is written
/// beside its points; the scale is at the left.
private struct NunaBPChart: View {
    let points: [NunaBP.Day]
    let days: Int

    var body: some View {
        Canvas { ctx, size in
            let left: CGFloat = 34, right: CGFloat = 34, top: CGFloat = 8, bottom: CGFloat = 24
            let w = size.width - left - right, h = size.height - top - bottom
            let all = points.flatMap { [$0.systolic, $0.diastolic] }
            let lo = (min(all.min() ?? 70, 70) / 20).rounded(.down) * 20
            let hi = (max(all.max() ?? 140, 140) / 20).rounded(.up) * 20
            let cal = Calendar.current
            let end = cal.startOfDay(for: Date())
            let start = cal.date(byAdding: .day, value: -(days - 1), to: end) ?? end
            let span = max(end.timeIntervalSince(start), 1)
            func x(_ d: Date) -> CGFloat { left + CGFloat(min(max(d.timeIntervalSince(start) / span, 0), 1)) * w }
            func y(_ v: Double) -> CGFloat { top + h - CGFloat((v - lo) / max(hi - lo, 1)) * h }
            func label(_ s: String, _ color: Color, _ at: CGPoint, _ anchor: UnitPoint) {
                ctx.draw(Text(verbatim: s).font(.nuna(size: 11, weight: .bold, design: NunaType.design)).foregroundColor(color), at: at, anchor: anchor)
            }
            for v in stride(from: lo, through: hi, by: 20) {
                var line = Path(); line.move(to: CGPoint(x: left, y: y(v))); line.addLine(to: CGPoint(x: left + w, y: y(v)))
                ctx.stroke(line, with: .color(NunaPalette.ink.opacity(0.07)), lineWidth: 1)
                label(String(format: "%.0f", v), NunaPalette.textMuted, CGPoint(x: left - 8, y: y(v)), .trailing)
            }
            for v in [120.0, 80.0] {
                var line = Path(); line.move(to: CGPoint(x: left, y: y(v))); line.addLine(to: CGPoint(x: left + w, y: y(v)))
                ctx.stroke(line, with: .color(NunaPalette.charge.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
            }
            let r: CGFloat = days > 30 ? 2 : 3.5
            for (value, color) in [(\NunaBP.Day.systolic, NunaPalette.textPrimary), (\NunaBP.Day.diastolic, NunaPalette.restText)] {
                var line = Path()
                for (i, p) in points.enumerated() {
                    let pt = CGPoint(x: x(p.date), y: y(p[keyPath: value]))
                    if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                }
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                for p in points {
                    ctx.fill(Path(ellipseIn: CGRect(x: x(p.date) - r, y: y(p[keyPath: value]) - r, width: r * 2, height: r * 2)), with: .color(color))
                }
                if let last = points.last {
                    label(String(format: "%.0f", last[keyPath: value]), color, CGPoint(x: x(last.date) + 8, y: y(last[keyPath: value])), .leading)
                }
            }
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("dMMM")
            label(f.string(from: start), NunaPalette.textSecondary, CGPoint(x: left, y: size.height - 6), .bottomLeading)
            let mid = start.addingTimeInterval(span / 2)
            label(f.string(from: mid), NunaPalette.textSecondary, CGPoint(x: left + w / 2, y: size.height - 6), .bottom)
            label(f.string(from: end), NunaPalette.textSecondary, CGPoint(x: left + w, y: size.height - 6), .bottomTrailing)
        }
        .textCase(nil)
        .accessibilityHidden(true)
    }
}

/// What the three bars under the ring mean on this page.
private struct NunaBPLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(.poor, String(localized: "bp.word.high", defaultValue: "High")); item(.sufficient, String(localized: "bp.legend.off", defaultValue: "A little off"))
            item(.optimal, String(localized: "bp.word.normal", defaultValue: "Normal"))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }

    private func item(_ level: NunaLevel, _ name: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(level.color).frame(width: 16, height: 4)
            Text(verbatim: name).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

// MARK: - The card on Health

/// On the Health tab: the latest reading and the way into the page.
struct NunaBloodPressureCard: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var latest: NunaBPReading?
    @State private var loaded = false

    var body: some View {
        NavigationLink(value: NunaTodayRoute.bloodPressure) {
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    NunaIconTile(NunaIcons.bloodPressure, tint: NunaPalette.restText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Blood pressure").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        if let latest {
                            Text(verbatim: latest.text + " mmHg").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                            Text(verbatim: latest.category.wordText + " · " + NunaBP.when(latest.date))
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        } else {
                            Text(loaded ? "No reading yet" : "Reading…").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text("Type it in or read it from Apple Health").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") {
            latest = await NunaBP.load(repo).last
            loaded = true
        }
    }
}
#endif
