#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

extension View {
    func nunaWorkoutDestinations() -> some View {
        navigationDestination(for: NunaWorkoutRoute.self) { r in
            switch r {
            case .start(let sport): NunaWorkoutStartView(sport: sport)
            case .summary(let k): NunaWorkoutSummaryView(key: k)
            case .history: NunaWorkoutHistoryView()
            case .calendar: NunaWorkoutHistoryView()
            case .load: NunaTrainingLoadView(tab: 0)
            case .loadCardio: NunaTrainingLoadView(tab: 1)
            case .loadMuscle: NunaTrainingLoadView(tab: 2)
            case .autoDetect: NunaAutoDetectView()
            case .settings: NunaWorkoutSettingsView()
            case .gym: NunaGymView()
            case .program(let id): NunaProgramEditor(programId: id)
            case .programImport: NunaProgramImportView()
            case .gymSession(let id): NunaGymSessionView(sessionId: id)
            }
        }
    }
}

/// Latihan hub (Workouts.dc): the last 7 days, training load, the calendar, an auto-detected suggestion, a start grid and
/// the recent history. Everything comes from saved workouts, daily Effort and lifting sessions.
struct NunaWorkoutsView: View {
    var autoOpenStart = false
    @State private var openStart = false
    @State private var didAutoOpen = false
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceRaw = ""
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetect = false
    @StateObject private var m = NunaWorkoutsModel()
    @State private var suggestion: AutoWorkoutSuggestion?
    @State private var showCoach = false
    @State private var tab = 0
    @State private var query = ""
    @State private var showAllSports = false
    @State private var editingPins = false
    @State private var limitHit = false
    @AppStorage(NunaPinnedSports.key) private var pinnedRaw = NunaPinnedSports.unset

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var system: UnitSystem { UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceRaw) }

    private let starts: [(String, String, String)] = [
        ("Running", "Run", "figure.run"), ("Walking", "Walk", "figure.walk"), ("Cycling", "Cycle", "bicycle"),
        ("Strength", "Gym", "dumbbell"), ("Pool swim", "Swim", "figure.pool.swim"),
        ("HIIT", "HIIT", "bolt.heart"), ("Yoga", "Yoga", "figure.mind.and.body"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                header
                NunaSegmented([(value: 0, title: "Workout"), (value: 1, title: "Insight")], selection: $tab)
                NunaActiveWorkoutBanner()
                if !m.loaded {
                    ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
                } else if tab == 0 {
                    startSection
                    suggestionCard
                    historySection
                } else {
                    weekCard
                    anyaCard
                    loadCard
                    calendarCard
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .nunaWorkoutDestinations()
        .nunaTodayDestinations()
        .navigationDestination(isPresented: $openStart) { NunaWorkoutStartView(sport: nil, resume: autoOpenStart) }
        .onAppear { if autoOpenStart, !didAutoOpen { didAutoOpen = true; openStart = true } }
        .task(id: repo.refreshSeq) {
            await m.load(repo: repo)
            suggestion = autoDetect ? await repo.autoDetectSuggestion() : nil
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "workouts") }
        .environment(\.nunaAnyaCardContext, "workouts")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
            }.buttonStyle(.plain).accessibilityLabel(Text("Back"))
            Text("Workouts").font(.nuna(size: 24, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            roundLink(.history, "line.3.horizontal.decrease", "All sessions")
            roundLink(.settings, "slider.horizontal.3", "Workout settings")
        }
    }

    private func roundLink(_ r: NunaWorkoutRoute, _ icon: String, _ label: LocalizedStringKey) -> some View {
        NavigationLink(value: r) {
            Image(systemName: icon).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
        }.buttonStyle(.plain).accessibilityLabel(Text(label))
    }

    // MARK: Last 7 days

    private var weekCard: some View {
        let week = m.recent(days: 7)
        let total = m.effort(week)
        let weekly = m.weeklyEffort(weeks: 7)
        let usualBlocks = weekly.dropLast().filter { $0 > 0 }
        let usual = usualBlocks.isEmpty ? nil : usualBlocks.reduce(0, +) / Double(usualBlocks.count)
        let cal = Calendar.current
        let days: [(Date, [WorkoutRow])] = (0..<7).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: Date())) ?? Date()
            return (d, week.filter { cal.isDate(Date(timeIntervalSince1970: TimeInterval($0.startTs)), inSameDayAs: d) })
        }
        let top = max(days.map { m.effort($0.1) }.max() ?? 1, 1)
        let kcal = week.compactMap(\.energyKcal).reduce(0, +)
        let wd = DateFormatter(); wd.locale = AppLanguage.activeLocale; wd.setLocalizedDateFormatFromTemplate("EEE")
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    nunaTrendsCap("Last 7 days")
                    Spacer()
                    if let usual, usual > 0 { NunaChip(verbatim: String(localized: "\(Int((total / usual * 100).rounded()))% of your usual"), color: NunaPalette.effortText) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: UnitFormatter.effortDisplay(total, scale: scale)).font(.nuna(size: 44, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(44)).foregroundStyle(NunaPalette.textPrimary)
                    if let usual { Text(verbatim: "/ " + UnitFormatter.effortDisplay(usual, scale: scale)).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                    Text("Effort").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
                NunaColumns(items: days.map { d, rs in
                    let e = m.effort(rs)
                    return NunaColumns.Item(weekday: wd.string(from: d), date: d, fraction: e > 0 ? e / top : nil,
                                            valueText: e > 0 ? UnitFormatter.effortDisplay(e, scale: scale) : nil, highlight: cal.isDateInToday(d),
                                            color: rs.isEmpty ? nil : (rs.allSatisfy(NunaWorkoutKind.isStrength) ? NunaPalette.rest : NunaPalette.effort))
                }, color: NunaPalette.effort, highlightColor: NunaPalette.effortText, showsDates: false)
                HStack(spacing: 14) { NunaLegendItem(color: NunaPalette.effort, text: "Cardio", dot: true); NunaLegendItem(color: NunaPalette.rest, text: "Strength", dot: true) }
                NunaDivider()
                HStack {
                    stat("Sessions", "\(week.count)")
                    stat("Duration", NunaWorkoutFormat.duration(m.minutes(week) * 60))
                    stat("Calories", kcal > 0 ? NunaTrendsFormat.num(kcal) : "–")
                }
            }
        }
    }

    private func stat(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.nuna(size: 19, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var anyaCard: some View {
        let week = m.recent(days: 7)
        return Group {
            if !week.isEmpty {
                NunaAnyaCard(verbatim: String(localized: "This week: \(week.count) sessions, Effort \(UnitFormatter.effortDisplay(m.effort(week), scale: scale)).")) { showCoach = true }
            }
        }
    }

    // MARK: Training load

    private var loadCard: some View {
        let cardio = m.weeklyEffort(weeks: 6)
        let volume = m.weeklyVolume(weeks: 6)
        let ratio = TrendInsights.loadRatio(blocks: cardio)
        let band = ratio.map(TrendInsights.loadBand)
        return NavigationLink(value: NunaWorkoutRoute.load) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        nunaTrendsCap("Training load")
                        Spacer()
                        if let band { NunaChip(bandName(band), color: band == .optimal ? NunaPalette.charge : NunaPalette.warning) }
                    }
                    HStack(alignment: .top, spacing: 0) {
                        loadRing("Cardio", UnitFormatter.effortDisplay(cardio.last ?? 0, scale: scale), "", (cardio.last ?? 0) / max(cardio.max() ?? 1, 1),
                                 NunaPalette.effort, TrendInsights.loadRatio(blocks: cardio).map(TrendInsights.loadBand), NunaPalette.effortText)
                        loadRing("Strength", volume.last.map { $0 >= 1000 ? String(format: "%.1f", locale: AppLanguage.activeLocale, $0 / 1000) : NunaTrendsFormat.num($0) } ?? "–",
                                 (volume.last ?? 0) >= 1000 ? "k" : "", (volume.last ?? 0) / max(volume.max() ?? 1, 1),
                                 NunaPalette.textPrimary, TrendInsights.loadRatio(blocks: volume).map(TrendInsights.loadBand), NunaPalette.textPrimary)
                    }
                    if let ratio, let band {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                .frame(width: 34, height: 34).background(NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(verbatim: String(localized: "Acute-to-chronic load ratio \(String(format: "%.2f", locale: AppLanguage.activeLocale, ratio)). \(bandSentence(band))"))
                                .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Text("Needs at least three weeks with workouts to read your balance.").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private func loadRing(_ title: LocalizedStringKey, _ v: String, _ unit: String, _ f: Double, _ color: Color, _ band: TrendInsights.LoadBand?, _ bandColor: Color) -> some View {
        VStack(spacing: 8) {
            NunaRingGauge(fraction: max(f, 0.02), color: color, size: 104, lineWidth: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: v).font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
                    if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                }
            }
            Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            if let band { Text(bandName(band)).font(.nuna(size: 13, weight: .heavy)).foregroundStyle(bandColor) }
        }.frame(maxWidth: .infinity)
    }

    private func bandName(_ b: TrendInsights.LoadBand) -> LocalizedStringKey {
        switch b { case .under: return "Light"; case .optimal: return "Optimal"; case .high: return "High"; case .excessive: return "Excessive" }
    }
    private func bandSentence(_ b: TrendInsights.LoadBand) -> String {
        switch b {
        case .under: return String(localized: "Below your usual load. There is room to add some.")
        case .optimal: return String(localized: "Within the safe range of 0.8 to 1.3. You can raise intensity a little.")
        case .high: return String(localized: "Above your usual load. Keep the next sessions easier.")
        case .excessive: return String(localized: "Well above your usual load. Take a rest day.")
        }
    }

    // MARK: Calendar

    private var calendarCard: some View {
        NavigationLink(value: NunaWorkoutRoute.calendar) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { nunaTrendsCap("Workout calendar"); Spacer(); Text("This week").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                    NunaWorkoutMonthGrid(model: m, weeks: 1, selected: .constant(nil), interactive: false)
                    let stats = NunaWorkoutStats(model: m, days: 7)
                    HStack {
                        stat("Active days", "\(stats.active)"); stat("Rest", "\(stats.rest)")
                        stat("In a row", String(localized: "\(stats.streak) days"))
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    // MARK: Auto-detect

    @ViewBuilder private var suggestionCard: some View {
        if let s = suggestion {
            let w = s.workout
            NunaCard(highlight: true) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        AnyaMark(size: 18).foregroundStyle(NunaPalette.textPrimary)
                        nunaTrendsCap("Detected automatically")
                    }
                    Text(verbatim: "\(NunaWorkoutFormat.clock(s.startSec)) · \(s.sport) · \(w.durationMin) min")
                        .font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: String(localized: "Average heart rate \(w.avgBpm) bpm. Save it as a workout?")).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    HStack(spacing: 10) {
                        Button {
                            Task { _ = await repo.saveDetectedWorkout(s); suggestion = nil; await repo.refresh() }
                        } label: {
                            Text("Save").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 24).frame(height: 44).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain)
                        Button { repo.dismissDetectedSuggestion(w); suggestion = nil } label: {
                            Text("Not a workout").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 18).frame(height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Start

    private var pinned: [String] { NunaPinnedSports.decode(pinnedRaw) }

    /// The short, localised label of the quick set, or the catalogue name for anything else.
    private func quickTitle(_ sport: String) -> (String, Bool) {
        if let q = starts.first(where: { $0.0 == sport }) { return (q.1, true) }
        return (sport, false)
    }

    private func togglePin(_ sport: String) {
        if let next = NunaPinnedSports.toggled(sport, in: pinned) {
            pinnedRaw = NunaPinnedSports.encode(next)
            UISelectionFeedbackGenerator().selectionChanged()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            limitHit = true
            Task { try? await Task.sleep(nanoseconds: 2_000_000_000); limitHit = false }
        }
    }

    private var startSection: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matches = WorkoutCatalog.matching(q)
        let pins = pinned
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    nunaTrendsCap("Start a workout")
                    Spacer()
                    Button { withAnimation(.easeInOut(duration: 0.2)) { editingPins.toggle(); limitHit = false } } label: {
                        Text(editingPins ? "Done" : "Edit").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 14).frame(height: 32).background(NunaPalette.glassStrong, in: Capsule())
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                    TextField("", text: $query, prompt: Text("Search all workouts").foregroundStyle(NunaPalette.textMuted))
                        .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).autocorrectionDisabled().textCase(nil)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(NunaPalette.textMuted) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).frame(height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                if editingPins {
                    HStack(spacing: 6) {
                        Image(systemName: "pin.fill").font(.nuna(size: 11, weight: .bold))
                        Text(verbatim: String(localized: "Pinned \(pins.count) of \(NunaPinnedSports.maxCount)")).font(.nuna(size: 12.5, weight: .bold))
                        Spacer()
                        Text(limitHit ? "You can pin up to 8 workouts." : "Tap a workout to pin or unpin it.").font(.nuna(size: 12, weight: .semibold)).textCase(nil).multilineTextAlignment(.trailing)
                    }
                    .foregroundStyle(limitHit ? NunaPalette.alertText : NunaPalette.textSecondary)
                    let rest = (q.isEmpty ? WorkoutCatalog.all : matches).map(\.name).filter { !pins.contains($0) }
                    let shown = (q.isEmpty ? pins : pins.filter { p in matches.contains { $0.name == p } }) + rest
                    if shown.isEmpty {
                        Text("No workouts match").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    } else {
                        sportGrid(shown)
                    }
                } else if !q.isEmpty {
                    if matches.isEmpty {
                        Text("No workouts match").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    } else {
                        sportGrid(matches.map(\.name))
                    }
                } else if showAllSports {
                    sportGrid(WorkoutCatalog.all.map(\.name))
                    moreButton(expanded: true)
                } else {
                    if pins.isEmpty {
                        Text("Pin the workouts you do most. Tap Edit to choose up to 8.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    } else {
                        sportGrid(pins)
                    }
                    moreButton(expanded: false)
                }
            }
        }
    }

    private func moreButton(expanded: Bool) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { showAllSports.toggle() } } label: {
            HStack(spacing: 6) {
                Text(expanded ? "Show fewer" : "More").font(.nuna(size: 14, weight: .bold))
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.nuna(size: 11, weight: .bold))
            }
            .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 44)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func cell(_ sport: String) -> some View {
        let (title, localized) = quickTitle(sport)
        let isPinned = pinned.contains(sport)
        return VStack(spacing: 8) {
            Image(systemName: NunaWorkoutKind.isStrengthName(sport) ? "dumbbell" : sportSymbol(sport)).font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(height: 26)
            Group { if localized { Text(LocalizedStringKey(title)) } else { Text(verbatim: title) } }
                .font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.center).frame(height: 30, alignment: .top)
        }
        .frame(maxWidth: .infinity).frame(height: 84).padding(.horizontal, 2)
        .background(editingPins && isPinned ? NunaPalette.glassStrong : NunaPalette.glass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(editingPins && isPinned ? NunaPalette.textSecondary : NunaPalette.hairline, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if editingPins {
                Image(systemName: isPinned ? "pin.fill" : "pin").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isPinned ? NunaPalette.onAccent : NunaPalette.textMuted)
                    .frame(width: 20, height: 20)
                    .background(isPinned ? NunaPalette.accent : NunaPalette.field, in: Circle())
                    .padding(5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// A grid of sports by catalogue name. While editing a tap pins or unpins; otherwise it starts the workout, and a long press
    /// offers the pin.
    private func sportGrid(_ sports: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(sports, id: \.self) { sport in
                if editingPins {
                    Button { togglePin(sport) } label: { cell(sport) }.buttonStyle(.plain)
                } else {
                    NavigationLink(value: sport == "Strength" ? NunaWorkoutRoute.gym : NunaWorkoutRoute.start(sport)) { cell(sport) }.buttonStyle(.plain)
                        .contextMenu {
                            Button { togglePin(sport) } label: {
                                Label(pinned.contains(sport) ? "Unpin" : "Pin", systemImage: pinned.contains(sport) ? "pin.slash" : "pin")
                            }
                        }
                }
            }
        }
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History").font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                NavigationLink(value: NunaWorkoutRoute.history) {
                    HStack(spacing: 4) { Text("See all").font(.nuna(size: 14, weight: .bold)); Image(systemName: "chevron.right").font(.nuna(size: 11, weight: .bold)) }
                        .foregroundStyle(NunaPalette.textPrimary)
                }
            }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    if m.rows.isEmpty {
                        NunaListRow("No workouts yet", subtitle: "Start one above or let auto-detect suggest one", systemImage: "figure.run")
                    }
                    ForEach(Array(m.rows.prefix(4).enumerated()), id: \.offset) { i, r in
                        if i > 0 { NunaDivider() }
                        NavigationLink(value: NunaWorkoutRoute.summary(m.key(r))) { NunaWorkoutRow(row: r, system: system, effortScale: scale) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Counts over the last N calendar days.
struct NunaWorkoutStats {
    let active: Int, rest: Int, streak: Int, longestGap: Int
    @MainActor init(model m: NunaWorkoutsModel, days: Int, filter: (WorkoutRow) -> Bool = { _ in true }) {
        let cal = Calendar.current
        let keys = (0..<days).map { cal.date(byAdding: .day, value: -$0, to: Date()).map(Repository.localDayKey) ?? "" }   // today first
        let on = Set(m.rows.filter(filter).map { m.dayKey($0.startTs) })
        active = keys.filter(on.contains).count
        rest = days - active
        var s = 0
        for k in keys { if on.contains(k) { s += 1 } else { break } }
        streak = s
        var gap = 0, best = 0
        for k in keys { if on.contains(k) { best = max(best, gap); gap = 0 } else { gap += 1 } }
        longestGap = max(best, gap)
    }
}

/// Weeks of days, Monday first, oldest week on top (WorkoutCalendar). Each day shows its number with a dot under it:
/// blue for cardio, white for strength, both when both happened, a dash for a rest day. The selected day is a filled
/// circle, today is ringed and days after today are dimmed. `offset` shifts the window back by that many 7-week pages.
struct NunaWorkoutMonthGrid: View {
    @ObservedObject var model: NunaWorkoutsModel
    let weeks: Int
    @Binding var selected: String?
    var offset = 0
    var filter = "all"
    var interactive = true

    /// Monday of the first row shown.
    static func firstMonday(weeks: Int, offset: Int) -> Date {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let monday = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: today) + 5) % 7), to: today) ?? today
        // A one-row window is the current week itself; longer ones end one week after it and older pages step back
        // a whole window at a time.
        if weeks == 1 { return cal.date(byAdding: .day, value: -7 * offset, to: monday) ?? monday }
        return cal.date(byAdding: .day, value: -7 * (weeks - 2) - 7 * weeks * offset, to: monday) ?? monday
    }

    private func symbols() -> [String] {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale
        return [1, 2, 3, 4, 5, 6, 0].map { String(f.shortWeekdaySymbols[$0].prefix(3)) }
    }

    var body: some View {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let first = Self.firstMonday(weeks: weeks, offset: offset)
        let byDay = Dictionary(grouping: model.rows, by: { model.dayKey($0.startTs) })
        let mf = DateFormatter()
        VStack(spacing: 10) {
            HStack {
                ForEach(symbols(), id: \.self) { Text(verbatim: $0).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity) }
            }
            ForEach(0..<weeks, id: \.self) { w in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { d in
                        let date = cal.date(byAdding: .day, value: w * 7 + d, to: first) ?? first
                        let key = Repository.localDayKey(date)
                        let rs = (byDay[key] ?? []).filter { filter == "all" || (filter == "cardio") != NunaWorkoutKind.isStrength($0) }
                        let cardio = rs.contains { !NunaWorkoutKind.isStrength($0) }, strength = rs.contains(where: NunaWorkoutKind.isStrength)
                        let future = date > today
                        let isSel = selected == key
                        let isToday = cal.isDate(date, inSameDayAs: today)
                        Button { if interactive, !future { selected = key } } label: {
                            VStack(spacing: 3) {
                                Text(verbatim: dayLabel(date, cal, first: weeks > 1 && w == 0 && d == 0))
                                    .font(.nuna(size: 14, weight: .heavy, design: NunaType.design)).monospacedDigit()
                                    .foregroundStyle(isSel ? NunaPalette.onAccent : (future ? NunaPalette.textMuted.opacity(0.7) : NunaPalette.textPrimary))
                                    .minimumScaleFactor(0.7).lineLimit(1)
                                if future {
                                    Color.clear.frame(height: 5)
                                } else if rs.isEmpty {
                                    RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(isSel ? NunaPalette.onAccent.opacity(0.5) : NunaPalette.textMuted).frame(width: 8, height: 1.5).frame(height: 5)
                                } else {
                                    HStack(spacing: 3) {
                                        if cardio { Circle().fill(NunaPalette.effort).frame(width: 5, height: 5) }
                                        if strength { Circle().fill(isSel ? NunaPalette.onAccent : NunaPalette.accent).frame(width: 5, height: 5) }
                                    }
                                }
                            }
                            .frame(width: 42, height: 46)
                            .background(Circle().fill(isSel ? NunaPalette.accent : .clear))
                            .overlay(RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous).strokeBorder(isToday && !isSel ? NunaPalette.accent.opacity(0.8) : .clear, lineWidth: 1.5))
                            .frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).disabled(!interactive || future)
                    }
                }
            }
            HStack(spacing: 16) {
                legend(NunaPalette.effort, "Cardio"); legend(NunaPalette.textPrimary, "Strength")
                HStack(spacing: 6) { RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.textMuted).frame(width: 9, height: 1.5); Text("Rest").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
        }
        .onAppear { _ = mf }
    }

    /// The first day of a month, and the very first cell, also carry the month, so the grid reads without a header.
    private func dayLabel(_ d: Date, _ cal: Calendar, first: Bool) -> String {
        let n = cal.component(.day, from: d)
        guard n == 1 || first else { return "\(n)" }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("MMM")
        return "\(n) " + f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    private func legend(_ c: Color, _ t: LocalizedStringKey) -> some View {
        HStack(spacing: 6) { Circle().fill(c).frame(width: 7, height: 7); Text(t).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
    }
}

/// Shown at the top of Workouts while a session is running; opens the live screen again.
struct NunaActiveWorkoutBanner: View {
    @EnvironmentObject private var model: AppModel
    @State private var live = false
    var body: some View {
        if let w = model.activeWorkout {
            Button { live = true } label: {
                NunaCard(highlight: true) {
                    HStack(spacing: 12) {
                        Circle().fill(NunaPalette.charge).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Workout in progress").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: WorkoutSource.displaySport(w.sport)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        Spacer()
                        Text("Open").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    }
                }
            }.buttonStyle(.plain)
            .fullScreenCover(isPresented: $live) { NunaLiveWorkoutView(goal: NunaWorkoutGoal(), zoneBuzz: false, onClose: { live = false }) }
        }
    }
}

#endif
