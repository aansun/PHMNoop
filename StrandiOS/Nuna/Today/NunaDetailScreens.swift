#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore
import Charts

private func rangeOptions() -> [(value: Int, title: LocalizedStringKey)] {
    [(value: 7, title: "W\u{2060}"), (value: 30, title: "M"), (value: 180, title: "6M")]
}

private func signedWhole(_ d: Double) -> String { (d >= 0 ? "+" : "−") + String(format: "%.0f", abs(d)) }

// MARK: - Charge

/// Today's Charge: the score, 7/30/90 day bars in the three Charge zones, and the three drivers.
struct NunaChargeDetailView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @StateObject private var series = NunaSeriesModel()
    @StateObject private var day = NunaTodayModel()
    /// Last night's Rest and skin-temperature deviation: two of the signals Charge is made of.
    @StateObject private var restSeries = NunaSeriesModel()
    @StateObject private var skinSeries = NunaSeriesModel()
    @State private var range = 7
    @State private var page = 0
    @State private var showCoach = false

    var body: some View {
        let latest = series.latest
        NunaDetailScreen("Charge") {
            NunaScoreHero(caption: "Today",
                          fraction: (day.charge.pct ?? latest?.value ?? 0) / 100,
                          number: (day.charge.pct ?? latest?.value).map { String(format: "%.0f", $0) } ?? "–",
                          unit: "%", name: chargeWord ?? "Charge", nameColor: (day.charge.pct ?? latest?.value).map(nunaChargeTextColor), color: (day.charge.pct ?? latest?.value).map(nunaChargeColor) ?? NunaPalette.charge,
                          hasNote: (day.charge.pct ?? latest?.value) != nil && series.baseline != nil) {
                if let v = day.charge.pct ?? latest?.value, let base = series.baseline {
                    let d = Int((v - base).rounded())
                    let readiness = chip.map { $0.0 + ". " } ?? ""
                    Text(verbatim: readiness + (d == 0 ? String(localized: "In line with your 30-day average")
                         : (d > 0 ? String(localized: "\(d) points above your 30-day average") : String(localized: "\(-d) points below your 30-day average"))))
                        .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
            NunaPlainList {
                contributor("Heart rate variability", "waveform.path.ecg", day.hrv.map { String(format: "%.0f", $0) }, "", day.hrvDelta, false, key: "hrv")
                NunaDivider()
                contributor("Resting heart rate", "heart", day.restingHr.map { String(format: "%.0f", $0) }, "", day.restingHrDelta, true, key: "rhr")
                NunaDivider()
                contributor("Respiratory rate", "lungs", day.respiratory.map { String(format: "%.1f", locale: AppLanguage.activeLocale, $0) }, "", day.respiratoryDelta, nil, decimals: 1, key: "resp_rate")
                NunaDivider()
                NavigationLink(value: NunaTodayRoute.metric(restMetric)) {
                    NunaContributorRow(title: "Sleep performance", icon: "moon",
                                       value: (day.rest ?? restSeries.latest?.value).map { String(format: "%.0f", $0) },
                                       delta: lastChange(restSeries), downIsGood: false)
                }.buttonStyle(.plain)
                NunaDivider()
                contributor("Skin temperature", "thermometer", skinSeries.latest.map { nunaSigned($0.value) }, "", lastChange(skinSeries), nil, decimals: 1, key: "skin_temp")
            }
            if coachEnabled, let line = anyaLine { NunaAnyaCard(verbatim: line) { showCoach = true } }
            NunaTrendDetailCard(
                caption: "Average", unit: "%",
                readings: { days, back in series.readings(days, endingDaysAgo: back) },
                hasOlder: { start in series.byDay.keys.min().map { Repository.localDayKey(start) > $0 } ?? false },
                loaded: series.loaded, band: series.typicalRange,
                lineColor: NunaPalette.charge, decimals: 0, directional: true,
                levelChip: { v in (text: v >= 67 ? "Ready" : (v >= 34 ? "Moderate" : "Low"), color: nunaChargeTextColor(v)) },
                sentence: nil, range: $range, page: $page)
                .columns(color: nunaChargeColor, top: 100, legend: AnyView(zoneKey))
            NunaExpandRow(title: "How it's calculated", subtitle: "Three signals, against your own baseline",
                          text: "Charge compares last night's heart rate variability, resting heart rate and sleep with your own baseline from the last 30 days. It is an estimate computed on this phone from your strap's data.")
        }
        .task(id: repo.refreshSeq) {
            await series.load(repo: repo, key: "recovery", source: "my-whoop")
            await restSeries.load(repo: repo, key: "sleep_performance", source: "my-whoop")
            await skinSeries.load(repo: repo, key: "skin_temp", source: "my-whoop")
            await day.load(repo: repo, profile: profile)
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "Charge") }
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d)
    }

    /// Anya's line about today's Charge: what lifts it, what holds it back and what that means for the day, not the figure the ring shows.
    private var anyaLine: String? {
        guard let v = day.charge.pct ?? series.latest?.value else { return nil }
        let rows = repo.days.suffix(31).dropLast()
        let efforts = rows.compactMap(\.strain).filter { $0 > 0 }.sorted()
        let usual = efforts.isEmpty ? nil : efforts[efforts.count / 2]
        let hrvBase = day.hrv.flatMap { h in day.hrvDelta.map { h - $0 } }
        let hrvPct = day.hrvDelta.flatMap { d in hrvBase.map { $0 > 0 ? d / $0 * 100 : 0 } }
        let prior = repo.days.dropLast().last?.strain
        let read = ChargeRead.analyze(hrvDeltaPct: hrvPct, rhrDeltaBpm: day.restingHrDelta, sleepPct: day.rest ?? restSeries.latest?.value,
                                      priorEffort: prior, usualEffort: usual, respDeltaBpm: day.respiratoryDelta,
                                      skinTempDevC: skinSeries.latest?.value)
        return NunaInsightText.charge(read, chargePct: v)
    }

    /// What the colours of the bars mean: the three Charge zones.
    private var zoneKey: some View {
        HStack(spacing: 16) {
            key(NunaPalette.scoreHigh, "67–100", "Ready")
            key(NunaPalette.scoreMid, "34–66", "Moderate")
            key(NunaPalette.scoreLow, "0–33", "Low")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func key(_ color: Color, _ range: String, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 10, height: 10)
            (Text(verbatim: range + " ") + Text(label)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
    }

    /// How the latest reading moved from the one before it (the night before), nil when there is only one.
    private func lastChange(_ m: NunaSeriesModel) -> Double? {
        let r = m.readings(30)
        guard r.count >= 2 else { return nil }
        return r[r.count - 1].value - r[r.count - 2].value
    }

    private var restMetric: MetricDescriptor {
        MetricCatalog.metric(key: "sleep_performance", source: "my-whoop") ?? MetricCatalog.metric(key: "recovery", source: "my-whoop")!
    }

    /// The word for today's Charge, which sits in the ring in place of the name.
    private var chargeWord: LocalizedStringKey? {
        (day.charge.pct ?? series.latest?.value).map { $0 >= 67 ? "Ready" : ($0 >= 34 ? "Moderate" : "Low") }
    }

    private var chip: (String, Bool)? {
        guard let level = day.readiness?.level else { return nil }
        switch level {
        case .primed: return (String(localized: "Ready for a hard session"), true)
        case .balanced: return (String(localized: "Ready for a moderate load"), true)
        case .strained, .rundown: return (String(localized: "Take it easy today"), false)
        case .insufficient: return nil
        }
    }

    @ViewBuilder private func contributor(_ title: LocalizedStringKey, _ icon: String, _ value: String?, _ unit: String,
                                          _ delta: Double?, _ downIsGood: Bool?, decimals: Int = 0, key: String) -> some View {
        let row = NunaContributorRow(title: title, icon: icon, value: value, unit: unit, delta: delta, downIsGood: downIsGood, decimals: decimals)
        if let m = MetricCatalog.metric(key: key, source: "my-whoop") {
            NavigationLink(value: NunaTodayRoute.metric(m)) { row }.buttonStyle(.plain)
        } else { row }
    }
}

// MARK: - Effort

struct NunaEffortDetailView: View {
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @StateObject private var series = NunaSeriesModel()
    @StateObject private var day = NunaTodayModel()
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @State private var range = 7
    @State private var page = 0
    @State private var showCoach = false
    /// Today's heart-rate readings, and yesterday's up to the same time of day, for the time in each zone and its change.
    @State private var hrToday: [HRSample] = []
    @State private var hrYesterday: [HRSample] = []
    @State private var strengthToday: Double?
    @State private var strengthYesterday: Double?
    @State private var todayWorkouts: [WorkoutRow] = []

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        NunaDetailScreen("Effort") {
            NunaScoreHero(caption: "Today",
                          fraction: (day.effort ?? 0) / 100,
                          number: day.effort.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–",
                          suffix: String(localized: "of \(UnitFormatter.effortScaleMax(scale))"),
                          name: level?.0 ?? "Effort", nameColor: level?.1, gradient: day.effort.map(nunaEffortRingColors), target: nunaEffortTargetFractions(charge: day.charge.pct),
                          color: day.effort.map(nunaEffortColor) ?? NunaPalette.effortModerate) {
                Text(verbatim: targetNote ?? String(localized: "Cardio load so far today")).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            zonesCard
            if coachEnabled, let e = day.effort {
                NunaAnyaCard(verbatim: NunaInsightText.effort(effort: e, chargePct: day.charge.pct)
                             ?? String(localized: "Your Effort is \(UnitFormatter.effortDisplay(e, scale: scale)) of \(UnitFormatter.effortScaleMax(scale)) so far today.")) { showCoach = true }
            }
            NunaTrendDetailCard(
                caption: "Average", unit: "",
                readings: { days, back in series.readings(days, endingDaysAgo: back).map { ($0.date, UnitFormatter.effortValue($0.value, scale: scale)) } },
                hasOlder: { start in series.byDay.keys.min().map { Repository.localDayKey(start) > $0 } ?? false },
                loaded: series.loaded,
                lineColor: NunaPalette.effortModerate, decimals: 1, directional: false,
                levelChip: { v in
                    let stored = scale == .whoop ? v / 21 * 100 : v
                    return (text: stored < 33 ? "Light" : (stored < 66 ? "Moderate" : "High"), color: nunaEffortTextColor(stored))
                }, sentence: nil, range: $range, page: $page)
                .columns(color: { v in nunaEffortColor(scale == .whoop ? v / 21 * 100 : v) }, legend: AnyView(effortKey))
            NunaTodayActivities(workouts: todayWorkouts, effortScale: scale,
                                dayStart: Calendar.current.startOfDay(for: Date()), sleepMinutes: nil,
                                includesSleep: false)
            NunaExpandRow(title: "How it's calculated", subtitle: "Cardio load across the day",
                          text: "Effort adds up how hard your heart worked during the day, weighted by heart rate zone. Workouts and everyday movement both count. It is shown on the scale you chose in Settings.")
        }
        .task(id: repo.refreshSeq) {
            await series.load(repo: repo, key: "strain", source: "my-whoop")
            await day.load(repo: repo, profile: profile)
            await loadZones()
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "Effort") }
    }

    /// What today's heart-rate load is made of, as plain rows: time in the easy and the hard zones, strength training and the average heart
    /// rate, each with the change against yesterday at the same time of day.
    private func loadZones() async {
        let cal = Calendar.current
        let now = Date()
        let start = Int(cal.startOfDay(for: now).timeIntervalSince1970)
        let nowTs = Int(now.timeIntervalSince1970)
        let yStart = Int((cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)) ?? now).timeIntervalSince1970)
        hrToday = await repo.hrSamples(from: start, to: nowTs, limit: 200_000)
        hrYesterday = await repo.hrSamples(from: yStart, to: yStart + (nowTs - start), limit: 200_000)
        let rows = await repo.workoutRows()
        todayWorkouts = rows.filter { $0.startTs >= start && $0.startTs <= nowTs }
        func strength(_ from: Int, _ to: Int) -> Double? {
            let hit = rows.filter { $0.startTs >= from && $0.startTs < to && NunaWorkoutKind.isStrength($0) }
            return hit.isEmpty ? nil : hit.reduce(0) { $0 + ($1.durationS ?? Double($1.endTs - $1.startTs)) } / 60
        }
        strengthToday = strength(start, nowTs)
        strengthYesterday = strength(yStart, start)
    }

    private struct ZoneFigures {
        let easy: Double, hard: Double, avg: Double?, total: Double
    }

    private func figures(_ hr: [HRSample]) -> ZoneFigures {
        let t = HRZones.timeInZone(hr, zoneSet: profile.hrZoneSet)
        return ZoneFigures(easy: (t.seconds[0] + t.seconds[1] + t.seconds[2]) / 60, hard: (t.seconds[3] + t.seconds[4]) / 60,
                           avg: hr.isEmpty ? nil : Double(hr.reduce(0) { $0 + $1.bpm }) / Double(hr.count), total: t.total)
    }

    @ViewBuilder private var zonesCard: some View {
        let now = figures(hrToday)
        let before = figures(hrYesterday)
        let hasBefore = before.total > 0
        VStack(alignment: .leading, spacing: 4) {
            NunaPlainList {
                NavigationLink { NunaEffortActivityDetailView(kind: .lowZones) } label: {
                    zoneRow("Heart rate zones 1–3", "heart.circle", now.total > 0 ? Self.hm(now.easy) : nil, hasBefore ? now.easy - before.easy : nil, downIsGood: false)
                }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink { NunaEffortActivityDetailView(kind: .highZones) } label: {
                    zoneRow("Heart rate zones 4–5", "bolt.heart", now.total > 0 ? Self.hm(now.hard) : nil, hasBefore ? now.hard - before.hard : nil, downIsGood: false)
                }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink { NunaEffortActivityDetailView(kind: .strength) } label: {
                    zoneRow("Strength training time", "dumbbell", strengthToday.map(Self.hm), strengthYesterday.flatMap { current in strengthToday.map { $0 - current } }, downIsGood: false)
                }.buttonStyle(.plain)
                NunaDivider()
                zoneRow("Average heart rate", "heart", now.avg.map { String(format: "%.0f", $0) },
                        (now.avg != nil && before.avg != nil) ? now.avg! - before.avg! : nil, downIsGood: nil)
            }
        }
    }

    private func zoneRow(_ title: LocalizedStringKey, _ icon: String, _ value: String?, _ delta: Double?, downIsGood: Bool?) -> some View {
        NunaContributorRow(title: title, icon: icon, value: value, delta: delta, downIsGood: downIsGood)
    }

    /// Minutes as h:mm.
    private static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// What the colours of the bars mean, on the scale the wearer chose.
    private var effortKey: some View {
        func edge(_ stored: Double) -> Int { Int(UnitFormatter.effortValue(stored, scale: scale).rounded()) }
        let top = UnitFormatter.effortScaleMax(scale)
        return NunaZoneKey(zones: [
            (NunaPalette.effortMinimal, "0–\(edge(33))", "Light"),
            (NunaPalette.effortModerate, "\(edge(33) + 1)–\(edge(66))", "Moderate"),
            (NunaPalette.effortAllOut, "\(edge(66) + 1)–\(top)", "High"),
        ])
    }

    /// "Today's target 67–86, from your Charge": the grey stretch of the ring, in the scale the wearer chose.
    private var targetNote: String? {
        guard let band = CoupledView.optimalStrainRange(recovery: day.charge.pct) else { return nil }
        func shown(_ whoop: Int) -> Int { Int(UnitFormatter.effortValue(Double(whoop) / 21.0 * 100, scale: scale).rounded()) }
        return String(localized: "Today's target \(shown(band.lowerBound))–\(shown(band.upperBound)), from your Charge")
    }

    private var level: (LocalizedStringKey, Color)? {
        day.effort.map { $0 < 33 ? ("Light", nunaEffortTextColor($0)) : ($0 < 66 ? ("Moderate", nunaEffortTextColor($0)) : ("High", nunaEffortTextColor($0))) }
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d)
    }
}

