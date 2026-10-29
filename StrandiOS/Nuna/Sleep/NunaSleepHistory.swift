#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import WhoopStore
import StrandAnalytics

/// The sleep figures of every stored day, for the long trend pages (a week, a month, six months). `NunaSleepModel` holds only the last month of nights
/// with their stage timelines; these pages need the year, so they read the daily rows and series, which are what the model's own figures come from.
@MainActor
final class NunaSleepHistory: ObservableObject {
    @Published private(set) var asleepMin: [String: Double] = [:]
    @Published private(set) var deepMin: [String: Double] = [:]
    @Published private(set) var remMin: [String: Double] = [:]
    @Published private(set) var needMin: [String: Double] = [:]
    @Published private(set) var consistency: [String: Double] = [:]
    @Published private(set) var efficiency: [String: Double] = [:]
    /// The Charge score of each day, for the Charge trend page.
    @Published private(set) var charge: [String: Double] = [:]
    /// The sleep debt as of each night, from the same recurrence the weekly Sleep debt card uses, run over every stored night.
    @Published private(set) var debtMin: [String: Double] = [:]
    /// When the main night began and ended, by the day it is filed under, in hours from that evening's midnight (a bedtime after midnight is 24 and
    /// more; the wake is always past 24), the way the weekly Time in bed card reads them.
    @Published private(set) var bedHour: [String: Double] = [:]
    @Published private(set) var wakeHour: [String: Double] = [:]
    @Published private(set) var loaded = false

    /// The need used for a night with no stored one: the same fallback the sleep model uses.
    private static let fallbackNeed = 450.0

    func load(repo: Repository) async {
        var a: [String: Double] = [:], d: [String: Double] = [:], r: [String: Double] = [:]
        for row in repo.days {
            guard let t = row.totalSleepMin, t > 0 else { continue }
            a[row.day] = t
            if let deep = row.deepMin, let rem = row.remMin { d[row.day] = deep; r[row.day] = rem }
        }
        let need = await repo.exploreSeries(key: "sleep_need_min", source: "my-whoop", days: 400)
        let cons = await repo.exploreSeries(key: "sleep_consistency", source: "my-whoop", days: 400)
        asleepMin = a; deepMin = d; remMin = r
        // Efficiency is stored as a fraction on some rows and a percentage on others; the series, when there is one, wins.
        var eff: [String: Double] = [:]
        for row in repo.days { if let e = row.efficiency, e > 0 { eff[row.day] = e <= 1 ? e * 100 : e } }
        for point in await repo.exploreSeries(key: "sleep_efficiency", source: "my-whoop", days: 400) { eff[point.day] = point.value <= 1 ? point.value * 100 : point.value }
        efficiency = eff
        charge = Dictionary((await repo.exploreSeries(key: "recovery", source: "my-whoop", days: 400)).map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        let healthy = SleepModel.debtNeedMin(days: repo.days)
        debtMin = Dictionary(SleepDebt.debtSeries(series: a.keys.sorted().map { ($0, a[$0]) }, needHours: healthy / 60).map { ($0.day, max($0.value, 0)) },
                             uniquingKeysWith: { _, l in l })
        await loadBedTimes(repo: repo)
        needMin = Dictionary(need.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        consistency = Dictionary(cons.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        loaded = true
    }

    private func loadBedTimes(repo: Repository) async {
        let hab = await repo.habitualMidsleepSec()
        let sessions = await repo.allSleepSessions(days: 400)
        var bed: [String: Double] = [:], wake: [String: Double] = [:]
        func hours(_ ts: Int) -> Double {
            let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
            return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        }
        for group in SleepModel.navDays(navSessions: sessions) {
            let main = SleepView.mainNightGroup(group, habitualMidsleepSec: hab)
            guard let last = main.last else { continue }
            let onset = SleepModel.nightOnsetTs(main)
            let key = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(last.endTs)))
            let b = hours(onset) < 12 ? hours(onset) + 24 : hours(onset)
            var w = hours(last.endTs) + 24
            if w <= b { w += 24 }
            bed[key] = b; wake[key] = w
        }
        bedHour = bed; wakeHour = wake
    }

    func need(_ day: String) -> Double { needMin[day] ?? Self.fallbackNeed }

    func hoursVsNeeded(_ day: String) -> Double? { asleepMin[day].map { $0 / need(day) * 100 } }

    /// The oldest day with a night, so the date stepper knows where to stop.
    var oldest: Date? {
        guard let k = asleepMin.keys.min() else { return nil }
        return NunaDayFormat.parse(k)
    }
}

/// The window a trend page shows: a week, a month or six months ending `endingDaysAgo` days (and `page` periods) before today, and the labels under it.
struct NunaTrendWindow {
    let range: Int
    let start: Date
    let end: Date
    private var cal: Calendar { Calendar.current }

    init(range: Int, page: Int, endingDaysAgo: Int) {
        let cal = Calendar.current
        self.range = range
        self.end = cal.date(byAdding: .day, value: -(page * range + endingDaysAgo), to: cal.startOfDay(for: Date())) ?? Date()
        self.start = cal.date(byAdding: .day, value: -(range - 1), to: end) ?? end
    }

    var label: String {
        let a = DateFormatter(); a.locale = AppLanguage.activeLocale; a.setLocalizedDateFormatFromTemplate("MMM d")
        let b = DateFormatter(); b.locale = AppLanguage.activeLocale; b.setLocalizedDateFormatFromTemplate("MMM d, yy")
        return "\(a.string(from: start)) – \(b.string(from: end))"
    }

