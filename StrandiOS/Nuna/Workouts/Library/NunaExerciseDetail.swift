#if os(iOS)
import SwiftUI
import Charts
import MuscleMap
import StrandDesign
import WhoopStore

/// One exercise of the library in three tabs. Summary: the animated demo, the muscles on a body map, a chart of what you lifted in it and
/// your records. History: every session you logged it in. How to: the steps. The chart, the records and the history are read from the sets
/// you logged; nothing in them comes from the library.
struct NunaExerciseDetailView: View {
    let exerciseId: String
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @StateObject private var history = NunaExerciseHistoryModel()
    @State private var tab = Tab.summary
    @State private var metric = Metric.heaviest
    @State private var period = Period.threeMonths
    @State private var selectedDate: Date?
    @State private var showSetRecords = false
    @State private var editingNote = false
    @State private var noteDraft = ""
    @State private var pinnedNote = ""

    private enum Tab: String, CaseIterable { case summary, history, howTo
        var title: LocalizedStringKey { switch self { case .summary: "Summary"; case .history: "History"; case .howTo: "How to" } }
    }
    private enum Metric: String, CaseIterable { case heaviest, oneRepMax, setVolume, sessionVolume, mostReps, totalReps, longestHold, totalTime
        var title: LocalizedStringKey {
            switch self {
            case .heaviest: "Heaviest weight"; case .oneRepMax: "One rep max"; case .setVolume: "Best set volume"; case .sessionVolume: "Session volume"
            case .mostReps: "Most reps in a set"; case .totalReps: "Total reps"; case .longestHold: "Longest hold"; case .totalTime: "Total time"
            }
        }
        /// What an exercise can be charted by, depending on how it is logged.
        static func available(for kind: NunaExerciseKind) -> [Metric] {
            switch kind {
            case .weighted: return [.heaviest, .oneRepMax, .setVolume, .sessionVolume]
            case .bodyweight: return [.mostReps, .totalReps]
            case .timed: return [.longestHold, .totalTime]
            }
        }
    }
    private enum Period: String, CaseIterable {
        case threeMonths, year, all
        var title: LocalizedStringKey { switch self { case .threeMonths: "Last 3 months"; case .year: "Last year"; case .all: "All time" } }
        var days: Int? { switch self { case .threeMonths: 92; case .year: 366; case .all: nil } }
    }

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        if let e = NunaExerciseLibrary.exercise(id: exerciseId) {
            NunaDetailScreen(LocalizedStringKey(e.name)) { content(e) }
                .task { await history.load(libraryId: e.id, repo: repo); pinnedNote = NunaExerciseNotes.note(for: e.id) }
        } else {
            NunaDetailScreen("Exercise") {
                NunaCard { Text("This exercise is not in the library.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            }
        }
    }

    @ViewBuilder private func content(_ e: NunaLibraryExercise) -> some View {
        tabs
        switch tab {
        case .summary: summary(e)
        case .history: historyList
        case .howTo: howTo(e)
        }
        if !e.id.hasPrefix("custom-") {
            nunaFootnote("Photos and text: free-exercise-db, public domain (The Unlicense). The body map is MuscleMap, MIT licence. Both are listed under About › Open-source notices.")
        }
    }

    private var tabs: some View {
        NunaPageTabs(Tab.allCases.map { (value: $0, title: $0.title) }, selection: $tab)
    }

    // MARK: Summary

    @ViewBuilder private func summary(_ e: NunaLibraryExercise) -> some View {
        NunaExerciseDemo(exercise: e)
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: e.name).font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Text(verbatim: String(localized: "Primary: \(e.primaryMuscles.map(NunaLibraryExercise.title).joined(separator: ", "))")).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            if !e.secondaryMuscles.isEmpty {
                Text(verbatim: String(localized: "Secondary: \(e.secondaryMuscles.map(NunaLibraryExercise.title).joined(separator: ", "))")).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 8) {
            if let t = e.equipmentTitle { NunaChip(verbatim: t) }
            if let t = e.levelTitle { NunaChip(verbatim: t) }
            if let m = e.mechanic { NunaChip(verbatim: m == "compound" ? String(localized: "Compound") : String(localized: "Isolation")) }
            Spacer(minLength: 0)
        }
        if e.id.hasPrefix("custom-") { customNote(e) }
        progressCard(kind: NunaExerciseKind.of(e.name))
        recordsCard(kind: NunaExerciseKind.of(e.name))
        if !(e.id.hasPrefix("custom-") && e.primaryMuscles.isEmpty) { musclesCard(e) }
    }

    /// An exercise the person made up has a page like any other; this says where its muscles came from, so they can be trusted or corrected.
    private func customNote(_ e: NunaLibraryExercise) -> some View {
        let words: LocalizedStringKey
        if e.primaryMuscles.isEmpty { words = "Your own exercise. Its muscles are not known yet; Anya fills them in from its name when she is connected." }
        else {
            switch NunaCustomExercises.source(forName: e.name) {
            case "anya": words = "Your own exercise. Anya worked out its muscles from the name. Correct them under Muscles and technique in a program."
            case "library": words = "Your own exercise. Its muscles come from the closest exercise in the library. Correct them under Muscles and technique in a program."
            default: words = "Your own exercise, with the muscles you gave it."
            }
        }
        return NunaCard(small: true) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                Text(words).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
    }

    private func value(_ s: NunaExerciseSession) -> Double? {
        switch metric {
        case .heaviest: return s.heaviest
        case .oneRepMax: return s.oneRepMax
        case .setVolume: return s.bestSetVolume
        case .sessionVolume: return s.volume > 0 ? s.volume : nil
        case .mostReps, .longestHold: return s.working.compactMap(\.reps).max().map(Double.init)
        case .totalReps, .totalTime: let t = s.working.compactMap(\.reps).reduce(0, +); return t > 0 ? Double(t) : nil
        }
    }

    private func isMass(_ m: Metric) -> Bool { [.heaviest, .oneRepMax, .setVolume, .sessionVolume].contains(m) }
    private func chartValue(_ v: Double, _ m: Metric) -> Double { isMass(m) ? LiftFormat.display(fromKilograms: v, system: system) : v }
    private func figure(_ v: Double, _ m: Metric) -> String {
        switch m {
        case .longestHold, .totalTime: return NunaExerciseKind.clock(Int(v))
        case .mostReps, .totalReps: return "\(Int(v))"
        default: return LiftFormat.trim(LiftFormat.display(fromKilograms: v, system: system))
        }
    }
    private func unit(_ m: Metric) -> String? { isMass(m) ? UnitFormatter.massUnit(system) : (m == .mostReps || m == .totalReps ? String(localized: "reps") : nil) }

    /// The chart for the chosen metric and period. Dragging over it reads any session; the header says its figure and day.
    private func progressCard(kind: NunaExerciseKind) -> some View {
        let metrics = Metric.available(for: kind)
        let activeMetric = metrics.contains(metric) ? metric : metrics[0]
        let cutoff = period.days.map { Date().addingTimeInterval(-Double($0) * 86_400) }
        let points = history.sessions.reversed().compactMap { s -> (date: Date, kg: Double)? in
            let d = Date(timeIntervalSince1970: TimeInterval(s.startTs))
            if let cutoff, d < cutoff { return nil }
            return value(s).map { (date: d, kg: $0) }
        }
        let shown = selectedDate.flatMap { sel in points.min { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) } } ?? points.last
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    if let last = shown {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: figure(last.kg, activeMetric)).font(.nuna(size: 30, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            if let unit = unit(activeMetric) { Text(verbatim: unit).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                            Text(verbatim: NunaWorkoutFormat.day(Int(last.date.timeIntervalSince1970))).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.restText).textCase(nil)
                        }
                    } else {
                        nunaTrendsCap(activeMetric.title)
                    }
                    Spacer(minLength: 8)
                    Menu {
                        Picker("Period", selection: $period) { ForEach(Period.allCases, id: \.self) { Text($0.title).tag($0) } }
                    } label: {
                        HStack(spacing: 4) {
                            Text(period.title).font(.nuna(size: 13.5, weight: .bold))
                            Image(systemName: "chevron.down").font(.nuna(size: 11, weight: .bold))
                        }.foregroundStyle(NunaPalette.restText).frame(minHeight: 32)
                    }
                }
                if points.isEmpty {
                    Text(history.loaded ? "Log this exercise in a gym session and its progress shows here." : " ")
                        .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                } else {
                    Chart {
                        ForEach(Array(points), id: \.date) { p in
                            let v = chartValue(p.kg, activeMetric)
                            LineMark(x: .value("Date", p.date), y: .value("Weight", v)).foregroundStyle(NunaPalette.textPrimary).interpolationMethod(.monotone)
                            PointMark(x: .value("Date", p.date), y: .value("Weight", v)).foregroundStyle(NunaPalette.textPrimary).symbolSize(points.count > 40 ? 8 : 30)
                        }
                        if let sel = shown {
                            RuleMark(x: .value("Date", sel.date)).foregroundStyle(NunaPalette.restText.opacity(0.5))
                            PointMark(x: .value("Date", sel.date), y: .value("Weight", chartValue(sel.kg, activeMetric)))
                                .foregroundStyle(NunaPalette.restText).symbolSize(90)
                        }
                    }
                    .chartXSelection(value: $selectedDate)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(NunaPalette.textMuted) } }
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(NunaPalette.hairline); AxisValueLabel().foregroundStyle(NunaPalette.textMuted) } }
                    .frame(height: 190)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(metrics, id: \.self) { m in
                            Button { metric = m } label: {
                                Text(m.title).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(activeMetric == m ? NunaPalette.onAccent : NunaPalette.textPrimary)
                                    .padding(.horizontal, 16).frame(height: 36).background(activeMetric == m ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func recordsCard(kind: NunaExerciseKind) -> some View {
        let r = NunaExerciseHistory.records(history.sessions)
        func mass(_ kg: Double?) -> String { LiftFormat.weight(kg, system: system) }
        return NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Personal records")
                if history.sessions.isEmpty {
                    Text("No sets logged yet.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                } else {
                    switch kind {
                    case .weighted:
                        recordRow("Heaviest weight", mass(r.heaviest))
                        recordRow("One rep max", mass(r.oneRepMax))
                        recordRow("Best set volume", mass(r.bestSetVolume))
                        recordRow("Best session volume", mass(r.bestSessionVolume))
                        recordRow("Most reps in a set", r.mostReps.map(String.init) ?? "—")
                        Text("The one rep max is an estimate from sets of 12 reps or fewer.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                        setRecords
                    case .bodyweight:
                        recordRow("Most reps in a set", r.mostReps.map(String.init) ?? "—")
                        recordRow("Most reps in a session", r.mostRepsInSession.map(String.init) ?? "—")
                    case .timed:
                        recordRow("Longest hold", r.mostReps.map(NunaExerciseKind.clock) ?? "—")
                        recordRow("Most time in a session", r.mostRepsInSession.map(NunaExerciseKind.clock) ?? "—")
                    }
                }
            }
        }
    }

    /// For every number of reps you have done, the heaviest weight you did it with.
    @ViewBuilder private var setRecords: some View {
        let table = NunaExerciseHistory.setRecords(history.sessions)
        if !table.isEmpty {
            NunaDivider()
            Button { withAnimation(.easeInOut(duration: 0.2)) { showSetRecords.toggle() } } label: {
                HStack {
                    Text("Set records").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted).rotationEffect(.degrees(showSetRecords ? 180 : 0))
                }.frame(minHeight: 36).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if showSetRecords {
                HStack {
                    Text("Reps").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    Text("Personal best").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                }
                ForEach(table, id: \.reps) { row in
                    HStack {
                        Text(verbatim: "\(row.reps)").font(.nuna(size: 15, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        Text(verbatim: LiftFormat.weight(row.kg, system: system)).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.restText)
                    }
                }
            }
        }
    }

    private func recordRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Text(verbatim: value).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.restText)
        }
    }

    private func musclesCard(_ e: NunaLibraryExercise) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("Muscles worked")
                NunaExerciseBodyMap(primary: e.primaryMap, secondary: e.secondaryMap)
                VStack(alignment: .leading, spacing: 8) {
                    legendRow(color: NunaExerciseBodyMap.primaryColor, title: "Main", names: e.primaryMuscles)
                    if !e.secondaryMuscles.isEmpty { legendRow(color: NunaExerciseBodyMap.secondaryColor, title: "Also", names: e.secondaryMuscles) }
                }
            }
        }
    }

    private func legendRow(color: Color, title: LocalizedStringKey, names: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Text(verbatim: names.map(NunaLibraryExercise.title).joined(separator: ", ")).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer(minLength: 0)
        }
    }

    // MARK: History

    @ViewBuilder private var historyList: some View {
        if history.sessions.isEmpty {
            NunaCard(small: true) {
                Text(history.loaded ? "You have not logged this exercise yet." : " ").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        let badges = NunaExerciseHistory.records(inSets: history.sessions)
        ForEach(history.sessions) { s in
            NavigationLink(value: NunaWorkoutRoute.gymSession(s.id)) {
                NunaCard(small: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: s.program ?? String(localized: "Gym session")).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(2)
                                Text(verbatim: NunaWorkoutFormat.day(s.startTs) + " · " + NunaWorkoutFormat.clock(s.startTs)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted).padding(.top, 4)
                        }
                        HStack {
                            Text("Set").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).frame(width: 40, alignment: .leading)
                            Text("Weight and reps").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                            Spacer()
                        }
                        ForEach(Array(s.sets.enumerated()), id: \.element.id) { i, set in
                            HStack(spacing: 8) {
                                Text(verbatim: set.isWarmup ? String(localized: "W") : "\(set.setIndex)").font(.nuna(size: 13, weight: .bold, design: NunaType.design))
                                    .foregroundStyle(set.isWarmup ? NunaPalette.warning : NunaPalette.textSecondary).frame(width: 40, alignment: .leading)
                                Text(verbatim: setText(set)).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                                Spacer()
                                ForEach(badges[set.id] ?? [], id: \.self) { label in
                                    HStack(spacing: 4) {
                                        Image(systemName: "medal.fill").font(.nuna(size: 11, weight: .bold))
                                        Text(verbatim: label).font(.nuna(size: 11.5, weight: .bold)).textCase(nil)
                                    }
                                    .foregroundStyle(NunaPalette.warning).padding(.horizontal, 8).frame(height: 22)
                                    .background(NunaPalette.tint(NunaPalette.warning), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            }
                        }
                    }
                }
            }.buttonStyle(.plain)
        }
    }

    private func setText(_ s: LiftSetRow) -> String {
        NunaExerciseKind.of(s.exercise).setText(weightKg: s.weightKg, reps: s.reps, system: system)
    }

    // MARK: How to

    private func howTo(_ e: NunaLibraryExercise) -> some View {
        VStack(spacing: NunaSpacing.section) {
            howToSteps(e)
            pinnedNoteCard(e)
        }
    }

    /// A note that goes with this exercise wherever it appears: a program, a session. Kept on this iPhone.
    private func pinnedNoteCard(_ e: NunaLibraryExercise) -> some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        Text("Pinned exercise note").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                    }
                    Spacer()
                    Button { noteDraft = pinnedNote; editingNote = true } label: {
                        Text(pinnedNote.isEmpty ? "Add note" : "Edit").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.restText).frame(minHeight: 32)
                    }.buttonStyle(.plain)
                }
                if !pinnedNote.isEmpty {
                    Text(verbatim: pinnedNote).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
        }
        .alert("Pinned exercise note", isPresented: $editingNote) {
            TextField("Setup, grip, cues", text: $noteDraft)
            Button("Save") { NunaExerciseNotes.set(noteDraft, for: e.id); pinnedNote = NunaExerciseNotes.note(for: e.id) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It shows with this exercise in your programs and sessions.") }
    }

    private func howToSteps(_ e: NunaLibraryExercise) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("How to do it")
                if e.instructions.isEmpty {
                    Text("There are no written steps for your own exercise. The video on the Summary tab shows the movement.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                ForEach(Array(e.instructions.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: "\(i + 1)").font(.nuna(size: 12, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.onAccent)
                            .frame(width: 22, height: 22).background(NunaPalette.accent, in: Circle())
                        Text(verbatim: step).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
            }
        }
    }
}

