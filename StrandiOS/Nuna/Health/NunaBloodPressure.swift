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
    /// Position and cuff place, for a typed reading that has them.
    var note: String? = nil

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
        case .aboveIdeal: return NunaPalette.warning
        case .high: return NunaPalette.caution
        case .veryHigh: return NunaPalette.alertText
        }
    }

    /// Where a pair sits along the three zones of the gauge, 0 to 1: each zone is a third, and the figure further along decides, as the words do.
    static func gaugePosition(_ systolic: Double, _ diastolic: Double) -> Double {
        func along(_ v: Double, _ edges: [Double]) -> Double {
            for i in 0..<3 where v < edges[i + 1] || i == 2 {
                return (Double(i) + min(max((v - edges[i]) / (edges[i + 1] - edges[i]), 0), 0.98)) / 3
            }
            return 0
        }
        return min(max(max(along(systolic, [90, 120, 140, 180]), along(diastolic, [60, 80, 90, 120])), 0.02), 0.98)
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
            return NunaBPReading(id: s.id, diastolicId: d.id, takenAt: s.takenAt, systolic: sv, diastolic: dv, source: s.source, note: s.note)
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

    /// A day's readings: the means the marks are drawn at, and the span from the lowest lower figure to the highest upper one.
    struct Day: Equatable {
        let date: Date
        let systolic: Double
        let diastolic: Double
        let top: Double
        let bottom: Double
        let count: Int
    }

    /// One entry a day with a reading, oldest first.
    static func daily(_ list: [NunaBPReading], calendar: Calendar = .current) -> [Day] {
        Dictionary(grouping: list) { calendar.startOfDay(for: $0.date) }
            .compactMap { day, rs in
                average(rs).map { Day(date: day, systolic: $0.systolic, diastolic: $0.diastolic,
                                      top: rs.map(\.systolic).max() ?? $0.systolic, bottom: rs.map(\.diastolic).min() ?? $0.diastolic, count: rs.count) }
            }
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

/// The latest reading on an arc of three zones, the week or the month as one mark a day, adding a reading and the way to all of them, and what the
/// ranges mean with what research links to blood pressure. Only readings that were taken are drawn: nothing is estimated.
struct NunaBloodPressureView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var readings: [NunaBPReading] = []
    @State private var loaded = false
    /// 7 or 30 days on the chart, and how many such periods back from today it stands.
    @State private var span = 7
    @State private var back = 0
    /// The day tapped on the chart; nil shows the latest of the period.
    @State private var picked: Date?
    @State private var adding = false

    private var latest: NunaBPReading? { readings.last }

    var body: some View {
        NunaDetailScreen("Blood pressure", trailing: AnyView(settingsButton), centersTitle: true) {
            if !loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
            } else if let latest {
                hero(latest)
                if latest.category == .veryHigh { veryHigh }
                period
                NunaBPLinksSection(readings: readings, days: linkDays, picked: selectedDay)
                addButton
            } else {
                empty
                addButton
            }
            if loaded, !readings.isEmpty { allReadings }
            NunaBPZones()
            NunaBPFindings()
        }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") {
            readings = await NunaBP.load(repo)
            loaded = true
            // New readings in Health are copied in as the page opens; a change comes back round through `changes`.
            await PHMBloodPressureImport.sync(repo: repo)
        }
        .sheet(isPresented: $adding) {
            NunaBPAddSheet { drafts in await NunaLabStore.save(drafts, repo: repo) }
        }
        // Opened from the measurement reminder: straight to typing the reading.
        .onAppear { openEntryIfAsked() }
        .onChange(of: router.openBloodPressureEntry) { _, _ in openEntryIfAsked() }
        // Her line is worked out from these figures; nothing is sent anywhere unless she is asked.
        .nunaAnyaFloating(context: "blood pressure", line: anyaLine, detail: anyaDetail, analyses: false)
    }

    private func openEntryIfAsked() {
        guard router.openBloodPressureEntry else { return }
        router.openBloodPressureEntry = false
        adding = true
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
        ZStack(alignment: .top) {
            NunaBPGauge(position: NunaBPCategory.gaugePosition(r.systolic, r.diastolic))
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    nunaTrendsCap("Latest reading")
                    Text(verbatim: r.text).font(.nuna(size: 50, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(50))
                        .foregroundStyle(NunaPalette.textPrimary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
                HStack(spacing: 40) {
                    figure("Systolic", r.systolic)
                    figure("Diastolic", r.diastolic)
                }
            }
            .padding(.top, 78)
        }
        .frame(height: 262)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        // The needle is the only thing on the page that says the range, so it is also said aloud.
        .accessibilityValue(Text(verbatim: r.category.wordText))
    }

    private func figure(_ title: LocalizedStringKey, _ value: Double) -> some View {
        VStack(spacing: 2) {
            nunaTrendsCap(title)
            Text(verbatim: "\(Int(value.rounded()))").font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
            Text(verbatim: "mmHg").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
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

    // MARK: The period

    /// The days on the chart: `span` of them, ending today or `back` periods before.
    private var window: [Date] {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: -back * span, to: cal.startOfDay(for: Date())) ?? Date()
        return (0..<span).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: end) }
    }

    /// The day the chart has lit: the one tapped, else the newest of the period that has a reading.
    private var selectedDay: Date? {
        let days = window
        let shown = NunaBP.daily(readings).filter { days.contains($0.date) }
        return (shown.first { $0.date == picked } ?? shown.last)?.date
    }

    /// The week of the rows under the chart: the chart's own week, or, over a month, the seven days up to the lit one.
    private var linkDays: [Date] {
        let cal = Calendar.current
        guard let end = span == 7 ? window.last : (selectedDay ?? window.last) else { return [] }
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: end) }
    }

    private var hasEarlier: Bool { guard let first = readings.first, let start = window.first else { return false }; return first.date < start }

    private var period: some View {
        let days = window
        let shown = NunaBP.daily(readings).filter { days.contains($0.date) }
        let selected = shown.first { $0.date == picked } ?? shown.last
        return VStack(spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    spanButton(7, String(localized: "bp.span.week", defaultValue: "W")); spanButton(30, String(localized: "bp.span.month", defaultValue: "M"))
                }
                .padding(3).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer(minLength: 4)
                arrow("chevron.left", "Earlier", enabled: hasEarlier) { back += 1; picked = nil }
                Text(verbatim: rangeText(days)).font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7).frame(minWidth: 96)
                arrow("chevron.right", "Later", enabled: back > 0) { back -= 1; picked = nil }
            }
            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    Capsule().fill(NunaPalette.textSecondary).frame(width: 14, height: 3)
                    nunaTrendsCap("Reading")
                }
                HStack(spacing: 6) {
                    Capsule().fill(NunaPalette.ink.opacity(0.18)).frame(width: 8, height: 14)
                    nunaTrendsCap("Upper to lower")
                }
                Spacer(minLength: 0)
            }
            NunaBPDayChart(days: days, entries: shown, picked: selected?.date) { picked = $0 }
                .frame(height: 280)
        }
    }

    private func spanButton(_ value: Int, _ title: String) -> some View {
        let on = span == value
        return Button { span = value; back = 0; picked = nil } label: {
            Text(verbatim: title).font(.nuna(size: 13, weight: .bold)).foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                .frame(width: 56, height: 36).background(on ? NunaPalette.glassStrong : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityLabel(Text(value == 7 ? "7 days" : "30 days")).accessibilityAddTraits(on ? .isSelected : [])
    }

    private func arrow(_ symbol: String, _ label: LocalizedStringKey, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 17, weight: .heavy)).foregroundStyle(enabled ? NunaPalette.textPrimary : NunaPalette.textMuted.opacity(0.4))
                .frame(width: 36, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityLabel(Text(label))
    }

    private func rangeText(_ days: [Date]) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("dMMM")
        guard let a = days.first, let b = days.last else { return "" }
        return f.string(from: a) + " - " + f.string(from: b)
    }

    // MARK: Readings and settings

    private var settingsButton: some View {
        NavigationLink(value: NunaTodayRoute.bloodPressureSettings) {
            Image(systemName: "gearshape").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(Text("Blood pressure settings"))
    }

    private var readingCount: String {
        readings.count == 1 ? String(localized: "bp.readings.one", defaultValue: "1 reading")
                            : String(localized: "bp.readings.many", defaultValue: "\(readings.count) readings")
    }

    /// The full list, which is also where a reading is removed.
    private var allReadings: some View {
        NavigationLink(value: NunaTodayRoute.bloodPressureHistory) {
            NunaCard(small: true) {
                NunaListRow("All readings", subtitle: LocalizedStringKey(readingCount),
                            systemImage: "list.bullet", showsChevron: true)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Adding

    private var empty: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 10) {
                NunaIconTile(NunaIcons.bloodPressure, tint: NunaPalette.restText)
                Text("No blood pressure yet").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text("Measure with a cuff, then type the two figures here. If your cuff's app saves them in Apple Health, connect it with the gear at the top right. The strap does not measure blood pressure.")
                    .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var addButton: some View {
        Button { adding = true } label: {
            NunaCard(small: true) {
                HStack(spacing: 16) {
                    Image(systemName: "plus").font(.nuna(size: 20, weight: .regular))
                    Text("Add manual reading").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(NunaPalette.textPrimary).frame(minHeight: 28)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The arc of three zones, normal, above ideal and high, with a mark across it where the latest reading sits.
private struct NunaBPGauge: View {
    /// 0 at the start of the normal zone, 1 at the end of the high one.
    let position: Double

    var body: some View {
        Canvas { ctx, size in
            let radius = min(size.width / 2 - 20, size.height * 0.62)
            let centre = CGPoint(x: size.width / 2, y: radius + 18)
            // From the lower left, over the top, to the lower right.
            let start = 160.0, sweep = 220.0, gap = 2.6
            let zones = [NunaPalette.charge, NunaPalette.warning, NunaPalette.caution]
            for (i, color) in zones.enumerated() {
                let a = start + sweep * Double(i) / 3 + (i == 0 ? 0 : gap / 2)
                let b = start + sweep * Double(i + 1) / 3 - (i == 2 ? 0 : gap / 2)
                func arc(_ r: CGFloat) -> Path {
                    var p = Path(); p.addArc(center: centre, radius: r, startAngle: .degrees(a), endAngle: .degrees(b), clockwise: false); return p
                }
                ctx.stroke(arc(radius - 8), with: .color(color.opacity(0.22)), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                ctx.stroke(arc(radius), with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            let angle = (start + sweep * position) * .pi / 180
            func point(_ r: CGFloat) -> CGPoint { CGPoint(x: centre.x + r * CGFloat(cos(angle)), y: centre.y + r * CGFloat(sin(angle))) }
            var tail = Path(); tail.move(to: point(radius - 52)); tail.addLine(to: point(radius - 16))
            ctx.stroke(tail, with: .linearGradient(Gradient(colors: [NunaPalette.ink.opacity(0), NunaPalette.ink.opacity(0.7)]),
                                                   startPoint: point(radius - 52), endPoint: point(radius - 16)), style: StrokeStyle(lineWidth: 9))
            var head = Path(); head.move(to: point(radius - 17)); head.addLine(to: point(radius + 5))
            ctx.stroke(head, with: .color(NunaPalette.ink), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

/// One column a day: a bar from the lower figure to the upper one, and a mark at each in the colour of that day's zone. The highest and the lowest
/// figures of the period are lined and named at the left. A day without a reading stays empty; a tap picks a day.
private struct NunaBPDayChart: View {
    let days: [Date]
    let entries: [NunaBP.Day]
    let picked: Date?
    let onPick: (Date) -> Void
    private let left: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let week = days.count <= 7
                let top: CGFloat = 26, bottom: CGFloat = 46
                let h = size.height - top - bottom
                let column = (size.width - left * 2) / CGFloat(max(days.count, 1))
                let high = entries.map(\.top).max(), low = entries.map(\.bottom).min()
                let hi = max((high ?? 140) + 20, 150), lo = min((low ?? 60) - 20, 50)
                func y(_ v: Double) -> CGFloat { top + h - CGFloat((v - lo) / (hi - lo)) * h }
                func x(_ i: Int) -> CGFloat { left + column * (CGFloat(i) + 0.5) }
                func words(_ s: String, _ size: CGFloat, _ weight: Font.Weight, _ color: Color, _ at: CGPoint, _ anchor: UnitPoint) {
                    ctx.draw(Text(verbatim: s).font(.nuna(size: size, weight: weight)).foregroundColor(color), at: at, anchor: anchor)
                }
                func rule(_ yy: CGFloat) {
                    var p = Path(); p.move(to: CGPoint(x: 0, y: yy)); p.addLine(to: CGPoint(x: size.width, y: yy))
                    ctx.stroke(p, with: .color(NunaPalette.ink.opacity(0.1)), lineWidth: 1)
                }
                rule(top + h / 2)
                if let high, let low {
                    rule(y(high) - 28); rule(y(low) + 28)
                    words(String(localized: "Highest"), 12, .bold, NunaPalette.caution, CGPoint(x: 0, y: y(high) - 31), .bottomLeading)
                    words(String(localized: "Lowest"), 12, .bold, NunaPalette.charge, CGPoint(x: 0, y: y(low) + 31), .topLeading)
                } else {
                    rule(top); rule(top + h)
                    words(String(localized: "No reading in this period."), 13, .semibold, NunaPalette.textSecondary, CGPoint(x: size.width / 2, y: top + h / 2 - 14), .center)
                }
                let width = min(column * 0.56, 20)
                let f = DateFormatter(); f.locale = AppLanguage.activeLocale
                var lit: (x: CGFloat, bar: CGRect, day: NunaBP.Day)?
                for (i, day) in days.enumerated() {
                    let isPicked = day == picked
                    if isPicked {
                        ctx.fill(Path(roundedRect: CGRect(x: x(i) - max(column, 14) / 2, y: 0, width: max(column, 14), height: size.height), cornerRadius: 6),
                                 with: .color(NunaPalette.ink.opacity(0.07)))
                    }
                    if let e = entries.first(where: { $0.date == day }) {
                        let bar = CGRect(x: x(i) - width / 2, y: y(e.top) - 8, width: width, height: max(y(e.bottom) - y(e.top) + 16, 16))
                        ctx.fill(Path(roundedRect: bar, cornerRadius: min(width / 3, 5)), with: .color(NunaPalette.ink.opacity(0.14)))
                        let tone = NunaBPCategory.of(e.systolic, e.diastolic).color
                        for v in [e.systolic, e.diastolic] {
                            ctx.fill(Path(roundedRect: CGRect(x: x(i) - width / 2, y: y(v) - 2.5, width: width, height: 5), cornerRadius: 2.5), with: .color(tone))
                        }
                        if week {
                            words("\(Int(e.systolic.rounded()))", 12, .bold, NunaPalette.textPrimary, CGPoint(x: x(i), y: bar.minY - 3), .bottom)
                            words("\(Int(e.diastolic.rounded()))", 12, .bold, NunaPalette.textSecondary, CGPoint(x: x(i), y: bar.maxY + 3), .top)
                        } else if isPicked {
                            // Written after every bar is drawn, so the neighbouring columns cannot cover them.
                            lit = (x(i), bar, e)
                        }
                    }
                    // Every day of a week is named; a month names a day in seven, counted back from its last.
                    if week || (days.count - 1 - i) % 7 == 0 {
                        f.setLocalizedDateFormatFromTemplate(week ? "EEE" : "MMM"); let first = f.string(from: day)
                        f.setLocalizedDateFormatFromTemplate("d"); let second = f.string(from: day)
                        let at = min(max(x(i), 16), size.width - 16)
                        let color = isPicked ? NunaPalette.textPrimary : NunaPalette.textSecondary
                        words(first, 12, .semibold, color, CGPoint(x: at, y: size.height - 24), .center)
                        words(second, 12, .semibold, color, CGPoint(x: at, y: size.height - 9), .center)
                    }
                }
                // The picked day of a month: each figure on its own small plate, kept inside the chart's sides.
                if let lit {
                    for (value, centre) in [(lit.day.systolic, lit.bar.minY - 13), (lit.day.diastolic, lit.bar.maxY + 13)] {
                        let at = CGPoint(x: min(max(lit.x, 18), size.width - 18), y: centre)
                        ctx.fill(Path(roundedRect: CGRect(x: at.x - 17, y: at.y - 10, width: 34, height: 20), cornerRadius: 6), with: .color(NunaPalette.ink))
                        words("\(Int(value.rounded()))", 12, .heavy, NunaPalette.canvas, at, .center)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { point in
                let column = (geo.size.width - left * 2) / CGFloat(max(days.count, 1))
                let i = Int((point.x - left) / max(column, 1))
                // A month's columns are narrow, so the nearest day with a reading answers the tap.
                let withData = days.indices.filter { j in entries.contains { $0.date == days[j] } }
                if let j = withData.min(by: { abs($0 - i) < abs($1 - i) }) { onPick(days[j]) }
            }
        }
        .textCase(nil)
        .accessibilityHidden(true)
    }
}

// MARK: - What the ranges mean

/// The three zones side by side with their figures, as under the gauge's colours.
private struct NunaBPZones: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Blood pressure and wellbeing").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            HStack(spacing: 2) {
                zone(.normal, "< 120", "< 80")
                zone(.aboveIdeal, "120 - 139", "80 - 89")
                zone(.high, "≥ 140", "≥ 90")
            }
            .clipShape(RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
            words("Very high is 180 or more, or 120 or more. Low is under 90, or under 60.")
            words("Over the years, higher blood pressure puts more strain on the heart, the brain and the kidneys, often without any symptom. That is why it is worth measuring.")
        }
        .padding(.top, 6)
    }

    private func zone(_ c: NunaBPCategory, _ systolic: String, _ diastolic: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(c.color.opacity(0.35)).frame(height: 16)
                .overlay(alignment: .top) { Rectangle().fill(c.color).frame(height: 4) }
            Text(verbatim: c.wordText).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.7).frame(height: 30, alignment: .topLeading)
            figure("Systolic (mmHg)", systolic)
            figure("Diastolic (mmHg)", diastolic)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(NunaPalette.glassStrong)
    }

    private func figure(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: value).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
    }

    private func words(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).textCase(nil).fixedSize(horizontal: false, vertical: true)
    }
}

/// A topic to choose, filled while it is the one shown.
struct NunaBPTopicChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title).font(.nuna(size: 14, weight: .bold)).foregroundStyle(selected ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .padding(.horizontal, 18).frame(height: 38).background(selected ? NunaPalette.accent : NunaPalette.glassStrong, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// General findings about sleep, activity and stress, a topic at a time, each point opening on a tap.
private struct NunaBPFindings: View {
    private struct Finding: Identifiable {
        let id: String
        let title: String
        let tag: String
        /// True where the point goes with higher pressure, false where it goes with lower.
        let raises: Bool
        let text: String
    }

    @State private var topic = 0
    @State private var open: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            nunaTrendsCap("From research")
            HStack(spacing: 10) {
                chip(0, "Sleep"); chip(1, "Activity"); chip(2, "Stress")
                Spacer(minLength: 0)
            }
            NunaCard(small: true) {
                Text(verbatim: intro).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).textCase(nil)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(findings) { f in row(f) }
            Text("General information, not advice about you. Talk with a health professional before changing any treatment. Readings stay on this iPhone; if you ask Anya about them, they go to an online provider only while Share patterns and Lab Book is on.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chip(_ value: Int, _ title: String.LocalizationValue) -> some View {
        NunaBPTopicChip(title: String(localized: title), selected: topic == value) { topic = value; open = nil }
    }

    private func row(_ f: Finding) -> some View {
        let shown = open == f.id
        return Button { withAnimation(.easeInOut(duration: 0.2)) { open = shown ? nil : f.id } } label: {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(verbatim: f.title).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        HStack(spacing: 4) {
                            Image(systemName: f.raises ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 8))
                            Text(verbatim: f.tag).font(.nuna(size: 11.5, weight: .bold)).textCase(nil)
                        }
                        .foregroundStyle(f.raises ? NunaPalette.caution : NunaPalette.charge)
                        .padding(.horizontal, 8).frame(height: 24)
                        .background((f.raises ? NunaPalette.caution : NunaPalette.charge).opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Image(systemName: shown ? "chevron.up" : "chevron.down").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    if shown {
                        Text(verbatim: f.text).font(.nunaWords(size: 14)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var intro: String {
        switch topic {
        case 0: return String(localized: "Sleep and blood pressure affect each other: poor sleep can push it up, and high pressure often goes with poorer sleep.")
        case 1: return String(localized: "Moving regularly is one of the most dependable ways to help blood pressure.")
        default: return String(localized: "Stress raises blood pressure for a while, and the habits that come with long stress matter too.")
        }
    }

    private var findings: [Finding] {
        let higher = String(localized: "bp.tag.higher", defaultValue: "higher"), lower = String(localized: "bp.tag.lower", defaultValue: "lower")
        switch topic {
        case 0: return [
            Finding(id: "short", title: String(localized: "Short sleep"), tag: higher, raises: true,
                    text: String(localized: "Regularly sleeping less than about six hours is linked with higher blood pressure.")),
            Finding(id: "apnoea", title: String(localized: "Sleep apnoea"), tag: higher, raises: true,
                    text: String(localized: "Loud snoring with pauses in breathing and sleepiness by day can raise blood pressure. A doctor can test for it.")),
            Finding(id: "dip", title: String(localized: "Fall during sleep"), tag: lower, raises: false,
                    text: String(localized: "Blood pressure normally falls while you sleep. A smaller fall is linked with more heart risk; measuring it takes a 24-hour monitor.")),
        ]
        case 1: return [
            Finding(id: "aerobic", title: String(localized: "Aerobic exercise"), tag: lower, raises: false,
                    text: String(localized: "Walking, cycling or swimming on most days tends to lower resting blood pressure by a few mmHg.")),
            Finding(id: "strength", title: String(localized: "Strength training"), tag: lower, raises: false,
                    text: String(localized: "Moderate strength work can lower it a little. Keep breathing through each lift.")),
            Finding(id: "weight", title: String(localized: "Healthy weight"), tag: lower, raises: false,
                    text: String(localized: "Where weight is above the healthy range, losing some usually lowers blood pressure.")),
            Finding(id: "effort", title: String(localized: "During effort"), tag: higher, raises: true,
                    text: String(localized: "It rises while you exercise and settles afterwards, so measure when you are rested.")),
        ]
        default: return [
            Finding(id: "acute", title: String(localized: "Tension and hurry"), tag: higher, raises: true,
                    text: String(localized: "Tension, pain or rushing can raise a reading, which is why you sit quietly first.")),
            Finding(id: "salt", title: String(localized: "Salt and alcohol"), tag: higher, raises: true,
                    text: String(localized: "Eating a lot of salt and drinking a lot of alcohol raise blood pressure.")),
            Finding(id: "caffeine", title: String(localized: "Caffeine"), tag: higher, raises: true,
                    text: String(localized: "It can raise a reading for a short while, so measure before your coffee.")),
            Finding(id: "breath", title: String(localized: "Slow breathing"), tag: lower, raises: false,
                    text: String(localized: "A few minutes of slow breathing may lower it for a while. The lasting effect is less certain.")),
        ]
        }
    }
}

// MARK: - The card on Health

/// The Health tab's blood pressure card, after the reference: the latest reading on the left and, on the right, the last seven days as one short mark a
/// day at the height of its upper figure, in the colour of its range. Every mark is a reading taken with a cuff; nothing is estimated.
struct NunaBloodPressureCard: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var readings: [NunaBPReading] = []
    @State private var loaded = false

    private var latest: NunaBPReading? { readings.last }

    var body: some View {
        NavigationLink(value: NunaTodayRoute.bloodPressure) {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Blood pressure insights").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    HStack(alignment: .center, spacing: 12) {
                        figures.frame(maxWidth: .infinity, alignment: .leading)
                        NunaBPWeekMarks(readings: readings).frame(maxWidth: .infinity).frame(height: 76)
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") {
            readings = await NunaBP.load(repo)
            loaded = true
        }
    }

    private var figures: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let latest {
                nunaTrendsCap(Calendar.current.isDateInToday(latest.date) ? "Today's reading" : "Latest reading")
                // In the colour of the range the reading falls in, as its mark on the right.
                Text(verbatim: latest.text).font(.nuna(size: 28, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(28))
                    .foregroundStyle(latest.category.color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityLabel(Text(verbatim: latest.text + ", " + latest.category.wordText))
                // An older reading says when it was taken, so it is not read as today's.
                if !Calendar.current.isDateInToday(latest.date) {
                    Text(verbatim: NunaBP.when(latest.date)).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
                }
            } else {
                Text(loaded ? "No reading yet" : "Reading…").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text("Type it in or read it from Apple Health").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Seven days ending today over four hairlines: a day with readings carries one short mark at its mean upper figure, in the colour of its range.
private struct NunaBPWeekMarks: View {
    let readings: [NunaBPReading]

    private var marks: [(slot: Int, systolic: Double, color: Color)] {
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        return NunaBP.daily(readings).compactMap { day in
            guard let back = cal.dateComponents([.day], from: day.date, to: today).day, (0..<7).contains(back) else { return nil }
            return (6 - back, day.systolic, NunaBPCategory.of(day.systolic, day.diastolic).color)
        }
    }

    var body: some View {
        let marks = marks
        Canvas { ctx, size in
            for i in 0..<4 {
                let y = 1 + (size.height - 2) * CGFloat(i) / 3
                var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(NunaPalette.textMuted.opacity(0.28)), lineWidth: 1)
            }
            // A span wide enough that an ordinary week sits in the middle of the lines, widened for figures beyond it.
            let low = min(90, (marks.map(\.systolic).min() ?? 90) - 5)
            let high = max(160, (marks.map(\.systolic).max() ?? 160) + 5)
            let slot = size.width / 7
            for m in marks {
                let x = slot * (CGFloat(m.slot) + 0.5)
                let y = 1 + (size.height - 2) * CGFloat((high - m.systolic) / (high - low))
                var dash = Path(); dash.move(to: CGPoint(x: x - 6, y: y)); dash.addLine(to: CGPoint(x: x + 6, y: y))
                ctx.stroke(dash, with: .color(m.color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The latest reading as a tile among the vital signs on the Health monitor page. It is not one of the five signs the page judges against the
/// person's own usual: its words are the general reference range, and an older reading carries its date.
struct NunaBPVitalTile: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var latest: NunaBPReading?
    @State private var loaded = false

    var body: some View {
        NavigationLink(value: NunaTodayRoute.bloodPressure) {
            NunaVitalTile(icon: NunaIcons.bloodPressure, label: "Blood pressure monitor", value: latest?.text ?? "–", unit: "mmHg",
                          chip: chip, chipColor: latest?.category.color ?? NunaPalette.textSecondary,
                          symbol: latest.map { $0.category == .normal ? "checkmark" : "exclamationmark" })
        }
        .buttonStyle(.plain)
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") {
            latest = await NunaBP.load(repo).last
            loaded = true
        }
    }

    private var chip: String? {
        guard let latest else { return loaded ? String(localized: "No reading yet") : nil }
        let word = latest.category.wordText
        guard !Calendar.current.isDateInToday(latest.date) else { return word }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("dMMM")
        return word + " · " + f.string(from: latest.date)
    }
}
#endif
