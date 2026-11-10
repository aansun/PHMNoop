#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - A workout of a starter program, as the Explore grid shows it

/// One routine of a starter program with what a card and its detail page need: a photo, a level, a rough length and what it works.
/// Everything here is derived from the program, so a new starter program shows up in the grid with no extra work.
struct NunaExploreWorkout: Identifiable {
    let program: NunaStarterProgram
    let routine: NunaStarterProgram.Routine

    var id: String { program.id + "·" + routine.id }

    /// The program's name without what the card already says elsewhere: the level (it has its badge) and the place.
    private var shortProgram: String {
        var name = program.name.replacingOccurrences(of: " (Gym)", with: "")
        for level in ["Beginner ", "Intermediate ", "Advanced "] where name.hasPrefix(level) { name.removeFirst(level.count) }
        return name
    }

    /// "Push/Pull/Legs: Push": the program's name, and the routine's when the program has several (and the routine's own name does not already start with it).
    var title: String {
        guard program.routines.count > 1 else { return shortProgram }
        return routine.name.hasPrefix(shortProgram) ? routine.name : shortProgram + ": " + routine.name
    }

    var level: NunaStarterProgram.Level { program.level }
    var exerciseCount: Int { routine.moves.count }
    var totalSets: Int { routine.moves.reduce(0) { $0 + $1.sets } }

    /// Five minutes to get ready, then about 40 seconds of work and the planned rest for every set, rounded to five minutes.
    var minutes: Int {
        let seconds = routine.moves.reduce(0) { $0 + $1.sets * (40 + $1.rest) }
        let raw = Double(seconds) / 60 + 5
        return max(10, Int((raw / 5).rounded()) * 5)
    }

    /// The muscle groups the routine works, the one with most sets first.
    var groups: [NunaMuscleGroup] {
        var sets: [NunaMuscleGroup: Int] = [:]
        for move in routine.moves {
            if let muscle = NunaExerciseLibrary.match(move.name)?.liftPrimary { sets[NunaMuscleGroup.of(muscle), default: 0] += move.sets }
        }
        // A tie goes to the group that says most about the session: the big lifts come before the small ones.
        let order: [NunaMuscleGroup] = [.legs, .back, .chest, .shoulders, .arms, .core]
        let rank: (NunaMuscleGroup) -> Int = { order.firstIndex(of: $0) ?? order.count }
        return sets.sorted { $0.value != $1.value ? $0.value > $1.value : rank($0.key) < rank($1.key) }.map(\.key)
    }

    var groupsText: String {
        let names = groups.map(\.name)
        return names.isEmpty ? String(localized: "Whole body") : names.joined(separator: ", ")
    }

    /// The kinds of equipment the exercises use, in the order they appear.
    var equipmentText: String {
        var out: [String] = []
        for move in routine.moves {
            if let title = NunaExerciseLibrary.match(move.name)?.equipmentTitle, !out.contains(title) { out.append(title) }
        }
        return out.isEmpty ? String(localized: "Body weight") : out.joined(separator: ", ")
    }

    /// Every starter workout has a photo of its own, by workout id; no two share one. A program added later needs its photos added here, or it falls back to a shared one.
    private static let photos: [String: String] = [
        "full-body-beginner-gym·Full Body A": "ExploreSquat",
        "full-body-beginner-gym·Full Body B": "ExploreCableRow",
        "ppl-beginner-gym·Push": "ExploreBench",
        "ppl-beginner-gym·Pull": "ExplorePullup",
        "ppl-beginner-gym·Legs": "ExploreLegMachine",
        "fat-loss-gym·Circuit": "ExploreKettlebell",
        "upper-lower-medium-gym·Upper": "ExploreIncline",
        "upper-lower-medium-gym·Lower": "ExploreBarbellSquat",
        "ppl-medium-gym·Push": "ExploreHeavyBench",
        "ppl-medium-gym·Pull": "ExploreLatPulldown",
        "ppl-medium-gym·Legs": "ExploreDeadliftLow",
        "strength-5x5·Workout A": "ExplorePlates",
        "strength-5x5·Workout B": "ExploreBarbellFloor",
        "upper-lower-advanced-strength·Upper": "ExploreBarPull",
        "upper-lower-advanced-strength·Lower": "ExploreDeadliftWoman",
        "dumbbell-full-body·Full Body A": "ExploreDumbbell",
        "dumbbell-full-body·Full Body B": "ExploreDumbbellPress",
        "dumbbell-upper-lower·Upper": "ExploreDumbbellRow",
        "dumbbell-upper-lower·Lower": "ExploreLunge",
        "bodyweight-basics·Day A": "ExploreMat",
        "bodyweight-basics·Day B": "ExploreBridge",
        "bodyweight-strength·Upper": "ExploreHandstand",
        "bodyweight-strength·Lower and core": "ExplorePlank",
        "band-full-body·Full Body": "ExploreBand",
    ]

