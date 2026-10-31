#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// One finished gym session (WorkoutSummaryGym.dc): volume, time, sets and reps, the Effort it added, every exercise
/// with its sets, volume per muscle, personal records and the housekeeping actions. Reads the Lift Log tables and the
/// workout row the session is pinned to; nothing is estimated beyond the weight times reps the sets already carry.
struct NunaGymSessionView: View {
    let sessionId: String
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @StateObject private var data = NunaWorkoutDetailData()
    /// The earlier sessions the cardio and muscular split is ranked against.
    @StateObject private var history = NunaWorkoutsModel()
    @State private var session: LiftSessionRow?
    @State private var sets: [LiftSetRow] = []
    @State private var workout: WorkoutRow?
    @State private var previousBest: [String: Double] = [:]
    @State private var loaded = false
    @State private var saveProgram = false
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var showCoach = false
    @State private var tab = Tab.exercises
    @State private var open: Set<String> = []
    @State private var zonePick: Int?
    /// The card showing under the chart: 0 is the whole session, then one per exercise.
    @State private var page = 0
    @State private var showAll = false
    /// Where the Strava upload of this session stands, shown in the three dots like any other workout.
    @State private var stravaState: NunaStravaState = .off
    @State private var stravaMessage: String?
    @StateObject private var strava = StravaSettingsModel()

