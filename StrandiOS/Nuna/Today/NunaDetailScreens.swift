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
    @EnvironmentObject private var router: NavRouter
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @StateObject private var series = NunaSeriesModel()
    @StateObject private var day = NunaTodayModel()
    /// Last night's Rest and skin-temperature deviation: two of the signals Charge is made of.
    @StateObject private var restSeries = NunaSeriesModel()
    @StateObject private var skinSeries = NunaSeriesModel()
    /// The daily series the 30-day averages under the ring are made from.
    @StateObject private var hrvSeries = NunaSeriesModel()
    @StateObject private var rhrSeries = NunaSeriesModel()
    @StateObject private var respSeries = NunaSeriesModel()
    @State private var showCoach = false
    @State private var showInfo = false

    /// The day picked on Today: nil for today; else the day key the readings below are cut at, so a past day shows its own figures.
    private var cutoff: String? { router.todayDayOffset == 0 ? nil : NunaSelectedDay.key(offset: router.todayDayOffset) }

    /// The mean of the last 30 readings before the day shown, what each figure under the ring is compared with.
    private func average30(_ m: NunaSeriesModel) -> Double? { m.average30(before: cutoff ?? Repository.localDayKey(Date())) }

    private var hasNote: Bool { (day.charge.pct ?? series.latest(asOf: cutoff)?.value) != nil && series.baseline != nil }

    var body: some View {
        let latest = series.latest(asOf: cutoff)
        // The day sits in the header where the metric dropdown used to be; the info button goes with it.
        NunaDetailScreen(NunaSelectedDay.caption(offset: router.todayDayOffset, today: "Today"),
                         trailing: hasNote ? AnyView(NunaInfoButton(isOn: $showInfo)) : nil, centersTitle: true) {
            NunaScoreHero(caption: "",
                          fraction: (day.charge.pct ?? latest?.value ?? 0) / 100,
                          number: (day.charge.pct ?? latest?.value).map { String(format: "%.0f", $0) } ?? "–",
                          unit: "%", name: chargeWord ?? "Recovery", nameColor: (day.charge.pct ?? latest?.value).map(nunaChargeTextColor), color: (day.charge.pct ?? latest?.value).map(nunaChargeColor) ?? NunaPalette.charge,
                          hasNote: hasNote, showsCaptionRow: false, ringTitle: "Recovery", ringSize: 252, info: $showInfo) {
                if let v = day.charge.pct ?? latest?.value, let base = series.baseline {
                    let d = Int((v - base).rounded())
                    let readiness = chip.map { $0.0 + ". " } ?? ""
                    Text(verbatim: readiness + (d == 0 ? String(localized: "In line with your 30-day average")
                         : (d > 0 ? String(localized: "\(d) points above your 30-day average") : String(localized: "\(-d) points below your 30-day average"))))
                        .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
            NunaSignalPanel {
                VStack(spacing: 0) {
                    signal("Heart rate variability", "met:heart-rate-variability", key: "hrv", value: day.hrv, average: average30(hrvSeries), good: true)
                    NunaDivider()
                    signal("Resting heart rate", "met:resting-heart-rate", key: "rhr", value: day.restingHr, average: average30(rhrSeries), good: false)
                    NunaDivider()
                    signal("Respiratory rate", "met:respiratory-rate", key: "resp_rate", value: day.respiratory, average: average30(respSeries), decimals: 1, good: nil)
                    NunaDivider()
                    signal("Sleep performance", "met:sleep-performance", key: "sleep_performance", value: day.rest ?? restSeries.latest(asOf: cutoff)?.value,
                           average: average30(restSeries), good: true)
                    NunaDivider()
                    signal("Skin temperature", "vital:temp", key: "skin_temp", value: skinSeries.latest(asOf: cutoff)?.value,
                           average: average30(skinSeries), decimals: 1, signed: true, good: nil)
                }
                NunaTrendLegend(text: router.todayDayOffset == 0 ? "Today vs. last 30 days" : "This day vs. the 30 days before")
                    .padding(.top, 8)
            }
            weeklyTrends
            NunaExpandRow(title: "How it's calculated", subtitle: "Three signals, against your own baseline",
                          text: "Recovery compares last night's heart rate variability, resting heart rate and sleep with your own baseline from the last 30 days. It is an estimate computed on this phone from your strap's data.")
        }
        .task(id: "\(repo.refreshSeq)-\(router.todayDayOffset)") {
            day.dayOffset = router.todayDayOffset
            await series.load(repo: repo, key: "recovery", source: "my-whoop")
            await restSeries.load(repo: repo, key: "sleep_performance", source: "my-whoop")
            await skinSeries.load(repo: repo, key: "skin_temp", source: "my-whoop")
            await hrvSeries.load(repo: repo, key: "hrv", source: "my-whoop")
            await rhrSeries.load(repo: repo, key: "rhr", source: "my-whoop")
            await respSeries.load(repo: repo, key: "resp_rate", source: "my-whoop")
            await day.load(repo: repo, profile: profile)
        }
        // Anya floats over the page and reads it as it opens; her line speaks of today, so on another day she is only the button.
        .nunaAnyaFloating(context: "Recovery", line: router.todayDayOffset == 0 ? anyaLine : nil, analyses: router.todayDayOffset == 0)
        .environment(\.nunaDetailSwitch, nil)
    }

    /// One signal under the ring: its figure against the 30-day average, opening that metric's own page.
    @ViewBuilder private func signal(_ title: LocalizedStringKey, _ icon: String, key: String, value: Double?, average: Double?, decimals: Int = 0,
                                     signed: Bool = false, good: Bool?) -> some View {
        let text: (Double) -> String = { signed ? nunaSigned($0, decimals) : String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, $0) }
        let row = NunaSignalRow(title: title, icon: icon, value: value.map(text),
                                trend: NunaTrend.make(current: value, previous: average, decimals: decimals, upIsGood: good, format: text))
        if let tp = NunaTrendPage.forMetric(key) ?? (key == "sleep_performance" ? NunaTrendPage.restPerformance : nil) {
            NavigationLink { NunaTrendHost(initial: tp, endingDaysAgo: router.todayDayOffset) } label: { row }.buttonStyle(.plain)
        } else if let m = MetricCatalog.metric(key: key, source: "my-whoop") {
            NavigationLink(value: NunaTodayRoute.metric(m)) { row }.buttonStyle(.plain)
        } else { row }
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d)
    }

    /// Anya's line about today's Charge: what lifts it, what holds it back and what that means for the day, not the figure the ring shows.
    private var anyaLine: String? {
        guard let v = day.charge.pct ?? series.latest(asOf: cutoff)?.value else { return nil }
        let rows = repo.days.suffix(31).dropLast()
        let efforts = rows.compactMap(\.strain).filter { $0 > 0 }.sorted()
        let usual = efforts.isEmpty ? nil : efforts[efforts.count / 2]
        let hrvBase = day.hrv.flatMap { h in day.hrvDelta.map { h - $0 } }
        let hrvPct = day.hrvDelta.flatMap { d in hrvBase.map { $0 > 0 ? d / $0 * 100 : 0 } }
        let prior = repo.days.dropLast().last?.strain
        let read = ChargeRead.analyze(hrvDeltaPct: hrvPct, rhrDeltaBpm: day.restingHrDelta, sleepPct: day.rest ?? restSeries.latest(asOf: cutoff)?.value,
                                      priorEffort: prior, usualEffort: usual, respDeltaBpm: day.respiratoryDelta,
                                      skinTempDevC: skinSeries.latest(asOf: cutoff)?.value)
        return NunaInsightText.charge(read, chargePct: v)
    }

    /// The week as bare cards, one each: Charge itself, then the signals it is made of; a card opens that metric's own page.
    private var weeklyTrends: some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaWeeklyHeading()
            NunaWeeklyTrendCard(title: "Recovery", key: "recovery", style: .bars, color: NunaPalette.charge,
                                barFill: { v, last in last ? nunaChargeColor(v) : NunaPalette.textSecondary },
                                labelFill: { v, last in last ? nunaChargeColor(v) : NunaPalette.textPrimary },
                                destination: { AnyView(NunaTrendHost(initial: .charge, endingDaysAgo: router.todayDayOffset)) }, endingDaysAgo: router.todayDayOffset)
            NunaWeeklyTrendCard(title: "Heart rate variability", key: "hrv", style: .line, color: NunaPalette.effortModerate,
                                destination: { AnyView(NunaTrendHost(initial: .hrv, endingDaysAgo: router.todayDayOffset)) }, endingDaysAgo: router.todayDayOffset)
            NunaWeeklyTrendCard(title: "Resting heart rate", key: "rhr", style: .line, color: NunaPalette.effortModerate,
                                destination: { AnyView(NunaTrendHost(initial: .rhr, endingDaysAgo: router.todayDayOffset)) }, endingDaysAgo: router.todayDayOffset)
            NunaWeeklyTrendCard(title: "Respiratory rate", key: "resp_rate", style: .line, decimals: 1, color: NunaPalette.effortModerate,
                                destination: { AnyView(NunaTrendHost(initial: .respiratory, endingDaysAgo: router.todayDayOffset)) }, endingDaysAgo: router.todayDayOffset)
            NunaWeeklyTrendCard(title: "Sleep performance", key: "sleep_performance", style: .bars, color: NunaPalette.restDeep, labelColor: NunaPalette.restText,
                                destination: { AnyView(NunaTrendHost(initial: .restPerformance, endingDaysAgo: router.todayDayOffset)) }, endingDaysAgo: router.todayDayOffset)
            NunaWeeklyTrendCard(title: "Skin temperature", key: "skin_temp", style: .line, decimals: 1, signed: true, color: NunaPalette.effortModerate, endingDaysAgo: router.todayDayOffset)
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
        (day.charge.pct ?? series.latest(asOf: cutoff)?.value).map { $0 >= 67 ? "Ready" : ($0 >= 34 ? "Moderate" : "Low") }
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
    @StateObject private var day = NunaTodayModel()
    /// Minutes in the heart-rate zones day by day, for the 30-day comparison and the weekly zone cards.
    @StateObject private var zones = NunaEffortZoneHistory()
    /// Steps for the 30-day comparison (the stored estimate), and the workouts of every day, for the strength time and its 30-day average.
    @StateObject private var stepsSeries = NunaSeriesModel()
    @State private var allWorkouts: [WorkoutRow] = []
    /// Steps day by day, the on-device estimate with Apple Health's count for the days that have none: the weekly steps card.
    @State private var stepsPoints: [(day: String, value: Double)] = []
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @State private var showCoach = false
    @State private var showInfo = false
    /// The day's heart-rate readings, for the time in each zone.
    @State private var hrDay: [HRSample] = []
    /// Effort points of the day that no workout explains (everyday movement).
    @State private var everydayDay: Double?
    @State private var restingDay: Double?
    @State private var todayWorkouts: [WorkoutRow] = []
    /// Calories burned day by day: the on-device estimate, with Apple Health's active energy for the days that have none.
    @State private var kcalPoints: [(day: String, value: Double)] = []
    /// Everyday movement is worked out but kept out of the panel for now.
    private let showsEverydayMovement = false

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var dayKey: String { NunaSelectedDay.key(offset: router.todayDayOffset) }

    var body: some View {
        // The day sits in the header and the ring starts the page, as on the Charge page.
        NunaDetailScreen(NunaSelectedDay.caption(offset: router.todayDayOffset, today: "Today"),
                         trailing: AnyView(NunaInfoButton(isOn: $showInfo)), centersTitle: true) {
            NunaScoreHero(caption: "",
                          fraction: (day.effort ?? 0) / 100,
                          number: day.effort.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–",
                          suffix: String(localized: "of \(UnitFormatter.effortScaleMax(scale))"),
                          name: level?.0 ?? "Strain", nameColor: level?.1, gradient: day.effort.map(nunaEffortRingColors), target: nunaEffortTargetFractions(charge: day.charge.pct),
                          color: day.effort.map(nunaEffortColor) ?? NunaPalette.effortModerate,
                          showsCaptionRow: false, ringTitle: "Strain", ringSize: 252, info: $showInfo) {
                Text(verbatim: router.todayDayOffset > 0 ? String(localized: "Cardio load for the day") : (targetNote ?? String(localized: "Cardio load so far today"))).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            signalPanel
            // Only the activities that gave Effort, as bare rows under a plain title, as on the WHOOP page.
            NunaTodayActivities(workouts: todayWorkouts, effortScale: scale,
                                dayStart: NunaSelectedDay.date(offset: router.todayDayOffset), sleepMinutes: nil,
                                isToday: router.todayDayOffset == 0, includesSleep: false, plain: true)
            weeklyTrends
            NunaExpandRow(title: "How it's calculated", subtitle: "Cardio load across the day",
                          text: "Strain adds up how hard your heart worked during the day, weighted by heart rate zone. Workouts and everyday movement both count. It is shown on the scale you chose in Settings.")
        }
        .task(id: "\(repo.refreshSeq)-\(router.todayDayOffset)") {
            day.dayOffset = router.todayDayOffset
            await stepsSeries.load(repo: repo, key: "steps_est", source: "my-whoop")
            await day.load(repo: repo, profile: profile)
            await loadDay()
            await loadCalories()
            await loadSteps()
        }
        .task(id: "zones-\(repo.refreshSeq)-\(router.todayDayOffset)") {
            await zones.load(repo: repo, profile: profile, endingOffset: router.todayDayOffset)
        }
        // Anya floats over the page, with today's read as a pill; on a past day she is only the button.
        .nunaAnyaFloating(context: "Strain", line: anyaFloatLine, analyses: router.todayDayOffset == 0)
        .environment(\.nunaDetailSwitch, nil)
    }

    /// What the floating pill says about today's Strain.
    private var anyaFloatLine: String? {
        guard router.todayDayOffset == 0, let e = day.effort else { return nil }
        return NunaInsightText.effort(effort: e, chargePct: day.charge.pct)
            ?? String(localized: "Your Strain is \(UnitFormatter.effortDisplay(e, scale: scale)) of \(UnitFormatter.effortScaleMax(scale)) so far today.")
    }

    /// Steps by day: the estimate and Apple Health's count, the larger of the two for a day that has both.
    private func loadSteps() async {
        var byDay: [String: Double] = [:]
        for r in await repo.appleDailyRows() { if let s = r.steps, s > 0 { byDay[r.day] = Double(s) } }
        for p in await repo.exploreSeries(key: "steps_est", source: "my-whoop", days: 60) where p.value > 0 { byDay[p.day] = max(byDay[p.day] ?? 0, p.value) }
        stepsPoints = byDay.map { (day: $0.key, value: $0.value) }
    }

    private func loadCalories() async {
        var byDay: [String: Double] = [:]
        for r in await repo.appleDailyRows() { if let k = r.activeKcal, k > 0 { byDay[r.day] = k } }
        for p in await repo.exploreSeries(key: "energy_kcal", source: "my-whoop", days: 60) where p.value > 0 { byDay[p.day] = p.value }
        kcalPoints = byDay.map { (day: $0.key, value: $0.value) }
    }

    /// The readings, workouts and resting heart rate of the day on show.
    private func loadDay() async {
        let cal = Calendar.current
        let dayStart = NunaSelectedDay.date(offset: router.todayDayOffset)
        let isToday = cal.isDateInToday(dayStart)
        let start = Int(dayStart.timeIntervalSince1970)
        let end = isToday ? Int(Date().timeIntervalSince1970) : Int((cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart).timeIntervalSince1970)
        hrDay = await repo.hrSamples(from: start, to: end, limit: 200_000)
        let rows = await repo.workoutRows()
        allWorkouts = rows
        todayWorkouts = rows.filter { $0.startTs >= start && $0.startTs < Int((cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart).timeIntervalSince1970) }
        // Everyday movement: the part of a finished day's Effort that none of its workouts explains. Effort is a logarithm of heart-rate load, so the split is
        // made on the load (`EffortAttribution`), not by subtracting points. Only for a past day: today's Effort is still moving.
        if showsEverydayMovement, !isToday,
           let stored = repo.days.first(where: { $0.day == Repository.localDayKey(dayStart) })?.strain, stored > 0 {
            let efforts = todayWorkouts.map(\.strain)
            let denominator = StrainScorer.logMapDenominator(method: PuffinExperiment.effortMethod, sex: profile.sex)
            everydayDay = EffortAttribution.split(dayEffort: stored, workoutEfforts: efforts, logDenominator: denominator).dailyPoints
        } else {
            everydayDay = nil
        }
        restingDay = repo.days.first { $0.day == Repository.localDayKey(dayStart) }?.restingHr.map(Double.init) ?? (isToday ? day.restingHr : nil)
    }

    /// Time in the easy zones (1 to 3, 50–80% of the heart-rate reserve) and the hard ones (4 and 5, 80–100%), the same bands the Effort is scored in.
    private func zoneMinutes(_ hr: [HRSample], resting: Double?) -> (easy: Double, hard: Double)? {
        guard !hr.isEmpty else { return nil }
        let maxHR = profile.age > 0 ? StrainScorer.tanakaHRmax(age: Double(profile.age)) : Double(StrainScorer.defaultMaxHR())
        let t = HRZones.timeInZone(hr, zoneSet: .reserveBands(maxHR: maxHR, restingHR: resting ?? StrainScorer.defaultRestingHR))
        return ((t.seconds[0] + t.seconds[1] + t.seconds[2]) / 60, (t.seconds[3] + t.seconds[4]) / 60)
    }

    /// What the day's heart-rate load is made of, each row against the average of the last 30 days, on one card under the ring.
    private var signalPanel: some View {
        let now = zoneMinutes(hrDay, resting: restingDay)
        func trend(_ current: Double?, _ average: Double?, good: Bool?, decimals: Int = 0, format: ((Double) -> String)? = nil) -> NunaTrend? {
            NunaTrend.make(current: current, previous: average, decimals: decimals, upIsGood: good, format: format)
        }
        return NunaSignalPanel {
            VStack(spacing: 0) {
                NavigationLink { NunaTrendHost(initial: .hrZonesLow) } label: {
                    NunaSignalRow(title: "Heart rate zones 1–3", icon: "met:heart-rate-zones-1-3", value: now.map { Self.hm($0.easy) },
                                  trend: trend(now?.easy, zones.average(easy: true, before: dayKey), good: true, format: Self.hm))
                }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink { NunaTrendHost(initial: .hrZonesHigh) } label: {
                    NunaSignalRow(title: "Heart rate zones 4–5", icon: "met:heart-rate-zones-4-5", value: now.map { Self.hm($0.hard) },
                                  trend: trend(now?.hard, zones.average(easy: false, before: dayKey), good: true, format: Self.hm))
                }.buttonStyle(.plain)
                if showsEverydayMovement {
                    NunaDivider()
                    NunaSignalRow(title: "Everyday movement", icon: "met:steps", value: everydayDay.map { UnitFormatter.effortDisplay($0, scale: scale) }, trend: nil)
                }
                NunaDivider()
                NavigationLink { NunaTrendHost(initial: .strengthTime) } label: {
                    NunaSignalRow(title: "Strength activity time", icon: "met:strength-activity-time", value: Self.hm(strengthMinutes(on: dayKey)),
                                  trend: trend(strengthMinutes(on: dayKey), strengthAverage(before: dayKey), good: true, format: Self.hm))
                }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink { NunaTrendHost(initial: .steps, endingDaysAgo: router.todayDayOffset) } label: {
                    NunaSignalRow(title: "Steps", icon: "met:steps", value: day.steps.map { String(format: "%.0f", locale: AppLanguage.activeLocale, $0) },
                                  trend: trend(day.steps, stepsSeries.average30(before: dayKey), good: true, format: { String(format: "%.0f", locale: AppLanguage.activeLocale, $0) }))
                }.buttonStyle(.plain)
            }
            NunaTrendLegend(text: router.todayDayOffset == 0 ? "Today vs. last 30 days" : "This day vs. the 30 days before")
                .padding(.top, 8)
        }
    }

    /// Minutes in logged strength activities on the day with this key.
    private func strengthMinutes(on key: String) -> Double {
        allWorkouts.filter { NunaWorkoutKind.isStrength($0) && Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) == key }
            .reduce(0) { $0 + ($1.durationS ?? Double($1.endTs - $1.startTs)) / 60 }
    }

    /// The daily average of strength minutes over the 30 days before `key`, days without any counted as zero.
    private func strengthAverage(before key: String) -> Double? {
        let cal = Calendar.current
        let end = NunaSelectedDay.date(offset: router.todayDayOffset)
        let keys = (1...30).compactMap { cal.date(byAdding: .day, value: -$0, to: end) }.map { Repository.localDayKey($0) }
        return keys.reduce(0) { $0 + strengthMinutes(on: $1) } / 30
    }

    /// The week as bare cards, one each: Effort itself, calories, the time in each zone group, then resting heart rate.
    private var weeklyTrends: some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaWeeklyHeading()
            // As on the WHOOP Strain card: every bar and its figure in one blue, the last day lifted on its lighter column.
            NunaWeeklyTrendCard(title: "Strain", key: "strain", style: .bars, color: NunaPalette.effortModerate,
                                barFill: { _, _ in Color(hex: "#3E90E0") },
                                labelFill: { _, _ in Color(hex: "#3E90E0") },
                                destination: { AnyView(NunaTrendHost(initial: .effort, endingDaysAgo: router.todayDayOffset)) },
                                valueText: { UnitFormatter.effortDisplay($0, scale: scale) }, endingDaysAgo: router.todayDayOffset)
            NunaZoneWeeklyCard(title: "HR zones 1–3", zones: [0, 1, 2], byDay: zones.zonesByDay, endingDaysAgo: router.todayDayOffset,
                               destination: { AnyView(NunaTrendHost(initial: .hrZonesLow)) })
            NunaZoneWeeklyCard(title: "HR zones 4–5", zones: [3, 4], byDay: zones.zonesByDay, endingDaysAgo: router.todayDayOffset,
                               destination: { AnyView(NunaTrendHost(initial: .hrZonesHigh)) })
            NunaWeeklyTrendCard(title: "Steps", key: "steps_est", style: .bars, color: NunaPalette.effortModerate,
                                destination: { AnyView(NunaTrendHost(initial: .steps, endingDaysAgo: router.todayDayOffset)) },
                                points: stepsPoints, valueText: { String(format: "%.0f", locale: AppLanguage.activeLocale, $0) }, autoScale: true,
                                endingDaysAgo: router.todayDayOffset)
            // Calories last.
            NunaWeeklyTrendCard(title: "Calories", key: "energy_kcal", style: .bars, color: NunaPalette.effortModerate,
                                destination: { AnyView(NunaTrendHost(initial: .calories, endingDaysAgo: router.todayDayOffset)) },
                                points: kcalPoints, valueText: { String(format: "%.0f", locale: AppLanguage.activeLocale, $0) }, autoScale: true,
                                endingDaysAgo: router.todayDayOffset)
            // Strength activity time last: the minutes of logged strength activities, day by day.
            NunaWeeklyTrendCard(title: "Strength activity time", key: "strength_time", style: .bars, color: NunaPalette.effortModerate,
                                destination: { AnyView(NunaTrendHost(initial: .strengthTime)) },
                                points: strengthPoints, valueText: { Self.hm($0) }, autoScale: true,
                                endingDaysAgo: router.todayDayOffset)
        }
    }

    /// Strength minutes for each of the last 60 days (zero for a day with none), for the weekly card.
    private var strengthPoints: [(day: String, value: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<60).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.map {
            let key = Repository.localDayKey($0)
            return (day: key, value: strengthMinutes(on: key))
        }
    }

    /// Minutes as h:mm.
    private static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// "Today's target 67–86, from your Charge": the grey stretch of the ring, in the scale the wearer chose.
    private var targetNote: String? {
        guard let band = NunaScoreStyle.effortTarget(charge: day.charge.pct) else { return nil }
        func shown(_ fraction: Double) -> Int { Int(UnitFormatter.effortValue(fraction * 100, scale: scale).rounded()) }
        return String(localized: "Today's target \(shown(band.lowerBound))–\(shown(band.upperBound)), from your Recovery")
    }

    private var level: (LocalizedStringKey, Color)? {
        day.effort.map { $0 < 33 ? ("Light", nunaEffortTextColor($0)) : ($0 < 66 ? ("Moderate", nunaEffortTextColor($0)) : ("High", nunaEffortTextColor($0))) }
    }
}

