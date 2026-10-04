#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Nuna "Kesehatan": a hub with All / Vital / Body / Sleep tabs. Phase 2 of docs/nuna/IMPLEMENTATION_PLAN.md.
/// Display only. Values come from the same loader as Nuna Today; screens that already have a good
/// flow (Lab Book, Rhythm with its consent gate, Apple Health permissions, cycle, mood) open as before.
struct NunaHealthView: View {
    var initialTab = 0

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @StateObject private var day = NunaTodayModel()
    @StateObject private var sleep = NunaSleepModel()
    @StateObject private var hrvS = NunaSeriesModel()
    @StateObject private var rhrS = NunaSeriesModel()
    @StateObject private var spo2S = NunaSeriesModel()
    @StateObject private var respS = NunaSeriesModel()
    @StateObject private var skinS = NunaSeriesModel()
    @StateObject private var weightS = NunaSeriesModel()
    @StateObject private var fatS = NunaSeriesModel()
    @StateObject private var leanS = NunaSeriesModel()
    @StateObject private var kcalInS = NunaSeriesModel()
    @StateObject private var proteinS = NunaSeriesModel()
    @StateObject private var carbsS = NunaSeriesModel()
    @StateObject private var fatGS = NunaSeriesModel()
    @State private var showWaist = false
    @AppStorage(HydrationStore.enabledKey) private var hydrationEnabled = false
    @State private var waterML = 0
    @State private var weightRange = 90
    @State private var hrvRange = 14

    @State private var tab = 0
    @State private var didSetTab = false
    @State private var legacy: Legacy?
    @State private var showCoach = false
    @State private var fitSeries: [(day: String, value: Double)] = []
    @State private var lastMaxHR: (bpm: Int, sport: String)?

