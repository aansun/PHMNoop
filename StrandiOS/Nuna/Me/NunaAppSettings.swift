#if os(iOS)
import SwiftUI
import StrandDesign

/// App Settings: one card per area, in the reference's order where this app has the area (activity, AI, export, integrations, notifications,
/// language), then the rest of what used to sit on the Settings page.
struct NunaAppSettingsView: View {
    var body: some View {
        NunaDetailScreen("App Settings", centersTitle: true) {
            VStack(spacing: 10) {
                NunaSettingsLink(route: .zones, icon: "heart.text.square", title: "Activity Settings")
                NunaSettingsLink(route: .anya, icon: "sparkles", title: "AI Settings")
                NunaSettingsLink(route: .appearance, icon: "slider.horizontal.3", title: "Appearance")
                NunaSettingsLink(route: .backup, icon: "square.and.arrow.down", title: "Data Export")
                NunaSettingsLink(route: .data, icon: "link", title: "Integrations")
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