// MARK: - Effort activity detail

/// The three activity contributors behind Effort.  The same detail surface keeps the time in HR zones
/// and time spent strength training legible without pretending that one is the other.
struct NunaEffortActivityDetailView: View {
    enum Kind: Hashable, CaseIterable {
        case lowZones, highZones, allZones, strength

        var title: String {
            switch self {
            case .lowZones: return String(localized: "Heart rate zones 1–3")
            case .highZones: return String(localized: "Heart rate zones 4–5")
            case .allZones: return String(localized: "Heart rate zones all")
            case .strength: return String(localized: "Strength activity time")
            }
        }

        /// Indexes into the five canonical HR zones (Zone 1 is index 0).
        var zoneIndexes: [Int] {
            switch self {
            case .lowZones: return [0, 1, 2]
            case .highZones: return [3, 4]
            case .allZones: return [0, 1, 2, 3, 4]
            case .strength: return []
            }
        }

        var switchKey: String {
            switch self {
            case .lowZones: return "low"
            case .highZones: return "high"
            case .allZones: return "all"
            case .strength: return "strength"
            }
        }

        var icon: String {
            switch self {
            case .lowZones: return "met:heart-rate-zones-1-3"
            case .highZones: return "met:heart-rate-zones-4-5"
            case .allZones: return "met:heart-rate-zones-all"
            case .strength: return "met:strength-activity-time"
            }
        }