    private enum Legacy: String, Identifiable { case appleHealth, live, mood, cycle, breathing; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Health").font(.nuna(size: NunaTypeSize.h1, weight: .bold, design: NunaType.design))
                        .foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: "WHOOP · Apple Health").font(.nuna(size: 13, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NunaSegmented([(value: 0, title: "All"), (value: 1, title: "Vital"), (value: 2, title: "Body"), (value: 3, title: "Sleep")],
                              selection: $tab)
                switch tab {
                case 1: vitalTab
                case 2: bodyTab
                case 3: sleepTab
                default: allTab
                }
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .nunaTodayDestinations()
        .onAppear { if !didSetTab { tab = initialTab; didSetTab = true } }
        .task(id: repo.refreshSeq) {
            await day.load(repo: repo, profile: profile)
            await sleep.load(repo: repo)
            await hrvS.load(repo: repo, key: "hrv", source: "my-whoop")
            await rhrS.load(repo: repo, key: "rhr", source: "my-whoop")
            await spo2S.load(repo: repo, key: "spo2", source: "my-whoop")
            await respS.load(repo: repo, key: "resp_rate", source: "my-whoop")
            await skinS.load(repo: repo, key: "skin_temp", source: "my-whoop")
            await weightS.load(repo: repo, key: "weight", source: "apple-health", days: 400, also: nunaManualSource)
            await fatS.load(repo: repo, key: "body_fat", source: "apple-health", days: 400)
            await leanS.load(repo: repo, key: "lean_mass", source: "apple-health", days: 400)
            await kcalInS.load(repo: repo, key: "calories_in", source: "nutrition-csv", days: 30)
            await proteinS.load(repo: repo, key: "protein_g", source: "nutrition-csv", days: 30)
            await carbsS.load(repo: repo, key: "carbs_g", source: "nutrition-csv", days: 30)
            await fatGS.load(repo: repo, key: "fat_g", source: "nutrition-csv", days: 30)
            fitSeries = await repo.exploreSeries(key: "fitness_age", source: "my-whoop", days: 120)
            if let w = await repo.workoutRows().filter({ ($0.maxHr ?? 0) > 0 }).max(by: { $0.startTs < $1.startTs }), let m = w.maxHr {
                lastMaxHR = (m, w.sport.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            await reloadWater()
        }
        .sheet(item: $legacy) { which in
            NavigationStack {
                Group {
                    switch which {
                    case .appleHealth: AppleHealthView()
                    case .live: LiveView()
                    case .breathing: BreathingView()
                    case .mood: ScrollView { MindSection().padding() }
                    case .cycle:
                        if let cycle = appModel.cyclePhase { CycleTrackerView(result: cycle, curve: appModel.cycleCurve) }
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { legacy = nil } } }
            }
            .environmentObject(repo).environmentObject(appModel)
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "health") }
    }

    // MARK: Tabs
    // MARK: All

    private var allTab: some View {
        VStack(spacing: NunaSpacing.section) {
            rangeCard
            if coachEnabled { NunaAnyaCard(title: "Are my vitals normal today?") { showCoach = true } }
            vitalList
            NunaTitleRow(title: "Body") { EmptyView() }
            weightCard
            bodyPair
            strapCard
        }
    }

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
                    Text("Your normal range").font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
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
                .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }

    /// The four vitals as long rows, each compared with the night before (up or down since yesterday).
    private var vitalList: some View {
        func change(_ d: Double?, decimals: Int, upIsGood: Bool?) -> (String, Bool?)? {
            guard let d else { return nil }
            let step = decimals == 0 ? 1.0 : 0.1
            guard abs(d) >= step - 0.0001 else { return nil }
            let shown = String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, abs(d))
            return ((d > 0 ? "▲ " : "▼ ") + shown, upIsGood.map { d > 0 ? $0 : !$0 })
        }
        func route(_ key: String) -> NunaTodayRoute? { MetricCatalog.metric(key: key, source: "my-whoop").map { .metric($0) } }
        let h = change(day.hrvDelta, decimals: 0, upIsGood: true)
        let r = change(day.restingHrDelta, decimals: 0, upIsGood: false)
        let o = change(day.spo2Delta, decimals: 0, upIsGood: true)
        let b = change(day.respiratoryDelta, decimals: 1, upIsGood: nil)
        let cap: LocalizedStringKey = "vs yesterday"
        return NunaMetricsGrid(tiles: [
            NunaMetricTile(id: "hrv", label: "HRV", value: fmt(day.hrv), unit: "ms", route: route("hrv"), delta: h?.0, deltaGood: h?.1, icon: "waveform.path.ecg", caption: cap),
            NunaMetricTile(id: "rhr", label: "Resting HR", value: fmt(day.restingHr), unit: "bpm", route: route("rhr"), delta: r?.0, deltaGood: r?.1, icon: "heart", caption: cap),
            NunaMetricTile(id: "spo2", label: "Blood Oxygen", value: fmt(day.spo2), unit: "%", route: route("spo2"), delta: o?.0, deltaGood: o?.1, icon: "drop", caption: cap),
            NunaMetricTile(id: "resp", label: "Respiratory", value: fmt(day.respiratory, 1), unit: "/min", route: route("resp_rate"), delta: b?.0, deltaGood: b?.1, icon: "wind", caption: cap),
        ], layout: .list)
    }

    /// "Stable" when the value sits inside the person's own recent range, otherwise up or down.
    private func bandCaption(_ v: Double?, _ s: NunaSeriesModel) -> LocalizedStringKey? {
        guard let v, let b = s.band else { return nil }
        let tol = max(b.sd, 0.3)
        return abs(v - b.mean) <= tol ? "Stable" : (v > b.mean ? "Above range" : "Below range")
    }

