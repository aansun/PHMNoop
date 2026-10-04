#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

private func rangeOptions() -> [(value: Int, title: LocalizedStringKey)] {
    [(value: 7, title: "7D"), (value: 30, title: "30D"), (value: 90, title: "90D")]
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
            NunaHeroCard(caption: "Today", chip: chip?.0, chipColor: NunaPalette.charge,
                         number: (day.charge.pct ?? latest?.value).map { String(format: "%.0f", $0) } ?? "–",
                         unit: "%", color: NunaPalette.charge) {
                if let v = day.charge.pct ?? latest?.value, let base = series.baseline {
                    let d = Int((v - base).rounded())
                    Text(verbatim: d == 0 ? String(localized: "In line with your 30-day average")
                         : (d > 0 ? String(localized: "\(d) points above your 30-day average") : String(localized: "\(-d) points below your 30-day average")))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            NunaSegmented(rangeOptions(), selection: $range)
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    NunaColorBars(values: slots.map(\.value), maxValue: 100, color: nunaChargeColor)
                    HStack {
                        Text(verbatim: String(localized: "\(range) days ago"))
                        Spacer()
                        Text("Today")
                    }
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    HStack(spacing: 14) {
                        legend(NunaPalette.charge, "67+"); legend(NunaPalette.warning, "34–66"); legend(NunaPalette.alert, "0–33")
                        Spacer()
                    }
                }
            }
            NunaTitleRow(title: "Drivers") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    driver("HRV", "waveform.path.ecg", NunaPalette.charge, day.hrv.map { String(format: "%.0f", $0) }, day.hrvDelta, false, key: "hrv")
                    NunaDivider()
                    driver("Resting HR", "heart", NunaPalette.alertText, day.restingHr.map { String(format: "%.0f", $0) }, day.restingHrDelta, true, key: "rhr")
                    NunaDivider()
                    NavigationLink(value: NunaTodayRoute.sleep(0)) {
                        HStack(spacing: 12) {
                            NunaIconTile("moon", tint: NunaPalette.restText)
                            Text("Rest").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            Text(verbatim: day.rest.map { String(format: "%.0f%%", $0) } ?? "–")
                                .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }
                        .frame(minHeight: 58)
                    }.buttonStyle(.plain)
                }
            }
            NunaExpandRow(title: "How it's calculated", subtitle: "Three signals, against your own baseline",
                          text: "Charge compares last night's heart rate variability, resting heart rate and sleep with your own baseline from the last 30 days. It is an estimate computed on this phone from your strap's data.")
        }
        .task(id: repo.refreshSeq) {
            await series.load(repo: repo, key: "recovery", source: "my-whoop")
            await day.load(repo: repo, profile: profile)
        }
        .sheet(isPresented: $showCoach) { CoachLauncherSheet(context: "Charge") }
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

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 10, height: 10)
            Text(verbatim: text).font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
        }
    }

    @ViewBuilder private func driver(_ title: LocalizedStringKey, _ icon: String, _ tint: Color, _ value: String?,
                                     _ delta: Double?, _ downIsGood: Bool, key: String) -> some View {
        let row = HStack(spacing: 12) {
            NunaIconTile(icon, tint: tint)
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Text(verbatim: value ?? "–").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
            if let delta, abs(delta.rounded()) >= 1 {
                let good = downIsGood ? delta < 0 : delta > 0
                let c = good ? NunaPalette.charge : NunaPalette.warning
                Text(verbatim: delta > 0 ? "▲" : "▼").font(.system(size: 11.5, weight: .bold)).foregroundStyle(c)
                    .padding(.horizontal, 8).frame(height: 24).background(NunaPalette.tint(c), in: Capsule())
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
        }
        .frame(minHeight: 58)
        if let m = MetricCatalog.metric(key: key, source: "my-whoop") {
            NavigationLink(value: NunaTodayRoute.metric(m)) { row }.buttonStyle(.plain)
        } else { row }
    }
}

// MARK: - Effort