        var color: Color {
            switch self {
            case .lowZones: return NunaPalette.rest
            case .highZones: return NunaPalette.alert
            case .allZones: return NunaPalette.rest
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

    /// The bar touched on a week (a day) or a month (a week): its zone times replace the total at the top and the other bars step back.
    @State private var picked: Date?
    @State private var touchBeganOnPicked: Bool?

    private var windowEnd: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: -pageOffset * range, to: cal.startOfDay(for: Date())) ?? Date()
    }

    private var colors: [Color] { (0..<5).map { NunaZoneWeeklyCard.color($0) } }

    /// What a bar is made of, bottom to top: the zones of the page, or one block for strength time.
    private func pieces(_ zones: [Double], total: Double) -> [(color: Color, minutes: Double)] {
        kind == .strength ? [(kind.color, total)] : kind.zoneIndexes.map { (colors[$0], zones[$0]) }
    }

    /// "Weekly total" for a week, "Avg. weekly total" for longer stretches.
    private var headerLabel: String { range == 7 ? String(localized: "Weekly total") : String(localized: "Avg. weekly total") }

    private var nameBox: some View {
        NunaTrendNameBox(icon: kind.icon, title: LocalizedStringKey(kind.title))
    }

    /// The zones (or the strength time) of the touched bar, top zone first, each a figure over its name.
    private func pickedBlock(_ title: String, _ parts: [(color: Color, minutes: Double)], names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            ForEach(Array(parts.enumerated()).reversed(), id: \.offset) { i, part in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: Self.hm(part.minutes)).font(.nuna(size: 24, weight: .semibold, design: NunaType.design)).foregroundStyle(part.color)
                    Text("hr").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(part.color).textCase(nil)
                    Text(verbatim: names[i]).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
    }

