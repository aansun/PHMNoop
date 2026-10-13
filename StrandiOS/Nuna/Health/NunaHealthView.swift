#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Nuna "Kesehatan": a hub with Vital and Sleep tabs. Phase 2 of docs/nuna/IMPLEMENTATION_PLAN.md.
/// Display only. Values come from the same loader as Nuna Today; screens that already have a good
/// flow (Lab Book, Rhythm with its consent gate, Apple Health permissions, cycle, mood) open as before.
struct NunaHealthView: View {
    var initialTab = 0
    /// The vital signs page (opened from the monitor card on Today and from Me): the vital content on its own. Without it this is the
    /// sleep overview.
    var vitalsOnly = false

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @StateObject private var day = NunaTodayModel()
    @StateObject private var sleep = NunaSleepModel()
    @StateObject private var hrvS = NunaSeriesModel()
    @StateObject private var rhrS = NunaSeriesModel()
    @StateObject private var spo2S = NunaSeriesModel()
    @StateObject private var respS = NunaSeriesModel()
    @StateObject private var skinS = NunaSeriesModel()
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var hrvRange = 30
    @State private var hrvPage = 0
    @State private var rhrRange = 30
    @State private var rhrPage = 0

    @State private var tab = 0
    @State private var didSetTab = false
    @State private var legacy: Legacy?
    @State private var showCoach = false
    @State private var showSleepCoach = false
    @State private var fitSeries: [(day: String, value: Double)] = []

    private enum Legacy: String, Identifiable { case appleHealth, live, mood, cycle, breathing; var id: String { rawValue } }

