#if os(iOS)
import SwiftUI
import StrandDesign

/// App Settings: one card per area. Export and backup are inside Data & Integrations, so they are not listed twice; what already has a place in front
/// (targets, alarms, Today cards) is not repeated here either.
struct NunaAppSettingsView: View {
    var body: some View {
        NunaDetailScreen("App Settings", centersTitle: true) {
            VStack(spacing: 10) {
                NunaSettingsLink(route: .activity, icon: "heart.text.square", title: "Activity Settings")
                NunaSettingsLink(route: .anya, icon: "sparkles", title: "AI Settings")
                NunaSettingsLink(route: .appearance, icon: "slider.horizontal.3", title: "Appearance")
                NunaSettingsLink(route: .data, icon: "link", title: "Data & Integrations")
                NunaSettingsLink(route: .features, icon: "square.and.pencil", title: "Optional features")
                NunaSettingsLink(route: .notifications, icon: "bell", title: "Notifications")
                NunaSettingsLink(route: .automations, icon: "applewatch.radiowaves.left.and.right", title: "Strap automations")
                NunaSettingsLink(route: .language, icon: "globe", title: "Language Preferences")
                NunaSettingsLink(route: .applications, icon: "square.grid.2x2", title: "Application")
                NunaSettingsLink(route: .advanced, icon: "flame", title: "Advanced and experiments")
            }
            .padding(.top, 10)
        }
    }
}
#endif
