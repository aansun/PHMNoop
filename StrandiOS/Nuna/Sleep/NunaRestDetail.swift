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
    var title: LocalizedStringKey = "Rest"
    @EnvironmentObject private var repo: Repository
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @StateObject private var series = NunaSeriesModel()
    @StateObject private var model = NunaSleepModel()
    @State private var range = 7
    @State private var page = 0
    @State private var showCoach = false
    @AppStorage(NunaNapPrefs.autoDetectKey) private var autoNaps = true

    private var rest: Double? { model.value("sleep_performance") ?? series.latest?.value }

    var body: some View {
        NunaDetailScreen(title, trailing: AnyView(settingsButton)) {
            if model.loaded, model.nights.count > 1 { NunaNightPicker(model: model) }
            hero
            if let night = model.night { components(night) }
            if coachEnabled, let line = anyaLine { NunaAnyaCard(verbatim: line) { showCoach = true } }
            NunaTrendDetailCard(
                caption: "Average", unit: "%",
                readings: { days, back in series.readings(days, endingDaysAgo: back) },
                hasOlder: { start in series.byDay.keys.min().map { Repository.localDayKey(start) > $0 } ?? false },
                loaded: series.loaded, band: series.band.map { $0.lo...$0.hi },
                lineColor: NunaPalette.rest, decimals: 0, directional: true,
                levelChip: { v in (text: nunaRestWord(v), color: nunaRestTextColor(v)) },
                sentence: nil, range: $range, page: $page)
                .columns(color: nunaRestColor, top: 100, legend: AnyView(restKey))
            if let night = model.night {
                NunaSleepNightSections(model: model, night: night, showsNeed: false)
                // After the Body clock card, which closes the night sections.
                insights(night)
            }
            NunaExpandRow(title: "How it's calculated", subtitle: "Four parts of the night",
                          text: "Rest adds up how long you slept against what you need (half of the score), how much of your time in bed you were asleep, the share of deep and REM sleep, and how regular your bedtime is. It is an estimate computed on this phone from your strap's data.")
        }
        .task(id: "\(repo.refreshSeq)-\(autoNaps)") {
            await series.load(repo: repo, key: "sleep_performance", source: "my-whoop")
            await model.load(repo: repo)
            if model.loaded, startIndex > 0, startIndex < model.nights.count, model.index == 0 { model.index = startIndex }
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "sleep") }
    }

    private var settingsButton: some View {
        NavigationLink(value: NunaTodayRoute.sleepSettings) {
            Image(systemName: "slider.horizontal.3").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(Text("Sleep settings"))
    }

    // MARK: Detail cards

    /// Hours against need, consistency over the last five nights, and efficiency with the wake events.
    @ViewBuilder private func insights(_ night: NunaNight) -> some View {
        let asleep = night.daily?.totalSleepMin ?? night.asleepMin
        let healthy = SleepModel.debtNeedMin(days: repo.days)
        let total = max(model.need(night), healthy)
        // The debt as of this night, from the same recurrence the ledger uses, kept inside what is left above the healthy minimum.
        let debts = SleepDebt.debtSeries(series: model.nights.reversed().map { ($0.dayKey, $0.daily?.totalSleepMin ?? $0.asleepMin) },
                                         needHours: healthy / 60)
        let debt = min(max(debts.first(where: { $0.day == night.dayKey })?.value ?? 0, 0), total - healthy)
        let strain = max(total - healthy - debt, 0)

        let facts = model.sleepFacts(night, debtMin: debt)
        NunaHoursVsNeededCard(asleepMin: asleep, healthyMin: healthy, strainMin: strain, debtMin: debt,
                              percent: model.hoursVsNeeded(night), usual: model.usual { model.hoursVsNeeded($0) },
                              note: NunaInsightText.hoursNote(asleepMin: asleep, needMin: total, debtMin: debt))
        NunaConsistencyCard(nights: consistencyNights(night), percent: model.consistency(night), usual: model.usual { model.consistency($0) },
                            note: NunaInsightText.consistencyNote(shiftMin: facts.bedShiftMin))
        let total2 = max(night.wake.timeIntervalSince(night.onset), 1)
        let events = night.intervals.filter { $0.stage == .awake && $0.end - $0.start >= 60 }.map { (start: $0.start, end: $0.end) }
        NunaEfficiencyCard(asleepMin: night.asleepMin, awakeMin: night.stages.awake, events: events, totalSec: total2,
                           percent: model.efficiency(night), usual: model.usual { model.efficiency($0) },
                           note: NunaInsightText.efficiencyNote(events: events, totalSec: total2))
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

    private var hero: some View {
        NunaScoreHero(caption: model.index == 0 ? "Last night" : "Earlier night",
                      fraction: (rest ?? 0) / 100, number: rest.map { "\(Int($0.rounded()))" } ?? "–", unit: "%",
                      name: rest.map(nunaRestWord) ?? "Rest", nameColor: rest.map(nunaRestTextColor),
                      color: rest.map(nunaRestColor) ?? NunaPalette.rest, hasNote: againstRecent != nil) {
            if let d = againstRecent {
                Text(verbatim: comparison(d)).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
    }

    /// Anya's line: what carried or held the night back and what to do about it tonight, not the figure the ring already shows.
    private var anyaLine: String? {
        if let night = model.night, let read = SleepRead.analyze(model.sleepFacts(night, debtMin: model.debtMin)) {
            return NunaInsightText.sleep(read)
        }
        guard let rest, let d = againstRecent else { return nil }
        let note = d == 0 ? String(localized: "in line with your last 14 nights")
            : (d > 0 ? String(localized: "\(d) points above your last 14 nights") : String(localized: "\(-d) points below your last 14 nights"))
        return String(localized: "Your Rest is \(Int(rest.rounded()))%, \(note).")
    }

    private var restKey: some View {
        NunaZoneKey(zones: [
            (nunaRestColor(100), "85–100", "Excellent"), (nunaRestColor(75), "70–84", "Good"),
            (nunaRestColor(60), "50–69", "Fair"), (nunaRestColor(10), "0–49", "Low"),
        ])
    }

    // MARK: What it is made of

    private func components(_ night: NunaNight) -> some View {
        let previous: NunaNight? = model.nights.indices.contains(model.index + 1) ? model.nights[model.index + 1] : nil
        func delta(_ f: (NunaNight) -> Double?) -> Double? {
            guard let a = f(night), let p = previous, let b = f(p) else { return nil }
            return a - b
        }
        func whole(_ v: Double?) -> String? { v.map { String(format: "%.0f", locale: AppLanguage.activeLocale, $0) } }
        return NunaPlainList {
            row("Performance", "bed.double", whole(model.hoursVsNeeded(night)), delta { model.hoursVsNeeded($0) })
            NunaDivider()
            row("Efficiency", "gauge.with.dots.needle.67percent", whole(model.efficiency(night)), delta { model.efficiency($0) })
            NunaDivider()
            row("Restorative", "moon.zzz", whole(model.restorative(night)), delta { model.restorative($0) })
            NunaDivider()
            row("Consistency", "calendar", whole(model.consistency(night)), delta { model.consistency($0) })
        }
    }

    private func row(_ title: LocalizedStringKey, _ icon: String, _ value: String?, _ delta: Double?) -> some View {
        NavigationLink(value: NunaTodayRoute.sleepPerformance(model.index)) {
            NunaContributorRow(title: title, icon: icon, value: value, delta: delta, downIsGood: false)
        }.buttonStyle(.plain)
    }
}
#endif
