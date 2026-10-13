#if os(iOS)
import SwiftUI
import StrandDesign

/// "Application": the screens that are apps in their own right, in one place: the vital signs and stress monitors, the water log, the lab
/// book, nutrition and naps (and the menstrual cycle while cycle awareness has a reading).
struct NunaApplicationsView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage(HydrationStore.enabledKey) private var hydration = false

    private var stressRoute: NunaTodayRoute {
        MetricCatalog.metric(key: "stress", source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }

    var body: some View {
        NunaDetailScreen("Application") {
            NunaCard(small: true) {
                VStack(spacing: 0) {
                    app(.vitalSigns, "Vital signs", "HRV, resting heart rate, blood oxygen and more", "heart.text.square")
                    NunaDivider()
                    app(stressRoute, "Stress monitor", "Level now and through the day", "gauge.with.dots.needle.50percent")
                    NunaDivider()
                    app(.hydration, "Water", hydration ? "Drink log with a daily target" : "Turn on in Optional features", "drop")
                    NunaDivider()
                    app(.labBook, "Lab book", "Your records", "testtube.2")
                    NunaDivider()
                    app(.nutrition, "Nutrition", "Calories and macros", "fork.knife")
                    NunaDivider()
                    app(.sleepNaps(0), "Nap", "Daytime sleep", "moon.zzz")
                    // Only when cycle awareness is on and has a reading.
                    if appModel.cyclePhase != nil {
                        NunaDivider()
                        app(.cycle, "Menstrual cycle", "Cycle awareness", "drop.fill")
                    }
                }
            }
        }
        // These are screens of the Today stack; this stack needs to know how to open them.
        .nunaTodayDestinations()
    }

    private func app(_ route: NunaTodayRoute, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ icon: String) -> some View {
        NavigationLink(value: route) { NunaListRow(title, subtitle: subtitle, systemImage: icon, showsChevron: true) }.buttonStyle(.plain)
    }
}
#endif
