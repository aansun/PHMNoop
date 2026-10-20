#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Starter programs

/// A ready-made program to start from: a few routines of library exercises with sets, reps and rest. They are general templates written for PHMN,
/// not advice for one person; add one, then change anything in it.
struct NunaStarterProgram: Identifiable {
    enum Level: Int, CaseIterable, Identifiable {
        case beginner, medium, advanced
        var id: Int { rawValue }
        var title: LocalizedStringKey { switch self { case .beginner: "Beginner"; case .medium: "Medium"; case .advanced: "Advanced" } }
        var icon: String { switch self { case .beginner: "chart.bar"; case .medium: "chart.bar.fill"; case .advanced: "flame" } }
    }
    enum Goal: Int, CaseIterable, Identifiable {
        case muscle, strength, loseWeight
        var id: Int { rawValue }
        var title: LocalizedStringKey { switch self { case .muscle: "Gain muscle"; case .strength: "Strength"; case .loseWeight: "Lose weight" } }
        var icon: String { switch self { case .muscle: "figure.arms.open"; case .strength: "dumbbell"; case .loseWeight: "scalemass" } }
    }
    enum Equipment: Int, CaseIterable, Identifiable {
        case gym, dumbbells, bands, none
        var id: Int { rawValue }
        var title: LocalizedStringKey { switch self { case .gym: "Gym"; case .dumbbells: "Dumbbells"; case .bands: "Bands"; case .none: "No equipment" } }
        var icon: String { switch self { case .gym: "figure.strengthtraining.traditional"; case .dumbbells: "dumbbell.fill"; case .bands: "lines.measurement.horizontal"; case .none: "figure.stand" } }
    }

    struct Move { let name: String; let sets: Int; let reps: Int?; let rest: Int }
    struct Routine: Identifiable { let name: String; let moves: [Move]; var id: String { name } }

    let id: String
    let name: String
    let level: Level
    let goal: Goal
    let equipment: Equipment
    let routines: [Routine]

    var exerciseCount: Int { routines.reduce(0) { $0 + $1.moves.count } }
}

enum NunaStarterPrograms {
    private static func m(_ name: String, _ sets: Int, _ reps: Int? = nil, rest: Int = 90) -> NunaStarterProgram.Move { .init(name: name, sets: sets, reps: reps, rest: rest) }
    private static func r(_ name: String, _ moves: [NunaStarterProgram.Move]) -> NunaStarterProgram.Routine { .init(name: name, moves: moves) }

