#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics
import WhoopStore

// The Stress monitor's day breakdown and its trend view.
//
// Three readings of one day, each as time in the Low, Medium and High bands:
//  - Non activity: the scored waking hours (the stress read leaves out the hours you were moving).
//  - Sleep: the night's resting heart rate and HRV against your baseline, applied to the time asleep.
//  - Total day: the two together.
// Nothing here is a new score: the bands are the same 0 to 3 cut-offs the gauge and the day line use.

// MARK: - Bands

/// Minutes in the three stress bands.
struct NunaStressZones: Equatable {
    var low = 0.0
    var medium = 0.0
    var high = 0.0

    var total: Double { low + medium + high }

    /// A whole stretch spent at one level (the night, read against the baseline).
    init(level: Double, minutes: Double) {
        if level < 1 { low = minutes } else if level < 2 { medium = minutes } else { high = minutes }
    }

    init(low: Double = 0, medium: Double = 0, high: Double = 0) { self.low = low; self.medium = medium; self.high = high }

    /// One hour per scored hour of the day's curve.
    init(hours: [DaytimeStress.HourPoint]) {
        for level in hours.compactMap(\.level) {
            if level < 1 { low += 60 } else if level < 2 { medium += 60 } else { high += 60 }
        }
    }

    static func + (a: NunaStressZones, b: NunaStressZones) -> NunaStressZones {
        NunaStressZones(low: a.low + b.low, medium: a.medium + b.medium, high: a.high + b.high)
    }

    /// The mean of several days, or nil with fewer than `minimum` of them.
    static func mean(_ days: [NunaStressZones], minimum: Int = 2) -> NunaStressZones? {
        guard days.count >= minimum else { return nil }
        let n = Double(days.count)
        return NunaStressZones(low: days.map(\.low).reduce(0, +) / n, medium: days.map(\.medium).reduce(0, +) / n,
                               high: days.map(\.high).reduce(0, +) / n)
    }
}

enum NunaStressCategory: CaseIterable, Hashable {
    case total, nonActivity, sleep

    var title: LocalizedStringKey {
        switch self {
        case .total: return "Total day"
        case .nonActivity: return "Non activity"
        case .sleep: return "Sleep"
        }
    }

    var trendTitle: LocalizedStringKey {
        switch self {
        case .total: return "Total day stress"
        case .nonActivity: return "Non activity stress"
        case .sleep: return "Sleep stress"
        }
    }

    /// The header dropdown's identifier and its text.
    var key: String {
        switch self {
        case .total: return "total"
        case .nonActivity: return "non-activity"
        case .sleep: return "sleep"
        }
    }

    var trendName: String {
        switch self {
        case .total: return String(localized: "Total day stress")
        case .nonActivity: return String(localized: "Non activity stress")
        case .sleep: return String(localized: "Sleep stress")
        }
    }

    var icon: String {
        switch self {
        case .total: return "gauge.with.dots.needle.33percent"
        case .nonActivity: return "figure.stand"
        case .sleep: return "moon"
        }
    }

    var note: LocalizedStringKey {
        switch self {
        case .total: return "Stress experienced throughout the day including sleep and activities."
        case .nonActivity: return "Stress experienced outside of activities and sleep."
        case .sleep: return "Stress experienced during sleep."
        }
    }

    /// The closing sentence of the trend view's summary.
    var trendNote: String {
        switch self {
        case .total: return String(localized: "This includes time asleep and leaves out workouts.")
        case .nonActivity: return String(localized: "This leaves out sleep and workouts.")
        case .sleep: return String(localized: "This is read from your overnight resting heart rate and HRV.")
        }
    }
}

// MARK: - History

/// Time in the stress bands for earlier days, read from each day's own heart rate once and kept.
///
/// Scoring a day reads its heart rate, R-R and motion, so a past day is scored the first time it is wanted and its
/// answer is stored with a count of the heart-rate rows it was scored from: more rows arriving later (a backfill)
/// re-scores that one day. Today is never stored; the caller scores it live.
@MainActor
final class NunaStressHistory: ObservableObject {
    struct Entry: Codable, Equatable {
        var low: Double
        var medium: Double
        var high: Double
        var samples: Int

        var zones: NunaStressZones { NunaStressZones(low: low, medium: medium, high: high) }
        var hasData: Bool { low + medium + high > 0 }
    }