    /// The x domain of a chart over this window.
    var domain: ClosedRange<Date> { start...(cal.date(byAdding: .day, value: 1, to: end) ?? end) }

    /// Noon of each day, so a point sits in the middle of its day.
    var noons: [Date] {
        (0..<range).compactMap { i in cal.date(byAdding: .day, value: i, to: start).flatMap { cal.date(byAdding: .hour, value: 12, to: $0) } }
    }

    func noon(_ day: Date) -> Date { cal.date(byAdding: .hour, value: 12, to: cal.startOfDay(for: day)) ?? day }

    private var monthMiddles: [Date] {
        var out: [Date] = []
        var cursor = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
        while cursor <= end {
            if let mid = cal.date(byAdding: .day, value: 14, to: cursor), mid >= start, mid <= end { out.append(mid) }
            cursor = cal.date(byAdding: .month, value: 1, to: cursor) ?? end.addingTimeInterval(86_400)
        }
        return out
    }

    /// Every day of a week, every seventh day of a month, the middle of each month over six months.
    var axisDates: [Date] {
        switch range {
        case 7: return noons
        case 30: return noons.enumerated().filter { $0.offset % 7 == 0 }.map(\.element)
        default: return monthMiddles
        }
    }

    @ViewBuilder func axisLabel(_ d: Date) -> some View {
        let templates: [String] = range == 7 ? ["EEE", "d"] : (range == 30 ? ["MMM", "d"] : ["MMM"])
        VStack(spacing: 2) {
            ForEach(templates, id: \.self) { t in
                let f = DateFormatter()
                Text(verbatim: { f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate(t); return f.string(from: d) }())
                    .font(.nuna(size: 12.5, weight: .semibold)).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }
}

/// One stretch of a six-month window (a sixth of it) with the average of its days and how that moved against the stretch before.
struct NunaPeriodSegment: Identifiable {
    let start: Date
    let end: Date
    let value: Double
    /// Change against the stretch before, in percent; nil for the first.
    let delta: Double?
    var id: Date { start }

    var tint: Color { tint(upIsGood: true) }

    /// Green when it moved the good way, orange the other way, white when it did not move; `upIsGood` false for a figure like debt.
    func tint(upIsGood: Bool) -> Color {
        guard let delta, abs(delta) >= 0.5 else { return Color.white }
        return (delta > 0) == upIsGood ? Color(hex: "#19D9A0") : Color(hex: "#F5A623")
    }

    /// Six equal stretches of the window, each the mean of the points inside it; a stretch with none is left out.
    static func make(_ points: [(date: Date, value: Double)], from: Date, to: Date, parts: Int = 6) -> [NunaPeriodSegment] {
        let cal = Calendar.current
        let days = max(cal.dateComponents([.day], from: from, to: to).day ?? 0, 1) + 1
        var out: [NunaPeriodSegment] = []
        var previous: Double?
        for i in 0..<parts {
            let a = cal.date(byAdding: .day, value: days * i / parts, to: from) ?? from
            let b = cal.date(byAdding: .day, value: days * (i + 1) / parts, to: from) ?? to
            let inside = points.filter { $0.date >= a && $0.date < b }.map(\.value)
            guard !inside.isEmpty else { continue }
            let mean = inside.reduce(0, +) / Double(inside.count)
            let delta: Double? = previous.flatMap { $0 != 0 ? (mean - $0) / abs($0) * 100 : nil }
            out.append(NunaPeriodSegment(start: a, end: b, value: mean, delta: delta))
            previous = mean
        }
        return out
    }
}

/// The six-month look drawn over a chart: a short line at each stretch's average with the figure above it and, in the colour of the move, the change
/// against the stretch before under it (green up, orange down, white when it did not move or is the first).
struct NunaSegmentsLayer: View {
    let segments: [NunaPeriodSegment]
    let proxy: ChartProxy
    let frame: CGRect
    /// A fixed colour for the line and figure (a series that has no good or bad direction); nil colours them by the move.
    var color: Color?
    var showsDelta = true
    /// Whether a rise is the good direction; false colours a rise orange (sleep debt).
    var upIsGood = true
    let text: (Double) -> String

    var body: some View {
        ZStack {
            ForEach(segments) { s in
                if let x0 = proxy.position(forX: s.start), let x1 = proxy.position(forX: s.end), let y = proxy.position(forY: s.value) {
                    let tint = color ?? s.tint(upIsGood: upIsGood)
                    Rectangle().fill(tint).frame(width: max(x1 - x0 - 8, 4), height: 3)
                        .position(x: frame.minX + (x0 + x1) / 2, y: frame.minY + y)
                    Text(verbatim: text(s.value)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(color ?? Color.white)
                        .fixedSize().position(x: frame.minX + (x0 + x1) / 2 - (showsDelta ? 0 : 0), y: frame.minY + y - 18)
                    if showsDelta, let d = s.delta {
                        Text(verbatim: Int(abs(d).rounded()) == 0 ? "0%" : String(format: "%@%d%%", d >= 0 ? "+" : "−", Int(abs(d).rounded()))).font(.nuna(size: 13, weight: .heavy, design: NunaType.design))
                            .foregroundStyle(tint).fixedSize().position(x: frame.minX + (x0 + x1) / 2, y: frame.minY + y + 18)
                    }
                }
            }
        }
    }
}
#endif