// MARK: - Effort activity detail

/// The three activity contributors behind Effort.  The same detail surface keeps the time in HR zones
/// and time spent strength training legible without pretending that one is the other.
struct NunaEffortActivityDetailView: View {
    enum Kind: Hashable, CaseIterable {
        case lowZones, highZones, strength

        var title: String {
            switch self {
            case .lowZones: return String(localized: "Heart rate zones 1–3")
            case .highZones: return String(localized: "Heart rate zones 4–5")
            case .strength: return String(localized: "Strength activity time")
            }
        }

        /// Indexes into the five canonical HR zones (Zone 1 is index 0).
        var zoneIndexes: [Int] {
            switch self {
            case .lowZones: return [0, 1, 2]
            case .highZones: return [3, 4]
            case .strength: return []
            }
        }

        var switchKey: String {
            switch self {
            case .lowZones: return "low"
            case .highZones: return "high"
            case .strength: return "strength"
            }
        }

        var icon: String {
            switch self {
            case .lowZones: return "heart.circle"
            case .highZones: return "bolt.heart"
            case .strength: return "dumbbell"
            }
        }

        var color: Color {
            switch self {
            case .lowZones: return NunaPalette.rest
            case .highZones: return NunaPalette.alert
            case .strength: return NunaPalette.effort
            }
        }
    }

