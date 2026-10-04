#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Training load (TrainingLoad / TrainingLoadCardio / TrainingLoadMuscle). Cardio load is the daily Effort, run through the
/// existing chronic / acute model; muscular load is the volume lifted. The two are never added together.
struct NunaTrainingLoadView: View {
    @State var tab: Int
    init(tab: Int) { _tab = State(initialValue: tab) }

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @StateObject private var m = NunaWorkoutsModel()
    @State private var weeks = 5
    @State private var zoneMinutes: [Double] = [0, 0, 0, 0, 0]
    @State private var showCoach = false

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private func eff(_ v: Double) -> Double { UnitFormatter.effortValue(v, scale: scale) }

    var body: some View {
        NunaDetailScreen("Training load", onAnya: tab == 1 ? { showCoach = true } : nil) {
            NunaSegmented([(value: 0, title: "Summary"), (value: 1, title: "Cardio"), (value: 2, title: "Strength")], selection: $tab)
            switch tab {
            case 1: cardio
            case 2: muscle
            default: summary
            }
            if tab == 0 {
                NunaAnyaCard(verbatim: anyaLine) { showCoach = true }
                NavigationLink(value: NunaWorkoutRoute.calendar) {
                    NunaCard(small: true) { NunaListRow("See the workout calendar", systemImage: "calendar", showsChevron: true) }
                }.buttonStyle(.plain)
            }
        }
        .nunaWorkoutDestinations()
        .task(id: repo.refreshSeq) {
            await m.load(repo: repo)
            await loadZones()
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "workouts") }
    }

    private var anyaLine: String {
        let r = TrendInsights.loadRatio(blocks: m.weeklyEffort(weeks: 6))
        guard let r else { return String(localized: "Training load needs at least three weeks with workouts.") }
        switch TrendInsights.loadBand(r) {
        case .under: return String(localized: "Your load is below your usual. A harder session is fine if you feel good.")
        case .optimal: return String(localized: "Your load is balanced with your usual. Keep the same rhythm.")
        case .high: return String(localized: "Cardio load is above your usual. Choose an easy day next.")
        case .excessive: return String(localized: "Cardio load is well above your usual. Take a rest day.")
        }
    }

    // MARK: Summary

    private var summary: some View {
        let cardio = m.weeklyEffort(weeks: 6), vol = m.weeklyVolume(weeks: 6)
        let ratio = TrendInsights.loadRatio(blocks: cardio)
        let band = ratio.map(TrendInsights.loadBand)
        let cBand = TrendInsights.loadRatio(blocks: cardio).map(TrendInsights.loadBand)
        let vBand = TrendInsights.loadRatio(blocks: vol).map(TrendInsights.loadBand)
        let week = m.recent(days: 7)
        let lifts = m.liftSessions.filter { Double($0.startTs) >= Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970 }
        let sets = lifts.flatMap { m.liftSets[$0.id] ?? [] }.filter { !$0.isWarmup }
        let cTop = max(cardio.max() ?? 1, 1), vTop = max(vol.max() ?? 1, 1)
        return VStack(spacing: NunaSpacing.section) {
            NunaCard {
                VStack(spacing: 16) {
                    HStack { nunaTrendsCap("Last 7 days"); Spacer(); if let band { NunaChip(bandName(band), color: band == .optimal ? NunaPalette.charge : NunaPalette.warning) } }
                    HStack(alignment: .top, spacing: 0) {
                        ringColumn("Cardio", UnitFormatter.effortDisplay(cardio.last ?? 0, scale: scale), "", (cardio.last ?? 0) / cTop, NunaPalette.effort, cBand, NunaPalette.effortText)
                        ringColumn("Strength", vol.last.map { $0 >= 1000 ? String(format: "%.1f", locale: AppLanguage.activeLocale, $0 / 1000) : NunaTrendsFormat.num($0) } ?? "–", (vol.last ?? 0) >= 1000 ? "k" : "",
                                   (vol.last ?? 0) / vTop, NunaPalette.textPrimary, vBand, NunaPalette.textPrimary)
                    }
                    HStack(spacing: 10) {
                        NavigationLink(value: NunaWorkoutRoute.loadCardio) { pill("Effort · see cardio") }.buttonStyle(.plain)
                        NavigationLink(value: NunaWorkoutRoute.loadMuscle) { pill("kg · see strength") }.buttonStyle(.plain)
                    }
                }
            }
            balanceCard(ratio, band)
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { nunaTrendsCap("6 weeks"); Spacer(); Text("Top: strength · bottom: cardio").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                    weeklyPair(cardio, vol)
                    HStack(spacing: 14) { NunaLegendItem(color: NunaPalette.effort, text: "Cardio · Effort", dot: true); NunaLegendItem(color: NunaPalette.textPrimary, text: "Strength · volume kg", dot: true) }
                }
            }
            NunaTitleRow(title: "This week's breakdown") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    NavigationLink(value: NunaWorkoutRoute.loadCardio) {
                        NunaListRow("Cardio", subtitle: LocalizedStringKey(String(localized: "Effort \(UnitFormatter.effortDisplay(m.effort(week), scale: scale)) · \(week.count) sessions with heart rate")), systemImage: "heart", showsChevron: true)
                    }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaWorkoutRoute.loadMuscle) {
                        NunaListRow("Strength", subtitle: LocalizedStringKey(String(localized: "\(Int((vol.last ?? 0).rounded())) kg · \(lifts.count) lifting sessions · \(sets.count) sets")), systemImage: "bolt", showsChevron: true)
                    }.buttonStyle(.plain)
                }
            }
            NunaCard(small: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles").foregroundStyle(NunaPalette.textMuted)
                    Text("Cardio is counted from daily Effort, not TRIMP. Strength is estimated from the volume you lift and is not added to cardio, because the heart strain of lifting is not invented.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func ringColumn(_ title: LocalizedStringKey, _ v: String, _ unit: String, _ f: Double, _ color: Color, _ band: TrendInsights.LoadBand?, _ bandColor: Color) -> some View {
        VStack(spacing: 8) {
            NunaRingGauge(fraction: max(f, 0.02), color: color, size: 104, lineWidth: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: v).font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
                    if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                }
            }
            Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            if let band { Text(bandName(band)).font(.nuna(size: 13, weight: .heavy)).foregroundStyle(bandColor) }
        }.frame(maxWidth: .infinity)
    }

    private func pill(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 36)
            .background(NunaPalette.glassStrong, in: Capsule())
    }

    private func bandName(_ b: TrendInsights.LoadBand) -> LocalizedStringKey {
        switch b { case .under: return "Light"; case .optimal: return "Optimal"; case .high: return "High"; case .excessive: return "Excessive" }
    }

    private func balanceCard(_ ratio: Double?, _ band: TrendInsights.LoadBand?) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    nunaTrendsCap("Load balance")
                    Spacer()
                    if let ratio { NunaChip(verbatim: String(format: "%.2f", locale: AppLanguage.activeLocale, ratio), color: band == .optimal ? NunaPalette.charge : NunaPalette.warning) }
                }
                if let ratio {
                    Text("Your last 7 days against your usual week over 6 weeks. Between 0.8 and 1.3 is the safe range.").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    NunaScaleBar(parts: [(3, NunaPalette.zoneBase), (5, NunaPalette.charge), (2, NunaPalette.warning), (2, NunaPalette.alert)], position: min(max((ratio - 0.5) / 1.1, 0), 1))
                    HStack { Text(verbatim: "0,5"); Spacer(); Text(verbatim: "1,6") }.font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    HStack { Text("Under"); Spacer(); Text("Optimal").foregroundStyle(NunaPalette.charge).fontWeight(.heavy); Spacer(); Text("High"); Spacer(); Text("Excess") }
                        .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                } else {
                    Text("Needs at least three weeks with workouts to read your balance.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
    }

    /// Six weeks side by side. In each column the strength volume sits above (white) and cardio Effort below (blue), each
    /// scaled to its own best week, so a week with no lifting shows only a thin line.
    private func weeklyPair(_ cardio: [Double], _ vol: [Double]) -> some View {
        let cTop = max(cardio.max() ?? 1, 1), vTop = max(vol.max() ?? 1, 1)
        let labels: [String] = (0..<cardio.count).map { i in
            let d = Calendar.current.date(byAdding: .day, value: -7 * (cardio.count - 1 - i), to: Date()) ?? Date()
            return nunaAxisDate(d)
        }
        return HStack(alignment: .top, spacing: 10) {
            ForEach(0..<cardio.count, id: \.self) { i in
                VStack(spacing: 6) {
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) { Color.clear; RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NunaPalette.accent.opacity(vol[i] > 0 ? 0.92 : 0.18)).frame(height: max(3, 56 * CGFloat(vol[i] / vTop))) }.frame(height: 56)
                        ZStack(alignment: .top) { Color.clear; RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NunaPalette.effort.opacity(cardio[i] > 0 ? 1 : 0.25)).frame(height: max(3, 56 * CGFloat(cardio[i] / cTop))) }.frame(height: 56)
                    }
                    Text(verbatim: labels[i]).font(.nuna(size: 10, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.6)
                }.frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Cardio

    private var model: TrainingLoadEngine.Result {
        TrainingLoadEngine.evaluate(days: repo.days.map { TrainingLoadEngine.DailyLoad(day: $0.day, load: $0.strain) })
    }

    private var cardio: some View {
        let r = model
        let pts = r.points
        let shown = Array(pts.suffix(weeks == 12 ? 90 : weeks * 7))
        let last = pts.last
        let form = last?.tsb
        let ctlColor = NunaPalette.restText
        return VStack(spacing: NunaSpacing.section) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text("Form (fitness minus fatigue)").font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if let form { NunaChip(formName(TrendInsights.formState(form)), color: formColor(TrendInsights.formState(form))) }
                    }
                    if let last, let form {
                        Text(verbatim: NunaTrendsFormat.signed(eff(form), 1)).font(.nuna(size: 64, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: formSentence(TrendInsights.formState(form))).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                        NunaDivider()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) { Text("Fitness · CTL").font(.nuna(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary); Text(verbatim: NunaTrendsFormat.num(eff(last.ctl), 1)).font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(ctlColor) }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) { Text("Fatigue · ATL").font(.nuna(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary); Text(verbatim: NunaTrendsFormat.num(eff(last.atl), 1)).font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.effortText) }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text("The model needs at least 14 days in a row with Effort before it draws anything.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
            }
            if !shown.isEmpty {
                NunaSegmented([(value: 4, title: "4 wk"), (value: 5, title: "5 wk"), (value: 12, title: "3 mo")], selection: $weeks)
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { nunaTrendsCap("Fitness and fatigue"); Spacer(); Text("Effort scale").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                        let all = shown.flatMap { [$0.ctl, $0.atl] }
                        let lo = all.min() ?? 0, span = max((all.max() ?? 1) - lo, 0.0001)
                        NunaMultiLineChart(start: shown.first!.day, days: shown.count,
                                           lines: [.init(series: shown.map { ($0.day, ($0.ctl - lo) / span) }, max: 1, color: ctlColor),
                                                   .init(series: shown.map { ($0.day, ($0.atl - lo) / span) }, max: 1, color: NunaPalette.effort)], height: 120)
                        HStack {
                            Text(verbatim: nunaAxisDate(NunaDayFormat.parse(shown.first!.day) ?? Date())); Spacer(); Text("Today")
                        }.font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        HStack(spacing: 14) {
                            squareLegend(ctlColor, "Fitness · 42 days"); squareLegend(NunaPalette.effort, "Fatigue · 7 days")
                        }
                    }
                }
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { nunaTrendsCap("Daily form"); Spacer(); Text("Green fresh · yellow loaded").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                        let top = max(shown.map { abs($0.tsb) }.max() ?? 1, 0.5)
                        HStack(alignment: .center, spacing: 1) {
                            ForEach(Array(shown.enumerated()), id: \.offset) { _, p in
                                let h = max(2, 22 * CGFloat(abs(p.tsb) / top))
                                VStack(spacing: 0) {
                                    ZStack(alignment: .bottom) { Color.clear; if p.tsb >= 0 { RoundedRectangle(cornerRadius: 1.5).fill(NunaPalette.charge).frame(height: h) } }.frame(height: 24)
                                    ZStack(alignment: .top) { Color.clear; if p.tsb < 0 { RoundedRectangle(cornerRadius: 1.5).fill(NunaPalette.warning).frame(height: h) } }.frame(height: 24)
                                }.frame(maxWidth: .infinity)
                            }
                        }.frame(height: 48)
                    }
                }
            }
            Text("Form states").font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    let states: [(TrendInsights.FormState, LocalizedStringKey, LocalizedStringKey)] = [
                        (.fresh, "Fresh", "above +2 · ready for hard training"), (.balanced, "Balanced", "−3 to +2 · you are here"),
                        (.loaded, "Loaded", "−6 to −3 · ease off"), (.overreached, "Overreached", "below −6 · needs rest"),
                    ]
                    ForEach(Array(states.enumerated()), id: \.offset) { i, st in
                        if i > 0 { NunaDivider() }
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 3).fill(formColor(st.0)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(st.1).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text(st.2).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                            Spacer()
                            if let form, TrendInsights.formState(form) == st.0 { NunaChip("Now", color: NunaPalette.charge) }
                        }.frame(minHeight: 60)
                    }
                }
            }
            sources
            zonesCard
            NunaCard(small: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles").foregroundStyle(NunaPalette.textMuted)
                    Text("Fitness (CTL) averages Effort over 42 days, fatigue (ATL) over 7 days, and form is the gap. Descriptive only: it does not change Charge or any other score.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func squareLegend(_ c: Color, _ t: LocalizedStringKey) -> some View {
        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 12); Text(t).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
    }

    private func formName(_ s: TrendInsights.FormState) -> LocalizedStringKey {
        switch s { case .fresh: return "Fresh"; case .balanced: return "Balanced"; case .loaded: return "Loaded"; case .overreached: return "Overreached" }
    }
    private func formColor(_ s: TrendInsights.FormState) -> Color { s == .fresh ? NunaPalette.charge : (s == .balanced ? NunaPalette.rest : (s == .loaded ? NunaPalette.warning : NunaPalette.alert)) }
    private func formSentence(_ s: TrendInsights.FormState) -> String {
        switch s {
        case .fresh: return String(localized: "Fatigue is below your fitness. You are fresh for a hard session.")
        case .balanced: return String(localized: "Fatigue and fitness are in balance.")
        case .loaded: return String(localized: "Fatigue is above your fitness. Common after a heavy week; ease off.")
        case .overreached: return String(localized: "Fatigue is well above your fitness. Rest.")
        }
    }

    private var sources: some View {
        let week = m.recent(days: 7)
        let groups = Dictionary(grouping: week, by: \.sport).map { (sport: $0.key, rows: $0.value) }.sorted { m.effort($0.rows) > m.effort($1.rows) }
        let top = max(groups.map { m.effort($0.rows) }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Load sources, 7 days").font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            NunaCard(small: true, padding: EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18)) {
                VStack(spacing: 0) {
                    if groups.isEmpty { Text("No workouts in the last 7 days.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading) }
                    ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                        if i > 0 { NunaDivider() }
                        VStack(spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: WorkoutSource.displaySport(g.sport)).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                    Text(verbatim: String(localized: "\(g.rows.count) sessions · \(Int(m.minutes(g.rows).rounded())) min")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                                }
                                Spacer()
                                Text(verbatim: UnitFormatter.effortDisplay(m.effort(g.rows), scale: scale)).font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            }
                            NunaProgressBar(fraction: m.effort(g.rows) / top, color: NunaPalette.effort)
                        }.padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private var zonesCard: some View {
        let total = zoneMinutes.reduce(0, +)
        let colors: [Color] = [NunaPalette.zoneBase, NunaPalette.charge, NunaPalette.restText, NunaPalette.warning, NunaPalette.alert]
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack { nunaTrendsCap("Time per heart-rate zone"); Spacer(); if total > 0 { Text(verbatim: String(localized: "\(Int(total.rounded())) min")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) } }
                if total > 0 {
                    NunaProportionBar(parts: zoneMinutes.enumerated().map { ($1, colors[$0]) }, height: 12)
                    ForEach(0..<5, id: \.self) { i in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3).fill(colors[i]).frame(width: 10, height: 10)
                            Text(verbatim: String(localized: "Zone \(i + 1)")).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            Spacer()
                            Text(verbatim: String(localized: "\(Int(zoneMinutes[i].rounded())) min")).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        }
                    }
                } else { Text("No heart-rate readings in saved sessions this week.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
            }
        }
    }

    private func loadZones() async {
        var out = [Double](repeating: 0, count: 5)
        for r in m.recent(days: 7) {
            let mins: [Double]?
            if let p = WorkoutZones.percents(r.zonesJSON) { let d = (r.durationS ?? Double(r.endTs - r.startTs)) / 60; mins = p.map { d * $0 / 100 } }
            else { mins = await repo.workoutZoneMinutes(from: r.startTs, to: r.endTs, zoneSet: profile.hrZoneSet, source: r.source) }
            if let mins { for i in 0..<5 { out[i] += mins[i] } }
        }
        zoneMinutes = out
    }

    // MARK: Strength

    private var muscle: some View {
        let vol = m.weeklyVolume(weeks: 6)
        let lifts = m.liftSessions.filter { Double($0.startTs) >= Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970 }
        let weekSets = lifts.flatMap { m.liftSets[$0.id] ?? [] }.filter { !$0.isWarmup }
        let reps = weekSets.compactMap(\.reps).reduce(0, +)
        let usual = vol.dropLast().filter { $0 > 0 }
        let usualMean = usual.isEmpty ? nil : usual.reduce(0, +) / Double(usual.count)
        let change = (usualMean ?? 0) > 0 ? ((vol.last ?? 0) / usualMean! - 1) * 100 : nil
        let band = TrendInsights.loadRatio(blocks: vol).map(TrendInsights.loadBand)
        return VStack(spacing: NunaSpacing.section) {
            if m.liftSessions.isEmpty {
                NunaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No lifting sessions yet").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Log a gym session with sets and weights in the Lift Log. Volume, muscle groups and personal records appear here.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { nunaTrendsCap("Volume, 7 days"); Spacer(); if let band { NunaChip(bandName(band), color: band == .optimal ? NunaPalette.charge : NunaPalette.warning) } }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, (vol.last ?? 0) / 1000)).font(.nuna(size: 64, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            Text("tonnes").font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        if let change {
                            Text(verbatim: (change >= 0 ? String(localized: "Up \(Int(abs(change).rounded()))% from your 6-week average.") : String(localized: "Down \(Int(abs(change).rounded()))% from your 6-week average.")) + " " + String(localized: "\(lifts.count) lifting sessions and \(weekSets.count) working sets."))
                                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        NunaDivider()
                        HStack { tileSmall("Sessions", "\(lifts.count)"); tileSmall("Sets", "\(weekSets.count)"); tileSmall("Reps", "\(reps)") }
                    }
                }
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { nunaTrendsCap("Volume per week"); Spacer(); Text("Tonnes").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                        let top = max(vol.max() ?? 1, 1)
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(0..<vol.count, id: \.self) { i in
                                let d = Calendar.current.date(byAdding: .day, value: -7 * (vol.count - 1 - i), to: Date()) ?? Date()
                                VStack(spacing: 6) {
                                    Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, vol[i] / 1000)).font(.nuna(size: 11.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NunaPalette.ink.opacity(vol[i] > 0 ? 0.55 : 0.12)).frame(height: max(3, 70 * CGFloat(vol[i] / top)))
                                    Text(verbatim: nunaAxisDate(d)).font(.nuna(size: 10, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.6)
                                }.frame(maxWidth: .infinity).frame(height: 112)
                            }
                        }
                    }
                }
                groupsCard
                recoveryNote
                recordsCard
            }
            NavigationLink { LiftLogView() } label: {
                NunaCard(small: true) {
                    HStack(spacing: 12) {
                        NunaIconTile("books.vertical")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Lift Log").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text("Sets, weights, rest and records").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                }
            }.buttonStyle(.plain)
            NunaCard(small: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles").foregroundStyle(NunaPalette.textMuted)
                    Text("Estimated from lifting volume (weight × reps). This is not heart strain, so it is not added to cardio Effort.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func tileSmall(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum MuscleGroup: String, CaseIterable { case legs, chest, back, shoulders, arms, core }
    private func group(_ mu: LiftMuscle) -> MuscleGroup {
        switch mu {
        case .quads, .hamstrings, .glutes, .adductors, .abductors, .calves: return .legs
        case .chest: return .chest
        case .lats, .upperBack, .traps, .lowerBack: return .back
        case .frontDelts, .sideDelts, .rearDelts, .neck: return .shoulders
        case .biceps, .triceps, .forearms: return .arms
        case .abs, .obliques: return .core
        }
    }
    private func groupName(_ g: MuscleGroup) -> LocalizedStringKey {
        switch g { case .legs: return "Legs"; case .chest: return "Chest"; case .back: return "Back"; case .shoulders: return "Shoulders"; case .arms: return "Arms"; case .core: return "Core" }
    }

    /// Volume (kg) in the last 7 days and days since last trained, per muscle group.
    private var groupStats: [(g: MuscleGroup, kg: Double, days: Int)] {
        let weekStart = Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970
        var volume: [MuscleGroup: Double] = [:], last: [MuscleGroup: Int] = [:]
        for s in m.liftSessions {
            for set in m.liftSets[s.id] ?? [] where !set.isWarmup {
                guard let p = set.primaryMuscle else { continue }
                let g = group(p)
                last[g] = max(last[g] ?? 0, s.startTs)
                if Double(s.startTs) >= weekStart, let w = set.weightKg, let r = set.reps { volume[g, default: 0] += w * Double(r) }
            }
        }
        return MuscleGroup.allCases.compactMap { g in
            last[g].map { (g, volume[g] ?? 0, Int((Date().timeIntervalSince1970 - Double($0)) / 86_400)) }
        }.sorted { $0.kg > $1.kg }
    }

    private var groupsCard: some View {
        let stats = groupStats
        let top = max(stats.map(\.kg).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("By muscle group").font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            NunaCard(small: true, padding: EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18)) {
                VStack(spacing: 0) {
                    if stats.isEmpty { Text("Classify your exercises by muscle in the Lift Log to see this.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading) }
                    ForEach(Array(stats.enumerated()), id: \.offset) { i, st in
                        if i > 0 { NunaDivider() }
                        VStack(spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(groupName(st.g)).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Spacer()
                                Text(verbatim: NunaTrendsFormat.num(st.kg)).font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                Text("kg").font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                            NunaProgressBar(fraction: st.kg / top, color: NunaPalette.textPrimary)
                            HStack {
                                Text(verbatim: String(localized: "Trained \(st.days) days ago")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                                Spacer()
                                Text(st.days >= 2 ? "Recovered" : "Recovering").font(.nuna(size: 12, weight: .heavy)).foregroundStyle(st.days >= 2 ? NunaPalette.charge : NunaPalette.warning)
                            }
                        }.padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private var recoveryNote: some View {
        let stats = groupStats
        let recovering = stats.filter { $0.days < 2 }
        let ready = stats.filter { $0.days >= 2 }.sorted { $0.days > $1.days }.prefix(2).map { String(localized: String.LocalizationValue(groupKey($0.g))) }
        return Group {
            if !stats.isEmpty {
                NunaCard(highlight: true) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.charge)
                            .frame(width: 40, height: 40).background(NunaPalette.tint(NunaPalette.charge), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recovering.isEmpty ? "All muscle groups are recovered" : "Some muscle groups are still recovering").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: ready.isEmpty ? String(localized: "Rest today") : String(localized: "\(ready.joined(separator: " and ")) are ready to train today"))
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func groupKey(_ g: MuscleGroup) -> String {
        switch g { case .legs: return "Legs"; case .chest: return "Chest"; case .back: return "Back"; case .shoulders: return "Shoulders"; case .arms: return "Arms"; case .core: return "Core" }
    }

    private var recordsCard: some View {
        var best: [String: (kg: Double, ts: Int)] = [:]
        for s in m.liftSessions {
            for set in m.liftSets[s.id] ?? [] where !set.isWarmup {
                guard let w = set.weightKg, let r = set.reps, r > 0 else { continue }
                if w > (best[set.exercise]?.kg ?? 0) { best[set.exercise] = (w, s.startTs) }
            }
        }
        let top = best.sorted { $0.value.ts > $1.value.ts }.prefix(3)
        return Group {
            if !top.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    NunaTitleRow(title: "Personal records") { EmptyView() }
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                        VStack(spacing: 0) {
                            ForEach(Array(top.enumerated()), id: \.element.key) { i, kv in
                                if i > 0 { NunaDivider() }
                                NunaListRow(LocalizedStringKey(kv.key), subtitle: LocalizedStringKey(NunaWorkoutFormat.day(kv.value.ts)), systemImage: "bolt") {
                                    Text(verbatim: String(format: "%.1f kg", locale: AppLanguage.activeLocale, kv.value.kg)).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
