#if os(iOS)
import Foundation
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// One night as the Nuna sleep screens read it: the main block group, its stage split and timeline, the
/// naps of the same day, and the cached daily row for vitals. Display only; the selection of the main
/// block, the nap classification and the stage decoding all come from the same helpers `SleepView` uses.
struct NunaNight: Identifiable {
    var id: String { dayKey }
    let dayKey: String
    let wakeDate: Date
    let onset: Date
    let wake: Date
    let stages: Stages
    let intervals: [SleepInterval]
    let naps: [NunaNap]
    let daily: DailyMetric?
    /// True when the stage split is the daily aggregate (no per-epoch timeline).
    let proportional: Bool

    var asleepMin: Double { stages.asleep }
    var inBedMin: Double { stages.total }
}

struct NunaNap: Identifiable {
    var id: Int { start.timeIntervalSince1970.hashValue }
    let start: Date
    let end: Date
    let asleepMin: Double
    let intervals: [SleepInterval]
    var spanMin: Double { end.timeIntervalSince(start) / 60 }
}

@MainActor
final class NunaSleepModel: ObservableObject {
    /// 0 = latest night, 1 = the one before, ...
    @Published var index = 0
    @Published private(set) var nights: [NunaNight] = []
    /// metric key -> (day key -> value)
    @Published private(set) var series: [String: [String: Double]] = [:]
    @Published private(set) var loaded = false
    /// Recency-weighted debt over the latest nights (same ledger the Default Sleep tab shows).
    @Published private(set) var ledger: SleepDebtLedger?
    private var importedNeed: [String: Double] = [:]
    private var fallbackNeed: Double = 450

    var night: NunaNight? { nights.indices.contains(index) ? nights[index] : nil }
    var hasOlder: Bool { index + 1 < nights.count }
    var hasNewer: Bool { index > 0 }

    private static let keys = ["sleep_performance", "sleep_need_min", "sleep_debt_min", "hours_vs_needed_pct",
                               "sleep_consistency", "restorative_pct", "sleep_efficiency", "restorative_min"]

    func value(_ key: String, _ night: NunaNight? = nil) -> Double? {
        guard let n = night ?? self.night else { return nil }
        return series[key]?[n.dayKey]
    }

    // Derived per-night figures. They use the same rules as `SleepModel` (imported figure wins, else a
    // personal estimate), so the Nuna and Default screens agree.

    func need(_ n: NunaNight) -> Double { importedNeed[n.dayKey] ?? series["sleep_need_min"]?[n.dayKey] ?? fallbackNeed }

    func hoursVsNeeded(_ n: NunaNight) -> Double? {
        if let v = series["hours_vs_needed_pct"]?[n.dayKey] { return v }
        let asleep = n.daily?.totalSleepMin ?? n.asleepMin
        return asleep > 0 ? asleep / need(n) * 100 : nil
    }

    func restorative(_ n: NunaNight) -> Double? {
        if let v = series["restorative_pct"]?[n.dayKey] { return v }
        let asleep = n.stages.asleep
        return asleep > 0 ? (n.stages.deep + n.stages.rem) / asleep * 100 : nil
    }

    func efficiency(_ n: NunaNight) -> Double? {
        if let e = n.daily?.efficiency { return e <= 1 ? e * 100 : e }
        return series["sleep_efficiency", default: [:]][n.dayKey]
    }

    /// Bedtime spread over the 14 nights up to this one: 100 when you go to bed at the same time.
    func consistency(_ n: NunaNight) -> Double? {
        if let v = series["sleep_consistency"]?[n.dayKey] { return v }
        guard let i = nights.firstIndex(where: { $0.id == n.id }) else { return nil }
        let window = nights.dropFirst(i).prefix(14)
        let cal = Calendar.current
        let mins: [Double] = window.map { night in
            let c = cal.dateComponents([.hour, .minute], from: night.onset)
            var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            if m < 12 * 60 { m += 24 * 60 }
            return m
        }
        guard mins.count >= 3 else { return nil }
        let mean = mins.reduce(0, +) / Double(mins.count)
        let sd = (mins.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(mins.count)).squareRoot()
        return max(0, min(100, 100 * (1 - sd / 120)))
    }

    /// Debt in minutes as of the latest night, when there is one.
    var debtMin: Double? { index == 0 ? ledger.flatMap { $0.isDebt ? $0.magnitudeMin : nil } : nil }

    /// A per-night figure for the last `count` nights ending at the selected one (oldest first).
    func recent(count: Int = 14, _ f: (NunaNight) -> Double?) -> [Double?] {
        nights.dropFirst(index).prefix(count).reversed().map(f)
    }

