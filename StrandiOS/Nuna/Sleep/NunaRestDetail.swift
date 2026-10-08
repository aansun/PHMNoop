#if os(iOS)
import SwiftUI
import StrandDesign

/// The screen behind the Rest ring, built like the Charge one: the ring, the four things Rest is made of, Anya's line, the trend of Rest and,
/// under it, a card that opens last night's sleep.
struct NunaRestDetailView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @StateObject private var series = NunaSeriesModel()
    @StateObject private var model = NunaSleepModel()
    @State private var range = 7
    @State private var page = 0
    @State private var showCoach = false

    private var rest: Double? { model.value("sleep_performance") ?? series.latest?.value }

    var body: some View {
        NunaDetailScreen("Rest") {
            hero
            if let night = model.night { components(night) }
            if coachEnabled, let line = anyaLine { NunaAnyaCard(verbatim: line) { showCoach = true } }
            NunaTrendDetailCard(
                caption: "Average", unit: "%",
                readings: { days, back in series.readings(days, endingDaysAgo: back) },
                hasOlder: { start in series.byDay.keys.min().map { Repository.localDayKey(start) > $0 } ?? false },
                loaded: series.loaded, band: series.band.map { $0.lo...$0.hi },
                lineColor: NunaPalette.rest, decimals: 0, directional: true,
                levelChip: { v in (text: Self.word(v).0, color: Self.word(v).1) },
                sentence: nil, range: $range, page: $page)
                .columns(top: 100)
            if let night = model.night { lastNight(night) }
            NunaExpandRow(title: "How it's calculated", subtitle: "Four parts of the night",
                          text: "Rest adds up how long you slept against what you need (half of the score), how much of your time in bed you were asleep, the share of deep and REM sleep, and how regular your bedtime is. It is an estimate computed on this phone from your strap's data.")
        }
        .task(id: repo.refreshSeq) {
            await series.load(repo: repo, key: "sleep_performance", source: "my-whoop")
            await model.load(repo: repo)
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "sleep") }
    }

    // MARK: Ring

    /// A word for the night's Rest and its colour.
    private static func word(_ v: Double) -> (LocalizedStringKey, Color) {
        switch v {
        case 85...: return ("Excellent", NunaPalette.charge)
        case 70..<85: return ("Good", NunaPalette.charge)
        case 50..<70: return ("Fair", NunaPalette.warning)
        default: return ("Low", NunaPalette.alertText)
        }
    }

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
        NunaScoreHero(caption: "Last night",
                      fraction: (rest ?? 0) / 100, number: rest.map { "\(Int($0.rounded()))" } ?? "–", unit: "%",
                      name: rest.map { Self.word($0).0 } ?? "Rest", nameColor: rest.map { Self.word($0).1 },
                      color: NunaPalette.rest, hasNote: againstRecent != nil) {
            if let d = againstRecent {
                Text(verbatim: comparison(d)).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
    }

    /// Anya's one line: the Rest figure against the recent nights.
    private var anyaLine: String? {
        guard let rest, let d = againstRecent else { return nil }
        let note = d == 0 ? String(localized: "in line with your last 14 nights")
            : (d > 0 ? String(localized: "\(d) points above your last 14 nights") : String(localized: "\(-d) points below your last 14 nights"))
        return String(localized: "Your Rest is \(Int(rest.rounded()))%, \(note).")
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
            NunaContributorRow(title: title, icon: icon, value: value, unit: "%", delta: delta, downIsGood: false)
        }.buttonStyle(.plain)
    }

    // MARK: Last night

    private func lastNight(_ night: NunaNight) -> some View {
        NavigationLink(value: NunaTodayRoute.sleep(0)) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Last night's sleep").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: NunaSleepFormat.duration(night.asleepMin))
                            .font(.nuna(size: NunaTypeSize.numberL, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(NunaTypeSize.numberL))
                            .foregroundStyle(NunaPalette.textPrimary)
                        Text("asleep").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Text(verbatim: "\(NunaSleepFormat.clock(night.onset)) – \(NunaSleepFormat.clock(night.wake))")
                        .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    if night.intervals.isEmpty { NunaStageSplitBar(stages: night.stages) } else { NunaHypnogramStrip(intervals: night.intervals, height: 90) }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