    var image: String { Self.photos[id] ?? fallbackImage }

    /// For a workout that is not in the table (a program added later): a photo by what the routine needs and what it works most.
    private var fallbackImage: String {
        let group = groups.first
        switch program.equipment {
        case .none: return Self.stable(id) % 2 == 0 ? "ExploreMat" : "ExploreKettlebell"
        case .bands: return "ExploreBand"
        case .dumbbells: return "ExploreDumbbell"
        case .gym:
            if program.goal == .loseWeight { return "ExploreKettlebell" }
            // The second routine of a program gets another photo of the same kind, so two neighbours never show the same picture.
            let second = (program.routines.firstIndex { $0.name == routine.name } ?? 0) % 2 == 1
            switch group {
            case .legs: return second ? "ExplorePlates" : "ExploreSquat"
            case .back: return program.goal == .strength || second ? "ExplorePlates" : "ExplorePullup"
            case .chest: return second ? "ExploreIncline" : "ExploreBench"
            case .shoulders, .arms: return second ? "ExploreBench" : "ExploreIncline"
            case .core: return "ExploreKettlebell"
            case nil: return "ExplorePlates"
            }
        }
    }

    /// A stable number from the id: `hashValue` changes from one launch to the next, and a card should keep its photo.
    private static func stable(_ s: String) -> Int { s.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) & 0xFFFF } }

    /// Two sentences about the session, written from its goal and what it works.
    var summary: String {
        let names = groups.prefix(2).map { $0.name.lowercased() }
        let focus: String
        switch names.count {
        case 0: focus = String(localized: "your whole body")
        case 1: focus = names[0]
        default: focus = String(localized: "\(names[0]) and \(names[1])")
        }
        switch program.goal {
        case .muscle: return String(localized: "Build size in your \(focus) with a mix of heavy compound lifts and focused isolation work. Set your weights, then start.")
        case .strength: return String(localized: "Build strength in your \(focus) with low-rep sets on the big lifts and long rests between them. Set your weights, then start.")
        case .loseWeight: return String(localized: "Keep your heart rate up while you work your \(focus), with short rests and higher reps. Set your weights, then start.")
        }
    }

    static func find(_ id: String) -> NunaExploreWorkout? { all(of: NunaStarterPrograms.all).first { $0.id == id } }

    /// Every routine of the programs, in the order of the programs.
    static func all(of programs: [NunaStarterProgram]) -> [NunaExploreWorkout] {
        programs.flatMap { p in p.routines.map { NunaExploreWorkout(program: p, routine: $0) } }
    }
}

// MARK: - Card