    @Published private(set) var entries: [String: Entry] = [:]
    @Published private(set) var loading = false

    private static let storeKey = "stress.zones.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let stored = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = stored
        }
    }

    /// Scores any of `days` (earlier than today) that are not yet stored, newest first.
    func ensure(days: [Date], repo: Repository) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wanted = Set(days.map { cal.startOfDay(for: $0) }).filter { $0 < today }.sorted(by: >)
        guard !wanted.isEmpty else { return }
        loading = true
        defer { loading = false }
        var changed = false
        for day in wanted {
            if Task.isCancelled { break }
            guard let next = cal.date(byAdding: .day, value: 1, to: day),
                  let end = cal.date(byAdding: .second, value: -1, to: next) else { continue }
            let key = Repository.localDayKey(day)
            guard let fingerprint = await repo.hrFingerprint(from: Int(day.timeIntervalSince1970), to: Int(end.timeIntervalSince1970)) else { continue }
            if let stored = entries[key], stored.samples == fingerprint.count { continue }
            var entry = Entry(low: 0, medium: 0, high: 0, samples: fingerprint.count)
            if fingerprint.count > 0, let scored = await StressDayCurve.today(repo: repo, now: end)?.result {
                let zones = NunaStressZones(hours: scored.hours)
                entry = Entry(low: zones.low, medium: zones.medium, high: zones.high, samples: fingerprint.count)
            }
            entries[key] = entry
            changed = true
        }
        // Scoring an earlier day replaces the curve's one-slot memo; put today's back so the next reader does not pay for it.
        if changed { _ = await StressDayCurve.today(repo: repo, now: Date()) }
        persist()
    }

    private func persist() {
        // Keep the last year; a long-running install would otherwise grow the entry list without bound.
        let cal = Calendar.current
        let cutoff = Repository.localDayKey(cal.date(byAdding: .day, value: -400, to: Date()) ?? Date())
        let kept = entries.filter { $0.key >= cutoff }
        if let data = try? JSONEncoder().encode(kept) { UserDefaults.standard.set(data, forKey: Self.storeKey) }
    }
}

/// The night's stress per day (0 to 3). The stored series only exists for an imported export, so on a strap-only install it is
/// empty and the sleep category had nothing to show; every day with a resting heart rate or HRV is scored the way the Day Stress
/// score is (against the 30 nights before it) and a stored value still wins for its day.
enum NunaNightlyStress {
    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func merged(stored: [String: Double], days: [DailyMetric]) -> [String: Double] {
        var out = stored
        guard let model = StressModel(days: days, stored: stored.map { (day: $0.key, value: $0.value) }) else { return out }
        for point in model.fullTrend {
            let key = keyFormatter.string(from: point.date)
            if out[key] == nil { out[key] = point.value }
        }
        return out
    }
}

/// Reads one day's zones for a category: the stored daytime read, the night, or both.
struct NunaStressDayReader {
    let history: [String: NunaStressHistory.Entry]
    /// The daily stress series (0 to 3, from the night's vitals) and the daily rows that carry the time asleep.
    let nightly: [String: Double]
    let rows: [DailyMetric]
    /// Today, scored live; today is not in `history`.
    let todayKey: String
    let today: NunaStressZones?

    func nonActivity(_ key: String) -> NunaStressZones? {
        if key == todayKey { return today.flatMap { $0.total > 0 ? $0 : nil } }
        return history[key].flatMap { $0.hasData ? $0.zones : nil }
    }

    func sleep(_ key: String) -> NunaStressZones? {
        guard let level = nightly[key], let minutes = rows.last(where: { $0.day == key })?.totalSleepMin, minutes > 0 else { return nil }
        return NunaStressZones(level: min(max(level, 0), 3), minutes: minutes)
    }

    func zones(_ category: NunaStressCategory, _ key: String) -> NunaStressZones? {
        switch category {
        case .nonActivity: return nonActivity(key)
        case .sleep: return sleep(key)
        case .total:
            switch (nonActivity(key), sleep(key)) {
            case let (a?, b?): return a + b
            case let (a?, nil): return a
            case let (nil, b?): return b
            default: return nil
            }
        }
    }
}

// MARK: - Shared drawing

