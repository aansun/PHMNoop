#if os(iOS)
import SwiftUI
import StrandDesign

/// "Application": the screens that are apps in their own right, in one place (Workouts opens only from here): the vital signs and stress monitors, the water log, the lab
/// book, nutrition and naps (and the menstrual cycle while cycle awareness has a reading). Sleep has no entry of its own: its detail is the Rest screen.
struct NunaApplicationsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var router: NavRouter
    @AppStorage(HydrationStore.enabledKey) private var hydration = false

    private var stressRoute: NunaTodayRoute {
        MetricCatalog.metric(key: "stress", source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }

    var body: some View {
        NunaDetailScreen("Application") {
            NunaCard(small: true) {
                VStack(spacing: 0) {
                    // Strength Trainer opens straight to its own page, by its route so the rows on it can push theirs; Trends opens over this one (it has no
                    // back button of its own).
                    NavigationLink(value: NunaWorkoutRoute.gym) {
                        NunaListRow("Strength Trainer", subtitle: "Programs, progress and sessions", systemImage: "act:strength-trainer", showsChevron: true)
                    }.buttonStyle(.plain)
                    NunaDivider()
                    // The page with every workout opens over this one, like Trends. This is the only way in to it.
                    Button { router.requestedDestination = .workouts } label: {
                        NunaListRow("Workouts", subtitle: "Every session, its history and training load", systemImage: "figure.run", showsChevron: true)
                    }.buttonStyle(.plain)
                    NunaDivider()
                    Button { router.requestedDestination = .trends } label: {
                        NunaListRow("Trends", subtitle: "Recovery, Strain and Sleep over time", systemImage: "chart.line.uptrend.xyaxis", showsChevron: true)
                    }.buttonStyle(.plain)
                    NunaDivider()
                    app(.vitalSigns, "Vital signs", "HRV, resting heart rate, blood oxygen and more", "heart.text.square")
                    NunaDivider()
                    app(stressRoute, "Stress monitor", "Level now and through the day", NunaIcons.stress)
                    NunaDivider()
                    app(.hydration, "Water", hydration ? "Drink log with a daily target" : "Turn on in Optional features", NunaIcons.water)
                    NunaDivider()
                    app(.labBook, "Lab book", "Your records", "testtube.2")
                    NunaDivider()
                    app(.nutrition, "Nutrition", "Calories and macros", "fork.knife")
                    NunaDivider()
                    app(.sleepNaps(0), "Nap", "Daytime sleep", NunaIcons.nap)
                    // Only when cycle awareness is on and has a reading.
                    if appModel.cyclePhase != nil {
                        NunaDivider()
                        app(.cycle, "Menstrual cycle", "Cycle awareness", NunaIcons.cycle)
                    }
                }
            }
        }
        // These are screens of the Today stack; this stack needs to know how to open them.
        .nunaTodayDestinations()
        .nunaWorkoutDestinations()
    }

    private func app(_ route: NunaTodayRoute, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ icon: String) -> some View {
        NavigationLink(value: route) { NunaListRow(title, subtitle: subtitle, systemImage: icon, showsChevron: true) }.buttonStyle(.plain)
    }
}
#endif