    /// Mean stage minutes over the nights before the selected one (up to 14), for "compared to usual".
    func typical() -> Stages? {
        let others = nights.enumerated().filter { $0.offset > index }.prefix(14).map(\.element)
            .filter { !$0.proportional || $0.stages.total > 0 }
        guard others.count >= 3 else { return nil }
        let n = Double(others.count)
        return Stages(awake: others.map { $0.stages.awake }.reduce(0, +) / n,
                      light: others.map { $0.stages.light }.reduce(0, +) / n,
                      deep: others.map { $0.stages.deep }.reduce(0, +) / n,
                      rem: others.map { $0.stages.rem }.reduce(0, +) / n)
    }

    /// Values of a series for the last `count` nights ending at the selected one (oldest first).
    func recent(_ key: String, count: Int = 14) -> [Double?] {
        let slice = nights.dropFirst(index).prefix(count).reversed()
        return slice.map { series[key]?[$0.dayKey] }
    }

    func load(repo: Repository) async {
        let hab = await repo.habitualMidsleepSec()
        let sessions = await repo.allSleepSessions(days: 60)
        var daily: [String: DailyMetric] = [:]
        for d in repo.days { daily[d.day] = d }

        var out: [NunaNight] = []
        for group in SleepModel.navDays(navSessions: sessions).prefix(30) {
            let main = SleepView.mainNightGroup(group, habitualMidsleepSec: hab)
            guard let first = main.first, let last = main.last else { continue }
            let mainStarts = Set(main.map(\.startTs))
            let onsetTs = SleepModel.nightOnsetTs(main)
            let wakeDate = Date(timeIntervalSince1970: TimeInterval(last.endTs))
            let key = Repository.localDayKey(wakeDate)
            let row = daily[key]

            var stages = Stages(awake: 0, light: 0, deep: 0, rem: 0)
            var intervals: [SleepInterval] = []
            var found = false
            for block in main {
                let start = block.effectiveStartTs
                if let seg = SleepView.decodeSegments(block.stagesJSON, sessionStart: start) {
                    found = true
                    stages.awake += seg.stages.awake; stages.light += seg.stages.light
                    stages.deep += seg.stages.deep; stages.rem += seg.stages.rem
                    let shift = TimeInterval(start - onsetTs)
                    intervals += seg.intervals.map { SleepInterval(stage: $0.stage, start: $0.start + shift, end: $0.end + shift) }
                } else if let s = SleepView.decodeStages(block.stagesJSON) {
                    found = true
                    stages.awake += s.awake; stages.light += s.light; stages.deep += s.deep; stages.rem += s.rem
                }
            }
            var proportional = intervals.isEmpty
            if !found, let row, let asleep = row.totalSleepMin, asleep > 0 {
                let eff = row.efficiency.map { $0 > 1 ? $0 / 100 : $0 }
                let bed = (eff ?? 0) > 0 ? asleep / eff! : asleep
                stages = Stages(awake: max(0, bed - asleep), light: row.lightMin ?? 0, deep: row.deepMin ?? 0, rem: row.remMin ?? 0)
                proportional = true
            }
            _ = first

            let naps: [NunaNap] = group.filter { !mainStarts.contains($0.startTs) }.map { b in
                let start = b.effectiveStartTs
                let seg = SleepView.decodeSegments(b.stagesJSON, sessionStart: start)
                let asleep = seg?.stages.asleep ?? SleepView.decodedAsleepMinutes(b.stagesJSON, effectiveStartTs: start)
                return NunaNap(start: Date(timeIntervalSince1970: TimeInterval(start)),
                               end: Date(timeIntervalSince1970: TimeInterval(b.endTs)),
                               asleepMin: asleep, intervals: seg?.intervals ?? [])
            }.sorted { $0.start < $1.start }

            out.append(NunaNight(dayKey: key, wakeDate: wakeDate,
                                 onset: Date(timeIntervalSince1970: TimeInterval(onsetTs)),
                                 wake: wakeDate, stages: stages, intervals: intervals, naps: naps,
                                 daily: row, proportional: proportional))
        }
        nights = out

        var all: [String: [String: Double]] = [:]
        for k in Self.keys {
            let s = await repo.exploreSeries(key: k, source: "my-whoop", days: 60)
            all[k] = Dictionary(s.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        }
        series = all
        importedNeed = repo.importedSleep.compactMapValues { $0.needMin }
        fallbackNeed = SleepModel.sleepNeedMin(days: repo.days)
        let napByDay = SleepModel.napSleepMinutesByDay(navDays: SleepModel.navDays(navSessions: sessions), habitualMidsleepSec: hab)
        ledger = SleepModel.debtLedger(days: repo.days, napSleepMinByDay: napByDay)
        if index >= out.count { index = 0 }
        loaded = true
    }
}

// MARK: - Formatting shared by the sleep screens

enum NunaSleepFormat {
    static func duration(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        let h = m / 60, r = m % 60
        if h == 0 { return String(localized: "\(r)m") }
        return String(localized: "\(h)h \(r)m")
    }

    static func clock(_ date: Date) -> String {
        AppClock.hourMinuteFormatter().string(from: date)
    }

    static func nightTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return f.string(from: date)
    }
}
#endif