    private var zoneNames: [String] { kind == .strength ? [String(localized: "Strength")] : kind.zoneIndexes.map { String(localized: "Zone \($0 + 1)") } }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if let picked, let sel = pickedParts {
                pickedBlock(pickedTitle(picked), sel, names: zoneNames)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: headerLabel).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: Self.hm(headlineValue)).font(.nuna(size: 40, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text("hr").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 14) {
                NunaRangeSwitch(range: $range) { pageOffset = 0; picked = nil }
                NunaDateStepper(label: dateRange, canGoBack: pageOffset < Self.maxPages, canGoForward: pageOffset > 0,
                                back: { pageOffset += 1; picked = nil }, forward: { pageOffset = max(0, pageOffset - 1); picked = nil })
            }
        }
        .padding(.horizontal, 2)
    }

    private func pickedTitle(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale
        if range == 7 { f.setLocalizedDateFormatFromTemplate("EEE, MMM d"); return f.string(from: date) }
        f.setLocalizedDateFormatFromTemplate("MMM d")
        let end = Calendar.current.date(byAdding: .day, value: 6, to: date) ?? date
        return "\(f.string(from: date)) – \(f.string(from: end))"
    }

    /// The bar under the finger as pieces, for the top of the page.
    private var pickedParts: [(color: Color, minutes: Double)]? {
        guard let picked else { return nil }
        if range == 7 {
            guard let b = buckets.first(where: { Calendar.current.isDate($0.start, inSameDayAs: picked) }) else { return nil }
            return pieces(b.zones, total: b.value)
        }
        guard let w = weeks.first(where: { $0.start == picked }) else { return nil }
        return pieces(w.zones, total: w.total)
    }

    var body: some View {
        NunaDetailScreen("Trend view", centersTitle: true) {
            nameBox
            header
            Text(verbatim: summary).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.horizontal, 2)
            if buckets.isEmpty {
                Text(loaded ? "No activity data in this period" : " ").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading).textCase(nil)
            } else {
                chart.padding(.top, 4)
            }
            HStack(spacing: 8) {
                Image(systemName: "info.circle").font(.nuna(size: 14, weight: .semibold))
                Text(kind == .strength ? "Strength activity time is derived from logged strength activities." : "Zone time is derived from heart-rate samples recorded on this device.")
                    .font(.nuna(size: 12, weight: .semibold)).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            .foregroundStyle(NunaPalette.textSecondary).padding(.horizontal, 2).frame(maxWidth: .infinity, alignment: .leading)
            breakdown
            if kind == .lowZones || kind == .highZones {
                NunaWeeklyFooter(target: kind == .highZones ? .zonesHard : .zonesEasy, fourWeekAverage: { await fourWeekZoneAverage() },
                                 onAdded: { await load() }, explainer: AnyView(NunaZonesExplainer()))
            } else if kind == .allZones {
                // All the zones together have no weekly target of their own, only the explanation.
                NunaZonesExplainer()
            } else if kind == .strength {
                NunaWeeklyFooter(target: .strength, fourWeekAverage: { await fourWeekStrengthAverage() },
                                 onAdded: { await load() }, explainer: AnyView(NunaStrengthExplainer()))
            }
        }
        .environment(\.nunaDetailSwitch, nil)
        .task(id: "\(repo.refreshSeq)-\(range)-\(pageOffset)-\(kind.icon)") { await load() }
        .onChange(of: range) { pageOffset = 0; picked = nil }
    }

    @ViewBuilder private var chart: some View {
        if range == 7 {
            weekChart
        } else if range == 180 {
            monthlyChart
        } else {
            monthWeeksChart
        }
    }

    /// Five labelled steps from zero, the step growing (0:15, 0:30, 1:00, 2:00) so the tallest bar always fits in four of them.
    private func axisScale(_ most: Double) -> (top: Double, ticks: [Double]) {
        let step = [15.0, 30, 60, 120, 240, 480].first { ceil(most / $0) <= 4 } ?? 480
        return (step * 4, (0...4).map { Double($0) * step })
    }

    @AxisContentBuilder private func minutesAxis(_ ticks: [Double]) -> some AxisContent {
        AxisMarks(position: .leading, values: ticks) { value in
            AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.7))
            AxisValueLabel {
                if let minutes = value.as(Double.self) { Text(verbatim: Self.hm(minutes)).font(.nuna(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.textMuted) }
            }
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
            let scale = axisScale(max(weeks.map(\.total).max() ?? 0, months.map(\.average).max() ?? 0) * 1.25)
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
                                .foregroundStyle(colors[index].opacity(0.4)).cornerRadius(2)
                        }
                    }
                }
                ForEach(months.filter { $0.average > 0 }) { month in
                    let tint = (month.delta ?? 0) < 0 ? NunaPalette.warning : NunaPalette.textPrimary
                    RuleMark(xStart: .value("Month start", month.first), xEnd: .value("Month end", month.end), y: .value("Average", month.average))
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .foregroundStyle(tint)
                        .annotation(position: .top, alignment: .center, spacing: 2) {
                            Text(verbatim: Self.hm(month.average)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design))
                                .foregroundStyle(NunaPalette.textPrimary).fixedSize()
                        }
                        .annotation(position: .bottom, alignment: .center, spacing: 2) {
                            if let delta = month.delta {
                                Text(verbatim: delta.rounded() == 0 ? "0%" : String(format: "%+.0f%%", locale: AppLanguage.activeLocale, delta))
                                    .font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(tint).fixedSize()
                            }
                        }
                }
            }
            .chartYScale(domain: 0...scale.top)
            .chartXScale(domain: first...end)
            .chartXAxis {
                AxisMarks(values: months.map(\.center)) { value in
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(verbatim: datePart(d, template: "MMM")).font(.nuna(size: 12.5, weight: .semibold)).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                }
            }
            .chartYAxis { minutesAxis(scale.ticks) }
            .frame(height: 285)
            .accessibilityLabel(Text("Activity time chart"))
        }
    }

    private func nearest(_ x: CGFloat, _ proxy: ChartProxy, _ frame: CGRect, among starts: [Date], centre: (Date) -> Date) -> Date? {
        guard let touched: Date = proxy.value(atX: x - frame.minX) else { return nil }
        return starts.min { abs(centre($0).timeIntervalSince(touched)) < abs(centre($1).timeIntervalSince(touched)) }
    }

    /// A week: one stacked bar per day with its total over it and "Fri 23" under it; touching a day shows its zones at the top.
    private var weekChart: some View {
        let cal = Calendar.current
        let end = windowEnd
        let start = cal.date(byAdding: .day, value: -6, to: end) ?? end
        let domain = start...(cal.date(byAdding: .day, value: 1, to: end) ?? end)
        let noon: (Date) -> Date = { cal.date(byAdding: .hour, value: 12, to: cal.startOfDay(for: $0)) ?? $0 }
        let days = buckets.map { (date: noon($0.start), b: $0) }
        let scale = axisScale(buckets.map(\.value).max() ?? 0)
        let lit: (Date) -> Double = { d in picked == nil || cal.isDate(picked!, inSameDayAs: d) ? 1 : 0.3 }
        return Chart {
            ForEach(days, id: \.date) { day in
                ForEach(Array(pieces(day.b.zones, total: day.b.value).enumerated()), id: \.offset) { _, piece in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", piece.minutes), width: .fixed(18))
                        .foregroundStyle(piece.color).opacity(lit(day.date))
                }
            }
            if let picked { RuleMark(x: .value("Picked", noon(picked))).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3])) }
        }
        .chartYScale(domain: 0...scale.top)
        .chartXScale(domain: domain)
        .chartYAxis { minutesAxis(scale.ticks) }
        .chartXAxis(.hidden)
        .chartPlotStyle { $0.padding(.bottom, 50) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame.map({ geo[$0] }) {
                    ZStack {
                        ZStack {
                            ForEach(days, id: \.date) { day in
                                if let x = proxy.position(forX: day.date), let y = proxy.position(forY: day.b.value) {
                                    Text(verbatim: Self.hm(day.b.value)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                        .opacity(lit(day.date)).fixedSize().position(x: frame.minX + x, y: frame.minY + y - 14)
                                }
                                if let x = proxy.position(forX: day.date) { axisDateLabel(day.date).position(x: frame.minX + x, y: frame.maxY + 26) }
                            }
                        }
                        .allowsHitTesting(false)
                        touchLayer(proxy, frame, starts: days.map(\.date), centre: { $0 }, pick: { d in days.first { $0.date == d }!.b.start })
                    }
                }
            }
        }
        .frame(height: 285)
        .accessibilityLabel(Text("Activity time chart"))
    }

    /// The touch layer of a week or a month: the nearest bar is picked, and touching the one already picked lets it go.
    private func touchLayer(_ proxy: ChartProxy, _ frame: CGRect, starts: [Date], centre: @escaping (Date) -> Date, pick: @escaping (Date) -> Date) -> some View {
        Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let hit = nearest(g.location.x, proxy, frame, among: starts, centre: centre).map(pick)
                    if touchBeganOnPicked == nil { touchBeganOnPicked = picked != nil && hit.map { Calendar.current.isDate($0, inSameDayAs: picked!) } == true }
                    if let hit { picked = hit }
                }
                .onEnded { g in
                    if touchBeganOnPicked == true, abs(g.translation.width) < 6 { picked = nil }
                    touchBeganOnPicked = nil
                })
    }

    /// A month: the weeks, one stacked bar each, with the dates of the week under it. Touching a week shows its zones at the top.
    private var monthWeeksChart: some View {
        let cal = Calendar.current
        let weeks = self.weeks
        let day: TimeInterval = 86_400
        let scale = axisScale(weeks.map(\.total).max() ?? 0)
        let first = weeks.first?.start ?? windowEnd
        let end = cal.date(byAdding: .day, value: 7, to: weeks.last?.start ?? first) ?? first
        func centre(_ d: Date) -> Date { d.addingTimeInterval(day * 3.5) }
        func label(_ w: Date) -> String {
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM d")
            let e = cal.date(byAdding: .day, value: 6, to: w) ?? w
            let sameMonth = cal.component(.month, from: w) == cal.component(.month, from: e)
            let g = DateFormatter(); g.locale = AppLanguage.activeLocale; g.setLocalizedDateFormatFromTemplate("d")
            return "\(f.string(from: w)) – \(sameMonth ? g.string(from: e) : f.string(from: e))"
        }
        return Chart {
            ForEach(weeks) { week in
                let from = week.start.addingTimeInterval(day * 0.8), to = week.start.addingTimeInterval(day * 6.2)
                let dim = picked == nil || picked == week.start ? 1.0 : 0.3
                ForEach(Array(pieces(week.zones, total: week.total).enumerated()), id: \.offset) { position, piece in
                    let below = pieces(week.zones, total: week.total).prefix(position).reduce(0) { $0 + $1.minutes }
                    RectangleMark(xStart: .value("Week", from), xEnd: .value("Week end", to), yStart: .value("From", below), yEnd: .value("To", below + piece.minutes))
                        .foregroundStyle(piece.color).opacity(dim)
                }
            }
            if let picked { RuleMark(x: .value("Picked", centre(picked))).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3])) }
        }
        .chartYScale(domain: 0...scale.top)
        .chartXScale(domain: first...end)
        .chartYAxis { minutesAxis(scale.ticks) }
        .chartXAxis(.hidden)
        .chartPlotStyle { $0.padding(.bottom, 50) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame.map({ geo[$0] }) {
                    ZStack {
                        ZStack {
                            ForEach(weeks) { week in
                                if let x = proxy.position(forX: centre(week.start)) {
                                    Text(verbatim: label(week.start)).font(.nuna(size: 12, weight: .semibold)).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
                                        .fixedSize().position(x: frame.minX + x, y: frame.maxY + 26)
                                }
                            }
                        }
                        .allowsHitTesting(false)
                        touchLayer(proxy, frame, starts: weeks.map(\.start), centre: centre, pick: { $0 })
                    }
                }
            }
        }
        .frame(height: 285)
        .accessibilityLabel(Text("Activity time chart"))
    }

    /// Zones 1 to 3 down the left and 4 and 5 down the right, as on the WHOOP page; a page with three zones or fewer keeps one column.
    private func zoneLegend(parts: [(color: Color, minutes: Double)], names: [String]) -> some View {
        let split = parts.count > 3 ? 3 : parts.count
        return HStack(alignment: .top, spacing: 12) {
            zoneLegendColumn(parts, names, 0..<split)
            if parts.count > split { zoneLegendColumn(parts, names, split..<parts.count) }
        }
    }

    private func zoneLegendColumn(_ parts: [(color: Color, minutes: Double)], _ names: [String], _ range: Range<Int>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(range), id: \.self) { i in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(parts[i].color).frame(width: 10, height: 10)
                    Text(verbatim: Self.hm(parts[i].minutes)).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 44, alignment: .leading)
                    Text(verbatim: names[i]).font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Time in each zone over the window (a week's total, or the weekly average of a longer stretch), as a bar split by zone and a line each.
    @ViewBuilder private var breakdown: some View {
        let divisor = range == 7 ? 1.0 : max(Double(range) / 7, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(kind == .strength ? "Strength activity breakdown" : "HR zones breakdown").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Text(range == 7 ? "(weekly total)" : "(avg. weekly total)").font(.nuna(size: 11, weight: .semibold)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            }
            let parts: [(color: Color, minutes: Double)] = kind == .strength
                ? [(kind.color, currentValue / divisor)]
                : kind.zoneIndexes.map { (colors[$0], totalZones[$0] / divisor) }
            let names = zoneNames
            if parts.map(\.minutes).reduce(0, +) > 0 {
                NunaProportionBar(parts: parts.map { (weight: $0.minutes, color: $0.color) }, height: 14)
                zoneLegend(parts: parts, names: names)
            } else {
                Text(kind == .strength ? "No strength activities in this period" : "No heart-rate samples in this period")
                    .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
        .padding(.top, 6).frame(maxWidth: .infinity, alignment: .leading)
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
        case .lowZones, .highZones, .allZones:
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
            case .lowZones, .highZones, .allZones: value = kind.zoneIndexes.reduce(0) { $0 + zones[$1] }
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

    /// The weekly strength time over the four weeks before today, as an average.
    private func fourWeekStrengthAverage() async -> Double? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let from = Int((cal.date(byAdding: .day, value: -28, to: today) ?? today).timeIntervalSince1970), to = Int(today.timeIntervalSince1970)
        let total = await repo.workoutRows().filter { $0.startTs >= from && $0.startTs < to && NunaWorkoutKind.isStrength($0) }.reduce(0.0) { $0 + duration($1) }
        return total > 0 ? total / 4 : nil
    }

    /// The weekly total of this page's zones over the four weeks before today, as an average: the figure the target screen sets the goal against.
    private func fourWeekZoneAverage() async -> Double? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (1...28).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let minutes = await zoneMinutes(for: days)
        let total = minutes.values.reduce(0.0) { sum, zones in sum + kind.zoneIndexes.reduce(0.0) { $0 + zones[$1] } }
        return total > 0 ? total / 4 : nil
    }

    /// Minutes in each of the five zones for every day (the shared reader, so the plan states the same time).
    private func zoneMinutes(for days: [Date]) async -> [Date: [Double]] {
        await NunaZoneMinutes.perDay(repo: repo, age: profile.age, days: days)
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
            .font(.nuna(size: 12.5, weight: .semibold)).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
        } else {
            Text(verbatim: datePart(date, template: "d MMM")).font(.nuna(size: 12.5, weight: .semibold)).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
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
    /// Read here so the target on the page follows a change made under Targets in Persona.
    @AppStorage(NunaGoals.steps) private var storedStepGoal = 0
    @StateObject private var series = NunaSeriesModel()
    @State private var range = 7
    @State private var page = 0
    @State private var showCoach = false

    private var isColumns: Bool { ["steps", "steps_est", "energy_kcal", "active_kcal"].contains(metric.key) }
    private var color: Color {
        switch metric.category {
        case "Strain": return NunaPalette.effortText
        case "Sleep": return NunaPalette.restText
        case "Recovery": return NunaPalette.charge
        default: return NunaPalette.textPrimary   // body and nutrition metrics carry no score meaning
        }
    }
    /// Chart colour by area: overnight vitals are Health (green), Rest is cyan, Effort is yellow, Charge green, the rest white.
    private var lineColor: Color {
        if ["Strain"].contains(metric.category) { return NunaPalette.effort }
        if ["Sleep"].contains(metric.category) { return NunaPalette.rest }
        if ["Recovery"].contains(metric.category) || overnight { return NunaPalette.charge }
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
            series: series, reference: (metric.key == "steps" || metric.key == "steps_est") ? Double(NunaGoals.stepTarget(storedStepGoal)) : nil, referenceLabel: "Target",
            lineColor: lineColor, decimals: metric.decimals,
            higherIsBetter: metric.higherIsBetter ?? true, bars: isColumns, range: $range, page: $page)
        if ["spo2", "resp_rate", "hrv", "rhr"].contains(metric.key) {
            NavigationLink(value: NunaTodayRoute.earlyWarning) {
                NunaCard(small: true) { NunaListRow("Part of the early warning", description: "Breathing, SpO₂, HRV and resting heart rate are watched too", systemImage: NunaIcons.earlyWarning, showsChevron: true) }
            }.buttonStyle(.plain)
        }
        NunaExpandRow(title: "What affects it", subtitle: "Common factors", systemImage: "chart.line.uptrend.xyaxis",
                      text: "Sleep, alcohol, hydration, stress, illness and training load all move your daily numbers. Look at the trend over weeks rather than a single day.")
        NunaExpandRow(title: "How it's calculated", subtitle: "Source and method",
                      text: metric.key == "spo2" && metric.source == "my-whoop" && PuffinExperiment.spo2CandidateDisplayEnabled
                        ? "Nights without a calibrated reading show the strap's own estimate (WHOOP 5/MG, Oura). It is not verified, so read it as a trend and not as a measurement. It never feeds Recovery or the early warning."
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
            NunaSegmented(rangeOptions(), selection: $range, onBlack: true)
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
                        stat("Target", NunaTrendsFormat.num(Double(NunaGoals.stepTarget(storedStepGoal))))
                        stat("Average", fmt(avg)); stat("Best", fmt(present.max() ?? avg))
                    } else {
                        stat("Average", fmt(avg)); stat("Lowest", fmt(present.min() ?? avg)); stat("Highest", fmt(present.max() ?? avg))
                    }
                }
            }
            if metric.key == "avg_hr" { NunaAverageHRInfo() }
            NunaExpandRow(title: "What affects it", subtitle: "Common factors", systemImage: "chart.line.uptrend.xyaxis",
                          text: "Sleep, alcohol, hydration, stress, illness and training load all move your daily numbers. Look at the trend over weeks rather than a single day.")
            NunaExpandRow(title: "How it's calculated", subtitle: "Source and method",
                          text: LocalizedStringKey("Source: \(metric.sourceLabel). Values are read from the data stored on this phone."))
            }
        }
        .task(id: "\(metric.id)-\(repo.refreshSeq)") { await series.load(repo: repo, key: metric.key, source: metric.source, days: usesTrendCard ? 400 : 190) }
        .nunaAnyaFloating(context: metric.title, line: anyaLine,
                          metric: NunaAnyaMetric(key: metric.key, source: metric.source, title: metric.title, unit: metric.unit,
                                                 decimals: metric.decimals, higherIsBetter: metric.higherIsBetter))
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
    @StateObject private var day = NunaTodayModel()
    @StateObject private var history = NunaStressHistory()
    @State private var sleepSpan: OverviewHRChart.SleepSpan?
    /// What the chart draws: today, the last 24 hours up to now; an earlier day, that calendar day.
    @State private var trail: WhoopStress.Result?
    @State private var trailWorkouts: [WorkoutRow] = []
    @State private var chartDomain: ClosedRange<Int>?
    @State private var showZoom = false
    @State private var showBreathing = false
    @State private var showCoach = false
    @State private var showInfo = false
    @State private var showSettings = false

    private func color(_ v: Double) -> Color { NunaStressBand.color(for: v) }

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
        NunaDetailScreen("Stress monitor", trailing: AnyView(settingsButton), centersTitle: true) {
            if !day.stressStatus.isReady {
                // Still learning the person: nothing about stress is shown, only how far along it is.
                if day.loaded {
                    NunaStressCalibrationCard(nights: day.stressStatus.nights, opensStress: false)
                    Text("Stress is read against your own baseline from your last 14 nights, so it stays hidden until they are in. That keeps every figure accurate.")
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                    NunaCard(small: true, padding: EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18)) {
                        NunaToggleRow("Stress monitor", subtitle: "Shown as a card on Today", isOn: cardShown)
                    }
                }
            } else {
            dayStepper
            VStack(spacing: 10) {
                NunaStressGauge(value: score, level: score.map { $0 < 1 ? "Low" : ($0 < 2 ? "Medium" : "High") },
                                levelColor: tint, time: gaugeTime, onInfo: { withAnimation { showInfo.toggle() } }, height: 205)
                if showInfo {
                    Text("0 to 3 against your own baseline from your last 14 nights. Under 1 is low, 1 to 2 medium, above 2 high. Exercise counts toward Total day but is eased toward neutral, and stays out of Non-activity.")
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
            stressChart
            ForEach(NunaStressCategory.allCases, id: \.self) { category in
                NunaStressCategoryCard(category: category, today: reader.zones(category, selectedKey),
                                       typical: typical(category), dateName: dateName)
            }
            NunaCard(small: true, highlight: true, padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)) {
                HStack(spacing: 14) {
                    NunaIconTile(NunaIcons.breathing, tint: NunaPalette.charge)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("2-minute breathing").font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("A gentle buzz on the strap helps the rhythm").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer(minLength: 4)
                    Button("Start") { showBreathing = true }.buttonStyle(.nuna(.primary, height: 40)).fixedSize()
                }
            }
        }
        }
        .task(id: "\(repo.refreshSeq)-\(day.dayOffset)") {
            await day.load(repo: repo, profile: profile)
            await loadChart()
            await history.ensure(days: [selectedDate] + previousDays, repo: repo)
            await loadAnnotations()
        }
        // Follows the day: the gauge and the line are re-read every minute while this screen is up.
        .task(id: day.dayOffset) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await day.refreshStress(repo: repo)
                if day.isToday { await loadChart() }
            }
        }
        .sheet(isPresented: $showBreathing) {
            NavigationStack { NunaBreathView().toolbar(.hidden, for: .navigationBar) }
        }
        .nunaAnyaFloating(context: "stress", line: day.isToday ? anyaLine(gaugeValue) : nil,
                          metric: NunaAnyaMetric(key: "stress", source: "my-whoop", title: String(localized: "Stress"), unit: "", decimals: 1, higherIsBetter: false),
                          analyses: day.isToday)
        .sheet(isPresented: $showSettings) { settingsSheet }
        .fullScreenCover(isPresented: $showZoom) {
            NunaStressZoomScreen(points: trail?.chartPoints ?? [], workouts: trailWorkouts, sleep: sleepSpan.map { Int($0.start.timeIntervalSince1970)...Int($0.end.timeIntervalSince1970) },
                                 domain: chartDomain, showsNow: day.isToday) { showZoom = false }
        }
    }

    // MARK: Header pieces

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape").font(.nuna(size: 22, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text("Settings"))
    }

    private var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stress monitor").font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).padding(.top, 22)
            NunaCard(small: true, padding: EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18)) {
                NunaToggleRow("Stress monitor", subtitle: "Shown as a card on Today", isOn: cardShown)
            }
            NunaExpandRow(title: "How it's calculated", subtitle: "Scale 0 to 3, against your own baseline",
                          text: "Stress compares your heart rate and heart rate variability, every five minutes, with your own baseline from your last 14 nights. Exercise counts toward Total day but is eased toward neutral, and stays out of Non-activity, so being active is not read as being stressed. Until 14 nights are in, stress is not shown.")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NunaSpacing.screenH)
        .background(NunaPalette.card.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .nunaSheetChrome(detents: [.medium])
    }

    /// "‹ TODAY ›": the day on show, one day back or forward.
    private var dayStepper: some View {
        let oldest = repo.days.first?.day ?? ""
        let canBack = oldest < selectedKey
        let label: String = {
            if day.dayOffset == 0 { return String(localized: "Today") }
            if day.dayOffset == 1 { return String(localized: "Yesterday") }
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE, MMM d")
            return f.string(from: selectedDate)
        }()
        return HStack(spacing: 22) {
            Button { step(1) } label: {
                Image(systemName: "chevron.left").font(.nuna(size: 18, weight: .heavy)).frame(width: 44, height: 40).contentShape(Rectangle())
            }
            .disabled(!canBack).opacity(canBack ? 1 : 0.3).accessibilityLabel(Text("Previous day"))
            Text(verbatim: label).font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).frame(minWidth: 90)
            Button { step(-1) } label: {
                Image(systemName: "chevron.right").font(.nuna(size: 18, weight: .heavy)).frame(width: 44, height: 40).contentShape(Rectangle())
            }
            .disabled(day.dayOffset == 0).opacity(day.dayOffset == 0 ? 0.3 : 1).accessibilityLabel(Text("Next day"))
        }
        .buttonStyle(.plain).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity)
    }

    private func step(_ delta: Int) {
        day.dayOffset = max(0, day.dayOffset + delta)
    }

    private var selectedDate: Date { day.displayDate }
    private var selectedKey: String { Repository.localDayKey(selectedDate) }

    // MARK: Day breakdown

    private var todayKey: String { Repository.localDayKey(Calendar.current.startOfDay(for: Date())) }

    private var reader: NunaStressDayReader {
        NunaStressDayReader(history: history.entries, todayKey: todayKey, today: day.isToday ? day.stressWhoop : nil)
    }

    /// The seven days before the one on show.
    private var previousDays: [Date] {
        let cal = Calendar.current, start = cal.startOfDay(for: selectedDate)
        return (1...7).compactMap { cal.date(byAdding: .day, value: -$0, to: start) }
    }

    private func typical(_ category: NunaStressCategory) -> NunaStressZones? {
        let reader = self.reader
        return NunaStressZones.mean(previousDays.compactMap { reader.zones(category, Repository.localDayKey($0)) })
    }

    private var dateName: String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return f.string(from: selectedDate)
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
        guard let score, let base = day.stressBaseline else { return nil }
        let b = String(format: "%.1f", locale: AppLanguage.activeLocale, base)
        let level = score < 1 ? String(localized: "Low") : (score < 2 ? String(localized: "Medium") : String(localized: "High"))
        let vs = score < base - 0.05 ? String(localized: "Calmer than your baseline (\(b))")
            : (score > base + 0.05 ? String(localized: "Tenser than your baseline (\(b))") : String(localized: "About your usual baseline (\(b))"))
        return level + " · " + vs
    }

    /// The day's stress as a line from 0 to 3 straight on the page, with the night marked on top and a glyph where a workout was. Hold to read,
    /// and the magnifier opens the last twelve hours across the screen.
    private var stressChart: some View {
        NunaStressMonitorChart(points: trail?.chartPoints ?? [], workouts: trailWorkouts, showsNow: day.isToday,
                               sleep: sleepSpan.map { Int($0.start.timeIntervalSince1970)...Int($0.end.timeIntervalSince1970) },
                               zoomed: false, onZoom: { showZoom = true }, reads: true, domain: chartDomain)
            .frame(height: 230)
    }

    /// Reads what the chart draws: the last 24 hours up to now for today (so last night is in it), the calendar day for an earlier one.
    private func loadChart() async {
        guard day.stressStatus.isReady else { trail = nil; return }
        let from: Int, to: Int
        if day.isToday {
            to = Int(Date().timeIntervalSince1970); from = to - 86_400
            trail = await StressEngine.shared.day(repo: repo, from: from, to: to)
        } else {
            from = Int(Calendar.current.startOfDay(for: day.displayDate).timeIntervalSince1970); to = from + 86_400 - 1
            trail = day.stressWhoop
        }
        chartDomain = from...to
        trailWorkouts = (await repo.workoutRows(days: 10)).filter { $0.startTs < to && $0.endTs > from }
    }

    /// The night of the window the chart covers, for the moon and the band above the line.
    private func loadAnnotations() async {
        guard let domain = chartDomain else { return }
        let bounds = Date(timeIntervalSince1970: TimeInterval(domain.lowerBound))...Date(timeIntervalSince1970: TimeInterval(domain.upperBound))
        let sleeps: [OverviewHRChart.SleepSpan] = await repo.allSleepSessions(days: day.dayOffset + 4).map { s in
            let secs = max(0, s.endTs - s.effectiveStartTs)
            return .init(start: Date(timeIntervalSince1970: TimeInterval(s.effectiveStartTs)), end: Date(timeIntervalSince1970: TimeInterval(s.endTs)),
                         label: "\(secs / 3600):" + String(format: "%02d", (secs % 3600) / 60))
        }
        guard !Task.isCancelled else { return }
        sleepSpan = OverviewHRChart.mainSleep(sleeps, overlapping: bounds)
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
            Row(id: "charge", title: "Recovery", icon: "bolt", tint: NunaPalette.charge, value: f(day.charge.pct, 0, "%"), route: r("recovery")),
            Row(id: "effort", title: "Strain", icon: "flame", tint: NunaPalette.effortText, value: day.effort.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–", route: r("strain")),
            Row(id: "rest", title: "Sleep", icon: NunaIcons.sleep, tint: NunaPalette.restText, value: f(day.rest, 0, "%"), route: .sleep(0)),
            Row(id: "hrv", title: "HRV", icon: "met:heart-rate-variability", tint: NunaPalette.charge, value: f(day.hrv, 0, " ms"), delta: h?.0, good: h?.1, route: r("hrv")),
            Row(id: "rhr", title: "Resting HR", icon: "met:resting-heart-rate", tint: NunaPalette.alertText, value: f(day.restingHr), delta: p?.0, good: p?.1, route: r("rhr")),
            Row(id: "spo2", title: "Blood Oxygen", icon: "vital:spo2", tint: NunaPalette.effortText, value: f(day.spo2, 0, "%"), route: r("spo2")),
            Row(id: "resp", title: "Respiratory", icon: "met:respiratory-rate", tint: NunaPalette.effortText, value: f(day.respiratory, 1), route: r("resp_rate")),
            Row(id: "steps", title: "Steps", icon: NunaIcons.steps, tint: NunaPalette.charge, value: f(day.steps),
                route: MetricCatalog.todayStepsMetric(hasMeasuredSteps: day.steps != nil).map { .metric($0) }),
            Row(id: "weight", title: "Weight", icon: NunaIcons.weight, tint: NunaPalette.effortText, value: f(day.extras["weight"], 1, " kg"), route: r("weight", "apple-health")),
            Row(id: "kcal", title: "Calories", icon: NunaIcons.calories, tint: NunaPalette.effortText, value: f(day.calories), route: r("energy_kcal")),
            Row(id: "skin", title: "Skin Temp", icon: "vital:temp", tint: NunaPalette.alertText, value: f(day.extras["skin_temp"], 1, "°"), route: r("skin_temp")),
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
                        Image(systemName: "chevron.left").font(.nuna(size: 23, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
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
        .background(NunaBackdrop())
        .toolbar(.hidden, for: .navigationBar)
    }
}

#endif