struct NunaEffortDetailView: View {
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
            NunaHeroCard(caption: "Today", chip: level.map { $0.0 }, chipColor: NunaPalette.effortText,
                         number: day.effort.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–",
                         suffix: String(localized: "of \(UnitFormatter.effortScaleMax(scale))"),
                         color: NunaPalette.effortText) {
                NunaProgressBar(fraction: (day.effort ?? 0) / 100, color: NunaPalette.effort).padding(.top, 4)
            }
            NunaTitleRow(title: "Today's sources") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(day.workouts.enumerated()), id: \.offset) { idx, w in
                        if idx > 0 { NunaDivider() }
                        NavigationLink(value: TabRoute.workouts) {
                            HStack(spacing: 12) {
                                NunaIconTile("flame", tint: NunaPalette.effortText)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: WorkoutSource.displaySport(w.sport)).font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                    if let d = w.durationS {
                                        Text(verbatim: String(localized: "\(Int((d / 60).rounded())) min")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                                    }
                                }
                                Spacer()
                                if let s = w.strain { NunaChip(verbatim: "+" + UnitFormatter.effortDisplay(s, scale: scale), color: NunaPalette.effortText) }
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                            }
                            .frame(minHeight: 58)
                        }.buttonStyle(.plain)
                    }
                    if !day.workouts.isEmpty { NunaDivider() }
                    HStack(spacing: 12) {
                        NunaIconTile("waveform.path.ecg")
                        Text("Daily activity").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        NunaChip(verbatim: "+" + UnitFormatter.effortDisplay(dailyActivity, scale: scale))
                    }
                    .frame(minHeight: 58)
                }
            }
            NunaSegmented(rangeOptions(), selection: $range)
            NunaCard {
                if range == 7 {
                    NunaColumns(items: slots.map { s in
                        NunaColumns.Item(label: weekday(s.date), fraction: s.value.map { $0 / 100 },
                                         highlight: Calendar.current.isDateInToday(s.date))
                    }, color: NunaPalette.effort, highlightColor: NunaPalette.effortText)
                } else {
                    NunaColorBars(values: slots.map(\.value), maxValue: 100, color: { _ in NunaPalette.effort })
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

    private var dailyActivity: Double {
        max(0, (day.effort ?? 0) - day.workouts.compactMap(\.strain).reduce(0, +))
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
    private var overnight: Bool { ["hrv", "rhr", "spo2", "resp_rate", "skin_temp"].contains(metric.key) }

    private func fmt(_ v: Double) -> String {
        String(format: "%.\(metric.decimals)f", locale: AppLanguage.activeLocale, v)
    }

    var body: some View {
        let slots = series.window(range)
        let present = slots.compactMap(\.value)
        let latest = series.latest
        NunaDetailScreen(LocalizedStringKey(metric.title), onAnya: coachEnabled ? { showCoach = true } : nil) {
            NunaHeroCard(caption: overnight ? "Last night" : "Today", chip: status?.0, chipColor: status?.1,
                         number: latest.map { fmt($0.value) } ?? "–", unit: metric.unit, color: isColumns ? NunaPalette.textPrimary : (metric.key == "hrv" || metric.key == "rhr" ? NunaPalette.textPrimary : color)) {
                if let latest, let prev = previous {
                    let d = latest.value - prev
                    Text(verbatim: d == 0 ? String(localized: "Same as yesterday")
                         : (d > 0 ? String(localized: "Up \(fmt(abs(d))) from yesterday") : String(localized: "Down \(fmt(abs(d))) from yesterday")))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                } else if let blurb = metric.description {
                    Text(verbatim: blurb).font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            NunaSegmented(rangeOptions(), selection: $range)
            NunaCard {
                VStack(alignment: .leading, spacing: 10) {
                    if present.isEmpty {
                        Text(series.loaded ? "No data in this period" : " ").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 130)
                    } else if isColumns && range == 7 {
                        let top = max(present.max() ?? 1, 1)
                        NunaColumns(items: slots.map { s in
                            NunaColumns.Item(label: weekday(s.date), fraction: s.value.map { $0 / top }, highlight: Calendar.current.isDateInToday(s.date))
                        }, color: NunaPalette.restText.opacity(0.85), highlightColor: NunaPalette.charge)
                    } else if isColumns {
                        NunaColorBars(values: slots.map(\.value), maxValue: max(present.max() ?? 1, 1), color: { _ in NunaPalette.restText })
                    } else {
                        NunaBandLine(values: slots.map(\.value), color: color)
                    }
                    if !isColumns {
                        HStack {
                            Text(verbatim: String(localized: "\(range) days ago"))
                            Spacer()
                            if present.count >= 2 { Text("Band: your normal range") }
                            Spacer()
                            Text("Today")
                        }
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
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
        .task(id: "\(metric.id)-\(repo.refreshSeq)") { await series.load(repo: repo, key: metric.key, source: metric.source) }
        .sheet(isPresented: $showCoach) { CoachLauncherSheet(context: metric.title) }
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
                Text(label).font(.system(size: 11, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Text(verbatim: value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
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
    @StateObject private var series = NunaSeriesModel()
    @StateObject private var day = NunaTodayModel()
    @State private var range = 1
    @State private var showBreathing = false
    @State private var showCoach = false

    var body: some View {
        let score = day.stress
        let tint: Color = score.map { $0 < 1 ? NunaPalette.charge : ($0 < 2 ? NunaPalette.warning : NunaPalette.alert) } ?? NunaPalette.textPrimary
        NunaDetailScreen("Stress monitor") {
            NunaHeroCard(caption: "Day average", chip: score.map { $0 < 1 ? "Low" : ($0 < 2 ? "Medium" : "High") },
                         chipColor: tint, number: score.map { String(format: "%.1f", locale: AppLanguage.activeLocale, $0) } ?? "–",
                         suffix: "/ 3", color: tint) {
                if let score, let base = series.baseline {
                    Text(verbatim: score < base - 0.05 ? String(localized: "Calmer than your baseline (\(String(format: "%.1f", locale: AppLanguage.activeLocale, base)))")
                         : (score > base + 0.05 ? String(localized: "Tenser than your baseline (\(String(format: "%.1f", locale: AppLanguage.activeLocale, base)))")
                            : String(localized: "About your usual baseline")))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            NunaSegmented([(value: 1, title: "Today"), (value: 7, title: "7D"), (value: 30, title: "30D")], selection: $range)
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    if range == 1 {
                        Text("All day").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        if let curve = day.stressCurve, !curve.hours.filter({ $0.level != nil }).isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .trailing, spacing: 0) {
                                    ForEach([3, 2, 1, 0], id: \.self) { t in
                                        Text(verbatim: "\(t)").font(.system(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                                        if t > 0 { Spacer(minLength: 0) }
                                    }
                                }.frame(width: 14, height: 110)
                                DaytimeLoadLine(hours: curve.hours).frame(height: 110)
                            }
                        } else {
                            Text("Calibrating").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: 110)
                        }
                    } else {
                        let slots = series.window(range)
                        NunaColorBars(values: slots.map(\.value), maxValue: 3,
                                      color: { $0 < 1 ? NunaPalette.charge : ($0 < 2 ? NunaPalette.warning : NunaPalette.alert) })
                        HStack {
                            Text(verbatim: String(localized: "\(range) days ago")); Spacer(); Text("Today")
                        }.font(.system(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
            }
            if range == 1, let curve = day.stressCurve {
                let zones = zoneMinutes(curve)
                if zones.total > 0 {
                    NunaTitleRow(title: "Stress zones") { EmptyView() }
                    NunaCard {
                        VStack(spacing: 16) {
                            zoneRow("Low", NunaPalette.charge, zones.low, zones.total)
                            zoneRow("Medium", NunaPalette.warning, zones.mid, zones.total)
                            zoneRow("High", NunaPalette.alert, zones.high, zones.total)
                        }
                    }
                }
                if let peak = curve.peak, let level = peak.level {
                    NunaTitleRow(title: "Today's peak") { EmptyView() }
                    NunaCard(small: true) {
                        HStack(spacing: 12) {
                            NunaIconTile("bolt", tint: level >= 2 ? NunaPalette.alertText : NunaPalette.warning)
                            Text(verbatim: NunaSleepFormat.clock(Date(timeIntervalSince1970: TimeInterval(peak.startTs))))
                                .font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, level))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(level >= 2 ? NunaPalette.alertText : NunaPalette.warning)
                        }
                    }
                }
            }
            NunaCard(small: true, highlight: true, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                HStack(spacing: 12) {
                    NunaIconTile("wind", tint: NunaPalette.charge)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("2-minute breathing").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Gentle, guided breathing").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer(minLength: 4)
                    Button("Start") { showBreathing = true }.buttonStyle(.nuna(.primary, height: 40)).fixedSize()
                }
            }
            if coachEnabled { NunaAnyaCard(title: "Why is my stress changing today?") { showCoach = true } }
            NunaExpandRow(title: "How it's calculated", subtitle: "Scale 0 to 3, against your own baseline",
                          text: "Stress compares your heart rate and heart rate variability, hour by hour, with your own calm reference. Hours when you were moving are left out so exercise is not read as stress.")
        }
        .task(id: repo.refreshSeq) {
            await series.load(repo: repo, key: "stress", source: "my-whoop")
            await day.load(repo: repo, profile: profile)
        }
        .sheet(isPresented: $showBreathing) {
            NavigationStack { BreathingView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showBreathing = false } } } }
        }
        .sheet(isPresented: $showCoach) { CoachLauncherSheet(context: "stress") }
    }

    private func zoneMinutes(_ r: DaytimeStress.Result) -> (low: Double, mid: Double, high: Double, total: Double) {
        let levels = r.hours.compactMap(\.level)
        let low = Double(levels.filter { $0 < 1 }.count) * 60
        let mid = Double(levels.filter { $0 >= 1 && $0 < 2 }.count) * 60
        let high = Double(levels.filter { $0 >= 2 }.count) * 60
        return (low, mid, high, low + mid + high)
    }

    private func zoneRow(_ title: LocalizedStringKey, _ color: Color, _ minutes: Double, _ total: Double) -> some View {
        VStack(spacing: 6) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Text(verbatim: NunaSleepFormat.duration(minutes)).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: "\(Int((minutes / total * 100).rounded()))%").font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NunaPalette.textSecondary).frame(width: 40, alignment: .trailing)
            }
            NunaProgressBar(fraction: minutes / total, color: color)
        }
    }
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
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
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
            Text(row.title).font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 8)
            Text(verbatim: row.value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
            if let d = row.delta {
                let c = (row.good ?? true) ? NunaPalette.charge : NunaPalette.warning
                Text(verbatim: d).font(.system(size: 11.5, weight: .bold)).foregroundStyle(c)
                    .padding(.horizontal, 8).frame(height: 24).background(NunaPalette.tint(c), in: Capsule())
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
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
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: Circle())
                            .overlay(Circle().strokeBorder(NunaPalette.hairline, lineWidth: 1))
                    }
                    Text("All metrics").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Button(action: onEdit) { Text("Edit").font(.system(size: 13.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                        .padding(.horizontal, 14).frame(height: 34).background(NunaPalette.glassStrong, in: Capsule())
                        .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1)) }
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