    static let all: [NunaStarterProgram] = [
        .init(id: "full-body-beginner-gym", name: "Beginner Full Body (Gym)", level: .beginner, goal: .muscle, equipment: .gym, routines: [
            r("Full Body A", [m("Barbell Squat", 3, 8, rest: 120), m("Barbell Bench Press - Medium Grip", 3, 8, rest: 120), m("Seated Cable Rows", 3, 10), m("Dumbbell Shoulder Press", 3, 10), m("Plank", 3, 30, rest: 60)]),
            r("Full Body B", [m("Leg Press", 3, 10, rest: 120), m("Wide-Grip Lat Pulldown", 3, 10), m("Incline Dumbbell Press", 3, 10), m("Romanian Deadlift", 3, 10, rest: 120), m("Triceps Pushdown", 3, 12), m("Dumbbell Bicep Curl", 3, 12)]),
        ]),
        .init(id: "ppl-beginner-gym", name: "Beginner Push/Pull/Legs (Gym)", level: .beginner, goal: .muscle, equipment: .gym, routines: [
            r("Push", [m("Barbell Bench Press - Medium Grip", 3, 8, rest: 120), m("Dumbbell Shoulder Press", 3, 10), m("Incline Dumbbell Press", 3, 10), m("Side Lateral Raise", 3, 12, rest: 60), m("Triceps Pushdown", 3, 12, rest: 60)]),
            r("Pull", [m("Wide-Grip Lat Pulldown", 3, 10), m("Seated Cable Rows", 3, 10), m("Face Pull", 3, 12, rest: 60), m("Dumbbell Bicep Curl", 3, 12, rest: 60), m("Hammer Curls", 3, 12, rest: 60)]),
            r("Legs", [m("Barbell Squat", 3, 8, rest: 120), m("Leg Press", 3, 10, rest: 120), m("Lying Leg Curls", 3, 12), m("Leg Extensions", 3, 12), m("Standing Calf Raises", 3, 15, rest: 60)]),
        ]),
        .init(id: "fat-loss-gym", name: "Fat-loss Circuit (Gym)", level: .beginner, goal: .loseWeight, equipment: .gym, routines: [
            r("Circuit", [m("Leg Press", 3, 15, rest: 45), m("Wide-Grip Lat Pulldown", 3, 15, rest: 45), m("Dumbbell Bench Press", 3, 15, rest: 45), m("Seated Cable Rows", 3, 15, rest: 45), m("Dumbbell Lunges", 3, 12, rest: 45), m("Cable Crunch", 3, 15, rest: 45)]),
        ]),
        .init(id: "upper-lower-medium-gym", name: "Intermediate Upper/Lower (Gym)", level: .medium, goal: .muscle, equipment: .gym, routines: [
            r("Upper", [m("Barbell Bench Press - Medium Grip", 4, 8, rest: 120), m("Bent Over Barbell Row", 4, 8, rest: 120), m("Dumbbell Shoulder Press", 3, 10), m("Wide-Grip Lat Pulldown", 3, 10), m("Barbell Curl", 3, 10, rest: 60), m("Triceps Pushdown", 3, 10, rest: 60)]),
            r("Lower", [m("Barbell Squat", 4, 6, rest: 150), m("Romanian Deadlift", 3, 8, rest: 120), m("Leg Press", 3, 10, rest: 120), m("Lying Leg Curls", 3, 10), m("Standing Calf Raises", 4, 12, rest: 60), m("Cable Crunch", 3, 12, rest: 60)]),
        ]),
        .init(id: "ppl-medium-gym", name: "Intermediate Push/Pull/Legs (Gym)", level: .medium, goal: .muscle, equipment: .gym, routines: [
            r("Push", [m("Barbell Bench Press - Medium Grip", 4, 6, rest: 150), m("Barbell Incline Bench Press - Medium Grip", 3, 8, rest: 120), m("Barbell Shoulder Press", 3, 8, rest: 120), m("Side Lateral Raise", 4, 12, rest: 60), m("Cable Crossover", 3, 12, rest: 60), m("Triceps Pushdown", 3, 10, rest: 60)]),
            r("Pull", [m("Barbell Deadlift", 3, 5, rest: 180), m("Bent Over Barbell Row", 4, 8, rest: 120), m("Wide-Grip Lat Pulldown", 3, 10), m("Face Pull", 3, 15, rest: 60), m("Barbell Curl", 3, 10, rest: 60), m("Hammer Curls", 3, 12, rest: 60)]),
            r("Legs", [m("Barbell Squat", 4, 6, rest: 150), m("Romanian Deadlift", 3, 8, rest: 120), m("Leg Press", 3, 10, rest: 120), m("Seated Leg Curl", 3, 12), m("Leg Extensions", 3, 12), m("Standing Calf Raises", 4, 12, rest: 60)]),
        ]),
        .init(id: "strength-5x5", name: "Strength Base 5×5 (Gym)", level: .medium, goal: .strength, equipment: .gym, routines: [
            r("Workout A", [m("Barbell Squat", 5, 5, rest: 180), m("Barbell Bench Press - Medium Grip", 5, 5, rest: 180), m("Bent Over Barbell Row", 5, 5, rest: 180)]),
            r("Workout B", [m("Barbell Squat", 5, 5, rest: 180), m("Barbell Shoulder Press", 5, 5, rest: 180), m("Barbell Deadlift", 1, 5, rest: 240)]),
        ]),
        .init(id: "upper-lower-advanced-strength", name: "Advanced Upper/Lower Strength (Gym)", level: .advanced, goal: .strength, equipment: .gym, routines: [
            r("Upper", [m("Barbell Bench Press - Medium Grip", 5, 3, rest: 180), m("Bent Over Barbell Row", 5, 5, rest: 150), m("Barbell Shoulder Press", 4, 5, rest: 150), m("Pullups", 4, 6, rest: 120), m("Close-Grip Barbell Bench Press", 3, 8, rest: 90), m("Barbell Curl", 3, 8, rest: 60)]),
            r("Lower", [m("Barbell Squat", 5, 3, rest: 210), m("Barbell Deadlift", 3, 3, rest: 240), m("Front Barbell Squat", 3, 6, rest: 150), m("Romanian Deadlift", 3, 6, rest: 120), m("Hanging Leg Raise", 3, 10, rest: 60), m("Standing Calf Raises", 4, 10, rest: 60)]),
        ]),
        .init(id: "dumbbell-full-body", name: "Dumbbell Full Body", level: .beginner, goal: .muscle, equipment: .dumbbells, routines: [
            r("Full Body A", [m("Goblet Squat", 3, 10), m("Dumbbell Bench Press", 3, 10), m("One-Arm Dumbbell Row", 3, 10), m("Dumbbell Shoulder Press", 3, 10), m("Dumbbell Bicep Curl", 3, 12, rest: 60), m("Plank", 3, 30, rest: 60)]),
            r("Full Body B", [m("Dumbbell Lunges", 3, 10), m("Incline Dumbbell Press", 3, 10), m("Bent Over Two-Dumbbell Row", 3, 10), m("Side Lateral Raise", 3, 12, rest: 60), m("Hammer Curls", 3, 12, rest: 60), m("Standing Dumbbell Calf Raise", 3, 15, rest: 60)]),
        ]),
        .init(id: "dumbbell-upper-lower", name: "Dumbbell Upper/Lower", level: .medium, goal: .muscle, equipment: .dumbbells, routines: [
            r("Upper", [m("Dumbbell Bench Press", 4, 8, rest: 120), m("One-Arm Dumbbell Row", 4, 8, rest: 90), m("Dumbbell Shoulder Press", 3, 10), m("Dumbbell Flyes", 3, 12, rest: 60), m("Dumbbell Bicep Curl", 3, 12, rest: 60), m("Dumbbell One-Arm Triceps Extension", 3, 12, rest: 60)]),
            r("Lower", [m("Goblet Squat", 4, 10, rest: 120), m("Dumbbell Rear Lunge", 3, 10), m("Dumbbell Step Ups", 3, 10), m("Standing Dumbbell Calf Raise", 4, 15, rest: 60), m("Reverse Crunch", 3, 15, rest: 60)]),
        ]),
        .init(id: "bodyweight-basics", name: "Bodyweight Basics", level: .beginner, goal: .loseWeight, equipment: .none, routines: [
            r("Day A", [m("Bodyweight Squat", 3, 15, rest: 60), m("Pushups", 3, 10, rest: 60), m("Superman", 3, 12, rest: 45), m("Bodyweight Walking Lunge", 3, 10, rest: 60), m("Plank", 3, 30, rest: 45), m("Mountain Climbers", 3, 20, rest: 45)]),
            r("Day B", [m("Incline Push-Up", 3, 12, rest: 60), m("Single Leg Glute Bridge", 3, 12, rest: 45), m("Bench Dips", 3, 12, rest: 60), m("Crunches", 3, 15, rest: 45), m("Reverse Crunch", 3, 12, rest: 45)]),
        ]),
        .init(id: "bodyweight-strength", name: "Bodyweight Strength", level: .medium, goal: .strength, equipment: .none, routines: [
            r("Upper", [m("Pullups", 4, 6, rest: 120), m("Decline Push-Up", 4, 10, rest: 90), m("Dips - Triceps Version", 3, 10, rest: 90), m("Chin-Up", 4, 6, rest: 120), m("Hanging Leg Raise", 3, 10, rest: 60)]),
            r("Lower and core", [m("Bodyweight Walking Lunge", 4, 12, rest: 60), m("Single Leg Glute Bridge", 3, 12, rest: 60), m("Bodyweight Squat", 4, 20, rest: 60), m("Plank", 3, 30, rest: 45), m("Mountain Climbers", 3, 20, rest: 45)]),
        ]),
        .init(id: "band-full-body", name: "Resistance Band Full Body", level: .beginner, goal: .muscle, equipment: .bands, routines: [
            r("Full Body", [m("Band Pull Apart", 3, 15, rest: 45), m("Bench Press - With Bands", 3, 12, rest: 60), m("Lateral Raise - With Bands", 3, 15, rest: 45), m("Bodyweight Squat", 3, 15, rest: 60), m("Calf Raises - With Bands", 3, 15, rest: 45)]),
        ]),
    ]