    fileprivate enum Tab: Hashable { case exercises, heartRate }

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        NunaDetailScreen("Gym session", titleSymbol: session.map { ActivitySport.symbol(for: $0.sport) } ?? "dumbbell", subtitle: session.map { NunaWorkoutFormat.span($0.startTs, $0.endTs ?? $0.startTs) }, trailing: session == nil ? nil : AnyView(actionsMenu)) {
            if let session { VStack(spacing: 14) { content(session) } }
            else if loaded { NunaCard { Text("This session is no longer saved.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading) } }
        }
        .navigationDestination(isPresented: $showAll) {
            NunaDetailScreen("Exercises") { allExercises }
        }
        .task(id: repo.refreshSeq) { await load(); await history.load(repo: repo) }
        .sheet(isPresented: $saveProgram) { if let session { NunaSaveProgramView(session: session, sets: sets) } }
        .sheet(isPresented: $editing) {
            if let session { LiftSessionEditSheet(session: session, sets: sets) { await load() } }
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "workouts") }
        .environment(\.nunaAnyaCardContext, "workouts")
        .alert(stravaMessage ?? "", isPresented: Binding(get: { stravaMessage != nil }, set: { if !$0 { stravaMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteSession() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("\(sets.count) recorded sets will be removed, and so will the workout this session created. This cannot be undone.") }
    }

    // MARK: Derived

    private var working: [LiftSetRow] { sets.filter { !$0.isWarmup } }
    private var summaries: [LiftMetrics.ExerciseSummary] { LiftMetrics.perExercise(sets) }
    /// Exercises where today's heaviest working set beats everything logged before it.
    private var records: [String] {
        summaries.compactMap { s in
            guard let w = s.bestWeightKg, w > 0, let prev = previousBest[s.exercise], w > prev else { return nil }
            return s.exercise
        }
    }

    /// The three outlined circles: what used to be buttons at the foot of the page.
    private var actionsMenu: some View {
        var items: [NunaActionItem] = []
        if let w = workout {
            switch stravaState {
            case .ready: items.append(NunaActionItem(title: "Upload to Strava", symbol: "arrow.up.circle") { Task { await sendToStrava(w) } })
            case .uploaded, .processing: items.append(NunaActionItem(title: "On Strava", symbol: "checkmark.circle", enabled: false) {})
            default: break
            }
        }
        items.append(NunaActionItem(title: "Save as program", symbol: "square.and.arrow.down") { saveProgram = true })
        items.append(NunaActionItem(title: "Edit sets", symbol: "pencil") { editing = true })
        items.append(NunaActionItem(title: "Delete", symbol: "trash", destructive: true) { confirmDelete = true })
        return NunaActionsButton(items: items)
    }

    /// Top to bottom: the program, the Effort it added beside the cardio and muscular split, two tabs (the exercises, with the heart rate, a
    /// card for the whole session and one for each exercise, and the key statistics; and the heart rate with its zones), then Anya's line.
    @ViewBuilder private func content(_ s: LiftSessionRow) -> some View {
        let averages = workout.flatMap { NunaWorkoutAverages(for: $0, in: history.rows) }
        if let program = s.programName, !program.isEmpty {
            Text(verbatim: program).font(.nuna(size: 14, weight: .semibold)).textCase(nil)
                .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 34)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(NunaPalette.textSecondary.opacity(0.55), lineWidth: 1.5))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        effortAndSplit(s, averages: averages)
        NunaCapsuleTabs(options: [(value: Tab.exercises, title: "Exercises"), (value: Tab.heartRate, title: "HR zones")], selection: $tab)
        switch tab {
        case .exercises: exercisesTab
        case .heartRate: heartRateTab
        }
        // Anya's line sits under the exercises and the heart rate, as on every other saved workout.
        if !records.isEmpty {
            NunaAnyaCard(verbatim: String(localized: "Personal record on \(records.joined(separator: ", ")). Give the trained muscles two days to recover before the next session.")) { showCoach = true }
        } else if let line = volumeLine { NunaAnyaCard(verbatim: line) { showCoach = true } }
    }

    private func sendToStrava(_ w: WorkoutRow) async {
        await strava.upload(w)
        stravaState = NunaStravaCheck.state(w)
        stravaMessage = strava.statusText
    }

    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// The Effort the session added with its 30-day average beside it, and the cardio and muscular share at the right. The bar is level with
    /// the figure and its two percentages with the caption under it.
    private func effortAndSplit(_ s: LiftSessionRow, averages: NunaWorkoutAverages?) -> some View {
        let strain = workout?.strain
        return GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(verbatim: strain.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "–")
                            .font(.nuna(size: 32, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(32))
                            .foregroundStyle(strain.map(nunaEffortColor) ?? NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                        if let st = strain, let avg = averages?.effort {
                            NunaAveragePill(value: st, average: avg, text: UnitFormatter.effortDisplay(avg, scale: effortScale), compact: true)
                        }
                    }
                    Text("Activity Effort").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                }
                .frame(width: geo.size.width * 0.45, alignment: .leading)
                Rectangle().fill(NunaPalette.textPrimary.opacity(0.1)).frame(width: 1, height: 58)
                NunaCardioMuscularCard(split: loadSplit(s), compact: true)
                    .padding(.leading, 18)
                    .frame(width: geo.size.width * 0.55 - 1, alignment: .leading)
            }
            .frame(height: geo.size.height, alignment: .bottom)
        }
        .frame(height: 64)
    }

    /// Effort per minute and kilograms per minute for one session, each nil when it cannot be worked out. Sessions under five
    /// minutes are left out: a rate over a few seconds is noise.
    private func rates(_ s: LiftSessionRow, sets: [LiftSetRow], strain: Double?) -> (cardio: Double?, muscular: Double?) {
        let minutes = Double((s.endTs ?? s.startTs) - s.startTs) / 60
        guard minutes >= 5 else { return (nil, nil) }
        return (strain.flatMap { $0 > 0 ? $0 / minutes : nil }, LiftMetrics.volumeLoadKg(sets).map { $0 / minutes })
    }

    /// This session against the earlier ones with sets (the last 120 days the model holds).
    private func loadSplit(_ s: LiftSessionRow) -> SessionLoadSplit.Result? {
        let now = rates(s, sets: sets, strain: workout?.strain)
        var cardio: [Double] = [], muscular: [Double] = []
        for other in history.liftSessions where other.id != s.id && other.startTs < s.startTs {
            let strain = history.rows.first { $0.startTs == other.startTs }?.strain
            let r = rates(other, sets: history.liftSets[other.id] ?? [], strain: strain)
            if let c = r.cardio { cardio.append(c) }
            if let m = r.muscular { muscular.append(m) }
        }
        return SessionLoadSplit.split(cardio: now.cardio, muscular: now.muscular, cardioHistory: cardio, muscularHistory: muscular)
    }

    /// Which muscle group took most of the volume, when no record was set.
    private var volumeLine: String? {
        var vol: [NunaMuscleGroup: Double] = [:]
        for r in working { if let p = r.primaryMuscle, let w = r.weightKg, let n = r.reps { vol[NunaMuscleGroup.of(p), default: 0] += w * Double(n) } }
        let total = vol.values.reduce(0, +)
        guard total > 0, let top = vol.max(by: { $0.value < $1.value }) else { return nil }
        let pct = Int((top.value / total * 100).rounded())
        return String(localized: "Most of the volume, \(pct)%, went to \(top.key.name).")
    }

    private struct StatTile: Identifiable {
        let id: String; let icon: String; let label: LocalizedStringKey; let value: String; var unit = ""
        /// Shown after the value in a smaller size (the seconds of a duration).
        var small = ""
        var pill: (value: Double, average: Double, text: String)?
    }

    /// Key statistics for lifting: how long, the calories and the heart rate, each against the wearer's
    /// 30-day average where there is one.
    private func keyStatistics(_ secs: Int, averages: NunaWorkoutAverages?) -> some View {
        // The volume and the sets are on the cards above, so they are not said twice here.
        var tiles: [StatTile] = []
        func clock(_ t: Int) -> String { String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) }
        var dur = StatTile(id: "dur", icon: "timer", label: "Duration", value: secs > 0 ? String(format: "%d:%02d", secs / 3600, (secs % 3600) / 60) : "–")
        if secs > 0 { dur.small = String(format: ":%02d", secs % 60) }
        if secs > 0, let avg = averages?.durationS { dur.pill = (Double(secs), avg, clock(Int(avg.rounded()))) }
        tiles.append(dur)
        if let hr = workout?.avgHr {
            var t = StatTile(id: "avg", icon: "heart", label: "Avg HR", value: "\(hr)", unit: "bpm")
            if let avg = averages?.avgHr { t.pill = (Double(hr), avg, "\(Int(avg.rounded())) bpm") }
            tiles.append(t)
        }
        if let hr = workout?.maxHr {
            var t = StatTile(id: "max", icon: "bolt.heart", label: "Max HR", value: "\(hr)", unit: "bpm")
            if let avg = averages?.maxHr { t.pill = (Double(hr), avg, "\(Int(avg.rounded())) bpm") }
            tiles.append(t)
        }
        if let kcal = workout?.energyKcal {
            var t = StatTile(id: "kcal", icon: "flame", label: "Calories", value: NunaTrendsFormat.num(kcal), unit: "kcal")
            if let avg = averages?.kcal { t.pill = (kcal, avg, NunaTrendsFormat.num(avg)) }
            tiles.append(t)
        }
        return VStack(alignment: .leading, spacing: 10) {
            NunaLogSectionTitle(title: "Key statistics", trailing: averages != nil ? "vs. 30 day average" : nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(tiles) { statTile($0, reservePill: tiles.contains { $0.pill != nil }).frame(width: 168) }
                }
                .padding(.horizontal, NunaSpacing.screenH)
            }
            .padding(.horizontal, -NunaSpacing.screenH)
        }
    }

    private func statTile(_ t: StatTile, reservePill: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: t.icon).font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                Text(t.label).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel + 0.4).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.bottom, 4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                (Text(verbatim: t.value).font(.nuna(size: 28, weight: .bold, design: NunaType.design))
                    + Text(verbatim: t.small).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary))
                    .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                if !t.unit.isEmpty && t.value != "–" { Text(verbatim: t.unit).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(1) }
            }
            .padding(.bottom, 4)
            if let p = t.pill { NunaAveragePill(value: p.value, average: p.average, text: p.text) }
            else if reservePill { Color.clear.frame(height: 24) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Tabs

    @ViewBuilder private var exercisesTab: some View {
        if let w = workout, data.hr.count >= 2 {
            NunaWorkoutHRArea(buckets: data.hr, start: w.startTs, end: w.endTs, around: data.hrAround, rangeHighlight: pageRanges)
        }
        exerciseCarousel
        if let s = session {
            keyStatistics(max(0, (s.endTs ?? s.startTs) - s.startTs), averages: workout.flatMap { NunaWorkoutAverages(for: $0, in: history.rows) })
        }
        muscleVolume
    }

    /// Every exercise with its sets, opened from VIEW ALL.
    @ViewBuilder private var allExercises: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: String(localized: "\(summaries.count) exercises") + " · " + String(localized: "\(working.count) sets"))
                .font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Spacer()
            if summaries.count > 1 {
                Button { withAnimation(.easeInOut(duration: 0.2)) { open = open.count == summaries.count ? [] : Set(summaries.map(\.exercise)) } } label: {
                    Text(open.count == summaries.count ? "Collapse all" : "Open all").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        .frame(minHeight: 32)
                }.buttonStyle(.plain)
            }
        }
        VStack(spacing: 10) {
            ForEach(summaries, id: \.exercise) { exerciseRow($0) }
        }
    }

    // MARK: Cards under the chart

    /// The sets of the exercise on the card, as stretches of the session: they are lit on the chart.
    private var pageRanges: [ClosedRange<Int>] {
        guard page >= 1, page - 1 < summaries.count else { return [] }
        let name = summaries[page - 1].exercise
        return sets.filter { $0.exercise == name }.compactMap { r in
            guard let a = r.startTs else { return nil }
            return (a - 5)...max(a + 20, (r.endTs ?? a) + 5)
        }
    }

    private var exerciseCarousel: some View {
        let pages = summaries.count + 1
        return VStack(spacing: 4) {
            TabView(selection: $page) {
                summaryCard.tag(0)
                ForEach(Array(summaries.enumerated()), id: \.element.exercise) { i, s in exerciseCard(s).tag(i + 1) }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 122)
            ZStack {
                HStack(spacing: 10) {
                    let first = max(0, min(page - 3, pages - 7))
                    ForEach(first..<min(pages, first + 7), id: \.self) { i in
                        let near = abs(i - page)
                        Circle().fill(i == page ? NunaPalette.textPrimary : NunaPalette.textMuted.opacity(0.7))
                            .frame(width: near == 0 ? 11 : (near < 3 ? 9 : 6), height: near == 0 ? 11 : (near < 3 ? 9 : 6))
                    }
                }
                HStack {
                    Spacer()
                    Button { showAll = true } label: {
                        HStack(spacing: 8) {
                            Text("View all").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel + 0.8).textCase(.uppercase)
                            Image(systemName: "arrow.right").font(.system(size: 17, weight: .regular))
                        }
                        .foregroundStyle(NunaPalette.textPrimary).frame(minHeight: 36)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var summaryCard: some View {
        let reps = working.compactMap(\.reps).reduce(0, +)
        let symbol = session.map { ActivitySport.symbol(for: $0.sport) } ?? "dumbbell"
        return carouselCard(title: String(localized: "\(summaries.count) Exercises"), setsText: String(localized: "\(working.count) Sets"), tint: NunaPalette.effortModerate,
                            thumb: AnyView(ZStack { Color.white.opacity(0.08); Image(systemName: symbol).font(.system(size: 26, weight: .regular)).foregroundStyle(NunaPalette.textPrimary) }),
                            volume: LiftMetrics.volumeLoadKg(sets), reps: reps, pr: false, route: nil)
    }

    private func exerciseCard(_ s: LiftMetrics.ExerciseSummary) -> some View {
        let rows = working.filter { $0.exercise == s.exercise }
        let reps = rows.compactMap(\.reps).reduce(0, +)
        return carouselCard(title: s.exercise, setsText: String(localized: "\(s.workingSets) Sets"), tint: NunaWorkoutLogZones.colors[2],
                            thumb: AnyView(NunaExerciseThumb(name: s.exercise, width: 60, height: 46)),
                            volume: s.volumeKg, reps: reps, pr: records.contains(s.exercise), route: NunaExerciseLibrary.match(s.exercise).map { NunaWorkoutRoute.exercise($0.id) })
    }

    /// A card of the strip under the chart: the picture, name and sets above, the volume load and the reps below.
    private func carouselCard(title: String, setsText: String, tint: Color, thumb: AnyView, volume: Double?, reps: Int, pr: Bool, route: NunaWorkoutRoute?) -> some View {
        VStack(spacing: 0) {
            let head = HStack(spacing: 14) {
                thumb.frame(width: 60, height: 46).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: title).font(.nuna(size: 15, weight: .medium)).textCase(nil).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 8) {
                        Text(verbatim: setsText).font(.nuna(size: 13.5, weight: .semibold)).textCase(nil).foregroundStyle(tint)
                        if pr { Image(systemName: "rosette").font(.system(size: 17, weight: .regular)).foregroundStyle(NunaPalette.warning) }
                    }
                }
                Spacer(minLength: 8)
                if route != nil { Image(systemName: "chevron.right").font(.system(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textPrimary) }
            }
            .padding(4).padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .contentShape(Rectangle())
            if let route { NavigationLink(value: route) { head }.buttonStyle(.plain) } else { head }
            HStack(alignment: .top, spacing: 0) {
                metric(volume.map { NunaTrendsFormat.num($0) } ?? "–", UnitFormatter.massUnit(system), "Volume load").frame(width: 140, alignment: .leading)
                metric("\(reps)", "", "Total reps")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NunaPalette.tile)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 1)
    }

    private func metric(_ value: String, _ unit: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value).font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil) }
            }
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel + 0.6).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
        }
    }

    @ViewBuilder private var heartRateTab: some View {
        if let w = workout, data.hr.count >= 2 {
            NunaWorkoutHRArea(buckets: data.hr, start: w.startTs, end: w.endTs, around: data.hrAround, highlightZone: zonePick, zoneSet: profile.hrZoneSet)
            if let mins = NunaWorkoutZoneMath.minutes(w, measured: data.zoneMin), mins.contains(where: { $0 > 0 }) {
                NunaWorkoutLogZones(minutes: mins, selection: $zonePick, buckets: data.hr, start: w.startTs, end: w.endTs, typical: NunaWorkoutLogZones.typical(for: w, in: history.rows), belowMinutes: NunaWorkoutZoneMath.below(w, measured: data.zoneMin))
            }
        } else {
            NunaCard(small: true) {
                Text("No heart rate was recorded for this session.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// One exercise: its name, the muscles and a line of what was done; tapping it opens every set, the record and the demo.
    private func exerciseRow(_ s: LiftMetrics.ExerciseSummary) -> some View {
        let rows = sets.filter { $0.exercise == s.exercise }.sorted { $0.ord < $1.ord }
        let first = rows.first
        let isOpen = open.contains(s.exercise)
        let best = rows.filter { !$0.isWarmup }.max { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }
        return NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { if isOpen { open.remove(s.exercise) } else { open.insert(s.exercise) } } } label: {
                    HStack(spacing: 12) {
                        NunaExerciseThumb(name: s.exercise, width: 50, height: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: s.exercise).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.leading)
                            Text(verbatim: String(localized: "\(s.workingSets) sets") + (best.map { " · " + setText($0) } ?? ""))
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        Spacer(minLength: 8)
                        if records.contains(s.exercise) { NunaChip("PR") }
                        Image(systemName: "chevron.down").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted).rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                if isOpen {
                    NunaDivider()
                    Text(verbatim: LiftMuscleSummary.line(primary: first?.primaryMuscle, secondaries: first?.secondaryMuscles ?? []))
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        HStack {
                            Text(verbatim: r.isWarmup ? String(localized: "Warm-up") : String(localized: "Set \(rows.prefix(i + 1).filter { !$0.isWarmup }.count)"))
                                .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            Spacer()
                            Text(verbatim: setText(r)).font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        }
                    }
                    if let lib = NunaExerciseLibrary.match(s.exercise) {
                        NavigationLink(value: NunaWorkoutRoute.exercise(lib.id)) {
                            Label("Show the demo", systemImage: "play.rectangle.fill").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                .frame(minHeight: 36)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func setText(_ r: LiftSetRow) -> String {
        NunaExerciseKind.of(r.exercise).setText(weightKg: r.weightKg, reps: r.reps, system: system)
    }

    private var muscleVolume: some View {
        var vol: [NunaMuscleGroup: Double] = [:]
        for r in working { if let p = r.primaryMuscle, let w = r.weightKg, let n = r.reps { vol[NunaMuscleGroup.of(p), default: 0] += w * Double(n) } }
        let ordered = vol.sorted { $0.value > $1.value }
        return Group {
            if !ordered.isEmpty {
                NunaTitleRow(title: "Volume per muscle") { EmptyView() }
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        ForEach(Array(ordered.enumerated()), id: \.element.key) { i, e in
                            if i > 0 { NunaDivider() }
                            HStack {
                                Text(e.key.title).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Spacer()
                                Text(verbatim: NunaTrendsFormat.num(e.value) + " " + UnitFormatter.massUnit(system)).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            }.padding(.vertical, 14)
                        }
                    }
                }
            }
        }
    }

    // MARK: Data

    private func load() async {
        guard let store = await repo.storeHandle() else { loaded = true; return }
        let now = Int(Date().timeIntervalSince1970)
        let all = (try? await store.liftSessions(deviceId: repo.deviceId, fromTs: 0, toTs: now + 86_400)) ?? []
        guard let s = all.first(where: { $0.id == sessionId }) else { session = nil; loaded = true; return }
        session = s
        sets = (try? await store.liftSets(sessionId: s.id)) ?? []
        // The same list Today and the Workouts hub read, not the raw stored row: the stored row has no Effort for a gym session (it is
        // filled in at read time from the measured heart rate), so reading it here showed a different figure, or none.
        workout = await repo.workoutRows().first { $0.startTs == s.startTs && $0.sport == s.sport }
        if let w = workout {
            await data.load(startTs: w.startTs, endTs: w.endTs, sport: w.sport, source: w.source, repo: repo, zoneSet: profile.hrZoneSet)
            stravaState = NunaStravaCheck.state(w)
        }
        // The heaviest working set of each exercise across every earlier session: a record means beating all of them.
        var prev: [String: Double] = [:]
        let names = Set(sets.map(\.exercise))
        for earlier in all where earlier.startTs < s.startTs {
            for r in (try? await store.liftSets(sessionId: earlier.id)) ?? [] where !r.isWarmup && names.contains(r.exercise) {
                if let w = r.weightKg { prev[r.exercise] = max(prev[r.exercise] ?? 0, w) }
            }
        }
        previousBest = prev
        loaded = true
    }

    private func deleteSession() async {
        guard let session, let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLiftSession(id: session.id)
        NunaWorkoutReviewStore.remove(startTs: session.startTs, sport: session.sport)
        if let workout { await repo.deleteWorkout(workout) }
        await repo.refresh()
        dismiss()
    }
}

// MARK: - Save as program (WorkoutSaveProgram.dc)

/// Turn a finished session into a program: choose the exercises and whether the weights it used become the targets.
struct NunaSaveProgramView: View {
    let session: LiftSessionRow
    let sets: [LiftSetRow]
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @State private var name = ""
    @State private var excluded: Set<String> = []
    @State private var useWeights = true
    @State private var saving = false

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var summaries: [LiftMetrics.ExerciseSummary] { LiftMetrics.perExercise(sets) }
    private var chosen: [LiftMetrics.ExerciseSummary] { summaries.filter { !excluded.contains($0.exercise) } }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chosen.isEmpty && !saving }

    var body: some View {
        NavigationStack {
            NunaDetailScreen("Save as program") {
                HStack {
                    Text(verbatim: NunaWorkoutFormat.day(session.startTs)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    Spacer()
                    Text(verbatim: session.programName ?? String(localized: "Gym")).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                }
                NunaFormField("Program name") { TextField("", text: $name, prompt: Text("Push · chest and shoulders").foregroundStyle(NunaPalette.textMuted)) }
                NunaTitleRow(title: "Included exercises") { EmptyView() }
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        ForEach(Array(summaries.enumerated()), id: \.element.exercise) { i, s in
                            if i > 0 { NunaDivider() }
                            Button { if excluded.contains(s.exercise) { excluded.remove(s.exercise) } else { excluded.insert(s.exercise) } } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: s.exercise).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                        Text(verbatim: line(s)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                    }
                                    Spacer()
                                    Image(systemName: excluded.contains(s.exercise) ? "circle" : "checkmark.circle.fill").font(.nuna(size: 22))
                                        .foregroundStyle(excluded.contains(s.exercise) ? NunaPalette.textMuted : NunaPalette.textPrimary)
                                }.padding(.vertical, 12).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                NunaCard(small: true) {
                    NunaToggleRow("Use this session's weights as targets", subtitle: "Off: only the name and number of sets", systemImage: "scalemass", isOn: $useWeights)
                }
                Button { Task { await save() } } label: {
                    Text("Save program").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(!canSave).opacity(canSave ? 1 : 0.4)
                Text("It shows up in Gym under Programs and can be edited any time.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .nunaKeyboardDone()
        }
        .preferredColorScheme(NunaTheme.colorScheme)
        .onAppear { if name.isEmpty { name = session.programName ?? "" } }
    }

    private func line(_ s: LiftMetrics.ExerciseSummary) -> String {
        var t = String(localized: "\(s.workingSets) sets")
        if useWeights, let w = s.bestWeightKg { t += " · " + LiftFormat.weight(w, system: system) }
        return t
    }

    private func save() async {
        guard canSave, let store = await repo.storeHandle() else { return }
        saving = true; defer { saving = false }
        let now = Int(Date().timeIntervalSince1970)
        let pid = UUID().uuidString
        _ = try? await store.upsertLiftPrograms([LiftProgramRow(id: pid, deviceId: repo.deviceId, name: name.trimmingCharacters(in: .whitespacesAndNewlines), note: nil, createdAt: now, updatedAt: now, archived: false)])
        let items = chosen.enumerated().map { i, s -> LiftProgramItemRow in
            let rows = sets.filter { $0.exercise == s.exercise && !$0.isWarmup }
            let best = rows.max { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }
            return LiftProgramItemRow(id: UUID().uuidString, deviceId: repo.deviceId, programId: pid, ord: i, exercise: s.exercise,
                                      targetSets: max(1, s.workingSets), targetRepsLow: useWeights ? best?.reps : nil, targetRepsHigh: nil, targetRpe: nil,
                                      targetWeightKg: useWeights ? best?.weightKg : nil, restSec: rows.compactMap(\.restSec).max(), note: nil)
        }
        _ = try? await store.replaceLiftProgramItems(programId: pid, items: items)
        NunaProgramGroupsModel.shared.placeNew(pid)
        await repo.refresh()
        dismiss()
    }
}

#endif