/// The front and the back of the body side by side, with the main muscles in one colour and the helping ones in another.
struct NunaExerciseBodyMap: View {
    let primary: [Muscle]
    let secondary: [Muscle]
    var height: CGFloat = 250

    static let primaryColor = NunaPalette.accent
    static let secondaryColor = NunaPalette.rest

    var body: some View {
        HStack(spacing: 6) {
            ForEach(BodySide.allCases, id: \.self) { side in
                BodyView(gender: .male, side: side)
                    .highlight(secondary, color: Self.secondaryColor, opacity: 0.85)
                    .highlight(primary, color: Self.primaryColor)
                    .frame(maxWidth: .infinity).frame(height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Body map of the muscles worked"))
    }
}

// MARK: - The library

/// The exercises of the library with a still of each, to open one.
struct NunaExerciseLibraryView: View {
    var body: some View {
        NunaDetailScreen("Exercise library") {
            Text("Animated demos and the muscles each exercise works. This is a sample of the library; more exercises are added over time.")
                .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                VStack(spacing: 0) {
                    ForEach(Array(NunaExerciseLibrary.all.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { NunaDivider() }
                        NavigationLink(value: NunaWorkoutRoute.exercise(e.id)) { row(e) }.buttonStyle(.plain)
                    }
                }
            }
            nunaFootnote("Photos and text: free-exercise-db, public domain. See About › Open-source notices.")
        }
    }

    private func row(_ e: NunaLibraryExercise) -> some View {
        HStack(spacing: 12) {
            Group {
                if let f = e.frames.first, let img = NunaExerciseLibrary.image(f) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else { Color.clear }
            }
            .frame(width: 64, height: 48).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: e.name).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2)
                Text(verbatim: e.primaryMuscles.map(NunaLibraryExercise.title).joined(separator: ", ") + (e.equipmentTitle.map { " · " + $0 } ?? ""))
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
        }
        .padding(.vertical, 10).contentShape(Rectangle())
    }
}
#endif
