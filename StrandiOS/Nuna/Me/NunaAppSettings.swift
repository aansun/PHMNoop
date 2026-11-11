#if os(iOS)
import SwiftUI
import StrandDesign

/// App Settings: one card per area. Export and backup are inside Data & Integrations, so they are not listed twice; what already has a place in front
/// (targets, alarms, Today cards) is not repeated here either.
struct NunaAppSettingsView: View {
    var body: some View {
        NunaDetailScreen("App Settings", centersTitle: true) {
            VStack(spacing: 10) {
                NunaSettingsLink(route: .recommended, icon: "wand.and.stars", title: "Recommended settings", subtitle: "Closest to the WHOOP app")
                NunaSettingsLink(route: .activity, icon: "heart.text.square", title: "Activity Settings")
                NunaSettingsLink(route: .anya, icon: NunaIcons.ai, title: "AI Settings")
                NunaSettingsLink(route: .appearance, icon: NunaIcons.appearance, title: "Appearance")
                NunaSettingsLink(route: .data, icon: NunaIcons.data, title: "Data & Integrations")
                NunaSettingsLink(route: .features, icon: NunaIcons.features, title: "Optional features")
                NunaSettingsLink(route: .notifications, icon: NunaIcons.notifications, title: "Notifications")
                NunaSettingsLink(route: .automations, icon: "applewatch.radiowaves.left.and.right", title: "Strap automations")
                NunaSettingsLink(route: .language, icon: "globe", title: "Language Preferences")
                NunaSettingsLink(route: .applications, icon: "square.grid.2x2", title: "Application")
                NunaSettingsLink(route: .advanced, icon: NunaIcons.advanced, title: "Advanced and experiments")
            }
            .padding(.top, 10)
        }
    }
}
#endif