enum NunaStressBand {
    static let low = NunaPalette.charge
    static let medium = NunaPalette.warning
    static let high = NunaPalette.alert

    static func hm(_ minutes: Double) -> String {
        let rounded = max(0, Int(minutes.rounded()))
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}

/// "■ LOW  ■ MEDIUM  ■ HIGH"
struct NunaStressLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(NunaStressBand.high, "High")
            item(NunaStressBand.medium, "Medium")
            item(NunaStressBand.low, "Low")
        }
    }

    private func item(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 10, height: 10)
            Text(title).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textSecondary)
        }
    }
}

// MARK: - The three cards on the Stress monitor

/// One category: today's split against a typical day on the same weekday, in time and in change.
struct NunaStressCategoryCard: View {
    let category: NunaStressCategory
    let today: NunaStressZones?
    let typical: NunaStressZones?
    let weekdayName: String
    let dateName: String

    private struct Band: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let color: Color
        let minutes: Double
        let typical: Double?
    }

    private var bands: [Band] {
        guard let today else { return [] }
        return [Band(id: 0, title: "Low", color: NunaStressBand.low, minutes: today.low, typical: typical?.low),
                Band(id: 1, title: "Medium", color: NunaStressBand.medium, minutes: today.medium, typical: typical?.medium),
                Band(id: 2, title: "High", color: NunaStressBand.high, minutes: today.high, typical: typical?.high)]
    }

    var body: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: category.icon).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    Text(category.title).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary)
                    Spacer(minLength: 0)
                }
                if let today, today.total > 0 {
                    (Text(verbatim: dateName + " ") + Text("stress").foregroundColor(NunaPalette.textPrimary)
                        + Text(verbatim: " ") + Text("vs. typical \(weekdayName)").foregroundColor(NunaPalette.textSecondary))
                        .font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary).lineLimit(2).minimumScaleFactor(0.8)
                    VStack(spacing: 6) {
                        NunaProportionBar(parts: [(today.low, NunaStressBand.low), (today.medium, NunaStressBand.medium), (today.high, NunaStressBand.high)], height: 14)
                        if let typical, typical.total > 0 {
                            NunaProportionBar(parts: [(typical.low, NunaStressBand.low.opacity(0.45)), (typical.medium, NunaStressBand.medium.opacity(0.45)),
                                                      (typical.high, NunaStressBand.high.opacity(0.45))], height: 14)
                        }
                    }
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(bands) { band in column(band) }
                    }
                } else {
                    Text("No data yet").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Text(category.note).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
                NavigationLink {
                    NunaStressTrendView(category: category)
                } label: {
                    HStack(spacing: 8) {
                        Text("See trends").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        Image(systemName: "arrow.right").font(.nuna(size: 13, weight: .bold))
                    }
                    .foregroundStyle(NunaPalette.textPrimary).frame(minHeight: 30)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The change against a typical day, in a small grey box with a triangle, as the monitor cards of the reference draw it.
    private func changeBox(_ band: Band) -> some View {
        HStack(spacing: 4) {
            if let typical = band.typical, typical > 0 {
                let change = (band.minutes - typical) / typical * 100
                Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.nuna(size: 8, weight: .bold))
                Text(verbatim: "\(Int(abs(change).rounded()))%").font(.nuna(size: 11.5, weight: .bold))
            } else {
                Text(verbatim: "–").font(.nuna(size: 11.5, weight: .bold))
            }
        }
        .foregroundStyle(NunaPalette.textSecondary)
        .padding(.horizontal, 8).frame(height: 24)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
    }

    private func column(_ band: Band) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: NunaStressBand.hm(band.minutes)).font(.nuna(size: 22, weight: .bold, design: NunaType.design))
                .foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
            changeBox(band)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(band.color).frame(width: 10, height: 10)
                Text(band.title).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Trend view

/// The three bands as a share of each day, over a week, a month or six months, for one category.
struct NunaStressTrendView: View {
    @State private var category: NunaStressCategory
    @EnvironmentObject private var repo: Repository
    @StateObject private var history = NunaStressHistory()
    @StateObject private var nightly = NunaSeriesModel()
    @State private var range = 7
    @State private var pageOffset = 0
    @State private var todayZones: NunaStressZones?
    private static let maxPages = 52

    init(category: NunaStressCategory) { _category = State(initialValue: category) }

