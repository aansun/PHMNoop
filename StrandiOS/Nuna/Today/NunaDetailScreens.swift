#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

private func rangeOptions() -> [(value: Int, title: LocalizedStringKey)] {
    [(value: 7, title: "7D"), (value: 30, title: "30D"), (value: 90, title: "90D"), (value: 180, title: "6M")]
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
    @State private var range = 7
    @State private var showCoach = false

    var body: some View {
        let latest = series.latest
        let slots = series.window(range)
        NunaDetailScreen("Charge", onAnya: coachEnabled ? { showCoach = true } : nil) {
            NunaScoreHero(caption: "Today", chip: chip?.0, chipColor: NunaPalette.charge,
                          fraction: (day.charge.pct ?? latest?.value ?? 0) / 100,
                          number: (day.charge.pct ?? latest?.value).map { String(format: "%.0f", $0) } ?? "–",
                          unit: "%", name: "Charge", color: NunaPalette.charge) {
                if let v = day.charge.pct ?? latest?.value, let base = series.baseline {
                    let d = Int((v - base).rounded())
                    Text(verbatim: d == 0 ? String(localized: "In line with your 30-day average")
                         : (d > 0 ? String(localized: "\(d) points above your 30-day average") : String(localized: "\(-d) points below your 30-day average")))
                        .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            NunaPlainList {
                contributor("Heart rate variability", "waveform.path.ecg", day.hrv.map { String(format: "%.0f", $0) }, "", day.hrvDelta, false, key: "hrv")
                NunaDivider()
                contributor("Resting heart rate", "heart", day.restingHr.map { String(format: "%.0f", $0) }, "", day.restingHrDelta, true, key: "rhr")
                NunaDivider()
                contributor("Respiratory rate", "lungs", day.respiratory.map { String(format: "%.1f", locale: AppLanguage.activeLocale, $0) }, "", day.respiratoryDelta, nil, decimals: 1, key: "resp_rate")
                NunaDivider()
                NavigationLink(value: NunaTodayRoute.sleep(0)) {
                    NunaContributorRow(title: "Sleep performance", icon: "moon", value: day.rest.map { String(format: "%.0f%%", $0) }, delta: nil)
                }.buttonStyle(.plain)
            }
            NunaSegmented(rangeOptions(), selection: $range)
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    if range == 7 {
                        NunaColumns(items: slots.map { s in
                            NunaColumns.Item(weekday: weekday(s.date), date: s.date, fraction: s.value.map { $0 / 100 },
                                             valueText: s.value.map { String(format: "%.0f", $0) },
                                             highlight: Calendar.current.isDateInToday(s.date), color: s.value.map(nunaChargeColor))
                        }, color: NunaPalette.charge)
                    } else {
                        NunaLine2Chart(points: series.readings(range), color: NunaPalette.charge, decimals: 0, baseline: series.baseline, band: series.band.map { $0.lo...$0.hi })
                    }
                }
            }
            NunaExpandRow(title: "How it's calculated", subtitle: "Three signals, against your own baseline",
                          text: "Charge compares last night's heart rate variability, resting heart rate and sleep with your own baseline from the last 30 days. It is an estimate computed on this phone from your strap's data.")
        }
        .task(id: repo.refreshSeq) {
            await series.load(repo: repo, key: "recovery", source: "my-whoop")
            await day.load(repo: repo, profile: profile)
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "Charge") }
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d)
    }

    private var chip: (LocalizedStringKey, Bool)? {
        guard let level = day.readiness?.level else { return nil }
        switch level {
        case .primed: return ("Ready for a hard session", true)
        case .balanced: return ("Ready for a moderate load", true)
        case .strained, .rundown: return ("Take it easy today", false)
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
    @State private var range = 7

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        let slots = series.window(range)
        NunaDetailScreen("Effort") {
            NunaScoreHero(caption: "Today", chip: level.map { $0.0 }, chipColor: NunaPalette.effortText,
                          fraction: (day.effort ?? 0) / 100,
                          number: day.effort.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–",
                          suffix: String(localized: "of \(UnitFormatter.effortScaleMax(scale))"),
                          name: "Effort", color: NunaPalette.effortText) {
                Text("Cardio load so far today").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sourcesSection
            NunaSegmented(rangeOptions(), selection: $range)
            NunaCard {
                if range == 7 {
                    let top = max(slots.compactMap(\.value).max() ?? 1, 1)
                    NunaColumns(items: slots.map { s in
                        NunaColumns.Item(weekday: weekday(s.date), date: s.date, fraction: s.value.map { $0 / top },
                                         valueText: s.value.map { UnitFormatter.effortDisplay($0, scale: scale) },
                                         highlight: Calendar.current.isDateInToday(s.date))
                    }, color: NunaPalette.effort, highlightColor: NunaPalette.effortText)
                } else {
                    NunaLine2Chart(points: series.readings(range).map { ($0.date, UnitFormatter.effortValue($0.value, scale: scale)) },
                                   color: NunaPalette.effort, decimals: 1, baseline: series.baseline.map { UnitFormatter.effortValue($0, scale: scale) })
                }
            }
            NunaExpandRow(title: "How it's calculated", subtitle: "Cardio load across the day",
                          text: "Effort adds up how hard your heart worked during the day, weighted by heart rate zone. Workouts and everyday movement both count. It is shown on the scale you chose in Settings.")
        }
        .task(id: repo.refreshSeq) {
            await series.load(repo: repo, key: "strain", source: "my-whoop")
            await day.load(repo: repo, profile: profile)
        }
    }

    // MARK: Today's sources

    private struct Source: Identifiable {
        let id: String; let title: String; let icon: String; let minutes: Int?; let points: Double; let share: Double; let isWorkout: Bool
    }

    /// Where today's Effort came from. Effort is a logarithm of the day's heart-rate load (TRIMP), so Effort points do not add up
    /// the way minutes do. The split is therefore made on the load: each workout's stored Effort is turned back into its load,
    /// the rest of the day's load is everyday movement, and each source gets its share of the day's Effort. A workout window
    /// that overlaps the day's measured load more than it can (their loads sum above the day's) is scaled down to fit.
    private var sources: [Source] {
        guard let e = day.effort, e > 0 else { return [] }
        let withEffort = day.workouts.filter { ($0.strain ?? 0) > 0 }
        let split = EffortAttribution.split(dayEffort: e, workoutEfforts: withEffort.map(\.strain),
                                            logDenominator: StrainScorer.logMapDenominator(method: PuffinExperiment.effortMethod, sex: profile.sex))
        var out: [Source] = withEffort.enumerated().map { i, w in
            let pts = split.workoutPoints[i]
            return Source(id: "w\(i)", title: WorkoutSource.displaySport(w.sport), icon: "flame",
                          minutes: w.durationS.map { Int(($0 / 60).rounded()) }, points: pts, share: pts / e, isWorkout: true)
        }
        if split.dailyPoints >= 0.5 || out.isEmpty {
            out.append(Source(id: "daily", title: String(localized: "Daily activity"), icon: "waveform.path.ecg", minutes: nil,
                              points: split.dailyPoints, share: split.dailyPoints / e, isWorkout: false))
        }
        return out
    }

    @ViewBuilder private var sourcesSection: some View {
        let list = sources
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Today's sources") { EmptyView() }
            if list.isEmpty {
                Text(day.effort == nil ? "Effort for today appears once the strap has recorded some heart rate." : "No Effort recorded yet today.")
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            } else {
                // Share of the day's load, as one bar.
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach(list) { s in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(s.isWorkout ? NunaPalette.effortText : NunaPalette.effort.opacity(0.45))
                                .frame(width: max(6, (geo.size.width - 3 * CGFloat(list.count - 1)) * CGFloat(s.share)))
                        }
                    }
                }
                .frame(height: 12)
                NunaPlainList {
                    ForEach(Array(list.enumerated()), id: \.element.id) { idx, s in
                        if idx > 0 { NunaDivider() }
                        row(s)
                    }
                }
                Text("Each source gets its share of today's heart-rate load, so the parts add up to the day's Effort.")
                    .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func row(_ s: Source) -> some View {
        let content = HStack(spacing: 14) {
            Image(systemName: s.icon).font(.nuna(size: 18)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: s.title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: [s.minutes.map { String(localized: "\($0) min") }, "\(Int((s.share * 100).rounded()))%"].compactMap { $0 }.joined(separator: " · "))
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
            Spacer(minLength: 8)
            Text(verbatim: "+" + UnitFormatter.effortDisplay(s.points, scale: scale))
                .font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            if s.isWorkout { Image(systemName: "chevron.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted) }
        }
        .padding(.vertical, 14).contentShape(Rectangle())
        if s.isWorkout {
            Button { router.requestedDestination = .workouts } label: { content }.buttonStyle(.plain)
        } else { content }
    }

    private var level: (LocalizedStringKey, Color)? {
        day.effort.map { $0 < 33 ? ("Light", NunaPalette.effortText) : ($0 < 66 ? ("Moderate", NunaPalette.effortText) : ("High", NunaPalette.effortText)) }
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d)
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

    /// Every metric except the daily totals (steps, energy), which stay as columns, uses the one-card trend layout.
    private var usesTrendCard: Bool { !isColumns }

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
            series: series, lineColor: lineColor, decimals: metric.decimals,
            higherIsBetter: metric.higherIsBetter ?? true, range: $range, page: $page)
        NunaExpandRow(title: "What affects it", subtitle: "Common factors", systemImage: "chart.line.uptrend.xyaxis",
                      text: "Sleep, alcohol, hydration, stress, illness and training load all move your daily numbers. Look at the trend over weeks rather than a single day.")
        NunaExpandRow(title: "How it's calculated", subtitle: "Source and method",
                      text: LocalizedStringKey("Source: \(metric.sourceLabel). Values are read from the data stored on this phone."))
    }

    var body: some View {
        let slots = series.window(range)
        let present = slots.compactMap(\.value)
        let latest = series.latest
        NunaDetailScreen(LocalizedStringKey(metric.title), onAnya: coachEnabled ? { showCoach = true } : nil) {
            if usesTrendCard { trendCardBody } else {
            NunaHeroCard(caption: overnight ? "Last night" : "Today", chip: status?.0, chipColor: status?.1,
                         number: latest.map { fmt($0.value) } ?? "–", unit: metric.unit, color: isColumns ? NunaPalette.textPrimary : (metric.key == "hrv" || metric.key == "rhr" ? NunaPalette.textPrimary : color)) {
                if let latest, let prev = previous {
                    let d = latest.value - prev
                    Text(verbatim: d == 0 ? String(localized: "Same as yesterday")
                         : (d > 0 ? String(localized: "Up \(fmt(abs(d))) from yesterday") : String(localized: "Down \(fmt(abs(d))) from yesterday")))
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                } else if let blurb = metric.description {
                    Text(verbatim: blurb).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            NunaSegmented(rangeOptions(), selection: $range)
            NunaCard {
                VStack(alignment: .leading, spacing: 10) {
                    if present.isEmpty {
                        Text(series.loaded ? "No data in this period" : " ").font(.nuna(size: 14, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 130)
                    } else if isColumns && range == 7 {
                        let top = max(present.max() ?? 1, 1)
                        NunaColumns(items: slots.map { s in
                            NunaColumns.Item(weekday: weekday(s.date), date: s.date, fraction: s.value.map { $0 / top },
                                             valueText: s.value.map { fmtShort($0) }, highlight: Calendar.current.isDateInToday(s.date))
                        }, color: NunaPalette.restText.opacity(0.85), highlightColor: NunaPalette.textPrimary)
                    } else {
                        NunaLine2Chart(points: series.readings(range), color: lineColor, decimals: metric.decimals, baseline: series.baseline, band: series.band.map { $0.lo...$0.hi }, higherIsBetter: !["rhr", "resting_hr"].contains(metric.key))
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
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: metric.title) }
    }

    private var previous: Double? {
        let keys = series.byDay.keys.sorted()
        guard keys.count >= 2 else { return nil }
        return series.byDay[keys[keys.count - 2]]
    }

    private func average(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }

    /// Compare the latest value with your own 30-day band (mean plus or minus one standard deviation).
    private var status: (LocalizedStringKey, Color)? {
        guard !isColumns, let latest = series.latest, let base = series.baseline else { return nil }
        let vals = series.byDay.keys.sorted().dropLast().suffix(30).compactMap { series.byDay[$0] }
        guard vals.count >= 5 else { return nil }
        let sd = (vals.map { ($0 - base) * ($0 - base) }.reduce(0, +) / Double(vals.count)).squareRoot()
        if abs(latest.value - base) <= sd { return ("In range", NunaPalette.charge) }
        let above = latest.value > base
        let good = metric.higherIsBetter.map { $0 == above }
        if good == nil { return (above ? "Above range" : "Below range", NunaPalette.textPrimary) }
        return (above ? "Above range" : "Below range", good! ? NunaPalette.charge : NunaPalette.warning)
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
    @AppStorage(TodayLayoutPrefs.orderKey) private var orderRaw = ""
    @AppStorage(TodayLayoutPrefs.hiddenKey) private var hiddenRaw = ""
    @StateObject private var series = NunaSeriesModel()
    @StateObject private var day = NunaTodayModel()
    @State private var range = 1
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

    var body: some View {
        let score = day.stress
        let tint: Color = score.map(color) ?? NunaPalette.textPrimary
        NunaDetailScreen("Stress monitor") {
            VStack(spacing: 10) {
                Text(day.isToday ? "Day average" : "Day average").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                NunaStressGauge(value: score, level: score.map { $0 < 1 ? "Low" : ($0 < 2 ? "Medium" : "High") },
                                levelColor: tint, time: gaugeTime, onInfo: { withAnimation { showInfo.toggle() } })
                if showInfo {
                    Text("0 to 3 against your own calm reference. Under 1 is low, 1 to 2 medium, above 2 high. Moments when you were moving are left out.")
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if let score, let base = series.baseline {
                    let b = String(format: "%.1f", locale: AppLanguage.activeLocale, base)
                    Text(verbatim: score < base - 0.05 ? String(localized: "Calmer than your baseline (\(b))")
                         : (score > base + 0.05 ? String(localized: "Tenser than your baseline (\(b))")
                            : String(localized: "About your usual baseline (\(b))")))
                        .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center)
                }
            }
            recoveryTiles
            NunaSegmented([(value: 1, title: "Today"), (value: 7, title: "7D"), (value: 30, title: "30D")], selection: $range)
            chartCard
            if range == 1, let curve = day.stressCurve {
                let zones = zoneMinutes(curve)
                if zones.total > 0 {
                    NunaTitleRow(title: "Stress zones") { EmptyView() }
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                        VStack(spacing: 0) {
                            zoneRow("Low", NunaPalette.charge, zones.low, zones.total)
                            NunaDivider()
                            zoneRow("Medium", NunaPalette.warning, zones.mid, zones.total)
                            NunaDivider()
                            zoneRow("High", NunaPalette.alert, zones.high, zones.total)
                        }
                    }
                }
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
            NunaCard(small: true, highlight: true, padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)) {
                HStack(spacing: 14) {
                    NunaIconTile("wind", tint: NunaPalette.charge)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("2-minute breathing").font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("A gentle buzz on the strap helps the rhythm").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer(minLength: 4)
                    Button("Start") { showBreathing = true }.buttonStyle(.nuna(.primary, height: 40)).fixedSize()
                }
            }
            if coachEnabled { NunaAnyaCard(title: "Why is my stress changing today?", highlight: false) { showCoach = true } }
            NunaCard(small: true, padding: EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18)) {
                NunaToggleRow("Stress monitor", subtitle: "Shown as a card on Today", isOn: cardShown)
            }
            NunaExpandRow(title: "How it's calculated", subtitle: "Scale 0 to 3, against your own baseline",
                          text: "Stress compares your heart rate and heart rate variability with your own calm reference, point by point through the day. Times when you were moving are left out so exercise is not read as stress.")
        }
        .task(id: repo.refreshSeq) {
            await series.load(repo: repo, key: "stress", source: "my-whoop")
            await day.load(repo: repo, profile: profile)
        }
        .sheet(isPresented: $showBreathing) {
            NavigationStack { BreathingView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showBreathing = false } } } }
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "stress") }
    }

    private var chartCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                if range == 1 {
                    HStack {
                        Text("All day").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Spacer()
                        Text("By time of day").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    if let curve = day.stressCurve, let pts = chartPoints(curve) {
                        // The same line NOOP draws on Default Today and in the widget.
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .trailing, spacing: 0) {
                                ForEach([3, 2, 1, 0], id: \.self) { t in
                                    Text(verbatim: "\(t)").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                                    if t > 0 { Spacer(minLength: 0) }
                                }
                            }
                            .frame(width: 14, height: 110)
                            DaytimeLoadLine(hours: pts).frame(height: 110)
                        }
                        HStack {
                            if let f = pts.first(where: { $0.level != nil }) { Text(verbatim: NunaSleepFormat.clock(Date(timeIntervalSince1970: TimeInterval(f.startTs)))) }
                            Spacer()
                            Text("Now")
                        }
                        .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .padding(.leading, 22)
                    } else {
                        Text("Calibrating").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 110)
                    }
                } else {
                    NunaLine2Chart(points: series.readings(range), color: NunaPalette.charge, decimals: 1, baseline: series.baseline, band: series.band.map { $0.lo...$0.hi })
                }
                HStack(spacing: 14) {
                    legend(NunaPalette.charge, "Low"); legend(NunaPalette.warning, "Medium"); legend(NunaPalette.alert, "High")
                    Spacer()
                }
            }
        }
    }

    /// HRV and resting heart rate, the two signals the stress read leans on. The same tile as Key metrics on
    /// Today, with the change from the night before.
    private var recoveryTiles: some View {
        func delta(_ d: Double?, downIsGood: Bool) -> (String, Bool)? {
            guard let d, abs(d.rounded()) >= 1 else { return nil }
            return ((d > 0 ? "▲ " : "▼ ") + "\(Int(abs(d).rounded()))", downIsGood ? d < 0 : d > 0)
        }
        func num(_ v: Double?) -> String { v.map { String(format: "%.0f", locale: AppLanguage.activeLocale, $0) } ?? "–" }
        let h = delta(day.hrvDelta, downIsGood: false), r = delta(day.restingHrDelta, downIsGood: true)
        return NunaMetricsGrid(tiles: [
            NunaMetricTile(id: "hrv", label: "HRV", value: num(day.hrv), unit: "ms",
                           route: MetricCatalog.metric(key: "hrv", source: "my-whoop").map { .metric($0) },
                           delta: h?.0, deltaGood: h?.1, icon: "waveform.path.ecg"),
            NunaMetricTile(id: "rhr", label: "Resting HR", value: num(day.restingHr), unit: "bpm",
                           route: MetricCatalog.metric(key: "rhr", source: "my-whoop").map { .metric($0) },
                           delta: r?.0, deltaGood: r?.1, icon: "heart"),
        ], layout: .list)
    }

    /// The finer 30-minute timeline when it has scored points, otherwise the hourly read the Today card uses.
    private func chartPoints(_ r: DaytimeStress.Result) -> [DaytimeStress.HourPoint]? {
        let fine = r.timeline.filter { $0.level != nil || $0.maskedForActivity }
        if fine.contains(where: { $0.level != nil }) { return fine }
        let coarse = r.hours.filter { $0.level != nil || $0.maskedForActivity }
        return coarse.contains(where: { $0.level != nil }) ? coarse : nil
    }

    private func legend(_ c: Color, _ t: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(c).frame(width: 10, height: 10)
            Text(t).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
        }
    }

    private func zoneMinutes(_ r: DaytimeStress.Result) -> (low: Double, mid: Double, high: Double, total: Double) {
        let levels = r.hours.compactMap(\.level)
        let low = Double(levels.filter { $0 < 1 }.count) * 60
        let mid = Double(levels.filter { $0 >= 1 && $0 < 2 }.count) * 60
        let high = Double(levels.filter { $0 >= 2 }.count) * 60
        return (low, mid, high, low + mid + high)
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

    private func zoneRow(_ title: LocalizedStringKey, _ color: Color, _ minutes: Double, _ total: Double) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color).frame(width: 12, height: 12)
            VStack(spacing: 8) {
                HStack {
                    Text(title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Text(verbatim: NunaSleepFormat.duration(minutes)).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }
                NunaProgressBar(fraction: minutes / total, color: color)
            }
            Text(verbatim: "\(Int((minutes / total * 100).rounded()))%").font(.nuna(size: 12.5, weight: .semibold))
                .foregroundStyle(NunaPalette.textSecondary).frame(width: 38, alignment: .trailing)
        }
        .frame(minHeight: 60)
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
    @AppStorage(TodayLayoutPrefs.orderKey) private var orderRaw = ""
    @AppStorage(TodayLayoutPrefs.hiddenKey) private var hiddenRaw = ""
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
            Row(id: "resp", title: "Respiratory", icon: "wind", tint: NunaPalette.effortText, value: f(day.respiratory, 1), route: r("resp_rate")),
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
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
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
                            .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
                    }
                    Text("All metrics").font(.nuna(size: 24, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Button(action: onEdit) { Text("Edit").font(.nuna(size: 13.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                        .padding(.horizontal, 14).frame(height: 34).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1)) }
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
