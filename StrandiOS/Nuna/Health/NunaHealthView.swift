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

    @State private var tab = 0
    @State private var legacy: Legacy?
    @State private var showCoach = false

    private enum Legacy: String, Identifiable { case appleHealth, live, mood, cycle; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Health").font(.system(size: NunaTypeSize.h1, weight: .bold, design: .rounded))
                        .foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: "WHOOP · Apple Health").font(.system(size: 13, weight: .semibold))
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
                if coachEnabled { NunaAnyaCard(title: "Are my vitals normal today?") { showCoach = true } }
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .nunaTodayDestinations()
        .onAppear { tab = initialTab }
        .task(id: repo.refreshSeq) {
            await day.load(repo: repo, profile: profile)
            await sleep.load(repo: repo)
        }
        .sheet(item: $legacy) { which in
            NavigationStack {
                Group {
                    switch which {
                    case .appleHealth: AppleHealthView()
                    case .live: LiveView()
                    case .mood: ScrollView { MindSection().padding() }
                    case .cycle:
                        if let cycle = appModel.cyclePhase { CycleTrackerView(result: cycle, curve: appModel.cycleCurve) }
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { legacy = nil } } }
            }
            .environmentObject(repo).environmentObject(appModel)
        }
        .sheet(isPresented: $showCoach) { CoachLauncherSheet(context: "health") }
    }

    // MARK: Tabs

    private var allTab: some View {
        VStack(spacing: NunaSpacing.section) {
            rangeCard
            vitalGrid
            NunaSectionHeader("Body")
            bodyGrid
            appleHealthCard
            strapCard
        }
    }

    private var vitalTab: some View {
        VStack(spacing: NunaSpacing.section) {
            liveCard
            vitalGrid
            NavigationLink(value: stressRoute) {
                NunaCard(small: true) {
                    NunaListRow("Stress monitor", subtitle: "Autonomic load, 0 to 3", systemImage: "wind", tint: NunaPalette.charge, showsChevron: true) {
                        Text(verbatim: fmt(day.stress, 1)).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                    }
                }
            }.buttonStyle(.plain)
            NavigationLink(value: NunaTodayRoute.fitnessAge) {
                NunaCard(small: true) {
                    NunaListRow("Fitness age", subtitle: "Estimate, plus or minus 5 years", systemImage: "figure.run", showsChevron: true) {
                        Text(verbatim: fmt(day.extras["fitness_age"])).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                    }
                }
            }.buttonStyle(.plain)
            card {
                row("Rhythm", "Beat-to-beat view. Experimental", "waveform.path.ecg.rectangle") { router.requestedDestination = .rhythm }
                NunaDivider()
                if let warn = appModel.illnessSignal, warn.level != .quiet {
                    NavigationLink(value: NunaTodayRoute.earlyWarning) {
                        NunaListRow("Early warning", subtitle: "Signals are up", systemImage: "exclamationmark.triangle.fill", tint: NunaPalette.warning, showsChevron: true)
                    }.buttonStyle(.plain)
                } else {
                    NavigationLink(value: NunaTodayRoute.earlyWarning) {
                        NunaListRow("Early warning", subtitle: "Nothing unusual", systemImage: "checkmark.shield.fill", tint: NunaPalette.charge, showsChevron: true)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var bodyTab: some View {
        VStack(spacing: NunaSpacing.section) {
            bodyGrid
            card {
                row("Mood check-in", "How are you feeling", "face.smiling") { legacy = .mood }
                NunaDivider()
                NavigationLink(value: TabRoute.dataSources) {
                    NunaListRow("Nutrition", subtitle: "Calories in, from an import", systemImage: "fork.knife", showsChevron: true)
                }.buttonStyle(.plain)
                NunaDivider()
                row("Lab Book", "Your records", "cross.vial.fill") { router.requestedDestination = .labBook }
                if appModel.cyclePhase != nil {
                    NunaDivider()
                    row("Menstrual cycle", "Cycle awareness", "drop.fill") { legacy = .cycle }
                }
                NunaDivider()
                row("Apple Health permissions", "What PHMNOOP reads and writes", "heart.text.square.fill") { legacy = .appleHealth }
            }
        }
    }

    private var sleepTab: some View {
        VStack(spacing: NunaSpacing.section) {
            if let night = sleep.night {
                NavigationLink(value: NunaTodayRoute.sleep(0)) {
                    NunaCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Last night").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                                    .foregroundStyle(NunaPalette.textSecondary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(verbatim: NunaSleepFormat.duration(night.asleepMin))
                                    .font(.system(size: NunaTypeSize.numberL, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                                if let r = sleep.value("sleep_performance") {
                                    NunaChip(verbatim: "Rest \(Int(r.rounded()))%", color: NunaPalette.restText)
                                }
                            }
                            if night.intervals.isEmpty { NunaStageSplitBar(stages: night.stages) }
                            else { NunaHypnogramStrip(intervals: night.intervals, height: 72) }
                        }
                    }
                }.buttonStyle(.plain)
                card {
                    NavigationLink(value: NunaTodayRoute.sleepStages(0)) { NunaListRow("Sleep stages", systemImage: "chart.bar.fill", tint: NunaPalette.restText, showsChevron: true) }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaTodayRoute.sleepVitals(0)) { NunaListRow("Overnight vitals", systemImage: "waveform.path.ecg", tint: NunaPalette.restText, showsChevron: true) }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaTodayRoute.sleepPerformance(0)) { NunaListRow("Need and debt", systemImage: "gauge.medium", tint: NunaPalette.restText, showsChevron: true) }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaTodayRoute.sleepNaps(0)) { NunaListRow("Naps", systemImage: "zzz", tint: NunaPalette.restText, showsChevron: true) }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaTodayRoute.bodyClock) { NunaListRow("Body clock", systemImage: "timer", tint: NunaPalette.restText, showsChevron: true) }.buttonStyle(.plain)
                }
            } else {
                NavigationLink(value: NunaTodayRoute.sleep(0)) {
                    NunaCard { NunaListRow("Sleep", subtitle: "No night recorded yet", systemImage: "moon.zzz.fill", tint: NunaPalette.restText, showsChevron: true) }
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: Pieces

    private var stressRoute: NunaTodayRoute {
        MetricCatalog.metric(key: "stress", source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }

    private var rangeCard: some View {
        NunaCard(small: true, highlight: true) {
            HStack(spacing: 12) {
                NunaIconTile("checkmark.seal.fill", tint: NunaPalette.charge)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your normal range").font(.system(size: 11, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Text(verbatim: appModel.illnessSignal.map { $0.level == .quiet ? String(localized: "All within your range") : String(localized: "Some signals are up") } ?? String(localized: "Still learning your range"))
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                }
                Spacer()
            }
        }
    }

    private var liveCard: some View {
        Button { legacy = .live } label: {
            NunaCard {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Live heart rate").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: "heart.fill").foregroundStyle(NunaPalette.alertText)
                            Text(verbatim: live.heartRate.map(String.init) ?? "–")
                                .font(.system(size: NunaTypeSize.numberL, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                            Text("bpm").font(.system(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                    Spacer()
                    NunaChip(live.connected ? "Strap connected" : "Not connected", color: live.connected ? NunaPalette.charge : NunaPalette.warning)
                }
            }
        }.buttonStyle(.plain)
    }

    private var vitalGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile("HRV", "hrv", fmt(day.hrv), "ms")
            tile("Resting HR", "rhr", fmt(day.restingHr), "bpm")
            tile("Blood Oxygen", "spo2", fmt(day.spo2), "%")
            tile("Respiratory", "resp_rate", fmt(day.respiratory, 1), "/min")
            tile("Skin Temp", "skin_temp", fmt(day.extras["skin_temp"], 1), "°C")
        }
    }

    private var bodyGrid: some View {
        let h = profile.heightCm
        let w = day.extras["weight"] ?? (profile.weightKg > 0 ? profile.weightKg : nil)
        let bmi: Double? = (w != nil && h > 0) ? w! / pow(h / 100, 2) : nil
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile("Weight", "weight", fmt(w, 1), "kg", source: "apple-health")
            NunaStatTile(label: "Waist", value: profile.waistCm > 0 ? fmt(profile.waistCm) : "–", unit: "cm")
            NunaStatTile(label: "BMI", value: fmt(bmi, 1))
        }
    }

    private var appleHealthCard: some View {
        card {
            row("Apple Health", "Steps, weight and waist", "heart.text.square.fill", NunaPalette.alertText) { legacy = .appleHealth }
        }
    }

    private var strapCard: some View {
        Button { router.openDevices() } label: {
            NunaCard(small: true) {
                NunaListRow("WHOOP strap", subtitle: live.connected ? "Connected" : "Not connected", systemImage: "applewatch", showsChevron: true) {
                    if let b = live.batteryPct { Text(verbatim: "\(Int(b.rounded()))%").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary) }
                }
            }
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func tile(_ label: LocalizedStringKey, _ key: String, _ value: String, _ unit: String,
                                   source: String = "my-whoop") -> some View {
        let t = NunaStatTile(label: label, value: value, unit: value == "–" ? "" : unit)
        if let m = MetricCatalog.metric(key: key, source: source) {
            NavigationLink(value: NunaTodayRoute.metric(m)) { t }.buttonStyle(.plain)
        } else { t }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        NunaCard(small: true) { VStack(spacing: 0) { content() } }
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

// MARK: - Fitness age

/// Weekly fitness comparison (docs/FITNESS_AGE.md): a number with a plus or minus 5 year band, against
/// the real age. It is a comparison, not a biological age. Reads the stored weekly series only.
struct NunaFitnessAgeView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var series: [(day: String, value: Double)] = []
    @State private var vo2: Double?
    @State private var loaded = false

    var body: some View {
        NunaScreen("Fitness age") {
            if let latest = series.last {
                let age = Double(profile.age)
                let diff = age > 0 ? age - latest.value : nil
                NunaCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: String(format: "%.0f", locale: AppLanguage.activeLocale, latest.value))
                                .font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                            Text("years").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            Spacer()
                            NunaChip("Estimate ±5 years")
                        }
                        if let diff {
                            let r = Int(abs(diff).rounded())
                            Text(verbatim: r == 0 ? String(localized: "About the same as your age")
                                 : (diff > 0 ? String(localized: "\(r) years younger than your age")
                                    : String(localized: "\(r) years older than your age")))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(diff >= 0 ? NunaPalette.charge : NunaPalette.warning)
                            band(latest.value, age)
                        }
                        Text(verbatim: String(localized: "Updated \(latest.day)")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                if let vo2 {
                    NunaStatTile(label: "VO₂ max (estimated)", value: String(format: "%.1f", locale: AppLanguage.activeLocale, vo2), unit: "ml/kg/min")
                }
                if series.count > 1 {
                    NunaCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Last weeks").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                            NunaBars(values: series.suffix(12).map { Optional($0.value) }, color: NunaPalette.charge, average: nil).frame(height: 100)
                        }
                    }
                }
            } else {
                NunaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loaded ? "Not ready yet" : " ").font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Fitness age needs your age, your sex and resting heart rate from at least 4 nights. It updates once a week.")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("This is a fitness comparison, not your biological age. It has no medical meaning.")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
        }
        .task(id: repo.refreshSeq) {
            series = await repo.exploreSeries(key: "fitness_age", source: "my-whoop", days: 120)
            vo2 = await repo.exploreSeries(key: "vo2max_est", source: "my-whoop", days: 60).last?.value
            loaded = true
        }
    }

    /// Plus or minus 5 years around the estimate, with the real age marked.
    private func band(_ fitness: Double, _ age: Double) -> some View {
        let lo = min(fitness - 5, age) - 3, hi = max(fitness + 5, age) + 3
        let span = max(hi - lo, 1)
        return GeometryReader { geo in
            let x: (Double) -> CGFloat = { CGFloat(($0 - lo) / span) * geo.size.width }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.09)).frame(height: 10)
                Capsule().fill(NunaPalette.charge.opacity(0.55)).frame(width: x(fitness + 5) - x(fitness - 5), height: 10)
                    .offset(x: x(fitness - 5))
                Circle().fill(.white).frame(width: 16, height: 16).offset(x: x(age) - 8)
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}
#endif
