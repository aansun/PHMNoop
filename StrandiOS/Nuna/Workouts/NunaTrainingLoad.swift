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
        NunaDetailScreen("Training load") {
            NunaSegmented([(value: 0, title: "Summary"), (value: 1, title: "Cardio"), (value: 2, title: "Strength")], selection: $tab)
            switch tab {
            case 1: cardio
            case 2: muscle
            default: summary
            }
            NunaAnyaCard(verbatim: anyaLine) { showCoach = true }
            NavigationLink(value: NunaWorkoutRoute.calendar) {
                NunaCard(small: true) { NunaListRow("See the workout calendar", systemImage: "calendar", showsChevron: true) }
            }.buttonStyle(.plain)
        }
        .nunaWorkoutDestinations()
        .task(id: repo.refreshSeq) {
            await m.load(repo: repo)
            await loadZones()
        }
        .sheet(isPresented: $showCoach) { CoachLauncherSheet(context: "workouts") }
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
        let week = m.recent(days: 7)
        let lifts = m.liftSessions.filter { Double($0.startTs) >= Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970 }
        let sets = lifts.flatMap { m.liftSets[$0.id] ?? [] }.filter { !$0.isWarmup }
        return VStack(spacing: NunaSpacing.section) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { nunaTrendsCap("Last 7 days"); Spacer(); if let band { NunaChip(bandName(band), color: band == .optimal ? NunaPalette.charge : NunaPalette.warning) } }
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Cardio").font(.system(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                            Text(verbatim: UnitFormatter.effortDisplay(cardio.last ?? 0, scale: scale)).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                            NunaSpark(values: cardio).frame(height: 36)
                            NavigationLink(value: NunaWorkoutRoute.loadCardio) { Text("Effort · see cardio").font(.system(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Strength").font(.system(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                            Text(verbatim: vol.last.map { $0 >= 1000 ? String(format: "%.1f k", locale: AppLanguage.activeLocale, $0 / 1000) : NunaTrendsFormat.num($0) } ?? "–").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                            NunaSpark(values: vol).frame(height: 36)
                            NavigationLink(value: NunaWorkoutRoute.loadMuscle) { Text("kg · see strength").font(.system(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            balanceCard(ratio, band)
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { nunaTrendsCap("6 weeks"); Spacer(); Text("Top: strength · bottom: cardio").font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                    weeklyPair(cardio.map(eff), vol)
                    HStack(spacing: 14) { NunaLegendItem(color: NunaPalette.effort, text: "Cardio · Effort", dot: true); NunaLegendItem(color: NunaPalette.rest, text: "Strength · volume kg", dot: true) }
                }
            }
            NunaTitleRow(title: "This week") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    NavigationLink(value: NunaWorkoutRoute.loadCardio) {
                        NunaListRow("Cardio", subtitle: LocalizedStringKey(String(localized: "Effort \(UnitFormatter.effortDisplay(m.effort(week), scale: scale)) · \(week.count) sessions")), systemImage: "heart", showsChevron: true)
                    }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaWorkoutRoute.loadMuscle) {
                        NunaListRow("Strength", subtitle: LocalizedStringKey(String(localized: "\(Int((vol.last ?? 0).rounded())) kg · \(lifts.count) lifting sessions · \(sets.count) sets")), systemImage: "dumbbell", showsChevron: true)
                    }.buttonStyle(.plain)
                }
            }
            NunaCard(small: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle").foregroundStyle(NunaPalette.textMuted)
                    Text("Cardio is counted from daily Effort, not TRIMP. Strength is estimated from the volume you lift and is not added to cardio, because the heart strain of lifting is not invented.")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func bandName(_ b: TrendInsights.LoadBand) -> LocalizedStringKey {
        switch b { case .under: return "Light"; case .optimal: return "Optimal"; case .high: return "High"; case .excessive: return "Excessive" }
    }

    private func balanceCard(_ ratio: Double?, _ band: TrendInsights.LoadBand?) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Load balance")
                if let ratio {
                    Text(verbatim: String(format: "%.2f", locale: AppLanguage.activeLocale, ratio)).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                    Text("Your last 7 days against your usual week over 6 weeks. Between 0.8 and 1.3 is the safe range.").font(.system(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    NunaScaleBar(parts: [(3, NunaPalette.zoneBase), (5, NunaPalette.charge), (2, NunaPalette.warning), (2, NunaPalette.alert)], position: min(max((ratio - 0.5) / 1.1, 0), 1))
                    HStack { Text(verbatim: "0,5"); Spacer(); Text(verbatim: "1,6") }.font(.system(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    HStack { Text("Light"); Spacer(); Text("Optimal").foregroundStyle(NunaPalette.charge).fontWeight(.heavy); Spacer(); Text("High"); Spacer(); Text("Excessive") }
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                } else {
                    Text("Needs at least three weeks with workouts to read your balance.").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
    }

    /// Two stacked bar rows over the same weeks: strength above, cardio below.
    private func weeklyPair(_ cardio: [Double], _ vol: [Double]) -> some View {
        let cTop = max(cardio.max() ?? 1, 1), vTop = max(vol.max() ?? 1, 1)
        let labels: [String] = (0..<cardio.count).map { i in
            let d = Calendar.current.date(byAdding: .day, value: -7 * (cardio.count - 1 - i), to: Date()) ?? Date()
            return nunaAxisDate(d)
        }
        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<vol.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 5).fill(NunaPalette.rest.opacity(vol[i] > 0 ? 1 : 0.2)).frame(height: max(4, 50 * CGFloat(vol[i] / vTop))).frame(maxWidth: .infinity)
                }
            }.frame(height: 52, alignment: .bottom)
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<cardio.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 5).fill(NunaPalette.effort.opacity(cardio[i] > 0 ? 1 : 0.2)).frame(height: max(4, 50 * CGFloat(cardio[i] / cTop))).frame(maxWidth: .infinity)
                }
            }.frame(height: 52, alignment: .top)
            HStack(spacing: 8) {
                ForEach(0..<labels.count, id: \.self) { i in Text(verbatim: labels[i]).font(.system(size: 10, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.6) }
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
        return VStack(spacing: NunaSpacing.section) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { nunaTrendsCap("Form (fitness minus fatigue)"); Spacer(); if let form { NunaChip(formName(TrendInsights.formState(form)), color: formColor(TrendInsights.formState(form))) } }
                    if let last, let form {
                        Text(verbatim: NunaTrendsFormat.signed(eff(form), 1)).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: formSentence(TrendInsights.formState(form))).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) { Text("Fitness · CTL").font(.system(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary); Text(verbatim: NunaTrendsFormat.num(eff(last.ctl), 1)).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary) }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) { Text("Fatigue · ATL").font(.system(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary); Text(verbatim: NunaTrendsFormat.num(eff(last.atl), 1)).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary) }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text("The model needs at least 14 days in a row with Effort before it draws anything.").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
            }
            if !shown.isEmpty {
                NunaSegmented([(value: 4, title: "4 wk"), (value: 5, title: "5 wk"), (value: 12, title: "3 mo")], selection: $weeks)
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { nunaTrendsCap("Fitness and fatigue"); Spacer(); Text("Effort scale").font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                        let all = shown.flatMap { [$0.ctl, $0.atl] }
                        let lo = all.min() ?? 0, span = max((all.max() ?? 1) - lo, 0.0001)
                        NunaMultiLineChart(start: shown.first!.day, days: shown.count,
                                           lines: [.init(series: shown.map { ($0.day, ($0.ctl - lo) / span) }, max: 1, color: NunaPalette.charge),
                                                   .init(series: shown.map { ($0.day, ($0.atl - lo) / span) }, max: 1, color: NunaPalette.effortText)], height: 150)
                        NunaDayAxis(first: shown.first!.day, last: shown.last!.day)
                        HStack(spacing: 14) { NunaLegendItem(color: NunaPalette.charge, text: "Fitness · 42 days"); NunaLegendItem(color: NunaPalette.effortText, text: "Fatigue · 7 days") }
                    }
                }
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { nunaTrendsCap("Daily form"); Spacer(); Text("Green fresh · yellow loaded").font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                        let top = max(shown.map { abs($0.tsb) }.max() ?? 1, 0.5)
                        HStack(alignment: .center, spacing: 1) {
                            ForEach(Array(shown.enumerated()), id: \.offset) { _, p in
                                let h = max(2, 40 * CGFloat(abs(p.tsb) / top))
                                VStack(spacing: 0) {
                                    ZStack(alignment: .bottom) { Color.clear; if p.tsb >= 0 { RoundedRectangle(cornerRadius: 1).fill(NunaPalette.charge).frame(height: h) } }.frame(height: 40)
                                    ZStack(alignment: .top) { Color.clear; if p.tsb < 0 { RoundedRectangle(cornerRadius: 1).fill(p.tsb >= -3 ? NunaPalette.rest : NunaPalette.warning).frame(height: h) } }.frame(height: 40)
                                }.frame(maxWidth: .infinity)
                            }
                        }.frame(height: 80)
                    }
                }
            }
            NunaTitleRow(title: "Form states") { EmptyView() }
            NunaCard {
                VStack(spacing: 12) {
                    ForEach([(TrendInsights.FormState.fresh, "Fresh above +2 · ready for hard training"), (.balanced, "Balanced −3 to +2"), (.loaded, "Loaded −6 to −3 · ease off"), (.overreached, "Overreached below −6 · needs rest")], id: \.0) { st, text in
                        HStack(spacing: 10) {
                            Circle().fill(formColor(st)).frame(width: 9, height: 9)
                            Text(LocalizedStringKey(text)).font(.system(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            if let form, TrendInsights.formState(form) == st { NunaChip("You are here") }
                        }
                    }
                }
            }
            sources
            zonesCard
            NunaCard(small: true) {
                Text("Fitness (CTL) averages Effort over 42 days, fatigue (ATL) over 7 days, and form is the gap. Descriptive only: it does not change Charge or any other score.")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
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
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Load sources, 7 days") { EmptyView() }
            NunaCard {
                VStack(spacing: 14) {
                    if groups.isEmpty { Text("No workouts in the last 7 days.").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(groups, id: \.sport) { g in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: WorkoutSource.displaySport(g.sport)).font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: String(localized: "\(g.rows.count) sessions · \(Int(m.minutes(g.rows).rounded())) min")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                            Spacer()
                            Text(verbatim: UnitFormatter.effortDisplay(m.effort(g.rows), scale: scale)).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private var zonesCard: some View {
        let total = zoneMinutes.reduce(0, +)
        let colors: [Color] = [NunaPalette.zoneBase, NunaPalette.rest, NunaPalette.charge, NunaPalette.warning, NunaPalette.alert]
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Time per heart-rate zone") { EmptyView() }
            NunaCard {
                VStack(spacing: 12) {
                    if total > 0 {
                        HStack { Spacer(); Text(verbatim: String(localized: "\(Int(total.rounded())) min")).font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                        NunaProportionBar(parts: zoneMinutes.enumerated().map { ($1, colors[$0]) })
                        ForEach(0..<5, id: \.self) { i in
                            HStack(spacing: 10) {
                                Circle().fill(colors[i]).frame(width: 9, height: 9)
                                Text(verbatim: String(localized: "Zone \(i + 1)")).font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Spacer()
                                Text(verbatim: String(localized: "\(Int(zoneMinutes[i].rounded())) min")).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                            }
                        }
                    } else { Text("No heart-rate readings in saved sessions this week.").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
                }
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
        return VStack(spacing: NunaSpacing.section) {
            if m.liftSessions.isEmpty {
                NunaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No lifting sessions yet").font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Log a gym session with sets and weights in the Lift Log. Volume, muscle groups and personal records appear here.").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { nunaTrendsCap("Volume, 7 days"); Spacer(); if let change { NunaChip(change >= -10 && change <= 30 ? "Optimal" : (change > 30 ? "High" : "Light"), color: change >= -10 && change <= 30 ? NunaPalette.charge : NunaPalette.warning) } }
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, (vol.last ?? 0) / 1000)).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                            Text("tonnes").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        if let change { Text(verbatim: String(localized: "\(change >= 0 ? "Up" : "Down") \(Int(abs(change).rounded()))% from your usual week.")).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                        HStack { tileSmall("Sessions", "\(lifts.count)"); tileSmall("Sets", "\(weekSets.count)"); tileSmall("Reps", "\(reps)") }
                    }
                }
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { nunaTrendsCap("Volume per week"); Spacer(); Text("Tonnes").font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                        let top = max(vol.max() ?? 1, 1)
                        NunaColumns(items: vol.enumerated().map { i, v in
                            let d = Calendar.current.date(byAdding: .day, value: -7 * (vol.count - 1 - i), to: Date()) ?? Date()
                            return NunaColumns.Item(weekday: "", date: d, fraction: v / top, valueText: String(format: "%.1f", locale: AppLanguage.activeLocale, v / 1000), highlight: i == vol.count - 1)
                        }, color: NunaPalette.rest, highlightColor: NunaPalette.restText)
                    }
                }
                groupsCard
                recordsCard
            }
            NavigationLink { LiftLogView() } label: {
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    NunaIconTile("books.vertical")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lift Log").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Sets, weights, rest and records").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
            }.buttonStyle(.plain)
            NunaCard(small: true) {
                Text("Estimated from lifting volume (weight × reps). This is not heart strain, so it is not added to cardio Effort.").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tileSmall(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.system(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
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

    private var groupsCard: some View {
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
        let shown = MuscleGroup.allCases.filter { last[$0] != nil }
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "By muscle group") { EmptyView() }
            NunaCard {
                VStack(spacing: 14) {
                    if shown.isEmpty { Text("Classify your exercises by muscle in the Lift Log to see this.").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(shown, id: \.self) { g in
                        let days = Int((Date().timeIntervalSince1970 - Double(last[g] ?? 0)) / 86_400)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(groupName(g)).font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: String(localized: "Last \(days) days ago")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(verbatim: "\(Int((volume[g] ?? 0).rounded())) kg").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                                NunaChip(days >= 2 ? "Recovered" : "Recovering", color: days >= 2 ? NunaPalette.charge : NunaPalette.warning)
                            }
                        }
                    }
                }
            }
        }
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
                                    Text(verbatim: String(format: "%.1f kg", locale: AppLanguage.activeLocale, kv.value.kg)).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
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
