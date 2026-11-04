#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// One badge a person can earn. Each time `count` reaches another multiple of five the badge goes up a level; `count % 5` is how far the next one is.
struct NunaAchievementDef: Identifiable {
    enum Group: String, CaseIterable {
        case sleep, recovery, strain, other, activities
        var title: LocalizedStringKey {
            switch self { case .sleep: "Sleep"; case .recovery: "Recovery"; case .strain: "Strain"; case .other: "Other"; case .activities: "Activities" }
        }
    }
    let id: String
    let title: LocalizedStringKey
    let group: Group
    let shape: NunaAchievementBadge.Shape
    let icon: String
    let count: Int

    static let perLevel = 5
    var level: Int { count / Self.perLevel }
    var progress: Int { count % Self.perLevel }
}

/// Works the badges out from the stored days and saved workouts, on this phone. Nothing is filled in: a badge with no days behind it stays locked.
enum NunaAchievementCatalog {
    static func build(days: [DailyMetric], workouts: [WorkoutRow]) -> [NunaAchievementDef] {
        let sorted = days.sorted { $0.day < $1.day }
        func rest(_ d: DailyMetric) -> Double { AnalyticsEngine.Rest.composite(daily: d) ?? 0 }
        let strainWorking = 10.0 / 21 * 100, strainAllOut = 18.0 / 21 * 100
        // Seven green days in a row, counted once each: every time a run of green days reaches another seven.
        var greenWeeks = 0, run = 0
        for d in sorted { if (d.recovery ?? 0) >= 67 { run += 1; if run % 7 == 0 { greenWeeks += 1 } } else { run = 0 } }
        func sport(_ test: (String) -> Bool) -> Int { workouts.filter { test(WorkoutSource.displaySport($0.sport).lowercased()) }.count }
        let kinds = Set(workouts.map { WorkoutSource.displaySport($0.sport).lowercased() }).count
        return [
            .init(id: "sleepSpecialist", title: "Sleep Specialist", group: .sleep, shape: .hexagon, icon: "moon.fill", count: sorted.filter { rest($0) >= 70 }.count),
            .init(id: "sandman", title: "Sandman", group: .sleep, shape: .hexagon, icon: "bed.double.fill", count: sorted.filter { ($0.totalSleepMin ?? 0) >= 480 }.count),
            .init(id: "greenMonster", title: "Green Monster", group: .recovery, shape: .shield, icon: "leaf.fill", count: sorted.filter { ($0.recovery ?? 0) >= 67 }.count),
            .init(id: "greenWeek", title: "Green Week", group: .recovery, shape: .shield, icon: "calendar", count: greenWeeks),
            .init(id: "peakDay", title: "Peak Day", group: .recovery, shape: .shield, icon: "bolt.fill", count: sorted.filter { ($0.recovery ?? 0) >= 90 }.count),
            .init(id: "steadyStepper", title: "Steady Stepper", group: .strain, shape: .diamond, icon: "shoeprints.fill", count: sorted.filter { ($0.steps ?? 0) >= 10_000 }.count),
            .init(id: "strainSeeker", title: "Strain Seeker", group: .strain, shape: .diamond, icon: "dumbbell.fill", count: sorted.filter { ($0.strain ?? 0) >= strainWorking }.count),
            .init(id: "allOut", title: "All Out Day", group: .strain, shape: .diamond, icon: "flame.fill", count: sorted.filter { ($0.strain ?? 0) >= strainAllOut }.count),
            .init(id: "jack", title: "Jack of All Trades", group: .other, shape: .diamond, icon: "square.grid.2x2.fill", count: kinds),
            .init(id: "walkStar", title: "Walk Star", group: .activities, shape: .seal, icon: "figure.walk", count: sport { $0.contains("walk") }),
            .init(id: "bubblegum", title: "Bubblegum Body", group: .activities, shape: .seal, icon: "figure.flexibility", count: sport { $0.contains("stretch") || $0.contains("yoga") || $0.contains("pilates") }),
            .init(id: "barbell", title: "Barbell Boss", group: .activities, shape: .seal, icon: "dumbbell", count: workouts.filter { NunaWorkoutKind.isStrength($0) }.count),
        ]
    }
}

/// Achievements: the totals, a row of filters and every badge by group, each with its level and how far the next one is.
struct NunaAchievementsView: View {
    @EnvironmentObject private var repo: Repository
    @State private var workouts: [WorkoutRow] = []
    @State private var filter: NunaAchievementDef.Group?

    private var list: [NunaAchievementDef] { NunaAchievementCatalog.build(days: repo.days, workouts: workouts) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 3)

    var body: some View {
        let all = list
        NunaDetailScreen("Achievements", centersTitle: true) {
            HStack(spacing: 0) {
                total(all.reduce(0) { $0 + $1.level }, "Total")
                Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 56)
                total(all.filter { $0.level > 0 }.count, "Unique")
            }
            .padding(.top, 6)
            chips
            ForEach(NunaAchievementDef.Group.allCases.filter { filter == nil || filter == $0 }, id: \.rawValue) { g in
                let items = all.filter { $0.group == g }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 14) {
                            Text(g.title).font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.3).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                            Rectangle().fill(NunaPalette.hairline).frame(height: 1)
                        }
                        LazyVGrid(columns: columns, spacing: 24) { ForEach(items) { cell($0) } }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .task(id: repo.refreshSeq) { workouts = await repo.workoutRows() }
    }

    private func total(_ n: Int, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: "\(n)").font(.nunaBoldFigure(size: 44)).foregroundStyle(NunaPalette.textPrimary)
            Text(label).font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }.frame(maxWidth: .infinity)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                chip("All", on: filter == nil) { filter = nil }
                ForEach(NunaAchievementDef.Group.allCases, id: \.rawValue) { g in chip(g.title, on: filter == g) { filter = g } }
            }
            .padding(.horizontal, NunaSpacing.screenH)
        }
        .scrollIndicators(.hidden).padding(.horizontal, -NunaSpacing.screenH)
    }

    private func chip(_ title: LocalizedStringKey, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { action() } } label: {
            Text(title).font(.nuna(size: 16, weight: .semibold)).textCase(nil)
                .foregroundStyle(on ? Color(red: 0.05, green: 0.06, blue: 0.08) : NunaPalette.textPrimary)
                .padding(.horizontal, 18).frame(height: 40)
                .background(on ? Color.white : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func cell(_ a: NunaAchievementDef) -> some View {
        VStack(spacing: 8) {
            NunaAchievementBadge(shape: a.shape, icon: a.icon, level: a.level)
            Text(a.title).font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).multilineTextAlignment(.center)
            if a.progress > 0 {
                (Text(verbatim: "\(a.progress)").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                 + Text(verbatim: " of \(NunaAchievementDef.perLevel)").font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)).textCase(nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
#endif
