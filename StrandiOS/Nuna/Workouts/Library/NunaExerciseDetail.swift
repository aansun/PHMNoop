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

    private enum Tab: String, CaseIterable { case summary, history, howTo
        var title: LocalizedStringKey { switch self { case .summary: "Summary"; case .history: "History"; case .howTo: "How to" } }
    }
    private enum Metric: String, CaseIterable { case heaviest, oneRepMax, setVolume
        var title: LocalizedStringKey { switch self { case .heaviest: "Heaviest weight"; case .oneRepMax: "One rep max"; case .setVolume: "Best set volume" } }
    }

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        if let e = NunaExerciseLibrary.exercise(id: exerciseId) {
            NunaDetailScreen(LocalizedStringKey(e.name)) { content(e) }
                .task { await history.load(libraryId: e.id, repo: repo) }
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
        nunaFootnote("Photos and text: free-exercise-db, public domain (The Unlicense). The body map is MuscleMap, MIT licence. Both are listed under About › Open-source notices.")
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
        progressCard
        recordsCard
        musclesCard(e)
    }

    private func value(_ s: NunaExerciseSession) -> Double? {
        switch metric { case .heaviest: return s.heaviest; case .oneRepMax: return s.oneRepMax; case .setVolume: return s.bestSetVolume }
    }

    private var progressCard: some View {
        let points = history.sessions.reversed().compactMap { s in value(s).map { (date: Date(timeIntervalSince1970: TimeInterval(s.startTs)), kg: $0) } }.suffix(30)
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap(metric.title)
                if points.isEmpty {
                    Text(history.loaded ? "Log this exercise in a gym session and its progress shows here." : " ")
                        .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                } else {
                    if let last = points.last {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: LiftFormat.trim(LiftFormat.display(fromKilograms: last.kg, system: system))).font(.nuna(size: 30, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: UnitFormatter.massUnit(system)).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            Text(verbatim: NunaWorkoutFormat.day(Int(last.date.timeIntervalSince1970))).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                        }
                    }
                    Chart {
                        ForEach(Array(points), id: \.date) { p in
                            let v = LiftFormat.display(fromKilograms: p.kg, system: system)
                            LineMark(x: .value("Date", p.date), y: .value("Weight", v)).foregroundStyle(NunaPalette.textPrimary).interpolationMethod(.monotone)
                            PointMark(x: .value("Date", p.date), y: .value("Weight", v)).foregroundStyle(NunaPalette.textPrimary)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(NunaPalette.textMuted) } }
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(NunaPalette.hairline); AxisValueLabel().foregroundStyle(NunaPalette.textMuted) } }
                    .frame(height: 170)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Metric.allCases, id: \.self) { m in
                            Button { metric = m } label: {
                                Text(m.title).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(metric == m ? NunaPalette.onAccent : NunaPalette.textPrimary)
                                    .padding(.horizontal, 16).frame(height: 36).background(metric == m ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var recordsCard: some View {
        let r = NunaExerciseHistory.records(history.sessions)
        func mass(_ kg: Double?) -> String { LiftFormat.weight(kg, system: system) }
        return NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Personal records")
                if history.sessions.isEmpty {
                    Text("No sets logged yet.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                } else {
                    recordRow("Heaviest weight", mass(r.heaviest))
                    recordRow("One rep max", mass(r.oneRepMax))
                    recordRow("Best set volume", mass(r.bestSetVolume))
                    recordRow("Best session volume", mass(r.bestSessionVolume))
                    recordRow("Most reps in a set", r.mostReps.map(String.init) ?? "—")
                    Text("The one rep max is an estimate from sets of 12 reps or fewer.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
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
        ForEach(history.sessions) { s in
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(verbatim: NunaWorkoutFormat.day(s.startTs)).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        Spacer()
                        if let p = s.program { Text(verbatim: p).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1) }
                    }
                    ForEach(Array(s.sets.enumerated()), id: \.element.id) { i, set in
                        HStack {
                            Text(verbatim: set.isWarmup ? String(localized: "W") : "\(set.setIndex)").font(.nuna(size: 13, weight: .bold, design: NunaType.design))
                                .foregroundStyle(set.isWarmup ? NunaPalette.warning : NunaPalette.textSecondary).frame(width: 26)
                            Text(verbatim: setText(set)).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func setText(_ s: LiftSetRow) -> String {
        switch (s.weightKg, s.reps) {
        case let (w?, r?): return "\(LiftFormat.weight(w, system: system)) × \(r)"
        case let (w?, nil): return LiftFormat.weight(w, system: system)
        case let (nil, r?): return "× \(r)"
        default: return "—"
        }
    }

    // MARK: How to

    private func howTo(_ e: NunaLibraryExercise) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("How to do it")
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
