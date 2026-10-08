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
    @State private var session: LiftSessionRow?
    @State private var sets: [LiftSetRow] = []
    @State private var workout: WorkoutRow?
    @State private var previousBest: [String: Double] = [:]
    @State private var loaded = false
    @State private var saveProgram = false
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var showCoach = false

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        NunaDetailScreen(LocalizedStringKey(session?.programName ?? String(localized: "Gym session"))) {
            if let session { content(session) }
            else if loaded { NunaCard { Text("This session is no longer saved.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading) } }
        }
        .task(id: repo.refreshSeq) { await load() }
        .sheet(isPresented: $saveProgram) { if let session { NunaSaveProgramView(session: session, sets: sets) } }
        .sheet(isPresented: $editing) {
            if let session { LiftSessionEditSheet(session: session, sets: sets) { await load() } }
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "workouts") }
        .environment(\.nunaAnyaCardContext, "workouts")
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

    @ViewBuilder private func content(_ s: LiftSessionRow) -> some View {
        let secs = max(0, (s.endTs ?? s.startTs) - s.startTs)
        NunaWorkoutHeaderCard(symbol: ActivitySport.symbol(for: s.sport), startTs: s.startTs, endTs: s.endTs ?? s.startTs, source: "Done", strain: workout?.strain, dayEffort: data.dayEffort)
        if !records.isEmpty {
            NunaAnyaCard(verbatim: String(localized: "Personal record on \(records.joined(separator: ", ")). Give the trained muscles two days to recover before the next session.")) { showCoach = true }
        } else if let line = volumeLine { NunaAnyaCard(verbatim: line) { showCoach = true } }
        statsCard(secs)
        NunaTitleRow(title: "Exercises") { EmptyView() }
        ForEach(summaries, id: \.exercise) { exerciseCard($0) }
        muscleVolume
        if let w = workout {
            NunaWorkoutHRCard(start: w.startTs, end: w.endTs, buckets: data.hr)
            if let mins = NunaWorkoutZoneMath.minutes(w, measured: data.zoneMin), mins.contains(where: { $0 > 0 }) { NunaWorkoutZonesCard(minutes: mins, avgHr: w.avgHr, maxHr: w.maxHr) }
        }
        NunaWorkoutReviewSection(startTs: s.startTs, sport: s.sport)
        if let w = workout { NunaWorkoutStravaCard(row: w, afterWorkout: false, checked: .constant(false)) }
        Button { saveProgram = true } label: {
            NunaCard(small: true) { NunaListRow("Save as program", description: "Repeat this session later with the same weights", systemImage: "square.and.arrow.down", showsChevron: true) }
        }.buttonStyle(.plain)
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            NunaListRow("Apple Health", description: "Strength workout, duration and energy are written by the sync. Manage it in Me", systemImage: "heart.text.square")
        }
        Button { editing = true } label: {
            Text("Edit sets").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
        Button(role: .destructive) { confirmDelete = true } label: {
            Text("Delete").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
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

    private func statsCard(_ secs: Int) -> some View {
        let volume = LiftMetrics.volumeLoadKg(sets)
        let reps = working.compactMap(\.reps).reduce(0, +)
        return NunaCard {
            VStack(spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Volume").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: volume.map { NunaTrendsFormat.num($0) } ?? "–").font(.nuna(size: 44, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(44)).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: UnitFormatter.massUnit(system)).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Duration").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: secs > 0 ? "\(max(1, secs / 60))" : "–").font(.nuna(size: 30, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            Text("min").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                }
                NunaDivider()
                HStack {
                    miniStat("Sets", "\(working.count)")
                    miniStat("Reps", "\(reps)")
                    miniStat("Avg heart rate", workout?.avgHr.map(String.init) ?? "–")
                }
            }
        }
    }

    private func miniStat(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(verbatim: v).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exerciseCard(_ s: LiftMetrics.ExerciseSummary) -> some View {
        let rows = sets.filter { $0.exercise == s.exercise }.sorted { $0.ord < $1.ord }
        let first = rows.first
        return NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    NunaExerciseThumb(name: s.exercise, width: 50, height: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: s.exercise).font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: LiftMuscleSummary.line(primary: first?.primaryMuscle, secondaries: first?.secondaryMuscles ?? [])).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    if records.contains(s.exercise) { NunaChip("PR") }
                    if let lib = NunaExerciseLibrary.match(s.exercise) {
                        NavigationLink(value: NunaWorkoutRoute.exercise(lib.id)) {
                            Image(systemName: "play.rectangle.fill").font(.nuna(size: 18)).foregroundStyle(NunaPalette.textSecondary)
                                .frame(width: 36, height: 36).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                        }.buttonStyle(.plain).accessibilityLabel(Text("Show the demo"))
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    HStack {
                        Text(verbatim: r.isWarmup ? String(localized: "Warm-up") : String(localized: "Set \(rows.prefix(i + 1).filter { !$0.isWarmup }.count)"))
                            .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        Spacer()
                        Text(verbatim: setText(r)).font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    }
                }
            }
        }
    }

    private func setText(_ r: LiftSetRow) -> String {
        switch (r.weightKg, r.reps) {
        case let (w?, n?): return "\(LiftFormat.weight(w, system: system)) × \(n)"
        case let (w?, nil): return LiftFormat.weight(w, system: system)
        case let (nil, n?): return "× \(n)"
        default: return "–"
        }
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
        if let w = workout { await data.load(startTs: w.startTs, endTs: w.endTs, sport: w.sport, source: w.source, repo: repo, zoneSet: profile.hrZoneSet) }
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
        await repo.refresh()
        dismiss()
    }
}
#endif