    /// Add a program to the person's own: one program per routine, in a folder named after it when there is more than one.
    @MainActor
    @discardableResult
    static func add(_ p: NunaStarterProgram, repo: Repository) async -> Int {
        guard let store = await repo.storeHandle() else { return 0 }
        let now = Int(Date().timeIntervalSince1970)
        let group = p.routines.count > 1 ? NunaProgramGroupsModel.shared.add(name: p.name) : nil
        var added = 0
        for (index, routine) in p.routines.enumerated() {
            let id = UUID().uuidString
            // The list shows the newest first, so the first routine gets the latest stamp and stays on top.
            let stamp = now + (p.routines.count - index)
            let name = p.routines.count > 1 ? routine.name : p.name
            _ = try? await store.upsertLiftPrograms([LiftProgramRow(id: id, deviceId: repo.deviceId, name: name, note: nil, createdAt: stamp, updatedAt: stamp, archived: false)])
            let items = routine.moves.enumerated().map { i, mv in
                LiftProgramItemRow(id: UUID().uuidString, deviceId: repo.deviceId, programId: id, ord: i, exercise: mv.name, targetSets: mv.sets,
                                   targetRepsLow: mv.reps, targetRepsHigh: nil, targetRpe: nil, targetWeightKg: nil, restSec: mv.rest, note: nil)
            }
            _ = try? await store.replaceLiftProgramItems(programId: id, items: items)
            if let group { NunaProgramGroupsModel.shared.move(id, to: group) }
            added += 1
        }
        await repo.refresh()
        return added
    }
}

