#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The screen behind the Rest ring, built like the Charge one: the ring, the four things Rest is made of, Anya's line, the trend of Rest and,
/// under it the whole night: stages, comparison, naps, vitals, need and body clock.
struct NunaRestDetailView: View {
    /// The night to open on (0 is the latest). The Sleep entries open this same screen on the night they were showing.
    var startIndex = 0
    /// "Rest" behind the ring, "Sleep" behind the Sleep tile and rows: one screen, one night, whichever way it was opened.
    var title: LocalizedStringKey = "Sleep"
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @StateObject private var series = NunaSeriesModel()
    @StateObject private var model = NunaSleepModel()
    @State private var showCoach = false
    @State private var showInfo = false
    @AppStorage(NunaNapPrefs.autoDetectKey) private var autoNaps = true
    /// The journal's evening habits against this wearer's own Rest, for the night's line.
    @State private var factors: NunaSleepFactorContext?

    /// The Rest ring is always this steel blue, whatever the score; the bars inside it say how the night reads.
    private static let ringBlue = Color(hex: "#7BA4C4")

    private var rest: Double? { model.value("sleep_performance") ?? series.latest?.value }

    /// How many days before today the night on show ended, so the trend card below ends on that morning.
    private var nightDaysAgo: Int {
        guard let n = model.night else { return router.todayDayOffset }
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: n.wakeDate), to: cal.startOfDay(for: Date())).day ?? 0)
    }

    var body: some View {
        // The night sits in the header, as the day does on the Charge page, with the info and settings buttons at the right.
        NunaDetailScreen(restCaption, trailing: AnyView(headerButtons), centersTitle: true) {
            hero
            if let night = model.night { components(night) }
            if let night = model.night {
                NunaSleepNightSections(model: model, night: night, showsNeed: false, showsBodyClock: false)
                insights(night)
                weeklyTrends
                NunaBodyClockLink()
            }
            NunaExpandRow(title: "How it's calculated", subtitle: "Four parts of the night",
                          text: "Sleep adds up how long you slept against what you need (half of the score), how much of your time in bed you were asleep, the share of deep and REM sleep, and how regular your bedtime is. It is an estimate computed on this phone from your strap's data.\n\nEach part has a range for Poor, Sufficient and Optimal.\n\nHours vs. needed: Optimal 85%+, Sufficient 70–85%, Poor under 70%.\nSleep consistency: Optimal 80%+, Sufficient 70–80%, Poor under 70%.\nSleep efficiency: Optimal 85%+, Sufficient 70–85%, Poor under 70%.")
        }
        .task(id: "\(repo.refreshSeq)-\(autoNaps)") {
            await series.load(repo: repo, key: "sleep_performance", source: "my-whoop")
            await model.load(repo: repo)
            factors = await NunaSleepFactorContext.load(repo: repo, restByWakeDay: series.byDay)
            if model.loaded, startIndex > 0, startIndex < model.nights.count, model.index == 0 { model.index = startIndex }
            // Opened from Today on another day: the night that ended that morning.
            else if model.loaded, startIndex == 0, router.todayDayOffset > 0, model.index == 0,
                    let i = model.nights.firstIndex(where: { $0.dayKey == NunaSelectedDay.key(offset: router.todayDayOffset) }) { model.index = i }
        }
        // Her line is about the latest night, so she reads it only while that night is on show.
        .nunaAnyaFloating(context: "sleep", line: (model.index == 0 && router.todayDayOffset == 0) ? anyaLine : nil,
                          analyses: model.index == 0 && router.todayDayOffset == 0)
        .environment(\.nunaDetailSwitch, nil)
    }

    private var headerButtons: some View {
        HStack(spacing: 0) {
            if againstRecent != nil { NunaInfoButton(isOn: $showInfo) }
            settingsButton
        }
    }

    private var settingsButton: some View {
        NavigationLink(value: NunaTodayRoute.sleepSettings) {
            Image(systemName: "gearshape").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(Text("Sleep settings"))
    }

    // MARK: Detail cards

    /// Hours against need, consistency over the last five nights, and efficiency with the wake events.
    @ViewBuilder private func insights(_ night: NunaNight) -> some View {
        let asleep = night.daily?.totalSleepMin ?? night.asleepMin
        let healthy = SleepModel.debtNeedMin(days: repo.days)
        // The debt as of this night, from the same recurrence the ledger uses.
        let debts = SleepDebt.debtSeries(series: model.nights.reversed().map { ($0.dayKey, $0.daily?.totalSleepMin ?? $0.asleepMin) },
                                         needHours: healthy / 60)
        let ledgerDebt = max(debts.first(where: { $0.day == night.dayKey })?.value ?? 0, 0)
        // A stored need already holds strain and debt, so the debt is what is left above the healthy minimum. Without one the need is only
        // the baseline, and the debt is added on top of it: capping it there would show no debt after a run of short nights.
        let stored = model.hasStoredNeed(night)
        let total = stored ? max(model.need(night), healthy) : healthy + ledgerDebt
        let debt = stored ? min(ledgerDebt, total - healthy) : ledgerDebt
        let strain = max(total - healthy - debt, 0)

        NunaHoursVsNeededCard(asleepMin: asleep, healthyMin: healthy, strainMin: strain, debtMin: debt,
                              percent: model.hoursVsNeeded(night), usual: model.usual { model.hoursVsNeeded($0) })
        NunaConsistencyCard(nights: consistencyNights(night), percent: model.consistency(night), usual: model.usual { model.consistency($0) })
        let total2 = max(night.wake.timeIntervalSince(night.onset), 1)
        let events = night.intervals.filter { $0.stage == .awake && $0.end - $0.start >= 60 }.map { (start: $0.start, end: $0.end) }
        NunaEfficiencyCard(asleepMin: night.asleepMin, awakeMin: night.stages.awake, events: events, totalSec: total2,
                           percent: model.efficiency(night), usual: model.usual { model.efficiency($0) })
    }

    /// Hours from the evening the night began: a bedtime after midnight is 24 and more, so a night is one unbroken stretch.
    private func hours(_ date: Date, evening: Bool) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        return evening ? (h < 12 ? h + 24 : h) : h + 24
    }

    private func consistencyNights(_ night: NunaNight) -> [NunaConsistencyCard.Night] {
        let recent = Array(model.nights.dropFirst(model.index).prefix(5).reversed())
        func weekday(_ d: Date) -> String {
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
            return f.string(from: d)
        }
        // The bed and wake time each night is measured against: the mean of the nights up to it, up to 14.
        func ideal(_ n: NunaNight) -> (bed: Double, wake: Double) {
            guard let i = model.nights.firstIndex(where: { $0.id == n.id }) else { return (hours(n.onset, evening: true), hours(n.wake, evening: false)) }
            let window = model.nights.dropFirst(i).prefix(14)
            let beds = window.map { hours($0.onset, evening: true) }, wakes = window.map { hours($0.wake, evening: false) }
            return (beds.reduce(0, +) / Double(max(beds.count, 1)), wakes.reduce(0, +) / Double(max(wakes.count, 1)))
        }
        return recent.map { n in
            let bed = hours(n.onset, evening: true)
            var wake = hours(n.wake, evening: false)
            if wake <= bed { wake += 24 }
            let ideal = ideal(n)
            return NunaConsistencyCard.Night(id: n.id, label: weekday(n.wakeDate), bed: bed, wake: wake,
                                             idealBed: ideal.bed, idealWake: max(ideal.wake, ideal.bed + 1), selected: n.id == night.id)
        }
    }

    // MARK: Ring

    /// Against the average of the 14 nights before, once there are at least three.
    private var againstRecent: Int? {
        guard let rest else { return nil }
        let before = model.nights.dropFirst(model.index + 1).prefix(14).compactMap { model.value("sleep_performance", $0) }
        guard before.count >= 3 else { return nil }
        return Int((rest - before.reduce(0, +) / Double(before.count)).rounded())
    }

    private func comparison(_ d: Int) -> String {
        d == 0 ? String(localized: "In line with your last 14 nights.")
            : (d > 0 ? String(localized: "\(d) points above your last 14 nights.") : String(localized: "\(-d) points below your last 14 nights."))
    }

    /// "Last night" for the latest night; otherwise the day that night ended on.
    private var restCaption: LocalizedStringKey {
        if model.index == 0, router.todayDayOffset == 0 { return "Last night" }
        if let n = model.night {
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEE d MMM")
            return LocalizedStringKey(f.string(from: n.wakeDate))
        }
        return "Earlier night"
    }

    private var hero: some View {
        NunaScoreHero(caption: "",
                      fraction: (rest ?? 0) / 100, number: rest.map { "\(Int($0.rounded()))" } ?? "–", unit: "%",
                      name: rest.map(nunaRestWord) ?? "Sleep", nameColor: Self.ringBlue,
                      color: Self.ringBlue, hasNote: againstRecent != nil,
                      showsCaptionRow: false, ringTitle: "Sleep", ringLevel: rest.map { NunaLevel.of($0, sufficientFrom: 70, optimalFrom: 85) },
                      ringSize: 252, info: $showInfo) {
            if let d = againstRecent {
                Text(verbatim: comparison(d)).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
    }

    /// Anya's line: what carried or held the night back and what to do about it tonight, not the figure the ring already shows.
    private var anyaLine: String? {
        if let night = model.night, let read = SleepRead.analyze(model.sleepFacts(night, debtMin: model.debtMin)) {
            return NunaInsightText.sleep(read, factors: factors, wakeDay: night.dayKey)
        }
        guard let rest, let d = againstRecent else { return nil }
        let note = d == 0 ? String(localized: "in line with your last 14 nights")
            : (d > 0 ? String(localized: "\(d) points above your last 14 nights") : String(localized: "\(-d) points below your last 14 nights"))
        return String(localized: "Your Sleep is \(Int(rest.rounded()))%, \(note).")
    }

    // MARK: Weekly trends

    /// A per-night figure for every stored night, by the day the night ended.
    private func points(_ f: (NunaNight) -> Double?) -> [(day: String, value: Double)] {
        model.nights.compactMap { n in f(n).map { (n.dayKey, $0) } }
    }

    private func byDay(_ f: (NunaNight) -> Double?) -> [String: Double] {
        Dictionary(points(f).map { ($0.day, $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    /// The sleep debt as of each night, from the recurrence the ledger uses.
    private var debtPoints: [(day: String, value: Double)] {
        let healthy = SleepModel.debtNeedMin(days: repo.days)
        return SleepDebt.debtSeries(series: model.nights.reversed().map { ($0.dayKey, $0.daily?.totalSleepMin ?? $0.asleepMin) }, needHours: healthy / 60)
            .map { (day: $0.day, value: max($0.value, 0)) }
    }

    /// The week as bare cards, in the order of the reference: the score, hours against need, the restorative stages, consistency, time in bed,
    /// efficiency and debt. A card opens the page that explains its figure.
    private static func percent(_ v: Double) -> String { "\(Int(v.rounded()))%" }

    private var bedTimes: [String: (bed: Double, wake: Double)] {
        Dictionary(model.nights.map { n -> (String, (bed: Double, wake: Double)) in
            let bed = hours(n.onset, evening: true)
            var wake = hours(n.wake, evening: false)
            if wake <= bed { wake += 24 }
            return (n.dayKey, (bed, wake))
        }, uniquingKeysWith: { a, _ in a })
    }

    private var stageMinutes: [String: [Double]] {
        Dictionary(model.nights.map { ($0.dayKey, [$0.stages.rem, $0.stages.deep]) }, uniquingKeysWith: { a, _ in a })
    }

    private var weeklyTrends: some View {
        let steel = NunaRestChart.steel
        let ending = nightDaysAgo
        let percent = Self.percent
        let beds = bedTimes
        let stages = stageMinutes
        return VStack(alignment: .leading, spacing: 12) {
            NunaWeeklyHeading()
            NunaWeeklyTrendCard(title: "Sleep performance", key: "sleep_performance", style: .bars, color: steel,
                                barFill: { _, _ in steel }, labelFill: { _, _ in steel },
                                destination: { AnyView(NunaTrendHost(initial: .restPerformance, endingDaysAgo: ending)) }, valueText: percent, endingDaysAgo: ending)
            NunaTwoLineWeeklyCard(title: "Hours vs. needed (hours)", slept: byDay { $0.daily?.totalSleepMin ?? $0.asleepMin },
                                  needed: byDay { model.need($0) }, endingDaysAgo: ending,
                                  destination: { AnyView(NunaTrendHost(initial: .hoursNeededHours, endingDaysAgo: ending)) })
            NunaWeeklyTrendCard(title: "Hours vs. needed (%)", key: "hours_vs_needed", style: .bars, color: steel,
                                barFill: { _, _ in steel }, labelFill: { _, _ in steel },
                                destination: { AnyView(NunaTrendHost(initial: .hoursNeededPct, endingDaysAgo: ending)) },
                                points: points { model.hoursVsNeeded($0) }, valueText: percent, endingDaysAgo: ending)
            NunaStackedWeeklyCard(title: "Restorative sleep (hours)", legend: [("Deep sleep", NunaRestChart.deep), ("REM sleep", NunaRestChart.rem)],
                                  colors: [NunaRestChart.rem, NunaRestChart.deep], byDay: stages, endingDaysAgo: ending,
                                  destination: { AnyView(NunaTrendHost(initial: .restorative, endingDaysAgo: ending)) })
            NunaWeeklyTrendCard(title: "Sleep consistency", key: "sleep_consistency", style: .bars, color: steel,
                                barFill: { _, _ in steel }, labelFill: { _, _ in steel },
                                destination: { AnyView(NunaTrendHost(initial: .consistency, endingDaysAgo: ending)) },
                                points: points { model.consistency($0) }, valueText: percent, endingDaysAgo: ending)
            NunaTimeInBedWeeklyCard(title: "Time in bed", nights: beds, endingDaysAgo: ending,
                                    destination: { AnyView(NunaTrendHost(initial: .timeInBed, endingDaysAgo: ending)) })
            NunaWeeklyTrendCard(title: "Sleep efficiency", key: "sleep_efficiency", style: .line, color: steel,
                                destination: { AnyView(NunaTrendHost(initial: .efficiency, endingDaysAgo: ending)) },
                                points: points { model.efficiency($0) }, valueText: percent, endingDaysAgo: ending)
            NunaWeeklyTrendCard(title: "Sleep debt", key: "sleep_debt", style: .bars, color: steel,
                                barFill: { _, _ in steel }, labelFill: { _, _ in steel },
                                destination: { AnyView(NunaTrendHost(initial: .debt, endingDaysAgo: ending)) },
                                points: debtPoints, valueText: NunaRestChart.hm, autoScale: true, endingDaysAgo: ending)
        }
    }

    // MARK: What it is made of

    private func components(_ night: NunaNight) -> some View {
        // The four parts of the night, each with how it reads (poor, sufficient or optimal) and its figure, on the card under the ring.
        func row(_ title: LocalizedStringKey, _ icon: String, _ v: Double?, sufficientFrom: Double, optimalFrom: Double, page: NunaTrendPage) -> some View {
            NavigationLink { NunaTrendHost(initial: page, endingDaysAgo: nightDaysAgo) } label: {
                NunaLevelRow(title: title, icon: icon, percent: v, level: v.map { NunaLevel.of($0, sufficientFrom: sufficientFrom, optimalFrom: optimalFrom) })
            }.buttonStyle(.plain)
        }
        return NunaSignalPanel {
            VStack(spacing: 0) {
                row("Hours vs. needed", "met:hours-vs-needed", model.hoursVsNeeded(night), sufficientFrom: 70, optimalFrom: 85, page: .hoursNeededPct)
                NunaDivider()
                row("Sleep consistency", "met:sleep-consistency", model.consistency(night), sufficientFrom: 70, optimalFrom: 80, page: .consistency)
                NunaDivider()
                row("Sleep efficiency", "met:sleep-efficiency", model.efficiency(night), sufficientFrom: 70, optimalFrom: 85, page: .efficiency)
                NunaDivider()
                row("Restorative sleep", "met:restorative-sleep", model.restorative(night), sufficientFrom: 50, optimalFrom: 75, page: .restorative)
            }
            NunaLevelLegend().padding(.top, 8)
        }
    }
}
#endif