    private struct Bar: Identifiable {
        let date: Date
        let zones: NunaStressZones
        var id: Date { date }
    }

    private var cal: Calendar { Calendar.current }
    private var todayStart: Date { cal.startOfDay(for: Date()) }
    private var lastDay: Date { cal.date(byAdding: .day, value: -pageOffset * range, to: todayStart) ?? todayStart }
    private var firstDay: Date { cal.date(byAdding: .day, value: -(range - 1), to: lastDay) ?? lastDay }
    private var windowDays: [Date] { (0..<range).compactMap { cal.date(byAdding: .day, value: $0, to: firstDay) } }
    private var priorDays: [Date] {
        let start = cal.date(byAdding: .day, value: -range, to: firstDay) ?? firstDay
        return (0..<range).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var reader: NunaStressDayReader {
        NunaStressDayReader(history: history.entries, nightly: NunaNightlyStress.merged(stored: nightly.byDay, days: repo.days), rows: repo.days,
                            todayKey: Repository.localDayKey(todayStart), today: todayZones)
    }

    private var bars: [Bar] {
        let reader = self.reader
        return windowDays.compactMap { day in reader.zones(category, Repository.localDayKey(day)).map { Bar(date: day, zones: $0) } }
    }

    /// The mean daily high-stress minutes over `days`, today left out (it is still being lived).
    private func averageHigh(_ days: [Date]) -> Double? {
        let reader = self.reader
        let values = days.filter { $0 < todayStart }.compactMap { reader.zones(category, Repository.localDayKey($0))?.high }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private var dateRange: String {
        let short = DateFormatter(); short.locale = AppLanguage.activeLocale; short.setLocalizedDateFormatFromTemplate("d MMM")
        let long = DateFormatter(); long.locale = AppLanguage.activeLocale; long.setLocalizedDateFormatFromTemplate("d MMM yy")
        return "\(short.string(from: firstDay)) – \(long.string(from: lastDay))"
    }

    private var periodWord: String {
        range == 7 ? String(localized: "week") : (range == 30 ? String(localized: "month") : String(localized: "six months"))
    }

    var body: some View {
        let average = averageHigh(windowDays)
        let prior = range <= 30 ? averageHigh(priorDays) : nil
        NunaDetailScreen("Trend view") {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Avg. high stress").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                .foregroundStyle(NunaPalette.textSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(verbatim: average.map(NunaStressBand.hm) ?? "–").font(.nuna(size: 44, weight: .bold, design: NunaType.design))
                                    .tracking(nunaTrackingNumber(44)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                                if average != nil {
                                    Text("hr").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 12) {
                            NunaRangeSwitch(range: $range) { pageOffset = 0 }
                            NunaDateStepper(label: dateRange, canGoBack: pageOffset < Self.maxPages, canGoForward: pageOffset > 0,
                                            back: { pageOffset += 1 }, forward: { pageOffset = max(0, pageOffset - 1) })
                        }
                    }
                    if let average, let prior, prior > 0 {
                        let change = (average - prior) / prior * 100
                        HStack(spacing: 0) {
                            NunaChip(verbatim: (change >= 0 ? "▲ " : "▼ ") + "\(Int(abs(change).rounded()))% " + String(localized: "vs. prior period"),
                                     color: change > 0 ? NunaPalette.warning : NunaPalette.charge)
                            Spacer(minLength: 0)
                        }
                    }
                    Text(verbatim: summary(average: average, prior: prior)).font(.nuna(size: 14.5, weight: .semibold))
                        .foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    HStack { Spacer(minLength: 0); NunaStressLegend() }
                    if bars.isEmpty {
                        Text(history.loading ? "Working out your days…" : "No stress data in this period")
                            .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center).textCase(nil)
                    } else {
                        chart(bars)
                        if history.loading {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Working out your days…").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle").font(.nuna(size: 13, weight: .semibold))
                        Text("Average does not include today (\(todayLabel)).")
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
            }
        }
        // The header's dropdown names the screen and moves between the three readings, like the other detail screens.
        .environment(\.nunaDetailSwitch, NunaDetailSwitch(
            current: category.key,
            items: NunaStressCategory.allCases.map { .init(key: $0.key, title: $0.trendName, icon: $0.icon) }) { key in
                if let next = NunaStressCategory.allCases.first(where: { $0.key == key }) { category = next }
            })
        .task(id: "\(repo.refreshSeq)-\(range)-\(pageOffset)") {
            await nightly.load(repo: repo, key: "stress", source: "my-whoop")
            if let live = await StressDayCurve.today(repo: repo, now: Date())?.result {
                let zones = NunaStressZones(hours: live.hours)
                if zones != todayZones { todayZones = zones }
            }
            await history.ensure(days: windowDays + (range <= 30 ? priorDays : []), repo: repo)
        }
    }

    private var todayLabel: String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: todayStart)
    }

    private func summary(average: Double?, prior: Double?) -> String {
        guard let average else { return category.trendNote }
        let value = NunaStressBand.hm(average)
        let lead: String
        if let prior {
            let delta = average - prior
            if abs(delta) < 1 {
                lead = String(localized: "You spent an average of \(value) a day in the high-stress zone this \(periodWord), in line with your previous average (\(NunaStressBand.hm(prior))).")
            } else if delta > 0 {
                lead = String(localized: "You spent an average of \(value) a day in the high-stress zone this \(periodWord), which is above your previous average (\(NunaStressBand.hm(prior))).")
            } else {
                lead = String(localized: "You spent an average of \(value) a day in the high-stress zone this \(periodWord), which is below your previous average (\(NunaStressBand.hm(prior))).")
            }
        } else {
            lead = String(localized: "You spent an average of \(value) a day in the high-stress zone this \(periodWord).")
        }
        return lead + " " + category.trendNote
    }

    // MARK: Chart

    @ViewBuilder private func chart(_ bars: [Bar]) -> some View {
        if range == 7 { weekChart(bars) } else if range == 180 { monthlyChart(bars) } else { dailyChart(bars) }
    }

    private func share(_ minutes: Double, of zones: NunaStressZones) -> Double { zones.total > 0 ? minutes / zones.total * 100 : 0 }

    @AxisContentBuilder private var percentAxis: some AxisContent {
        AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
            AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.5))
            AxisValueLabel {
                if let v = value.as(Double.self) { Text(verbatim: "\(Int(v))%").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted) }
            }
        }
    }

    private static func key(_ date: Date) -> String { String(Int(date.timeIntervalSince1970)) }

    /// A week: one column per day, labelled with the weekday and date.
    private func weekChart(_ bars: [Bar]) -> some View {
        let all = windowDays
        return Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Day", Self.key(bar.date)), y: .value("Low", share(bar.zones.low, of: bar.zones)), width: .ratio(0.62))
                    .foregroundStyle(NunaStressBand.low).cornerRadius(2)
                BarMark(x: .value("Day", Self.key(bar.date)), y: .value("Medium", share(bar.zones.medium, of: bar.zones)), width: .ratio(0.62))
                    .foregroundStyle(NunaStressBand.medium).cornerRadius(2)
                BarMark(x: .value("Day", Self.key(bar.date)), y: .value("High", share(bar.zones.high, of: bar.zones)), width: .ratio(0.62))
                    .foregroundStyle(NunaStressBand.high).cornerRadius(2)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: all.map { Self.key($0) })
        .chartXAxis {
            AxisMarks(values: all.map { Self.key($0) }) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel {
                    if let k = value.as(String.self), let date = all.first(where: { Self.key($0) == k }) { axisLabel(date) }
                }
            }
        }
        .chartYAxis { percentAxis }
        .frame(height: 260)
        .accessibilityLabel(Text("Stress share chart"))
    }

    @ViewBuilder private func axisLabel(_ date: Date) -> some View {
        let f = DateFormatter()
        VStack(spacing: 1) {
            Text(verbatim: { f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE"); return f.string(from: date) }())
            Text(verbatim: { f.setLocalizedDateFormatFromTemplate("d"); return f.string(from: date) }())
        }
        .font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
    }

    // MARK: Six months: each month's average split, drawn as a line per band over the faint days

    private struct MonthShare: Identifiable {
        let first: Date
        let end: Date
        let low: Double
        let medium: Double
        let high: Double
        var id: Date { first }
        var center: Date { Date(timeIntervalSince1970: (first.timeIntervalSince1970 + end.timeIntervalSince1970) / 2) }
    }

    /// The mean daily share of each band in every calendar month of the window.
    private func monthShares(_ bars: [Bar]) -> [MonthShare] {
        var groups: [(first: Date, last: Date, shares: [(Double, Double, Double)])] = []
        var lastKey: DateComponents?
        for bar in bars {
            let key = cal.dateComponents([.year, .month], from: bar.date)
            let total = max(bar.zones.total, 0.0001)
            let share = (bar.zones.low / total * 100, bar.zones.medium / total * 100, bar.zones.high / total * 100)
            if key == lastKey, !groups.isEmpty {
                groups[groups.count - 1].last = bar.date
                groups[groups.count - 1].shares.append(share)
            } else {
                groups.append((bar.date, bar.date, [share])); lastKey = key
            }
        }
        return groups.map { group in
            let n = Double(group.shares.count)
            return MonthShare(first: group.first, end: cal.date(byAdding: .day, value: 1, to: group.last) ?? group.last,
                              low: group.shares.map(\.0).reduce(0, +) / n, medium: group.shares.map(\.1).reduce(0, +) / n,
                              high: group.shares.map(\.2).reduce(0, +) / n)
        }
    }

    private func monthlyChart(_ bars: [Bar]) -> some View {
        let months = monthShares(bars)
        let end = cal.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        return Chart {
            // The days, faint behind the lines.
            ForEach(bars) { bar in
                BarMark(x: .value("Day", bar.date, unit: .day), y: .value("Low", share(bar.zones.low, of: bar.zones)), width: .automatic)
                    .foregroundStyle(NunaStressBand.low.opacity(0.22))
                BarMark(x: .value("Day", bar.date, unit: .day), y: .value("Medium", share(bar.zones.medium, of: bar.zones)), width: .automatic)
                    .foregroundStyle(NunaStressBand.medium.opacity(0.22))
                BarMark(x: .value("Day", bar.date, unit: .day), y: .value("High", share(bar.zones.high, of: bar.zones)), width: .automatic)
                    .foregroundStyle(NunaStressBand.high.opacity(0.22))
            }
            // Each band's monthly mean sits at the middle of its stretch of the stacked 100%.
            ForEach(months) { month in
                bandLine(month, share: month.low, at: month.low / 2, color: NunaStressBand.low)
                bandLine(month, share: month.medium, at: month.low + month.medium / 2, color: NunaStressBand.medium)
                bandLine(month, share: month.high, at: month.low + month.medium + month.high / 2, color: NunaStressBand.high)
            }
        }
        .chartYScale(domain: 0...114)
        .chartXScale(domain: firstDay...end)
        .chartXAxis {
            AxisMarks(values: months.map(\.center)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
        .chartYAxis { percentAxis }
        .frame(height: 280)
        .accessibilityLabel(Text("Stress share chart"))
    }

    private func bandLine(_ month: MonthShare, share: Double, at height: Double, color: Color) -> some ChartContent {
        RuleMark(xStart: .value("Month start", month.first), xEnd: .value("Month end", month.end), y: .value("Mean", height))
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .foregroundStyle(color)
            .annotation(position: .top, alignment: .center, spacing: 2) {
                Text(verbatim: "\(Int(share.rounded()))%").font(.nuna(size: 11.5, weight: .bold, design: NunaType.design))
                    .foregroundStyle(NunaPalette.textPrimary).fixedSize()
            }
    }

    /// A month: one thin column per day on a time axis, like the other trend cards.
    private func dailyChart(_ bars: [Bar]) -> some View {
        let end = cal.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        return Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Day", bar.date, unit: .day), y: .value("Low", share(bar.zones.low, of: bar.zones)), width: .automatic)
                    .foregroundStyle(NunaStressBand.low)
                BarMark(x: .value("Day", bar.date, unit: .day), y: .value("Medium", share(bar.zones.medium, of: bar.zones)), width: .automatic)
                    .foregroundStyle(NunaStressBand.medium)
                BarMark(x: .value("Day", bar.date, unit: .day), y: .value("High", share(bar.zones.high, of: bar.zones)), width: .automatic)
                    .foregroundStyle(NunaStressBand.high)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: firstDay...end)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.5))
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
        .chartYAxis { percentAxis }
        .frame(height: 260)
        .accessibilityLabel(Text("Stress share chart"))
    }
}
#endif