    var body: some View {
        container
        .nunaTodayDestinations()
        .nunaWorkoutDestinations()
        .task(id: repo.refreshSeq) {
            if vitalsOnly {
                await day.load(repo: repo, profile: profile)
                await hrvS.load(repo: repo, key: "hrv", source: "my-whoop", days: 400)
                await rhrS.load(repo: repo, key: "rhr", source: "my-whoop", days: 400)
                await spo2S.load(repo: repo, key: "spo2", source: "my-whoop")
                await respS.load(repo: repo, key: "resp_rate", source: "my-whoop")
                await skinS.load(repo: repo, key: "skin_temp", source: "my-whoop")
                fitSeries = await repo.exploreSeries(key: "fitness_age", source: "my-whoop", days: 120)
            } else {
                await sleep.load(repo: repo)
            }
        }
        .sheet(item: $legacy) { which in
            NavigationStack {
                Group {
                    switch which {
                    case .appleHealth: AppleHealthView()
                    case .live: LiveView()
                    case .breathing: NunaBreathView().toolbar(.hidden, for: .navigationBar)
                    case .mood: ScrollView { MindSection().padding() }
                    case .cycle:
                        NunaWithApp { appModel in
                            if let cycle = appModel.cyclePhase { CycleTrackerView(result: cycle, curve: appModel.cycleCurve) }
                        }
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { legacy = nil } } }
            }
            .environmentObject(repo)
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "health") }
        .sheet(isPresented: $showSleepCoach) { NunaAnyaSheet(context: "sleep") }
    }

    @ViewBuilder private var container: some View {
        if vitalsOnly {
            NunaDetailScreen("Vital signs") { vitalTab }
        } else {
            // The sleep overview: the last seven nights, need against actual, bedtime and stages. A page of its own now that Health
            // is no longer a tab.
            NunaDetailScreen("Sleep") { sleepTab }
        }
    }

    // MARK: Tabs
    /// "Your normal range": HRV and resting heart rate against the last 30 days, with the position on a bar.
    private var rangeCard: some View {
        let statusText: String = {
            guard let hb = hrvS.band, let rb = rhrS.band, let h = day.hrv, let r = day.restingHr else {
                return String(localized: "Still learning your range")
            }
            let inH = abs(h - hb.mean) <= max(hb.sd, 1), inR = abs(r - rb.mean) <= max(rb.sd, 1)
            return inH && inR ? String(localized: "All within your range") : String(localized: "Some signals are up")
        }()
        return NunaCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Your normal range").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    NunaChip(verbatim: statusText, color: statusText == String(localized: "All within your range") ? NunaPalette.charge : nil)
                }
                rangeRow("HRV", day.hrv, "ms", hrvS.band)
                Rectangle().fill(NunaPalette.hairline).frame(height: 1)
                rangeRow("Resting HR", day.restingHr, "bpm", rhrS.band)
            }
        }
    }

    private func rangeRow(_ label: LocalizedStringKey, _ value: Double?, _ unit: String,
                          _ band: (mean: Double, sd: Double, lo: Double, hi: Double)?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Text(verbatim: fmt(value)).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
            if let band {
                NunaRangeBar(value: value, lo: band.lo, hi: band.hi, mean: band.mean)
                HStack {
                    Text(verbatim: fmt(band.lo)); Spacer()
                    Text(verbatim: String(localized: "30-day average: \(fmt(band.mean))")); Spacer()
                    Text(verbatim: fmt(band.hi))
                }
                .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
    }

    // MARK: Vital

    private var vitalTab: some View {
        VStack(spacing: NunaSpacing.section) {
            liveCard
            if coachEnabled { NunaAnyaCard(title: "Are my vitals normal today?") { showCoach = true } }
            vitalBento
            rangeCard
            fitnessCard
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    NavigationLink(value: NunaTodayRoute.rhythm) {
                        NunaListRow("Rhythm", description: "Beat-to-beat view", systemImage: "waveform.path.ecg.rectangle", showsChevron: true) {
                            NunaChip("Experimental")
                        }
                    }.buttonStyle(.plain)
                }
            }
            earlyWarningCard
        }
    }

    /// Resting heart rate in the same one-card layout as every metric detail: the reading, the W / M / 6M switch and date stepper, and the chart.
    private var rhrHero: some View {
        let d = day.restingHrDelta
        return NunaTrendDetailCard(
            caption: "Resting HR", valueText: fmt(day.restingHr), unit: "bpm",
            chip: d.flatMap { abs($0.rounded()) >= 1 ? (text: LocalizedStringKey((($0 > 0 ? "+" : "−") + "\(Int(abs($0).rounded()))") + " " + String(localized: "vs yesterday")), color: $0 < 0 ? NunaPalette.charge : NunaPalette.warning) : nil },
            series: rhrS, lineColor: NunaPalette.charge, decimals: 0, higherIsBetter: false, range: $rhrRange, page: $rhrPage)
    }

    private func metricRoute(_ key: String) -> NunaTodayRoute {
        MetricCatalog.metric(key: key, source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }

    private func linked(_ key: String, _ tile: some View) -> some View {
        NavigationLink(value: metricRoute(key)) { tile }.buttonStyle(.plain)
    }

    /// Respiratory, blood oxygen, resting heart rate, HRV and skin temperature, each with its status chip. Each opens its own chart.
    private var vitalBento: some View {
        let spo2 = day.spo2
        let spo2Chip: (LocalizedStringKey, Color)? = spo2.map { $0 >= 95 ? ("Normal", NunaPalette.charge) : ("Low", NunaPalette.warning) }
        var respChip: (LocalizedStringKey, Color)?
        if let v = day.respiratory, let b = respS.band {
            let tol = max(b.sd, 0.3)
            respChip = abs(v - b.mean) <= tol ? ("Normal", NunaPalette.charge) : (v > b.mean ? ("Above range", NunaPalette.warning) : ("Below range", NunaPalette.warning))
        }
        let skin = day.extras["skin_temp"]
        let skinChip: (LocalizedStringKey, Color)? = skin.map { abs($0) < 0.5 ? ("Small deviation", NunaPalette.charge) : ("Larger deviation", NunaPalette.warning) }
        let skinText = skin.map { (($0 >= 0 ? "+" : "−") + String(format: "%.1f", locale: AppLanguage.activeLocale, abs($0))) } ?? "–"
        let hrvB = hrvS.band
        var hrvChip: (LocalizedStringKey, Color)?
        if let v = day.hrv, let b = hrvB {
            let inRange = abs(v - b.mean) <= max(b.sd, 1)
            hrvChip = (inRange ? "In range" : (v > b.mean ? "Above range" : "Below range"), inRange ? NunaPalette.charge : NunaPalette.warning)
        }
        var rhrChip: (LocalizedStringKey, Color)?
        if let v = day.restingHr, let b = rhrS.band {
            let tol = max(b.sd, 1)
            rhrChip = abs(v - b.mean) <= tol ? ("In range", NunaPalette.charge) : (v > b.mean ? ("Above range", NunaPalette.warning) : ("Below range", NunaPalette.charge))
        }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            linked("resp_rate", NunaVitalTile(icon: "lungs", label: "Respiratory", value: fmt(day.respiratory, 1), unit: "/min", chip: respChip?.0, chipColor: respChip?.1 ?? NunaPalette.charge))
            linked("spo2", NunaVitalTile(icon: "drop", label: "Blood Oxygen", value: fmt(spo2), unit: "%", chip: spo2Chip?.0, chipColor: spo2Chip?.1 ?? NunaPalette.charge))
            linked("rhr", NunaVitalTile(icon: "heart", label: "Resting HR", value: fmt(day.restingHr), unit: "bpm", chip: rhrChip?.0, chipColor: rhrChip?.1 ?? NunaPalette.charge))
            linked("hrv", NunaVitalTile(icon: "waveform.path.ecg", label: "HRV", value: fmt(day.hrv), unit: "ms", chip: hrvChip?.0, chipColor: hrvChip?.1 ?? NunaPalette.charge))
            linked("skin_temp", NunaVitalTile(icon: "thermometer.medium", label: "Skin Temp", value: skinText, unit: "°C", chip: skinChip?.0, chipColor: skinChip?.1 ?? NunaPalette.charge))
        }
    }

    private var skinCaption: LocalizedStringKey? {
        guard let v = day.extras["skin_temp"] else { return nil }
        return abs(v) < 0.5 ? "Small deviation" : "Larger deviation"
    }

    private var hrvHero: some View {
        let b = hrvS.band
        var chip: (text: LocalizedStringKey, color: Color)?
        if let v = day.hrv, let b {
            let inRange = abs(v - b.mean) <= max(b.sd, 1)
            chip = (text: inRange ? "In range" : (v > b.mean ? "Above range" : "Below range"), color: inRange ? NunaPalette.charge : NunaPalette.warning)
        }
        return NunaTrendDetailCard(
            caption: "HRV", valueText: fmt(day.hrv), unit: "ms", chip: chip,
            note: day.hrvDelta.flatMap { abs($0.rounded()) >= 1 ? (($0 > 0 ? "+" : "−") + "\(Int(abs($0).rounded()))" + " " + String(localized: "vs yesterday")) : nil },
            series: hrvS, lineColor: NunaPalette.charge, decimals: 0, range: $hrvRange, page: $hrvPage)
    }

    private func miniStat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardTitle(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
    }

    private var stressCard: some View {
        let score = day.stress
        let level: (LocalizedStringKey, Color)? = score.map { $0 < 1 ? ("Low", NunaPalette.charge) : ($0 < 2 ? ("Medium", NunaPalette.warning) : ("High", NunaPalette.alert)) }
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: stressRoute) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            cardTitle("Stress monitor")
                            Spacer()
                            if let level { NunaChip(level.0, color: level.1) }
                        }
                        NunaHalfGauge(value: score, maxValue: 3, color: level?.1 ?? NunaPalette.textSecondary)
                            .frame(height: 112)
                            .overlay(alignment: .bottom) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(verbatim: fmt(score, 1)).font(.nuna(size: 40, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(40)).foregroundStyle(NunaPalette.textPrimary)
                                    Text(verbatim: "/ 3").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                                }
                            }
                        Text("Calculated from heart rate and HRV through the day, against your own baseline.")
                            .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }.buttonStyle(.plain)
                HStack(spacing: 10) {
                    Button { legacy = .breathing } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wind").font(.nuna(size: 14, weight: .bold))
                            Text("Breathe 5 min").font(.nuna(size: 15, weight: .bold))
                        }
                        .foregroundStyle(NunaPalette.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain)
                    NavigationLink(value: NunaTodayRoute.mood) {
                        Image(systemName: "face.smiling").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Mood check-in"))
                }
            }
        }
    }

    /// Fitness age as one quiet row: the age on the left, how it compares with the real age on the right.
    private var fitnessCard: some View {
        let fit = day.extras["fitness_age"]
        let age = profile.age
        let diff: Int? = (fit != nil && age > 0) ? Int((Double(age) - fit!).rounded()) : nil
        return NavigationLink(value: NunaTodayRoute.fitnessAge) {
            NunaCard(small: true) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "figure.run").font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        cardTitle("Fitness age")
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(verbatim: fmt(fit)).font(.nuna(size: 30, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            Text("years").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let diff {
                        Text(diff == 0 ? LocalizedStringKey("Same as your age")
                             : (diff > 0 ? LocalizedStringKey("\(diff) years younger") : LocalizedStringKey("\(-diff) years older")))
                            .font(.nuna(size: 13, weight: .heavy)).textCase(nil)
                            .foregroundStyle(diff > 0 ? NunaPalette.charge : (diff == 0 ? NunaPalette.textSecondary : NunaPalette.warning))
                    }
                    Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }.buttonStyle(.plain)
    }

    /// "Updated Saturday · 4-week trend ▼ 1 yr", from the stored weekly series.
    private var fitnessFooter: String? {
        guard let last = fitSeries.last else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        var text = ""
        if let d = f.date(from: last.day) {
            let w = DateFormatter(); w.locale = AppLanguage.activeLocale; w.setLocalizedDateFormatFromTemplate("EEEE")
            text = String(localized: "Updated \(w.string(from: d))")
        }
        if fitSeries.count >= 5 {
            let delta = last.value - fitSeries[fitSeries.count - 5].value
            let n = Int(abs(delta).rounded())
            if n >= 1 { text += (text.isEmpty ? "" : " · ") + String(localized: "4-week trend") + (delta < 0 ? " ▼ " : " ▲ ") + String(localized: "\(n) yr") }
        }
        return text.isEmpty ? nil : text
    }

    private var earlyWarningCard: some View { NunaWithApp { earlyWarningBody($0) } }

    private func earlyWarningBody(_ appModel: AppModel) -> some View {
        let raised = appModel.illnessSignal.map { $0.level != .quiet } ?? false
        let fired = (appModel.illnessSignal?.firedSignals ?? []).map { $0.lowercased() }
        func hit(_ keys: [String]) -> Bool { fired.contains { f in keys.contains { f.contains($0) } } }
        let signals: [(LocalizedStringKey, Bool)] = [
            ("Resting HR", hit(["rhr", "resting"])), ("HRV", hit(["hrv"])),
            ("Skin Temp", hit(["skin"])), ("Respiratory", hit(["respirat"])),
        ]
        return NavigationLink(value: NunaTodayRoute.earlyWarning) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: raised ? "exclamationmark.triangle" : "checkmark.shield").font(.nuna(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        cardTitle("Early warning")
                        Spacer()
                        NunaChip(raised ? "Signals are up" : "Safe", color: raised ? NunaPalette.warning : NunaPalette.charge)
                    }
                    Text(raised ? "Some signals are away from your range. Take it easy and watch how you feel."
                                : "No vital-sign warning. It takes two signals away from your range to raise a warning.")
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(0..<signals.count, id: \.self) { i in
                            HStack(spacing: 8) {
                                Image(systemName: signals[i].1 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.nuna(size: 15)).foregroundStyle(signals[i].1 ? NunaPalette.warning : NunaPalette.textSecondary)
                                Text(signals[i].0).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).frame(height: 40)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private var liveCard: some View { NunaLiveHRCard() }

    // MARK: Sleep

    private var sleepTab: some View {
        let recent = Array(sleep.nights.prefix(7).reversed())
        return VStack(spacing: NunaSpacing.section) {
            if recent.isEmpty {
                NavigationLink(value: NunaTodayRoute.sleep(0)) {
                    NunaCard { NunaListRow("Sleep", description: "No night recorded yet", systemImage: "moon.zzz.fill", showsChevron: true) }
                }.buttonStyle(.plain)
            } else {
                weekCard(recent)
                sleepRead(recent)
                needCard(recent)
                bedtimeCard(recent)
                stagesAverageCard(recent)
                napsWeekCard(recent)
                NunaSleepAlarmRows()
                NavigationLink(value: NunaTodayRoute.sleep(0)) {
                    NunaCard(small: true) { NunaListRow("See last night in detail", systemImage: "moon.zzz.fill", showsChevron: true) }
                }.buttonStyle(.plain)
            }
        }
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d)
    }

    private func weekCard(_ nights: [NunaNight]) -> some View {
        let rest = nights.compactMap { sleep.value("sleep_performance", $0) }
        let avgRest = rest.isEmpty ? nil : rest.reduce(0, +) / Double(rest.count)
        let avgSleep = nights.map(\.asleepMin).reduce(0, +) / Double(nights.count)
        let effs = nights.compactMap { sleep.efficiency($0) }
        let avgEff = effs.isEmpty ? nil : effs.reduce(0, +) / Double(effs.count)
        let wakes = nights.compactMap { $0.daily?.disturbances }.map(Double.init)
        let avgWakes = wakes.isEmpty ? nil : wakes.reduce(0, +) / Double(wakes.count)
        let top = max(nights.map(\.asleepMin).max() ?? 1, 1)
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Last 7 nights").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    if let avgRest { NunaChip(verbatim: String(localized: "Average Rest \(Int(avgRest.rounded()))%"), color: NunaPalette.restText) }
                }
                NunaColumns(items: nights.map { n in
                    NunaColumns.Item(weekday: weekday(n.wakeDate), date: n.wakeDate, fraction: n.asleepMin / top,
                                     valueText: NunaSleepFormat.duration(n.asleepMin), highlight: n.id == nights.last?.id)
                }, color: NunaPalette.rest, highlightColor: NunaPalette.restText)
                HStack(spacing: 0) {
                    miniStat("Duration", NunaSleepFormat.duration(avgSleep))
                    miniStat("Efficiency", avgEff.map { "\(Int($0.rounded()))%" } ?? "–")
                    miniStat("Wake-ups", avgWakes.map { String(format: "%.1f×", locale: AppLanguage.activeLocale, $0) } ?? "–")
                }
                .padding(.top, 4)
            }
        }
    }

    /// Anya's read of the last seven nights: how long and how well you slept on average, against what you need.
    @ViewBuilder private func sleepRead(_ nights: [NunaNight]) -> some View {
        if coachEnabled, !nights.isEmpty {
            let avg = nights.map(\.asleepMin).reduce(0, +) / Double(nights.count)
            let need = nights.last.map { sleep.need($0) }
            let rest = nights.compactMap { sleep.value("sleep_performance", $0) }
            let line: String = {
                let dur = NunaSleepFormat.duration(avg)
                guard let need, need > 0 else { return String(localized: "You slept \(dur) a night over the last \(nights.count) nights.") }
                let gap = Int((avg - need).rounded())
                if abs(gap) < 10 { return String(localized: "You slept \(dur) a night over the last \(nights.count) nights, close to what you need.") }
                let diff = NunaSleepFormat.duration(abs(Double(gap)))
                return gap < 0 ? String(localized: "You slept \(dur) a night over the last \(nights.count) nights, \(diff) short of what you need.")
                               : String(localized: "You slept \(dur) a night over the last \(nights.count) nights, \(diff) more than you need.")
            }()
            let detail: String? = rest.isEmpty ? nil : String(localized: "Average Rest \(Int((rest.reduce(0, +) / Double(rest.count)).rounded()))%")
            NunaAnyaCard(verbatim: line, detail: detail) { showSleepCoach = true }
        }
    }

    private func needCard(_ nights: [NunaNight]) -> some View {
        let avg = nights.map(\.asleepMin).reduce(0, +) / Double(nights.count)
        let need = nights.last.map { sleep.need($0) } ?? 480
        let debt = max(0, need - avg)
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Need vs actual").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    if debt >= 1 { NunaChip(verbatim: String(localized: "Sleep debt \(Int(debt.rounded())) min"), color: NunaPalette.warning) }
                }
                HStack(spacing: 0) {
                    miniStat("Need", NunaSleepFormat.duration(need)); miniStat("Average", NunaSleepFormat.duration(avg))
                }
                NunaProgressBar(fraction: avg / max(need, 1), color: NunaPalette.rest)
            }
        }
    }

    /// Bedtime to wake time for each of the 7 nights as a bar on one shared clock, and how far bedtimes spread.
    private func bedtimeCard(_ nights: [NunaNight]) -> some View {
        let cal = Calendar.current
        func hour(_ d: Date, evening: Bool) -> Double {
            let c = cal.dateComponents([.hour, .minute], from: d)
            let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
            return evening && h < 12 ? h + 24 : (evening ? h : h + 24)
        }
        let starts = nights.map { hour($0.onset, evening: true) }
        let ends = nights.map { n -> Double in
            let h = hour(n.wake, evening: false)
            return h < 24 ? h + 24 : h
        }
        let mean = starts.reduce(0, +) / Double(max(starts.count, 1))
        let sd = (starts.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(starts.count, 1))).squareRoot()
        // One shared clock: whole hours around the earliest bedtime and latest wake, five evenly spaced ticks.
        let lo = floor((starts.min() ?? 21) - 0.25), hi = ceil((ends.max() ?? 32) + 0.25)
        let span = max(hi - lo, 1)
        let ticks = (0...4).map { lo + span * Double($0) / 4 }
        func tickLabel(_ h: Double) -> String {
            let half = (h * 2).rounded() / 2
            let hh = Int(half) % 24, mm = half.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 30
            return String(format: "%02d:%02d", hh, mm)
        }
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    cardTitle("Bedtime consistency")
                    Spacer()
                    NunaChip(verbatim: String(localized: "Spread \(Int((sd * 60).rounded())) min"), color: NunaPalette.restText)
                }
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        ForEach(nights.indices, id: \.self) { i in
                            Text(verbatim: weekday(nights[i].wakeDate)).font(.nuna(size: 12, weight: .semibold))
                                .foregroundStyle(NunaPalette.textSecondary).frame(width: 30, height: 34, alignment: .leading).textCase(nil)
                        }
                    }
                    GeometryReader { geo in
                        let w = geo.size.width
                        ZStack(alignment: .topLeading) {
                            ForEach(1..<4, id: \.self) { t in
                                Rectangle().fill(NunaPalette.hairlineSoft).frame(width: 1, height: geo.size.height)
                                    .offset(x: w * CGFloat(t) / 4)
                            }
                            ForEach(nights.indices, id: \.self) { i in
                                let x0 = w * CGFloat((starts[i] - lo) / span)
                                let x1 = w * CGFloat((min(ends[i], hi) - lo) / span)
                                RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.glass).frame(width: w, height: 16).offset(y: CGFloat(i) * 34 + 9)
                                RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.rest).frame(width: max(8, x1 - x0), height: 16)
                                    .offset(x: x0, y: CGFloat(i) * 34 + 9)
                            }
                        }
                    }
                    .frame(height: CGFloat(nights.count) * 34)
                }
                HStack(spacing: 10) {
                    Color.clear.frame(width: 30, height: 1)
                    GeometryReader { geo in
                        ForEach(0..<ticks.count, id: \.self) { t in
                            let label = tickLabel(ticks[t])
                            Text(verbatim: label).font(.nuna(size: 11, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(NunaPalette.textSecondary).fixedSize()
                                .position(x: min(max(geo.size.width * CGFloat(t) / 4, 18), geo.size.width - 18), y: 8)
                        }
                    }
                    .frame(height: 16)
                }
            }
        }
    }

    private func stagesAverageCard(_ nights: [NunaNight]) -> some View {
        let n = Double(nights.count)
        let avg = Stages(awake: nights.map { $0.stages.awake }.reduce(0, +) / n, light: nights.map { $0.stages.light }.reduce(0, +) / n,
                         deep: nights.map { $0.stages.deep }.reduce(0, +) / n, rem: nights.map { $0.stages.rem }.reduce(0, +) / n)
        let typ = sleep.typical()
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Average stages").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    Text("Marker = your usual").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                stageLine(.deep, avg.deep, typ?.deep, avg.total)
                stageLine(.rem, avg.rem, typ?.rem, avg.total)
                stageLine(.light, avg.light, typ?.light, avg.total)
            }
        }
    }

    private func napTitle(_ nap: NunaNap) -> String { weekday(nap.start) + " " + NunaSleepFormat.clock(nap.start) }

    private func stageLine(_ stage: SleepStage, _ minutes: Double, _ typical: Double?, _ total: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stage.nunaName).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Text(verbatim: NunaSleepFormat.duration(minutes)).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            }
            NunaRangeBar(value: minutes, lo: 0, hi: max(total / 2, 1), mean: typical, color: stage.nunaColor, showsMarkerDot: false)
        }
    }

    private func napsWeekCard(_ nights: [NunaNight]) -> some View {
        let napItems: [(night: NunaNight, nap: NunaNap)] = nights.flatMap { n in n.naps.map { (n, $0) } }
        let naps = napItems.map(\.nap)
        return NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 18, bottom: 6, trailing: 18)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Naps").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    Text(verbatim: String(localized: "This week · \(naps.count)")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                .padding(.bottom, 6)
                if naps.isEmpty {
                    Text("No naps this week").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).padding(.vertical, 12)
                }
                ForEach(Array(napItems.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 { NunaDivider() }
                    NavigationLink(value: NunaTodayRoute.nap(item.night.dayKey, Int(item.nap.start.timeIntervalSince1970))) {
                        NunaListRow(LocalizedStringKey(napTitle(item.nap)), subtitle: LocalizedStringKey(NunaSleepFormat.duration(item.nap.asleepMin)), systemImage: "moon", showsChevron: true) {
                            NunaChip(item.nap.manual ? "Manual" : "Auto")
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Pieces

    private var stressRoute: NunaTodayRoute {
        MetricCatalog.metric(key: "stress", source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }

    @ViewBuilder private func tile(_ label: LocalizedStringKey, _ key: String, _ value: String, _ unit: String,
                                   source: String = "my-whoop", caption: LocalizedStringKey? = nil) -> some View {
        let t = NunaStatTile(label: label, value: value, unit: value == "–" ? "" : unit, caption: caption)
        if let m = MetricCatalog.metric(key: key, source: source) {
            NavigationLink(value: NunaTodayRoute.metric(m)) { t }.buttonStyle(.plain)
        } else { t }
    }

    private func link(_ route: NunaTodayRoute, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ icon: String) -> some View {
        NavigationLink(value: route) { NunaListRow(title, description: subtitle, systemImage: icon, showsChevron: true) }.buttonStyle(.plain)
    }

    private func row(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ icon: String,
                     _ tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { NunaListRow(title, description: subtitle, systemImage: icon, tint: tint, showsChevron: true) }
            .buttonStyle(.plain)
    }

    private func fmt(_ v: Double?, _ digits: Int = 0) -> String {
        v.map { String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, $0) } ?? "–"
    }
}
#endif