    private struct Bucket: Identifiable {
        let start: Date
        let end: Date
        let value: Double
        let zones: [Double]
        var id: Date { start }
    }

    private struct StrengthEntry: Identifiable {
        let id: String
        let title: String
        let minutes: Double
    }

    @State private var kind: Kind
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var range = 7
    @State private var buckets: [Bucket] = []
    @State private var totalZones = [Double](repeating: 0, count: 5)
    @State private var loaded = false
    @State private var rows: [WorkoutRow] = []
    /// How many whole periods the window sits behind today (0 = the current period).
    @State private var pageOffset = 0
    @State private var previousValue: Double = 0

    init(kind: Kind) { _kind = State(initialValue: kind) }

    private var currentValue: Double { buckets.map(\.value).reduce(0, +) }
    /// Month and six-month headers are comparable weekly averages; the one-week header remains the actual weekly total.
    private var headlineValue: Double { range == 7 ? currentValue : currentValue / max(Double(range) / 7, 1) }
    private var averageValue: Double { buckets.isEmpty ? 0 : currentValue / Double(buckets.count) }
    private var rangeName: String { range == 7 ? String(localized: "Weekly total") : String(localized: "Average weekly total") }
        private var unitCopy: String { String(localized: "hr") }
    private static let maxPages = 52
    private var strengthEntries: [StrengthEntry] {
        return rows.filter(NunaWorkoutKind.isStrength).map {
            StrengthEntry(id: "\($0.startTs)-\($0.sport)", title: WorkoutSource.displaySport($0.sport), minutes: duration($0))
        }
    }

    var body: some View {
        NunaDetailScreen("Effort") {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(rangeName).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(verbatim: Self.hm(headlineValue)).font(.nuna(size: 44, weight: .bold, design: NunaType.design))
                                    .tracking(nunaTrackingNumber(44)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                                Text(verbatim: unitCopy).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 12) {
                            NunaRangeSwitch(range: $range)
                            NunaDateStepper(label: dateRange, canGoBack: pageOffset < Self.maxPages, canGoForward: pageOffset > 0,
                                            back: { pageOffset += 1 }, forward: { pageOffset = max(0, pageOffset - 1) })
                        }
                    }
                    if let change = comparison {
                        HStack(spacing: 0) {
                            NunaChip(verbatim: change.text, color: change.color)
                            Spacer(minLength: 0)
                        }
                    }
                    Text(verbatim: summary).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    if buckets.isEmpty {
                        Text(loaded ? "No activity data in this period" : " ").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 180, alignment: .leading).textCase(nil)
                    } else {
                        chart
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle").font(.nuna(size: 13, weight: .semibold))
                        Text(kind == .strength ? "Strength activity time is derived from logged strength activities." : "Zone time is derived from heart-rate samples recorded on this device.")
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
            }