// MARK: - Explore

/// Ready-made programs to add to your own, narrowed by level, goal and equipment, and ready-made routines by where you train.
struct NunaGymExploreView: View {
    @State private var level: NunaStarterProgram.Level?
    @State private var goal: NunaStarterProgram.Goal?
    @State private var equipment: NunaStarterProgram.Equipment?
    @State private var filtering = false

    private var results: [NunaStarterProgram] {
        NunaStarterPrograms.all.filter { (level == nil || $0.level == level) && (goal == nil || $0.goal == goal) && (equipment == nil || $0.equipment == equipment) }
    }
    private var anyFilter: Bool { level != nil || goal != nil || equipment != nil }

    var body: some View {
        NunaDetailScreen("Explore") {
            NunaTitleRow(title: "Programs") { EmptyView() }
            filterBar
            if results.isEmpty {
                NunaCard(small: true) {
                    Text("No program matches these filters.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(results) { p in
                NavigationLink { NunaStarterProgramView(program: p) } label: { programCard(p) }.buttonStyle(.plain)
            }
            NunaTitleRow(title: "Routines") { EmptyView() }
            categories
            NavigationLink { NunaProgramImportView() } label: {
                NunaCard(small: true) { NunaListRow("Import a program", description: "Bring a routine in from a spreadsheet", systemImage: "tablecells", showsChevron: true) }
            }.buttonStyle(.plain)
            nunaFootnote("General templates written for PHMN, with exercises from the library. They are a place to start: add one, then change anything in it. Not personal advice.")
        }
        .sheet(isPresented: $filtering) { filterSheet.nunaSheetChrome(detents: [.large]) }
    }

    // MARK: Filters

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { filtering = true } label: {
                    HStack(spacing: 6) { Image(systemName: "line.3.horizontal.decrease").font(.nuna(size: 12, weight: .bold)); Text("Filters").font(.nuna(size: 13.5, weight: .bold)) }
                        .foregroundStyle(anyFilter ? NunaPalette.onAccent : NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 36)
                        .background(anyFilter ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
                menuChip("Level", on: level != nil) {
                    Button("Any") { level = nil }
                    ForEach(NunaStarterProgram.Level.allCases) { l in Button { level = l } label: { Label { Text(l.title) } icon: { if level == l { Image(systemName: "checkmark") } } } }
                }
                menuChip("Goal", on: goal != nil) {
                    Button("Any") { goal = nil }
                    ForEach(NunaStarterProgram.Goal.allCases) { g in Button { goal = g } label: { Label { Text(g.title) } icon: { if goal == g { Image(systemName: "checkmark") } } } }
                }
                menuChip("Equipment", on: equipment != nil) {
                    Button("Any") { equipment = nil }
                    ForEach(NunaStarterProgram.Equipment.allCases) { e in Button { equipment = e } label: { Label { Text(e.title) } icon: { if equipment == e { Image(systemName: "checkmark") } } } }
                }
            }
        }
    }

    private func menuChip<Content: View>(_ title: LocalizedStringKey, on: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        Menu { content() } label: {
            HStack(spacing: 6) { Text(title).font(.nuna(size: 13.5, weight: .bold)); Image(systemName: "chevron.down").font(.nuna(size: 11, weight: .bold)) }
                .foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 36)
                .background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }
    }