/// A tile of the Explore grid: the photo fills the top of the card and fades into it, with the level in its corner; the name in capitals and the
/// length sit on the fade, so photo and text read as one piece.
struct NunaExploreCard: View {
    let workout: NunaExploreWorkout
    private let photoHeight: CGFloat = 176
    private let textTop: CGFloat = 112

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.frame(height: photoHeight)
                .overlay { Image(workout.image).resizable().scaledToFill() }
                .clipped()
                // Faded by its own opacity, not painted over with the card colour, so no seam shows whatever the card sits on.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.30), .init(color: .black.opacity(0.35), location: 0.52), .init(color: .clear, location: 0.68)],
                                     startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: textTop)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: workout.title).font(.nuna(size: 15.5, weight: .bold)).tracking(1.0).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.leading).lineLimit(3).minimumScaleFactor(0.85)
                    Text("\(workout.minutes) min").font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 88, alignment: .topLeading)
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .overlay(alignment: .topTrailing) { badge.padding(10) }
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(NunaPalette.hairlineSoft, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// A small square-cornered label over the photo, like a tag.
    private var badge: some View {
        Text(workout.level.title).font(.nuna(size: 12.5, weight: .semibold)).tracking(0.9).textCase(.uppercase)
            .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 10).frame(height: 27)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Details

/// The page a card opens: the photo, the numbers of the session, what it is and works, and its exercises. Next goes on to the sets and weights.
struct NunaExploreWorkoutDetail: View {
    let workout: NunaExploreWorkout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 26) {
                        Text(verbatim: workout.summary).font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                            .textCase(nil).fixedSize(horizontal: false, vertical: true)
                        NunaDivider()
                        fact("Equipment", workout.equipmentText)
                        fact("Muscle groups", workout.groupsText)
                        exercises
                    }
                    .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 130)
                }
            }
            .scrollIndicators(.hidden).ignoresSafeArea(edges: .top)
            topBar
        }
        .background(NunaBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { nextBar }
    }

    private var topBar: some View {
        ZStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(Text("Close"))
                Spacer()
            }
            Text("Workout details").font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8)
    }

    /// A wide photo is not stretched to the height of a tall one: it would be enlarged past what its pixels can show.
    private var heroHeight: CGFloat {
        guard let size = UIImage(named: workout.image)?.size, size.height > 0 else { return 520 }
        return size.width > size.height ? 400 : 540
    }

    private var hero: some View {
        Color.clear.frame(height: heroHeight)
            .overlay { Image(workout.image).resizable().scaledToFill() }
            .overlay(LinearGradient(colors: [NunaPalette.canvas.opacity(0.55), NunaPalette.canvas.opacity(0)], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25)))
            .overlay(LinearGradient(colors: [NunaPalette.canvas.opacity(0), NunaPalette.canvas], startPoint: .init(x: 0.5, y: 0.35), endPoint: .bottom))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: workout.title).font(.nuna(size: 34, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("By PHMN").font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    HStack(alignment: .top, spacing: 0) {
                        stat("\(workout.minutes)", unit: "min", label: "Est duration")
                        stat("\(workout.exerciseCount)", unit: nil, label: "Exercises")
                        stat("\(workout.totalSets)", unit: nil, label: "Total sets")
                    }.padding(.top, 10)
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 14)
            }
            .clipped()
    }

    private func stat(_ value: String, unit: LocalizedStringKey?, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value).font(.nuna(size: 30, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                if let unit { Text(unit).font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil) }
            }
            Text(label).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fact(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Text(verbatim: value).font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exercises: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Exercises").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Rectangle().fill(NunaPalette.hairlineSoft).frame(height: 1)
            }
            ForEach(Array(workout.routine.moves.enumerated()), id: \.offset) { _, move in
                HStack(spacing: 14) {
                    NunaExerciseThumb(name: move.name, width: 70, height: 56)
                    Text(verbatim: move.name).font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if let match = NunaExerciseLibrary.match(move.name) {
                        NavigationLink(value: NunaWorkoutRoute.exercise(match.id)) {
                            Image(systemName: "info.circle").font(.nuna(size: 24, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(Text("About this exercise"))
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var nextBar: some View {
        NavigationLink(value: NunaWorkoutRoute.exploreEdit(workout.id)) {
            Text("Next").font(.nuna(size: 17, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.accent)
                .frame(maxWidth: .infinity).frame(height: 58)
                .overlay(Capsule().strokeBorder(NunaPalette.accent, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 10)
        .background(LinearGradient(colors: [NunaPalette.canvas.opacity(0), NunaPalette.canvas], startPoint: .top, endPoint: .init(x: 0.5, y: 0.4)))
    }
}

// MARK: - Editor

/// The sets of the workout, to change before it starts: reps and weight for every set, more sets, more exercises, fewer. Start runs it as it
/// stands, and Save keeps it among the person's own programs; nothing is saved by looking at it.
///
/// The session plans one target per exercise, not one per set, so the reps become the lowest and highest of the sets and the weight the
/// heaviest one entered.
struct NunaExploreWorkoutEditor: View {
    let workout: NunaExploreWorkout
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var session: LiftSessionController
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @State private var items: [Item] = []
    @State private var loaded = false
    @State private var adding = false
    @State private var saving = false
    @State private var saved = false
    @State private var keyboardUp = false

    private struct SetRow: Identifiable { let id = UUID(); var reps: String; var weight: String }
    private struct Item: Identifiable { let id = UUID(); var name: String; var rest: Int; var sets: [SetRow] }

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 4)
            ScrollView {
                VStack(spacing: 14) {
                    ForEach($items) { $item in card($item) }
                    saveButton
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 10).padding(.bottom, 120)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }
        .background(NunaBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        // The bar steps aside while a number is typed, so it does not ride on top of the keyboard and the fields.
        .safeAreaInset(edge: .bottom, spacing: 0) { if !keyboardUp { startBar } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            items = workout.routine.moves.map { move in
                Item(name: move.name, rest: move.rest, sets: (0..<max(1, move.sets)).map { _ in SetRow(reps: move.reps.map(String.init) ?? "", weight: "") })
            }
        }
        .sheet(isPresented: $adding) {
            NunaExercisePicker(confirm: { $0 == 1 ? String(localized: "Add 1 exercise") : String(localized: "Add \($0) exercises") }, title: "Add exercise") { picked in
                for p in picked where !items.contains(where: { $0.name == p.name }) {
                    items.append(Item(name: p.name, rest: LiftPlanItem.defaultRestSec, sets: (0..<3).map { _ in SetRow(reps: "", weight: "") }))
                }
            }
            .nunaSheetChrome(detents: [.large])
        }
        .nunaKeyboardDone()
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.nuna(size: 23, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(Text("Go back"))
                Spacer()
                Button { adding = true } label: {
                    Image(systemName: "plus").font(.nuna(size: 24, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(Text("Add exercise"))
            }
            Text(verbatim: workout.title).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 52).accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: One exercise

    private func card(_ item: Binding<Item>) -> some View {
        let kind = NunaExerciseKind.of(item.wrappedValue.name)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                NunaExerciseThumb(name: item.wrappedValue.name, width: 76, height: 62)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: item.wrappedValue.name).font(.nuna(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(item.wrappedValue.sets.count) sets").font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Spacer(minLength: 8)
                Menu {
                    Button { move(item.wrappedValue.id, by: -1) } label: { Label("Move up", systemImage: "arrow.up") }
                    Button { move(item.wrappedValue.id, by: 1) } label: { Label("Move down", systemImage: "arrow.down") }
                    Button(role: .destructive) { remove(item.wrappedValue.id) } label: { Label("Remove exercise", systemImage: "trash") }
                } label: {
                    Image(systemName: "line.3.horizontal").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("More"))
            }
            .padding(8)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 12) {
                Color.clear.frame(width: 26)
                columnLabel(kind == .timed ? "Seconds" : "Reps").frame(maxWidth: .infinity, alignment: .leading)
                if kind == .weighted { Text(verbatim: "WEIGHT (\(UnitFormatter.massUnit(system).uppercased()))").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
                Color.clear.frame(width: 36)
            }
            .padding(.horizontal, 14).padding(.top, 18).padding(.bottom, 8)

            VStack(spacing: 10) {
                ForEach(item.sets) { $row in
                    HStack(spacing: 12) {
                        Text(verbatim: "\((item.wrappedValue.sets.firstIndex { $0.id == row.id } ?? 0) + 1)").font(.nuna(size: 20, weight: .semibold, design: NunaType.design))
                            .foregroundStyle(NunaPalette.textSecondary).frame(width: 26)
                        box("0", text: $row.reps, decimal: false)
                        if kind == .weighted { box("0", text: $row.weight, decimal: true) }
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { item.wrappedValue.sets.removeAll { $0.id == row.id } }
                        } label: {
                            Image(systemName: "xmark").font(.nuna(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 36, height: 44)
                        }
                        .buttonStyle(.plain).disabled(item.wrappedValue.sets.count <= 1).opacity(item.wrappedValue.sets.count <= 1 ? 0.3 : 1)
                        .accessibilityLabel(Text("Remove set"))
                    }
                }
            }
            .padding(.horizontal, 14)

            HStack {
                Button {
                    // A new set starts from the one before it, which is what a person does next anyway.
                    let last = item.wrappedValue.sets.last
                    withAnimation(.easeInOut(duration: 0.2)) { item.wrappedValue.sets.append(SetRow(reps: last?.reps ?? "", weight: last?.weight ?? "")) }
                } label: {
                    HStack(spacing: 10) {
                        Text("Add set").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        Image(systemName: "plus").font(.nuna(size: 18, weight: .semibold))
                    }.foregroundStyle(NunaPalette.textPrimary).frame(height: 44)
                }.buttonStyle(.plain)
                Spacer()
                Button { remove(item.wrappedValue.id) } label: {
                    Image(systemName: "trash").font(.nuna(size: 19, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(Text("Remove exercise"))
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
        }
        .padding(6)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
    }

    private func columnLabel(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
    }

    private func box(_ placeholder: String, text: Binding<String>, decimal: Bool) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .font(.nuna(size: 20, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            .padding(.horizontal, 16).frame(height: 54)
            .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NunaPalette.hairlineSoft, lineWidth: 1))
    }

    private func move(_ id: UUID, by step: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }), items.indices.contains(i + step) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { items.swapAt(i, i + step) }
    }

    private func remove(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) { items.removeAll { $0.id == id } }
    }

    // MARK: Start and save

    /// What the screen holds as moves of a program: the lowest and highest reps of the sets, the heaviest weight, in kilograms.
    private func moves() -> [NunaStarterProgram.Move] {
        let toKg: Double = system == .imperial ? 1 / UnitFormatter.poundsPerKilogram : 1
        var out: [NunaStarterProgram.Move] = []
        for item in items {
            var reps: [Int] = []
            var weights: [Double] = []
            for row in item.sets {
                if let r = Int(row.reps.trimmingCharacters(in: .whitespaces)), r > 0 { reps.append(r) }
                if let w = Double(row.weight.replacingOccurrences(of: ",", with: ".")), w > 0 { weights.append(w * toKg) }
            }
            let low: Int? = reps.min()
            let high: Int? = reps.max() == low ? nil : reps.max()
            let heaviest: Double? = weights.max().map { ($0 * 10).rounded() / 10 }
            out.append(NunaStarterProgram.Move(name: item.name, sets: max(1, item.sets.count), reps: low, rest: item.rest, weightKg: heaviest, repsHigh: high))
        }
        return out
    }

    private func start() {
        guard !items.isEmpty else { return }
        if session.isActive { session.present(); return }
        let plan = moves().map { mv -> LiftPlanItem in
            let lib = NunaExerciseLibrary.match(mv.name)
            return LiftPlanItem(exercise: mv.name, primaryMuscle: lib?.liftPrimary, secondaryMuscles: lib?.liftSecondary ?? [], targetSets: mv.sets,
                                restSec: mv.rest, targetRepsLow: mv.reps, targetRepsHigh: mv.repsHigh, targetWeightKg: mv.weightKg,
                                note: NunaGymStore.mergedNote(nil, pinned: NunaExerciseNotes.note(forName: mv.name)))
        }
        session.start(plan: plan, programId: nil, programName: workout.title)
    }

    private func save() {
        guard !items.isEmpty, !saving, !saved else { return }
        saving = true
        let program = NunaStarterProgram(id: workout.program.id, name: workout.title, level: workout.level, goal: workout.program.goal,
                                         equipment: workout.program.equipment, routines: [.init(name: workout.title, moves: moves())])
        Task {
            _ = await NunaStarterPrograms.add(program, repo: repo)
            saving = false; saved = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private var saveButton: some View {
        Button { save() } label: {
            HStack(spacing: 8) {
                Image(systemName: saved ? "checkmark" : "square.and.arrow.down").font(.nuna(size: 15, weight: .semibold))
                Text(saved ? "Saved to your programs" : "Save to my programs").font(.nuna(size: 15, weight: .bold))
            }
            .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 50)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }
        .buttonStyle(.plain).disabled(items.isEmpty || saving || saved).opacity(saved || items.isEmpty ? 0.6 : 1)
        .padding(.top, 6)
    }

    private var startBar: some View {
        Button { start() } label: {
            Text("Start workout").font(.nuna(size: 17, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.accent)
                .frame(maxWidth: .infinity).frame(height: 58)
                .overlay(Capsule().strokeBorder(NunaPalette.accent, lineWidth: 2))
        }
        .buttonStyle(.plain).disabled(items.isEmpty).opacity(items.isEmpty ? 0.4 : 1)
        .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 10)
        .background(LinearGradient(colors: [NunaPalette.canvas.opacity(0), NunaPalette.canvas], startPoint: .top, endPoint: .init(x: 0.5, y: 0.4)))
    }
}
#endif