    /// Weight with its last 30 days, as on the Body tab but fixed to 30D.
    private var weightCard: some View {
        let pts = weightS.readings(30)
        let latest = weightS.latest?.value ?? (profile.weightKg > 0 ? profile.weightKg : nil)
        let delta: Double? = pts.count >= 2 ? pts.last!.value - pts.first!.value : nil
        return NavigationLink(value: weightRoute) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Weight").font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Spacer()
                        Text("30D").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: fmt(latest, 1)).font(.nuna(size: 48, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text("kg").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        Spacer()
                        if let delta {
                            NunaChip(verbatim: (delta <= 0 ? "−" : "+") + String(format: "%.1f", locale: AppLanguage.activeLocale, abs(delta)) + " kg")
                        }
                    }
                    NunaLine2Chart(points: pts, color: NunaPalette.ink, decimals: 1, height: 160)
                }
            }
        }.buttonStyle(.plain)
    }

    private var weightRoute: NunaTodayRoute { .weight }

    /// Waist and BMI side by side under the weight card.
    private var bodyPair: some View {
        let w = weightS.latest?.value ?? (profile.weightKg > 0 ? profile.weightKg : nil)
        let h = profile.heightCm
        let bmi: Double? = (w != nil && h > 0) ? w! / pow(h / 100, 2) : nil
        return HStack(spacing: 12) {
            NunaStatTile(label: "Waist", value: profile.waistCm > 0 ? fmt(profile.waistCm) : "–", unit: profile.waistCm > 0 ? "cm" : "")
            NunaStatTile(label: "BMI", value: fmt(bmi, 1))
        }
    }

    /// Change in weight over the last 30 days, from stored readings only.
    private var weightDeltaCaption: LocalizedStringKey? {
        let r = weightS.readings(30)
        guard let first = r.first?.value, let last = r.last?.value, r.count >= 2 else { return nil }
        let d = last - first
        let t = String(format: "%.1f", locale: AppLanguage.activeLocale, abs(d))
        return d <= 0 ? LocalizedStringKey("Down \(t) kg in 30 days") : LocalizedStringKey("Up \(t) kg in 30 days")
    }

    private var strapCard: some View {
        Button { router.openDevices() } label: {
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    NunaIconTile("applewatch")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WHOOP strap").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text(live.connected ? "Connected" : "Not connected").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let b = live.batteryPct {
                            Text(verbatim: "\(Int(b.rounded()))%").font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        }
                        if let t = live.lastSyncedAt {
                            Text(verbatim: String(localized: "Synced \(NunaSleepFormat.clock(Date(timeIntervalSince1970: t)))"))
                                .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                    Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }.buttonStyle(.plain)
    }

    // MARK: Vital

    private var vitalTab: some View {
        VStack(spacing: NunaSpacing.section) {
            liveCard
            hrvHero
            rhrHero
            vitalBento
            stressCard
            fitnessCard
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    NavigationLink(value: NunaTodayRoute.rhythm) {
                        NunaListRow("Rhythm", subtitle: "Beat-to-beat view", systemImage: "waveform.path.ecg.rectangle", showsChevron: true) {
                            NunaChip("Experimental")
                        }
                    }.buttonStyle(.plain)
                }
            }
            earlyWarningCard
        }
    }

    private var rhrHero: some View {
        let pts = rhrS.readings(14)
        let d = day.restingHrDelta
        return NavigationLink(value: metricRoute("rhr")) {
            NunaCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        cardTitle("Resting HR")
                        Spacer()
                        if let d, abs(d.rounded()) >= 1 {
                            NunaChip(verbatim: (d > 0 ? "+" : "−") + "\(Int(abs(d).rounded()))" + String(localized: " vs yesterday"),
                                     color: d < 0 ? NunaPalette.charge : NunaPalette.warning)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: fmt(day.restingHr)).font(.nuna(size: 56, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text("bpm").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    NunaLine2Chart(points: pts, color: NunaPalette.ink, decimals: 0, baseline: rhrS.band?.mean, height: 120)
                }
            }
        }.buttonStyle(.plain)
    }

    private func metricRoute(_ key: String) -> NunaTodayRoute {
        MetricCatalog.metric(key: key, source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }

    private func linked(_ key: String, _ tile: some View) -> some View {
        NavigationLink(value: metricRoute(key)) { tile }.buttonStyle(.plain)
    }

    /// SpO2, respiratory, skin temperature and the highest recent heart rate, each with its status chip.
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
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            linked("spo2", NunaVitalTile(icon: "drop", label: "SpO₂", value: fmt(spo2), unit: "%", chip: spo2Chip?.0, chipColor: spo2Chip?.1 ?? NunaPalette.charge))
            linked("resp_rate", NunaVitalTile(icon: "wind", label: "Respiratory", value: fmt(day.respiratory, 1), unit: "/min", chip: respChip?.0, chipColor: respChip?.1 ?? NunaPalette.charge))
            linked("skin_temp", NunaVitalTile(icon: "thermometer.medium", label: "Skin Temp", value: skinText, unit: "°C", chip: skinChip?.0, chipColor: skinChip?.1 ?? NunaPalette.charge))
            NunaVitalTile(icon: "bolt.heart", label: "Max HR", value: lastMaxHR.map { String($0.bpm) } ?? "–", unit: "bpm", note: lastMaxHR?.sport)
        }
    }

    private var skinCaption: LocalizedStringKey? {
        guard let v = day.extras["skin_temp"] else { return nil }
        return abs(v) < 0.5 ? "Small deviation" : "Larger deviation"
    }

    private var hrvHero: some View {
        let pts = hrvS.readings(hrvRange)
        let b = hrvS.band
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("HRV · average last night").font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    if let v = day.hrv, let b {
                        let inRange = abs(v - b.mean) <= max(b.sd, 1)
                        NunaChip(inRange ? "In range" : (v > b.mean ? "Above range" : "Below range"), color: inRange ? NunaPalette.charge : NunaPalette.warning)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: fmt(day.hrv)).font(.nuna(size: 56, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text("ms").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    if let d = day.hrvDelta, abs(d.rounded()) >= 1 {
                        NunaChip(verbatim: (d > 0 ? "+" : "−") + "\(Int(abs(d).rounded()))" + String(localized: " vs yesterday"),
                                 color: d > 0 ? NunaPalette.charge : NunaPalette.warning)
                    }
                }
                NunaSegmented([(value: 14, title: "14D"), (value: 30, title: "30D"), (value: 90, title: "90D")], selection: $hrvRange)
                NunaLine2Chart(points: pts, color: NunaPalette.ink, decimals: 0, baseline: b?.mean, height: 170)
                if let b {
                    HStack(spacing: 12) {
                        miniStat("Average", fmt(b.mean)); miniStat("Lowest", fmt(b.lo)); miniStat("Highest", fmt(b.hi))
                    }
                }
            }
        }
    }

    private func miniStat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardTitle(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
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
                                    Text(verbatim: fmt(score, 1)).font(.nuna(size: 40, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                    Text(verbatim: "/ 3").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                                }
                            }
                        Text("Calculated from heart rate and HRV through the day, against your own baseline.")
                            .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
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
                            .frame(width: 48, height: 48).background(NunaPalette.glassStrong, in: Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Mood check-in"))
                }
            }
        }
    }

    private var fitnessCard: some View {
        let fit = day.extras["fitness_age"]
        let age = profile.age
        let diff: Int? = (fit != nil && age > 0) ? Int((Double(age) - fit!).rounded()) : nil
        return NavigationLink(value: NunaTodayRoute.fitnessAge) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        cardTitle("Fitness age")
                        Spacer()
                        NunaChip("Estimate ±5 years")
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: fmt(fit)).font(.nuna(size: 52, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text("years").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        Spacer()
                        if let diff, diff != 0 {
                            NunaChip(diff > 0 ? LocalizedStringKey("\(diff) years younger") : LocalizedStringKey("\(-diff) years older"),
                                     color: diff > 0 ? NunaPalette.charge : NunaPalette.warning)
                        }
                    }
                    if age > 0 {
                        Text(verbatim: String(localized: "Actual age \(age)")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    if let fit, age > 0 { NunaAgeSlider(fitness: fit, age: Double(age)) }
                    if let note = fitnessFooter {
                        Text(verbatim: note).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                    }
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

    private var earlyWarningCard: some View {
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
                                : "No signs of strain. It takes two signals away from your range to raise a warning.")
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(0..<signals.count, id: \.self) { i in
                            HStack(spacing: 8) {
                                Image(systemName: signals[i].1 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.nuna(size: 15)).foregroundStyle(signals[i].1 ? NunaPalette.warning : NunaPalette.textSecondary)
                                Text(signals[i].0).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).frame(height: 40)
                            .background(NunaPalette.glassStrong, in: Capsule())
                        }
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private var liveCard: some View { NunaLiveHRCard() }

    // MARK: Body

    private var bodyTab: some View {
        VStack(spacing: NunaSpacing.section) {
            weightHero
            compositionCard
            waistCard
            nutritionCard
            if hydrationEnabled { waterCard }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    link(.labBook, "Lab Book", "Your records", "cross.vial.fill")
                    NunaDivider()
                    link(.mood, "Mood check-in", "How are you feeling", "face.smiling")
                    if appModel.cyclePhase != nil {
                        NunaDivider()
                        link(.cycle, "Menstrual cycle", "Cycle awareness", "drop.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showWaist) { NunaWaistSheet() }
    }

    private var weightHero: some View {
        let pts = weightS.readings(weightRange)
        let latest = weightS.latest?.value
        let delta: Double? = (pts.count >= 2) ? (pts.last!.value - pts.first!.value) : nil
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: NunaTodayRoute.weight) {
                    HStack {
                        Text("Weight").font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Spacer()
                        Text("Details").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        Image(systemName: "chevron.right").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                }.buttonStyle(.plain)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: fmt(latest, 1)).font(.nuna(size: 56, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text("kg").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    if let delta {
                        NunaChip(verbatim: (delta <= 0 ? "−" : "+") + String(format: "%.1f", locale: AppLanguage.activeLocale, abs(delta)) + " kg")
                    }
                }
                NunaSegmented([(value: 30, title: "30D"), (value: 90, title: "90D"), (value: 365, title: "1Y")], selection: $weightRange)
                NunaLine2Chart(points: pts, color: NunaPalette.ink, decimals: 1, height: 170)
                Text("Read from Apple Health, or typed in under Details.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }

    private var compositionCard: some View {
        let w = weightS.latest?.value ?? (profile.weightKg > 0 ? profile.weightKg : nil)
        let h = profile.heightCm
        let bmi: Double? = (w != nil && h > 0) ? w! / pow(h / 100, 2) : nil
        let fat = fatS.latest?.value, lean = leanS.latest?.value
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("Body composition")
                if let fat, let lean, let w, w > 0 {
                    let fatShare = max(0, min(100, fat)), leanShare = max(0, min(100 - fatShare, lean / w * 100))
                    NunaProportionBar(parts: [(fatShare, NunaPalette.warning), (leanShare, NunaPalette.charge), (max(0, 100 - fatShare - leanShare), NunaPalette.zoneBase)], height: 16)
                    HStack {
                        Text(verbatim: String(localized: "Fat \(Int(fat.rounded()))%")); Spacer()
                        Text(verbatim: String(localized: "Lean mass \(Int(lean.rounded())) kg"))
                    }
                    .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                HStack(spacing: 10) {
                    miniTile("Body fat", fat.map { fmt($0, 1) } ?? "–", fat == nil ? "" : "%")
                    miniTile("Lean mass", lean.map { fmt($0, 1) } ?? "–", lean == nil ? "" : "kg")
                    miniTile("BMI", fmt(bmi, 1), "")
                }
            }
        }
    }

    private func miniTile(_ label: LocalizedStringKey, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.glass, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(NunaPalette.hairlineSoft, lineWidth: 1))
    }

    private var waistCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: NunaTodayRoute.waist) {
                    HStack(spacing: 12) {
                        NunaIconTile("ruler")
                        VStack(alignment: .leading, spacing: 2) {
                            cardTitle("Waist")
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(verbatim: profile.waistCm > 0 ? fmt(profile.waistCm) : "–").font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                if profile.waistCm > 0 { Text("cm").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                }.buttonStyle(.plain)
                Text("Reads the latest value from Apple Health and fills your profile for the VO₂max estimate.")
                    .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                Button { showWaist = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.nuna(size: 13, weight: .bold))
                        Text("Add a manual measurement").font(.nuna(size: 15, weight: .bold))
                    }
                    .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 46)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    private var nutritionCard: some View {
        let kcalIn = kcalInS.latest
        let macros: [(LocalizedStringKey, Double?, Double, Color)] = [
            ("Protein", proteinS.latest?.value, 4, NunaPalette.charge),
            ("Carbs", carbsS.latest?.value, 4, NunaPalette.effort),
            ("Fat", fatGS.latest?.value, 9, NunaPalette.warning),
        ]
        return NavigationLink(value: NunaTodayRoute.nutrition) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        cardTitle("Nutrition")
                        Spacer()
                        NunaChip("Import CSV")
                    }
                    if let kcalIn {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: fmt(kcalIn.value)).font(.nuna(size: 40, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            Text("kcal in").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            Spacer()
                            if let out = day.calories { Text(verbatim: String(localized: "Out \(fmt(out))")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                        }
                        if let out = day.calories, out > 0 { NunaProgressBar(fraction: min(kcalIn.value / out, 1), color: NunaPalette.warning) }
                        VStack(spacing: 12) {
                            ForEach(0..<macros.count, id: \.self) { i in
                                if let g = macros[i].1 {
                                    VStack(spacing: 6) {
                                        HStack {
                                            Text(macros[i].0).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                            Spacer()
                                            Text(verbatim: "\(fmt(g)) g").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                        }
                                        NunaProgressBar(fraction: kcalIn.value > 0 ? g * macros[i].2 / kcalIn.value : 0, color: macros[i].3)
                                    }
                                }
                            }
                        }
                        Text(verbatim: kcalIn.day + " · " + String(localized: "Bars show each macro's share of calories")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    } else {
                        Text("No nutrition imported yet. Import a CSV from Cronometer or MacroFactor, processed on this phone.")
                            .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private var waterCard: some View {
        let goal = repo.hydrationGoalML(profileSex: profile.sex)
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Water").font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, Double(waterML) / 1000))
                        .font(.nuna(size: NunaTypeSize.numberL, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: "/ " + String(format: "%.1f", locale: AppLanguage.activeLocale, Double(goal) / 1000) + " L")
                        .font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
                NunaProgressBar(fraction: Double(waterML) / Double(max(goal, 1)), color: NunaPalette.effort)
                HStack(spacing: 10) {
                    Button("+250") { Task { await addWater(250) } }.buttonStyle(.nuna(.ghost, height: 44, fullWidth: true))
                    Button("+500") { Task { await addWater(500) } }.buttonStyle(.nuna(.ghost, height: 44, fullWidth: true))
                }
            }
        }
    }

    private func reloadWater() async {
        guard hydrationEnabled else { return }
        waterML = Int(await repo.hydrationTotal(day: Repository.localDayKey(Date())))
    }

    private func addWater(_ ml: Int) async {
        _ = await repo.logHydration(amountMl: ml)
        repo.noteHydrationChanged()
        await reloadWater()
    }

    // MARK: Sleep

    private var sleepTab: some View {
        let recent = Array(sleep.nights.prefix(7).reversed())
        return VStack(spacing: NunaSpacing.section) {
            if recent.isEmpty {
                NavigationLink(value: NunaTodayRoute.sleep(0)) {
                    NunaCard { NunaListRow("Sleep", subtitle: "No night recorded yet", systemImage: "moon.zzz.fill", showsChevron: true) }
                }.buttonStyle(.plain)
            } else {
                weekCard(recent)
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
                    Text("Last 7 nights").font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
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

    private func needCard(_ nights: [NunaNight]) -> some View {
        let avg = nights.map(\.asleepMin).reduce(0, +) / Double(nights.count)
        let need = nights.last.map { sleep.need($0) } ?? 480
        let debt = max(0, need - avg)
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Need vs actual").font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
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
                                .foregroundStyle(NunaPalette.textSecondary).frame(width: 30, height: 34, alignment: .leading)
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
                                Capsule().fill(NunaPalette.glass).frame(width: w, height: 16).offset(y: CGFloat(i) * 34 + 9)
                                Capsule().fill(NunaPalette.rest).frame(width: max(8, x1 - x0), height: 16)
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
                    Text("Average stages").font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    Text("Marker = your usual").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
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
        let naps = nights.flatMap(\.naps)
        return NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 18, bottom: 6, trailing: 18)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Naps").font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    Text(verbatim: String(localized: "This week · \(naps.count)")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                .padding(.bottom, 6)
                if naps.isEmpty {
                    Text("No naps this week").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).padding(.vertical, 12)
                }
                ForEach(Array(naps.enumerated()), id: \.offset) { idx, nap in
                    if idx > 0 { NunaDivider() }
                    NunaListRow(LocalizedStringKey(napTitle(nap)), subtitle: LocalizedStringKey(NunaSleepFormat.duration(nap.asleepMin)), systemImage: "moon") {
                        NunaChip(nap.manual ? "Manual" : "Auto")
                    }
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
        NavigationLink(value: route) { NunaListRow(title, subtitle: subtitle, systemImage: icon, showsChevron: true) }.buttonStyle(.plain)
    }

    private func row(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ icon: String,
                     _ tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { NunaListRow(title, subtitle: subtitle, systemImage: icon, tint: tint, showsChevron: true) }
            .buttonStyle(.plain)
    }

    private func fmt(_ v: Double?, _ digits: Int = 0) -> String {
        v.map { String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, $0) } ?? "–"
    }
}
#endif