    /// The sheet with all three at once, and the count the choice gives.
    private var filterSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Filters").font(.nuna(size: 18, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                .frame(maxWidth: .infinity).padding(.top, 20).padding(.bottom, 14)
            NunaDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    filterGroup("Level", NunaStarterProgram.Level.allCases.map { ($0.id, $0.title, $0.icon) }, selection: level?.id) { id in level = id.flatMap(NunaStarterProgram.Level.init(rawValue:)) }
                    filterGroup("Goal", NunaStarterProgram.Goal.allCases.map { ($0.id, $0.title, $0.icon) }, selection: goal?.id) { id in goal = id.flatMap(NunaStarterProgram.Goal.init(rawValue:)) }
                    filterGroup("Equipment", NunaStarterProgram.Equipment.allCases.map { ($0.id, $0.title, $0.icon) }, selection: equipment?.id) { id in equipment = id.flatMap(NunaStarterProgram.Equipment.init(rawValue:)) }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 18)
            }
            HStack(spacing: 12) {
                Button { level = nil; goal = nil; equipment = nil } label: {
                    Text("Clear filters").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 54).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(!anyFilter).opacity(anyFilter ? 1 : 0.4)
                Button { filtering = false } label: {
                    Text(verbatim: results.count == 1 ? String(localized: "Show 1 result") : String(localized: "Show \(results.count) results")).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 54).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 12)
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
    }

    private func filterGroup(_ title: LocalizedStringKey, _ options: [(Int, LocalizedStringKey, String)], selection: Int?, _ pick: @escaping (Int?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.nuna(size: 15, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
            HStack(spacing: 10) {
                ForEach(options, id: \.0) { o in
                    Button { pick(selection == o.0 ? nil : o.0) } label: {
                        VStack(alignment: .leading, spacing: 18) {
                            Image(systemName: o.2).font(.nuna(size: 22, weight: .regular))
                            Text(o.1).font(.nuna(size: 13.5, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        .foregroundStyle(selection == o.0 ? NunaPalette.onAccent : NunaPalette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading).padding(12)
                        .background(selection == o.0 ? NunaPalette.accent : NunaPalette.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Cards

    private func programCard(_ p: NunaStarterProgram) -> some View {
        NunaCard(small: true) {
            HStack(spacing: 14) {
                Image(systemName: p.goal.icon).font(.nuna(size: 22, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 52, height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: p.name).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        tag(p.level.title); tag(p.goal.title); tag(p.equipment.title)
                    }
                    Text(verbatim: (p.routines.count == 1 ? String(localized: "1 routine") : String(localized: "\(p.routines.count) routines")) + " · " + String(localized: "\(p.exerciseCount) exercises"))
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
    }

    private func tag(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            .padding(.horizontal, 7).frame(height: 20).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var categories: some View {
        let cats: [(LocalizedStringKey, String, [NunaStarterProgram.Equipment])] = [
            ("At home", "house", [.dumbbells, .bands, .none]), ("Dumbbells only", "dumbbell.fill", [.dumbbells]),
            ("Bands", "lines.measurement.horizontal", [.bands]), ("Gym", "building.2", [.gym]), ("Bodyweight", "figure.stand", [.none]),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(cats.enumerated()), id: \.offset) { _, c in
                NavigationLink { NunaStarterCategoryView(title: c.0, equipment: c.2) } label: {
                    HStack {
                        Text(c.0).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Image(systemName: c.1).font(.nuna(size: 22, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 74).background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: - One starter program

/// A starter program: its routines and their exercises, with a button to add it to your own programs.
struct NunaStarterProgramView: View {
    let program: NunaStarterProgram
    @EnvironmentObject private var repo: Repository
    @State private var adding = false
    @State private var added = false

    var body: some View {
        NunaDetailScreen(LocalizedStringKey(program.name)) {
            HStack(spacing: 8) { tag(program.level.title); tag(program.goal.title); tag(program.equipment.title); Spacer(minLength: 0) }
            ForEach(program.routines) { routine in
                VStack(alignment: .leading, spacing: 10) {
                    NunaTitleRow(title: LocalizedStringKey(routine.name)) { EmptyView() }
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                        VStack(spacing: 0) {
                            ForEach(Array(routine.moves.enumerated()), id: \.offset) { i, mv in
                                if i > 0 { NunaDivider() }
                                HStack(spacing: 12) {
                                    NunaExerciseThumb(name: mv.name, width: 50, height: 38)
                                    Text(verbatim: mv.name).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2)
                                    Spacer(minLength: 6)
                                    Text(verbatim: NunaExerciseKind.of(mv.name).targetText(sets: mv.sets, reps: mv.reps) ?? "\(mv.sets)").font(.nuna(size: 15.5, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                }.padding(.vertical, 10)
                            }
                        }
                    }
                }
            }
            nunaFootnote("Adding it copies the routines into your Gym tab. Change the exercises, sets, reps and rest there; nothing here changes.")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { addBar }
    }

    private func tag(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            .padding(.horizontal, 7).frame(height: 22).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var addBar: some View {
        Button {
            guard !adding, !added else { return }
            adding = true
            Task { _ = await NunaStarterPrograms.add(program, repo: repo); adding = false; added = true; UINotificationFeedbackGenerator().notificationOccurred(.success) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: added ? "checkmark" : "plus").font(.nuna(size: 14, weight: .bold))
                Text(added ? "Added to your programs" : "Add to my programs").font(.nuna(size: 17, weight: .bold))
            }
            .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56)
            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }
        .buttonStyle(.plain).disabled(added || adding).opacity(added ? 0.6 : 1)
        .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 10)
        .background(LinearGradient(colors: [NunaPalette.canvas.opacity(0), NunaPalette.canvas], startPoint: .top, endPoint: .center))
    }
}

// MARK: - Routines by place

/// The routines of every starter program that suits a place to train, each with its exercises, to add one at a time.
struct NunaStarterCategoryView: View {
    let title: LocalizedStringKey
    let equipment: [NunaStarterProgram.Equipment]
    @EnvironmentObject private var repo: Repository
    @State private var addedIds: Set<String> = []

    private var entries: [(program: NunaStarterProgram, routine: NunaStarterProgram.Routine)] {
        NunaStarterPrograms.all.filter { equipment.contains($0.equipment) }.flatMap { p in p.routines.map { (program: p, routine: $0) } }
    }

    var body: some View {
        NunaDetailScreen(title) {
            ForEach(entries, id: \.routine.id) { entry in
                let key = entry.program.id + "·" + entry.routine.id
                NunaCard(small: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: entry.program.routines.count > 1 ? entry.routine.name : entry.program.name).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: entry.program.name).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                            Spacer(minLength: 8)
                            Button {
                                Task {
                                    var single = entry.program
                                    single = NunaStarterProgram(id: entry.program.id, name: entry.program.routines.count > 1 ? entry.routine.name : entry.program.name,
                                                                level: entry.program.level, goal: entry.program.goal, equipment: entry.program.equipment, routines: [entry.routine])
                                    _ = await NunaStarterPrograms.add(single, repo: repo)
                                    addedIds.insert(key)
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                }
                            } label: {
                                Text(addedIds.contains(key) ? "Added" : "Add").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                                    .padding(.horizontal, 18).frame(height: 38).background(NunaPalette.accent.opacity(addedIds.contains(key) ? 0.5 : 1), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                            }.buttonStyle(.plain).disabled(addedIds.contains(key))
                        }
                        Text(verbatim: entry.routine.moves.map(\.name).joined(separator: ", ")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
#endif