            breakdown
        }
        // The header's dropdown names the screen and moves between the three readings, like the other detail screens.
        .environment(\.nunaDetailSwitch, NunaDetailSwitch(
            current: kind.switchKey,
            items: Kind.allCases.map { .init(key: $0.switchKey, title: $0.title, icon: $0.icon) }) { key in
                if let next = Kind.allCases.first(where: { $0.switchKey == key }) { kind = next; pageOffset = 0 }
            })
        .task(id: "\(repo.refreshSeq)-\(range)-\(pageOffset)-\(kind.icon)") { await load() }
        .onChange(of: range) { pageOffset = 0 }
    }

    /// Change against the window immediately before the visible one; omitted until that window carries readings.
    private var comparison: (text: String, color: Color)? {
        guard previousValue > 0, currentValue > 0 else { return nil }
        let change = ((currentValue - previousValue) / previousValue) * 100
        let arrow = change >= 0 ? "↑" : "↓"
        return ("\(arrow) \(Int(abs(change).rounded()))% " + String(localized: "vs. prior period"), change >= 0 ? kind.color : NunaPalette.warning)
    }

    @ViewBuilder private var chart: some View {
        let top = max((buckets.map(\.value).max() ?? 0) * 1.15, averageValue * 1.15, 15)
        if range == 7 {
            weekChart(top: top)
        } else if range == 180 {
            monthlyChart
        } else {
            dailyChart(top: top)
        }
    }

    // MARK: Six months: weekly bars grouped by month, each month with its average and the move against the month before

    private struct WeekStretch: Identifiable {
        let start: Date
        let zones: [Double]
        let total: Double
        var id: Date { start }
    }

    private struct MonthStretch: Identifiable {
        let first: Date
        let end: Date
        let average: Double
        let delta: Double?
        var id: Date { first }
        var center: Date { Date(timeIntervalSince1970: (first.timeIntervalSince1970 + end.timeIntervalSince1970) / 2) }
    }

    /// Whole weeks counted back from the latest day, oldest first; a stub of fewer than seven days is left out.
    private var weeks: [WeekStretch] {
        var out: [WeekStretch] = []
        var end = buckets.count
        while end >= 7 {
            let slice = buckets[(end - 7)..<end]
            var zones = [Double](repeating: 0, count: 5)
            for bucket in slice { for index in 0..<5 { zones[index] += bucket.zones[index] } }
            out.append(WeekStretch(start: slice[slice.startIndex].start, zones: zones, total: slice.map(\.value).reduce(0, +)))
            end -= 7
        }
        return out.reversed()
    }

    /// A week belongs to the calendar month of its middle day; a month's figure is the mean of its weekly totals.
    private var months: [MonthStretch] {
        let cal = Calendar.current
        let weeks = self.weeks
        var groups: [(first: Date, last: Date, totals: [Double])] = []
        var lastKey: DateComponents?
        for week in weeks {
            let middle = cal.date(byAdding: .day, value: 3, to: week.start) ?? week.start
            let key = cal.dateComponents([.year, .month], from: middle)
            if key == lastKey, !groups.isEmpty {
                groups[groups.count - 1].last = week.start
                groups[groups.count - 1].totals.append(week.total)
            } else {
                groups.append((week.start, week.start, [week.total]))
                lastKey = key
            }
        }
        var previous: Double?
        return groups.map { group in
            let average = group.totals.reduce(0, +) / Double(group.totals.count)
            var delta: Double?
            if groups.count <= 8, let previous, previous > 0 { delta = (average - previous) / previous * 100 }
            defer { previous = average }
            return MonthStretch(first: group.first, end: cal.date(byAdding: .day, value: 7, to: group.last) ?? group.last, average: average, delta: delta)
        }
    }

    @ViewBuilder private var monthlyChart: some View {
        let weeks = self.weeks
        let months = self.months
        if let first = weeks.first?.start, let end = months.last?.end {
            let day: TimeInterval = 86_400
            let top = max(weeks.map(\.total).max() ?? 0, months.map(\.average).max() ?? 0, 5) * 1.35
            Chart {
                ForEach(weeks) { week in
                    let from = week.start.addingTimeInterval(day * 0.5)
                    let to = week.start.addingTimeInterval(day * 6.5)
                    if kind == .strength {
                        RectangleMark(xStart: .value("Week", from), xEnd: .value("Week end", to),
                                      yStart: .value("From", 0), yEnd: .value("Minutes", week.total))
                            .foregroundStyle(kind.color.opacity(0.55)).cornerRadius(2)
                    } else {
                        ForEach(Array(kind.zoneIndexes.enumerated()), id: \.offset) { position, index in
                            let below = kind.zoneIndexes.prefix(position).reduce(0) { $0 + week.zones[$1] }
                            RectangleMark(xStart: .value("Week", from), xEnd: .value("Week end", to),
                                          yStart: .value("From", below), yEnd: .value("Minutes", below + week.zones[index]))
                                .foregroundStyle(nunaHRZoneColors[index].opacity(0.55)).cornerRadius(2)
                        }
                    }
                }
                ForEach(months) { month in
                    let tint = (month.delta ?? 0) < 0 ? NunaPalette.warning : NunaPalette.textPrimary
                    RuleMark(xStart: .value("Month start", month.first), xEnd: .value("Month end", month.end), y: .value("Average", month.average))
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .foregroundStyle(tint)
                        .annotation(position: .top, alignment: .center, spacing: 2) {
                            Text(verbatim: Self.hm(month.average)).font(.nuna(size: 11.5, weight: .bold, design: NunaType.design))
                                .foregroundStyle(NunaPalette.textPrimary).fixedSize()
                        }
                        .annotation(position: .bottom, alignment: .center, spacing: 2) {
                            if let delta = month.delta {
                                Text(verbatim: delta.rounded() == 0 ? "0%" : String(format: "%+.0f%%", locale: AppLanguage.activeLocale, delta))
                                    .font(.nuna(size: 11.5, weight: .bold, design: NunaType.design)).foregroundStyle(tint).fixedSize()
                            }
                        }
                }
            }
            .chartYScale(domain: 0...top)
            .chartXScale(domain: first...end)
            .chartXAxis {
                AxisMarks(values: months.map(\.center)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
            .chartYAxis { minutesAxis }
            .frame(height: 270)
            .accessibilityLabel(Text("Activity time chart"))
        }
    }

    private var averageRule: some ChartContent {
        RuleMark(y: .value("Average", averageValue))
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))
            .foregroundStyle(NunaPalette.textPrimary.opacity(0.75))
            .annotation(position: .trailing, alignment: .center, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                Text("AVG.").font(.nuna(size: 10, weight: .heavy)).foregroundStyle(NunaPalette.canvas).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(NunaPalette.textPrimary, in: Capsule())
            }
    }

    @AxisContentBuilder private var minutesAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
            AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.5))
            AxisValueLabel {
                if let minutes = value.as(Double.self) { Text(verbatim: Self.hm(minutes)).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted) }
            }
        }
    }

    /// A week: one column per day, labelled with the weekday and date. Buckets are plotted as categories so each bar and
    /// its label share one centre.
    private func weekChart(top: Double) -> some View {
        Chart {
            ForEach(buckets) { bucket in
                switch kind {
                case .lowZones, .highZones:
                    zoneBar(bucket, indexes: kind.zoneIndexes)
                case .strength:
                    BarMark(x: .value("Period", Self.key(bucket.start)), y: .value("Minutes", bucket.value), width: .ratio(0.62))
                        .foregroundStyle(kind.color).cornerRadius(4)
                }
            }
            if averageValue > 0 { averageRule }
        }
        .chartYScale(domain: 0...top)
        .chartXAxis {
            AxisMarks(values: buckets.map { Self.key($0.start) }) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel {
                    if let key = value.as(String.self), let date = buckets.first(where: { Self.key($0.start) == key })?.start {
                        axisDateLabel(date)
                    }
                }
            }
        }
        .chartYAxis { minutesAxis }
        .frame(height: 240)
        .accessibilityLabel(Text("Activity time chart"))
    }

    /// A month or six months: one thin bar per day on a time axis, drawn as the other trend cards draw theirs.
    private func dailyChart(top: Double) -> some View {
        let cal = Calendar.current
        let first = buckets.first?.start ?? Date()
        let end = cal.date(byAdding: .day, value: 1, to: buckets.last?.start ?? first) ?? first
        return Chart {
            ForEach(buckets) { bucket in
                switch kind {
                case .lowZones, .highZones:
                    ForEach(kind.zoneIndexes, id: \.self) { index in
                        BarMark(x: .value("Day", bucket.start, unit: .day), y: .value("Minutes", bucket.zones[index]), width: .automatic)
                            .foregroundStyle(nunaHRZoneColors[index]).cornerRadius(1.5)
                    }
                case .strength:
                    BarMark(x: .value("Day", bucket.start, unit: .day), y: .value("Minutes", bucket.value), width: .automatic)
                        .foregroundStyle(kind.color).cornerRadius(1.5)
                }
            }
            if averageValue > 0 { averageRule }
        }
        .chartYScale(domain: 0...top)
        .chartXScale(domain: first...end)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.5))
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
        .chartYAxis { minutesAxis }
        .frame(height: 240)
        .accessibilityLabel(Text("Activity time chart"))
    }

    /// Buckets are plotted as categories so each bar and its label share one centre.
    private static func key(_ date: Date) -> String { String(Int(date.timeIntervalSince1970)) }

    @ChartContentBuilder private func zoneBar(_ bucket: Bucket, indexes: [Int]) -> some ChartContent {
        ForEach(indexes, id: \.self) { index in
            BarMark(x: .value("Period", Self.key(bucket.start)), y: .value("Minutes", bucket.zones[index]), width: .ratio(0.62))
                .foregroundStyle(nunaHRZoneColors[index]).cornerRadius(3)
        }
    }

    @ViewBuilder private var breakdown: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(kind == .strength ? "Strength activity breakdown" : "Heart-rate zones breakdown")
                    .font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                if kind == .strength {
                    let sessions = strengthEntries
                    if sessions.isEmpty {
                        Text("No strength activities in this period").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    } else {
                        NunaProportionBar(parts: sessions.map { ($0.minutes, NunaPalette.effort) }, height: 12)
                        ForEach(sessions.prefix(5)) { entry in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3).fill(NunaPalette.effort).frame(width: 10, height: 10)
                                Text(verbatim: entry.title).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                Spacer(minLength: 8)
                                Text(verbatim: Self.hm(entry.minutes)).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
                            }
                        }
                    }
                } else {
                    let indexes = kind.zoneIndexes
                    let colors = nunaHRZoneColors
                    let selected = indexes.map { (totalZones[$0], colors[$0]) }
                    if selected.map(\.0).reduce(0, +) > 0 {
                        NunaProportionBar(parts: selected.map { (weight: $0.0, color: $0.1) }, height: 12)
                        ForEach(indexes, id: \.self) { index in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3).fill(colors[index]).frame(width: 10, height: 10)
                                Text(verbatim: String(localized: "Zone \(index + 1)")).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                Spacer(minLength: 8)
                                Text(verbatim: Self.hm(totalZones[index])).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
                            }
                        }
                    } else {
                        Text("No heart-rate samples in this period").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
            }
        }
    }

    private func load() async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let lastDay = cal.date(byAdding: .day, value: -pageOffset * range, to: today) ?? today
        let firstDay = cal.date(byAdding: .day, value: -(range - 1), to: lastDay) ?? lastDay
        let priorFirst = cal.date(byAdding: .day, value: -range, to: firstDay) ?? firstDay
        let days = (0..<range).compactMap { cal.date(byAdding: .day, value: $0, to: firstDay) }
        let priorDays = (0..<range).compactMap { cal.date(byAdding: .day, value: $0, to: priorFirst) }
        let allRows = await repo.workoutRows()
        let windowStart = Int(firstDay.timeIntervalSince1970)
        let windowEnd = Int((cal.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay).timeIntervalSince1970)
        rows = allRows.filter { $0.startTs >= windowStart && $0.startTs < windowEnd }

        func strengthMinutes(_ day: Date) -> Double {
            let from = Int(day.timeIntervalSince1970)
            let to = Int((cal.date(byAdding: .day, value: 1, to: day) ?? day).timeIntervalSince1970)
            return allRows.filter { $0.startTs >= from && $0.startTs < to && NunaWorkoutKind.isStrength($0) }.reduce(0) { $0 + duration($1) }
        }

        var zonesByDay: [Date: [Double]] = [:]
        var prior = 0.0
        switch kind {
        case .lowZones, .highZones:
            zonesByDay = await zoneMinutes(for: days)
            // A month is two reads of 30 days; six months would double an already long scan, so it carries no comparison.
            if range <= 30 {
                let previous = await zoneMinutes(for: priorDays)
                prior = previous.values.reduce(0) { total, zones in total + kind.zoneIndexes.reduce(0) { $0 + zones[$1] } }
            }
        case .strength:
            prior = priorDays.reduce(0) { $0 + strengthMinutes($1) }
        }

        let output: [Bucket] = days.map { day in
            let zones = zonesByDay[day] ?? [Double](repeating: 0, count: 5)
            let value: Double
            switch kind {
            case .lowZones, .highZones: value = kind.zoneIndexes.reduce(0) { $0 + zones[$1] }
            case .strength: value = strengthMinutes(day)
            }
            return Bucket(start: day, end: cal.date(byAdding: .day, value: 1, to: day) ?? day, value: value, zones: zones)
        }
        buckets = output
        previousValue = prior
        totalZones = output.reduce(into: [Double](repeating: 0, count: 5)) { total, bucket in
            for index in 0..<5 { total[index] += bucket.zones[index] }
        }
        loaded = true
    }

    /// Minutes in each of the five zones for every day, read one day at a time so a long window is never cut short
    /// by the sample limit of a single read. A few days are read at once.
    private func zoneMinutes(for days: [Date]) async -> [Date: [Double]] {
        let cal = Calendar.current
        let now = Int(Date().timeIntervalSince1970)
        let zoneSet = profile.hrZoneSet
        var out: [Date: [Double]] = [:]
        await withTaskGroup(of: (Date, [Double]).self) { group in
            var running = 0
            for day in days {
                if running >= 4, let done = await group.next() { out[done.0] = done.1; running -= 1 }
                let from = Int(day.timeIntervalSince1970)
                let nextDay = Int((cal.date(byAdding: .day, value: 1, to: day) ?? day).timeIntervalSince1970)
                guard from < now else { out[day] = [Double](repeating: 0, count: 5); continue }
                group.addTask { [repo] in
                    let samples = await repo.hrSamples(from: from, to: min(nextDay - 1, now), limit: 200_000)
                    let minutes = HRZones.timeInZone(samples, zoneSet: zoneSet).seconds.map { $0 / 60 }
                    return (day, minutes)
                }
                running += 1
            }
            for await done in group { out[done.0] = done.1 }
        }
        return out
    }

    private var summary: String {
        if range == 180, let current = months.last?.average, kind != .strength {
            return String(localized: "This month's weekly average in \(kind.title.lowercased()) is \(Self.hm(current)). Your weekly average over the last 6 months is \(Self.hm(headlineValue)).")
        }
        if range == 180, let current = months.last?.average {
            return String(localized: "This month's weekly average in strength activities is \(Self.hm(current)). Your weekly average over the last 6 months is \(Self.hm(headlineValue)).")
        }
        let period = range == 7 ? String(localized: "the last 7 days") : String(localized: "this period")
        let average = range == 7 ? Self.hm(averageValue) : Self.hm(headlineValue)
        let averageLabel = range == 7 ? String(localized: "daily average") : String(localized: "weekly average")
        if kind == .strength {
            return String(localized: "You spent \(Self.hm(currentValue)) in strength activities during \(period). Your \(averageLabel) is \(average).")
        }
        return String(localized: "You spent \(Self.hm(currentValue)) in \(kind.title.lowercased()) during \(period). Your \(averageLabel) is \(average).")
    }

    private var dateRange: String {
        guard let first = buckets.first?.start, let last = buckets.last?.start else { return "" }
        let short = DateFormatter(); short.locale = AppLanguage.activeLocale; short.setLocalizedDateFormatFromTemplate("d MMM")
        let long = DateFormatter(); long.locale = AppLanguage.activeLocale; long.setLocalizedDateFormatFromTemplate("d MMM yy")
        return "\(short.string(from: first)) – \(long.string(from: last))"
    }

    @ViewBuilder private func axisDateLabel(_ date: Date) -> some View {
        if range == 7 {
            VStack(spacing: 1) {
                Text(verbatim: datePart(date, template: "EEE"))
                Text(verbatim: datePart(date, template: "d"))
            }
            .font(.nuna(size: 10.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
        } else {
            Text(verbatim: datePart(date, template: "d MMM")).font(.nuna(size: 10.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
        }
    }

    private func datePart(_ date: Date, template: String) -> String {
        let formatter = DateFormatter(); formatter.locale = AppLanguage.activeLocale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private func duration(_ row: WorkoutRow) -> Double { (row.durationS ?? Double(row.endTs - row.startTs)) / 60 }

    private static func hm(_ minutes: Double) -> String {
        let rounded = max(0, Int(minutes.rounded()))
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}

// MARK: - Any other metric: HRV, resting HR, SpO2, steps, weight ...

struct NunaMetricDetailView: View {
    let metric: MetricDescriptor

    @EnvironmentObject private var repo: Repository
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @StateObject private var series = NunaSeriesModel()
    @State private var range = 7
    @State private var page = 0
    @State private var showCoach = false

    private var isColumns: Bool { ["steps", "steps_est", "energy_kcal", "active_kcal"].contains(metric.key) }
    private var color: Color {
        switch metric.category {
        case "Effort": return NunaPalette.effortText
        case "Rest": return NunaPalette.restText
        case "Charge": return NunaPalette.charge
        default: return NunaPalette.textPrimary   // body and nutrition metrics carry no score meaning
        }
    }
    /// Chart colour by area: overnight vitals are Health (green), Rest is cyan, Effort is yellow, Charge green, the rest white.
    private var lineColor: Color {
        if ["Effort"].contains(metric.category) { return NunaPalette.effort }
        if ["Rest"].contains(metric.category) { return NunaPalette.rest }
        if ["Charge"].contains(metric.category) || overnight { return NunaPalette.charge }
        return NunaPalette.ink
    }
    private var overnight: Bool { ["hrv", "rhr", "spo2", "resp_rate", "skin_temp"].contains(metric.key) }

    private func fmt(_ v: Double) -> String {
        String(format: "%.\(metric.decimals)f", locale: AppLanguage.activeLocale, v)
    }

    /// Compact label for chart columns: 8.2K for 8,214 steps.
    private func fmtShort(_ v: Double) -> String { TrendChart.line2ValueString(v, formattedValue: fmt(v)) }

    /// Every metric, the daily totals (steps, energy) included, uses the one-card trend layout.
    private var usesTrendCard: Bool { true }

    @ViewBuilder private var trendCardBody: some View {
        let latest = series.latest
        NunaTrendDetailCard(
            caption: overnight ? "Last night" : "Today",
            valueText: latest.map { fmt($0.value) } ?? "–", unit: metric.unit,
            chip: status.map { (text: $0.0, color: $0.1) },
            note: previous.flatMap { prev in latest.map { l in
                let d = l.value - prev
                return d == 0 ? String(localized: "Same as yesterday")
                    : (d > 0 ? String(localized: "Up \(fmt(abs(d))) from yesterday") : String(localized: "Down \(fmt(abs(d))) from yesterday"))
            } },
            series: series, reference: (metric.key == "steps" || metric.key == "steps_est") ? 10_000 : nil, referenceLabel: "Target",
            lineColor: lineColor, decimals: metric.decimals,
            higherIsBetter: metric.higherIsBetter ?? true, bars: isColumns, range: $range, page: $page)
        if coachEnabled, let line = anyaLine { NunaAnyaCard(verbatim: line) { showCoach = true } }
        if ["spo2", "resp_rate", "hrv", "rhr"].contains(metric.key) {
            NavigationLink(value: NunaTodayRoute.earlyWarning) {
                NunaCard(small: true) { NunaListRow("Part of the early warning", description: "Breathing, SpO₂, HRV and resting heart rate are watched too", systemImage: "bell", showsChevron: true) }
            }.buttonStyle(.plain)
        }
        NunaExpandRow(title: "What affects it", subtitle: "Common factors", systemImage: "chart.line.uptrend.xyaxis",
                      text: "Sleep, alcohol, hydration, stress, illness and training load all move your daily numbers. Look at the trend over weeks rather than a single day.")
        NunaExpandRow(title: "How it's calculated", subtitle: "Source and method",
                      text: metric.key == "spo2" && metric.source == "my-whoop" && PuffinExperiment.spo2CandidateDisplayEnabled
                        ? "Nights without a calibrated reading show the strap's own estimate (WHOOP 5/MG, Oura). It is not verified, so read it as a trend and not as a measurement. It never feeds Charge or the early warning."
                        : LocalizedStringKey("Source: \(metric.sourceLabel). Values are read from the data stored on this phone."))
    }

    var body: some View {
        let slots = series.window(range)
        let present = slots.compactMap(\.value)
        let latest = series.latest
        NunaDetailScreen(LocalizedStringKey(metric.title)) {
            if usesTrendCard { trendCardBody } else {
            NunaHeroCard(caption: overnight ? "Last night" : "Today", chip: status?.0, chipColor: status?.1,
                         number: latest.map { fmt($0.value) } ?? "–", unit: metric.unit, color: isColumns ? NunaPalette.textPrimary : (metric.key == "hrv" || metric.key == "rhr" ? NunaPalette.textPrimary : color)) {
                if let latest, let prev = previous {
                    let d = latest.value - prev
                    Text(verbatim: d == 0 ? String(localized: "Same as yesterday")
                         : (d > 0 ? String(localized: "Up \(fmt(abs(d))) from yesterday") : String(localized: "Down \(fmt(abs(d))) from yesterday")))
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                } else if let blurb = metric.description {
                    Text(verbatim: blurb).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
            NunaSegmented(rangeOptions(), selection: $range)
            NunaCard {
                VStack(alignment: .leading, spacing: 10) {
                    if present.isEmpty {
                        Text(series.loaded ? "No data in this period" : " ").font(.nuna(size: 14, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 130).textCase(nil)
                    } else if isColumns && range == 7 {
                        let top = max(present.max() ?? 1, 1)
                        NunaColumns(items: slots.map { s in
                            NunaColumns.Item(weekday: weekday(s.date), date: s.date, fraction: s.value.map { $0 / top },
                                             valueText: s.value.map { fmtShort($0) }, highlight: Calendar.current.isDateInToday(s.date))
                        }, color: NunaPalette.restText.opacity(0.85), highlightColor: NunaPalette.textPrimary)
                    } else {
                        NunaLine2Chart(points: series.readings(range), color: lineColor, decimals: metric.decimals, baseline: series.baseline, band: series.typicalRange, higherIsBetter: !["rhr", "resting_hr"].contains(metric.key))
                    }
                }
            }
            if let avg = average(present) {
                HStack(spacing: 12) {
                    if metric.key == "steps" || metric.key == "steps_est" {
                        stat("Target", "10,000".replacingOccurrences(of: ",", with: AppLanguage.activeLocale.groupingSeparator ?? ","))
                        stat("Average", fmt(avg)); stat("Best", fmt(present.max() ?? avg))
                    } else {
                        stat("Average", fmt(avg)); stat("Lowest", fmt(present.min() ?? avg)); stat("Highest", fmt(present.max() ?? avg))
                    }
                }
            }
            NunaExpandRow(title: "What affects it", subtitle: "Common factors", systemImage: "chart.line.uptrend.xyaxis",
                          text: "Sleep, alcohol, hydration, stress, illness and training load all move your daily numbers. Look at the trend over weeks rather than a single day.")
            NunaExpandRow(title: "How it's calculated", subtitle: "Source and method",
                          text: LocalizedStringKey("Source: \(metric.sourceLabel). Values are read from the data stored on this phone."))
            }
        }
        .task(id: "\(metric.id)-\(repo.refreshSeq)") { await series.load(repo: repo, key: metric.key, source: metric.source, days: usesTrendCard ? 400 : 190) }
        .sheet(isPresented: $showCoach) {
            NunaAnyaSheet(context: metric.title, metric: NunaAnyaMetric(key: metric.key, source: metric.source, title: metric.title, unit: metric.unit,
                                                                       decimals: metric.decimals, higherIsBetter: metric.higherIsBetter))
        }
    }

    private var previous: Double? {
        let keys = series.byDay.keys.sorted()
        guard keys.count >= 2 else { return nil }
        return series.byDay[keys[keys.count - 2]]
    }

    private func average(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }

    /// Compare the latest value with your own 30-day band (mean plus or minus one standard deviation).
    /// Anya's line on this metric: the latest figure and where it sits against the usual range (or against yesterday).
    private var anyaLine: String? {
        guard let latest = series.latest else { return nil }
        // What the reading means against the person's own usual and recent days; the older "figure · status" line is the fallback.
        let history = series.byDay.keys.sorted().dropLast().suffix(30).compactMap { series.byDay[$0] }
        if !isColumns, let text = NunaInsightText.vital(key: metric.key, title: String(localized: String.LocalizationValue(metric.title)),
                                                         latest: latest.value, read: VitalRead.analyze(latest: latest.value, history: Array(history)),
                                                         higherIsBetter: metric.higherIsBetter) {
            return text
        }
        var line = String(localized: String.LocalizationValue(metric.title)) + " " + fmt(latest.value) + (metric.unit.isEmpty ? "" : " " + metric.unit)
        if let st = statusText { line += " · " + st }
        else if let prev = previous {
            let d = latest.value - prev
            line += " · " + (d == 0 ? String(localized: "Same as yesterday")
                : (d > 0 ? String(localized: "Up \(fmt(abs(d))) from yesterday") : String(localized: "Down \(fmt(abs(d))) from yesterday")))
        }
        return line
    }

    private var statusText: String? {
        guard let st = status else { return nil }
        return st.2
    }

    private var status: (LocalizedStringKey, Color, String)? {
        guard !isColumns, let latest = series.latest, let base = series.baseline else { return nil }
        let vals = series.byDay.keys.sorted().dropLast().suffix(30).compactMap { series.byDay[$0] }
        guard vals.count >= 5 else { return nil }
        let sd = (vals.map { ($0 - base) * ($0 - base) }.reduce(0, +) / Double(vals.count)).squareRoot()
        if abs(latest.value - base) <= sd { return ("In range", NunaPalette.charge, String(localized: "In range")) }
        let above = latest.value > base
        let good = metric.higherIsBetter.map { $0 == above }
        let word = above ? String(localized: "Above range") : String(localized: "Below range")
        if good == nil { return (above ? "Above range" : "Below range", NunaPalette.textPrimary, word) }
        return (above ? "Above range" : "Below range", good! ? NunaPalette.charge : NunaPalette.warning, word)
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d)
    }
}

// MARK: - Stress

struct NunaStressDetailView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(NunaTodayDefaults.orderKey) private var orderRaw = ""
    @AppStorage(NunaTodayDefaults.hiddenKey) private var hiddenRaw = ""
    @StateObject private var series = NunaSeriesModel()
    @StateObject private var day = NunaTodayModel()
    @StateObject private var history = NunaStressHistory()
    @State private var sleepSpan: OverviewHRChart.SleepSpan?
    @State private var workoutSpans: [OverviewHRChart.WorkoutSpan] = []
    @State private var zoomDomain: ClosedRange<Date>?
    @State private var showBreathing = false
    @State private var showCoach = false
    @State private var showInfo = false

    private func color(_ v: Double) -> Color { NunaStressBars.color(v) }

    /// Clock time of the latest reading on the curve, for today only.
    private var gaugeTime: String? {
        guard day.isToday, let ts = day.stressCurve?.hours.last(where: { $0.level != nil })?.startTs else { return nil }
        return NunaSleepFormat.clock(Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// Whether the Stress card is shown on Today. The same switch as hiding it in Today's edit mode.
    private var cardShown: Binding<Bool> {
        Binding(
            get: {
                let hidden = hiddenRaw.trimmingCharacters(in: .whitespaces).isEmpty ? NunaTodayDefaults.hidden : TodayLayoutPrefs.decodeHidden(hiddenRaw)
                return !hidden.contains(.recoveryVitals)
            },
            set: { on in
                var hidden = hiddenRaw.trimmingCharacters(in: .whitespaces).isEmpty ? NunaTodayDefaults.hidden : TodayLayoutPrefs.decodeHidden(hiddenRaw)
                hidden.removeAll { $0 == .recoveryVitals }
                if !on { hidden.append(.recoveryVitals) }
                if orderRaw.trimmingCharacters(in: .whitespaces).isEmpty { orderRaw = TodayLayoutPrefs.encode(NunaTodayDefaults.order) }
                hiddenRaw = hidden.isEmpty ? "none" : TodayLayoutPrefs.encodeHidden(hidden)
            })
    }

    /// What the gauge shows: the latest reading on today's curve (it moves through the day), or the day's mean for a past day. The
    /// day-level score from the baseline model is only the fallback when there is no curve.
    private var gaugeValue: Double? {
        if let curve = day.stressCurve {
            if day.isToday, let now = StressDayCurve.latestLevel(curve) { return now }
            if !day.isToday, let mean = curve.dayMean { return min(max(mean, 0), 3) }
        }
        return day.stress.map { min(max($0, 0), 3) }
    }

    var body: some View {
        let score = gaugeValue
        let tint: Color = score.map(color) ?? NunaPalette.textPrimary
        NunaDetailScreen("Stress monitor") {
            VStack(spacing: 10) {
                Text(day.isToday ? "Right now" : "Day average").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                NunaStressGauge(value: score, level: score.map { $0 < 1 ? "Low" : ($0 < 2 ? "Medium" : "High") },
                                levelColor: tint, time: gaugeTime, onInfo: { withAnimation { showInfo.toggle() } })
                if showInfo {
                    Text("0 to 3 against your own calm reference. Under 1 is low, 1 to 2 medium, above 2 high. Moments when you were moving are left out.")
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
            recoveryTiles
            // The reading in words, then the day's curve, then Anya, then the peaks.
            if let score { levelExplanation(score) }
            stressChartCard
            if coachEnabled, let line = anyaLine(score) { NunaAnyaCard(verbatim: line) { showCoach = true } }
            if day.isToday, let curve = day.stressCurve {
                let peaks = topPeaks(curve)
                if !peaks.isEmpty {
                    NunaTitleRow(title: "Today's peaks") { EmptyView() }
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                        VStack(spacing: 0) {
                            ForEach(Array(peaks.enumerated()), id: \.offset) { idx, p in
                                if idx > 0 { NunaDivider() }
                                let level = p.level ?? 0
                                HStack(spacing: 12) {
                                    NunaIconTile("bolt", tint: level >= 2 ? NunaPalette.alertText : NunaPalette.effortText)
                                    Text(verbatim: NunaSleepFormat.clock(Date(timeIntervalSince1970: TimeInterval(p.startTs))))
                                        .font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                    Spacer()
                                    Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, level))
                                        .font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(color(level))
                                }
                                .frame(minHeight: 58)
                            }
                        }
                    }
                }
            }
            ForEach(NunaStressCategory.allCases, id: \.self) { category in
                NunaStressCategoryCard(category: category, today: reader.zones(category, todayKey),
                                       typical: typical(category), weekdayName: weekdayName, dateName: dateName)
            }
            NunaCard(small: true, highlight: true, padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)) {
                HStack(spacing: 14) {
                    NunaIconTile("wind", tint: NunaPalette.charge)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("2-minute breathing").font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("A gentle buzz on the strap helps the rhythm").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer(minLength: 4)
                    Button("Start") { showBreathing = true }.buttonStyle(.nuna(.primary, height: 40)).fixedSize()
                }
            }
            NunaCard(small: true, padding: EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18)) {
                NunaToggleRow("Stress monitor", subtitle: "Shown as a card on Today", isOn: cardShown)
            }
            NunaExpandRow(title: "How it's calculated", subtitle: "Scale 0 to 3, against your own baseline",
                          text: "Stress compares your heart rate and heart rate variability with your own calm reference, point by point through the day. Times when you were moving are left out so exercise is not read as stress.")
        }
        .task(id: repo.refreshSeq) {
            await series.load(repo: repo, key: "stress", source: "my-whoop")
            await day.load(repo: repo, profile: profile)
            await history.ensure(days: typicalDays, repo: repo)
            await loadAnnotations()
        }
        // Follows the day: the gauge and the line are re-read every minute while this screen is up.
        .task(id: day.dayOffset) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await day.refreshStress(repo: repo)
            }
        }
        .sheet(isPresented: $showBreathing) {
            NavigationStack { NunaBreathView().toolbar(.hidden, for: .navigationBar) }
        }
        .sheet(isPresented: $showCoach) {
            NunaAnyaSheet(context: "stress", metric: NunaAnyaMetric(key: "stress", source: "my-whoop", title: String(localized: "Stress"), unit: "", decimals: 1, higherIsBetter: false))
        }
    }

    // MARK: Day breakdown

    private var todayKey: String { Repository.localDayKey(Calendar.current.startOfDay(for: Date())) }

    private var reader: NunaStressDayReader {
        NunaStressDayReader(history: history.entries, nightly: NunaNightlyStress.merged(stored: series.byDay, days: repo.days),
                            rows: repo.days, todayKey: todayKey,
                            today: day.stressCurve.map { NunaStressZones(hours: $0.hours) })
    }

    /// The same weekday over the four weeks before.
    private var typicalDays: [Date] {
        let cal = Calendar.current, start = cal.startOfDay(for: Date())
        return (1...4).compactMap { cal.date(byAdding: .day, value: -7 * $0, to: start) }
    }

    private func typical(_ category: NunaStressCategory) -> NunaStressZones? {
        let reader = self.reader
        return NunaStressZones.mean(typicalDays.compactMap { reader.zones(category, Repository.localDayKey($0)) })
    }

    private var weekdayName: String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEE")
        return f.string(from: Date())
    }

    private var dateName: String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE, d MMM")
        return f.string(from: Date())
    }

    /// "Medium stress" and why: the resting heart rate and HRV against the wearer's last month.
    @ViewBuilder private func levelExplanation(_ score: Double) -> some View {
        let word = score < 1 ? String(localized: "Low") : (score < 2 ? String(localized: "Medium") : String(localized: "High"))
        let rows = repo.days.suffix(31).dropLast()
        let rhrBase = rows.compactMap { $0.restingHr.map(Double.init) }
        let hrvBase = rows.compactMap(\.avgHrv)
        let rhrUp = (day.restingHr != nil && rhrBase.count >= 5) ? day.restingHr! > rhrBase.reduce(0, +) / Double(rhrBase.count) + 1 : false
        let hrvDown = (day.hrv != nil && hrvBase.count >= 5) ? day.hrv! < hrvBase.reduce(0, +) / Double(hrvBase.count) - 3 : false
        let cause: String = {
            let level = word.lowercased()
            if rhrUp && hrvDown { return String(localized: "Your resting heart rate is elevated and HRV is lower than usual, resulting in a \(level) level of stress.") }
            if rhrUp { return String(localized: "Your resting heart rate is elevated, resulting in a \(level) level of stress.") }
            if hrvDown { return String(localized: "Your HRV is lower than usual, resulting in a \(level) level of stress.") }
            // Nothing off in the night's signals: a raised level comes from the heart rate through the day, so it is not blamed on them.
            if score >= 1 { return String(localized: "Your resting heart rate and HRV are close to your usual. The \(level) level comes from your heart rate through the day.") }
            return String(localized: "Your resting heart rate and HRV are close to your usual, which keeps stress at a \(level) level.")
        }()
        let meaning = score < 1 ? String(localized: "This indicates your body is calm.")
            : (score < 2 ? String(localized: "This indicates your body is moderately activated.") : String(localized: "This indicates your body is highly activated."))
        VStack(alignment: .leading, spacing: 8) {
            Text(score < 1 ? "Low stress" : (score < 2 ? "Medium stress" : "High stress"))
                .font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Text(verbatim: cause + " " + meaning).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Anya's line on the stress: the level now, against the wearer's own baseline.
    private func anyaLine(_ score: Double?) -> String? {
        if day.isToday, let curve = day.stressCurve {
            let cal = Calendar.current
            let levels: [(hour: Int, level: Double)] = curve.hours.compactMap { h in
                h.level.map { (cal.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(h.startTs))), $0) }
            }
            if let read = StressRead.analyze(levels: levels) { return NunaInsightText.stress(read) }
        }
        guard let score, let base = series.baseline else { return nil }
        let b = String(format: "%.1f", locale: AppLanguage.activeLocale, base)
        let level = score < 1 ? String(localized: "Low") : (score < 2 ? String(localized: "Medium") : String(localized: "High"))
        let vs = score < base - 0.05 ? String(localized: "Calmer than your baseline (\(b))")
            : (score > base + 0.05 ? String(localized: "Tenser than your baseline (\(b))") : String(localized: "About your usual baseline (\(b))"))
        return level + " · " + vs
    }

    /// The day's stress as a line from 0 to 3, in the colours of the level (cyan calm, green, then yellow), with the night marked on top and
    /// a glyph where a workout was. Pinch to zoom and hold to read, as on the heart rate page.
    @ViewBuilder private var stressChartCard: some View {
        let dayStart = Repository.logicalDayStart(Date())
        let all: [TrendPoint] = (day.stressCurve.flatMap { chartPoints($0) } ?? []).compactMap { p in
            p.level.map { TrendPoint(date: Date(timeIntervalSince1970: TimeInterval(p.startTs)), value: min(max($0, 0), 3)) }
        }
        NunaCard(padding: EdgeInsets(top: 16, leading: 12, bottom: 14, trailing: 12)) {
            VStack(alignment: .leading, spacing: 10) {
                if all.count >= 2, let first = all.first?.date, let last = all.last?.date {
                    OverviewHRChart(points: all, sleep: sleepSpan, workouts: workoutSpans,
                                    gradient: Gradient(stops: [.init(color: NunaPalette.rest, location: 0), .init(color: NunaPalette.charge, location: 0.45),
                                                               .init(color: NunaPalette.warning, location: 0.9)]),
                                    valueRange: 0...3, xRange: first...max(last, first.addingTimeInterval(60)), height: 230, touchScrub: true,
                                    zoomDomain: $zoomDomain, zoomBounds: dayStart...dayStart.addingTimeInterval(86_400),
                                    valueFormat: { String(format: "%.1f", locale: AppLanguage.activeLocale, $0) },
                                    dateFormat: { NunaSleepFormat.clock($0) })
                    HStack(spacing: 8) {
                        Image(systemName: zoomDomain == nil ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                        Text(zoomDomain == nil ? "Pinch to zoom · hold to read" : "Zoomed in. Drag to pan · hold to read")
                        Spacer()
                        if zoomDomain != nil { Button("Reset") { zoomDomain = nil }.foregroundStyle(NunaPalette.textPrimary) }
                    }
                    .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                } else {
                    Text("Calibrating").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
            }
        }
    }

    /// The night and the workouts of the day on show, for the marks above the line.
    private func loadAnnotations() async {
        let start = Repository.logicalDayStart(Date())
        let bounds = start...start.addingTimeInterval(86_400)
        let sleeps: [OverviewHRChart.SleepSpan] = await repo.allSleepSessions(days: 3).map { s in
            let secs = max(0, s.endTs - s.effectiveStartTs)
            return .init(start: Date(timeIntervalSince1970: TimeInterval(s.effectiveStartTs)), end: Date(timeIntervalSince1970: TimeInterval(s.endTs)),
                         label: "\(secs / 3600):" + String(format: "%02d", (secs % 3600) / 60))
        }
        let works: [OverviewHRChart.WorkoutSpan] = await repo.workoutRows(days: 3).map { w in
            .init(start: Date(timeIntervalSince1970: TimeInterval(w.startTs)), end: Date(timeIntervalSince1970: TimeInterval(w.endTs)), symbol: sportSymbol(w.sport))
        }
        guard !Task.isCancelled else { return }
        sleepSpan = OverviewHRChart.mainSleep(sleeps, overlapping: bounds)
        workoutSpans = OverviewHRChart.workouts(works, overlapping: bounds)
    }

    /// HRV and resting heart rate, the two signals the stress read leans on: the same plain rows as the signals under Charge, with the
    /// change from the night before.
    private var recoveryTiles: some View {
        NunaPlainList {
            signal("Heart rate variability", "waveform.path.ecg", day.hrv, day.hrvDelta, false, key: "hrv")
            NunaDivider()
            signal("Resting heart rate", "heart", day.restingHr, day.restingHrDelta, true, key: "rhr")
        }
    }

    @ViewBuilder private func signal(_ title: LocalizedStringKey, _ icon: String, _ value: Double?, _ delta: Double?, _ downIsGood: Bool, key: String) -> some View {
        let row = NunaContributorRow(title: title, icon: icon, value: value.map { String(format: "%.0f", $0) }, unit: "", delta: delta, downIsGood: downIsGood, decimals: 0)
        if let m = MetricCatalog.metric(key: key, source: "my-whoop") {
            NavigationLink(value: NunaTodayRoute.metric(m)) { row }.buttonStyle(.plain)
        } else { row }
    }

    /// The finer 30-minute timeline when it has scored points, otherwise the hourly read the Today card uses.
    private func chartPoints(_ r: DaytimeStress.Result) -> [DaytimeStress.HourPoint]? {
        let fine = r.timeline.filter { $0.level != nil || $0.maskedForActivity }
        if fine.contains(where: { $0.level != nil }) { return fine }
        let coarse = r.hours.filter { $0.level != nil || $0.maskedForActivity }
        return coarse.contains(where: { $0.level != nil }) ? coarse : nil
    }

    /// The two highest scored hours, at least two hours apart so one episode is not listed twice.
    private func topPeaks(_ r: DaytimeStress.Result) -> [DaytimeStress.HourPoint] {
        var out: [DaytimeStress.HourPoint] = []
        for p in r.hours.filter({ ($0.level ?? 0) >= 1 }).sorted(by: { ($0.level ?? 0) > ($1.level ?? 0) }) {
            if out.allSatisfy({ abs($0.hour - p.hour) >= 2 }) { out.append(p) }
            if out.count == 2 { break }
        }
        return out.sorted { $0.startTs < $1.startTs }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - All metrics

struct NunaAllMetricsView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @StateObject private var day = NunaTodayModel()
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var showEdit = false
    @AppStorage(KeyMetricPrefs.layoutKey) private var keyMetricsRaw = ""
    @AppStorage("today.keyMetricsDetailed") private var detailed = false
    @AppStorage("today.keyMetricsWindowDays") private var windowDays = 14
    @AppStorage(NunaTodayDefaults.orderKey) private var orderRaw = ""
    @AppStorage(NunaTodayDefaults.hiddenKey) private var hiddenRaw = ""
    @AppStorage(DashboardCardPrefs.selectionKey) private var dashRaw = ""
    @AppStorage(HostedCardPrefs.selectionKey) private var hostedRaw = ""

    private struct Row: Identifiable {
        let id: String; let title: LocalizedStringKey; let icon: String; let tint: Color?; let value: String
        var delta: String?; var good: Bool?; let route: NunaTodayRoute?
    }

    private var rows: [Row] {
        func f(_ v: Double?, _ d: Int = 0, _ unit: String = "") -> String {
            v.map { String(format: "%.\(d)f", locale: AppLanguage.activeLocale, $0) + unit } ?? "–"
        }
        func r(_ key: String, _ source: String = "my-whoop") -> NunaTodayRoute? { MetricCatalog.metric(key: key, source: source).map { .metric($0) } }
        func dl(_ d: Double?, down: Bool = false) -> (String, Bool)? {
            guard let d, abs(d.rounded()) >= 1 else { return nil }
            return (d > 0 ? "▲" : "▼", down ? d < 0 : d > 0)
        }
        let h = dl(day.hrvDelta), p = dl(day.restingHrDelta, down: true)
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        return [
            Row(id: "charge", title: "Charge", icon: "bolt", tint: NunaPalette.charge, value: f(day.charge.pct, 0, "%"), route: r("recovery")),
            Row(id: "effort", title: "Effort", icon: "flame", tint: NunaPalette.effortText, value: day.effort.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–", route: r("strain")),
            Row(id: "rest", title: "Rest", icon: "moon", tint: NunaPalette.restText, value: f(day.rest, 0, "%"), route: .sleep(0)),
            Row(id: "hrv", title: "HRV", icon: "waveform.path.ecg", tint: NunaPalette.charge, value: f(day.hrv, 0, " ms"), delta: h?.0, good: h?.1, route: r("hrv")),
            Row(id: "rhr", title: "Resting HR", icon: "heart", tint: NunaPalette.alertText, value: f(day.restingHr), delta: p?.0, good: p?.1, route: r("rhr")),
            Row(id: "spo2", title: "Blood Oxygen", icon: "drop", tint: NunaPalette.effortText, value: f(day.spo2, 0, "%"), route: r("spo2")),
            Row(id: "resp", title: "Respiratory", icon: "lungs", tint: NunaPalette.effortText, value: f(day.respiratory, 1), route: r("resp_rate")),
            Row(id: "steps", title: "Steps", icon: "figure.walk", tint: NunaPalette.charge, value: f(day.steps),
                route: MetricCatalog.todayStepsMetric(hasMeasuredSteps: day.steps != nil).map { .metric($0) }),
            Row(id: "weight", title: "Weight", icon: "scalemass", tint: NunaPalette.effortText, value: f(day.extras["weight"], 1, " kg"), route: r("weight", "apple-health")),
            Row(id: "kcal", title: "Calories", icon: "flame.fill", tint: NunaPalette.effortText, value: f(day.calories), route: r("energy_kcal")),
            Row(id: "skin", title: "Skin Temp", icon: "thermometer", tint: NunaPalette.alertText, value: f(day.extras["skin_temp"], 1, "°"), route: r("skin_temp")),
        ]
    }

    var body: some View {
        NunaAllMetricsScaffold(onEdit: { showEdit = true }) {
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 { NunaDivider() }
                        link(row)
                    }
                }
            }
            Text("Tap a metric for its detail. Change the order with Edit.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
        .task(id: repo.refreshSeq) { await day.load(repo: repo, profile: profile) }
        .sheet(isPresented: $showEdit) {
            TodayCustomizationSheet(initialDestination: .keyMetrics, sectionOrderRaw: $orderRaw, hiddenSectionsRaw: $hiddenRaw,
                                    keyMetricsRaw: $keyMetricsRaw, keyMetricsDetailed: $detailed, keyMetricsWindowDays: $windowDays,
                                    dashboardCardsRaw: $dashRaw, hostedCardsRaw: $hostedRaw)
        }
    }

    @ViewBuilder private func link(_ row: Row) -> some View {
        let content = HStack(spacing: 12) {
            NunaIconTile(row.icon, tint: row.tint)
            Text(row.title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 8)
            Text(verbatim: row.value).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            if let d = row.delta {
                let c = (row.good ?? true) ? NunaPalette.charge : NunaPalette.warning
                Text(verbatim: d).font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(c)
                    .padding(.horizontal, 8).frame(height: 24).background(NunaPalette.tint(c), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }
            Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
        }
        .frame(minHeight: 58)
        if let route = row.route { NavigationLink(value: route) { content }.buttonStyle(.plain) } else { content }
    }
}

private struct NunaAllMetricsScaffold<Content: View>: View {
    let onEdit: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                HStack(spacing: 10) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    Text("All metrics").font(.nuna(size: 24, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Button(action: onEdit) { NunaBareIcon("pencil") }.buttonStyle(.plain).accessibilityLabel(Text("Edit"))
                }
                content
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

#endif
