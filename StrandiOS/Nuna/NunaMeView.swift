#if os(iOS)
import SwiftUI
import StrandDesign

/// Settings, as the reference lays them out: "Account & settings" (My Account, Device Settings, App Settings, Privacy Settings) and "Support", each row
/// one card. The long list of what used to sit here lives one level down, in App Settings.
struct NunaMeView: View {
    /// Opened from the profile page: it then has a way back, as the Settings tab does not need.
    var pushed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NunaHeader("Settings", onBack: pushed ? { dismiss() } : nil) {
                    NavigationLink(value: NunaMeRoute.search) {
                        NunaGlyph("magnifyingglass", pointSize: 16).foregroundStyle(NunaPalette.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Search"))
                }
                NunaSettingsHeading("Account & settings").padding(.top, 22).padding(.bottom, 12)
                VStack(spacing: 10) {
                    NunaSettingsLink(route: .profile, icon: "person.crop.circle", title: "My Account")
                    NunaSettingsLink(route: .devices, icon: "applewatch", title: "Device Settings")
                    NunaSettingsLink(route: .appSettings, icon: "doc.text", title: "App Settings")
                    NunaSettingsLink(route: .privacy, icon: "eye", title: "Privacy Settings")
                }
                NunaSettingsHeading("Support").padding(.top, 34).padding(.bottom, 12)
                VStack(spacing: 10) {
                    NunaSettingsLink(route: .howItWorks, icon: "questionmark.circle", title: "How it works", subtitle: "How your scores are worked out")
                    NunaSettingsLink(route: .whatsNew, icon: "graduationcap", title: "What's new")
                    NunaSettingsLink(route: .about, icon: "info.circle", title: "About")
                }
                Text(verbatim: Self.versionLine).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 40)
                Text("PHMN · a fork of NOOP. Not a medical device.")
                    .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).frame(maxWidth: .infinity).multilineTextAlignment(.center).textCase(nil).padding(.top, 8)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .nunaScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?", b = info?["CFBundleVersion"] as? String ?? "?"
        return String(localized: "App version: \(v) (build \(b))")
    }
}

enum NunaMeRoute: Hashable {
    case persona, zones, goals, devices, anya, appearance, widgets, theme, achievements
    case units, language, features, notifications, privacy
    case automations, doubleTap, presence, sessionCues, sedentary, shortcuts, alarm
    case data, backup, imports, appleHealth, strava, hevy, environment
    case advanced, experiments, testCentre, about
    case search
    case applications
    /// The new Settings structure: the profile page, the App Settings list, the levels, and the two Support pages.
    case profile, appSettings, levels, howItWorks, whatsNew, dayStreak
    /// The Settings list, pushed from the profile page.
    case settings
}

extension View {
    func nunaMeDestinations() -> some View {
        navigationDestination(for: NunaMeRoute.self) { r in
            switch r {
            case .persona: NunaPersonaView()
            case .achievements: NunaAchievementsView()
            case .zones: NunaZonesView()
            case .goals: NunaGoalsView()
            case .devices: NunaDevicesView()
            case .anya: NunaAnyaSettingsView()
            case .appearance: NunaAppearanceView()
            case .theme: NunaAppearanceView()
            case .widgets: NunaWidgetSettingsView()
            case .units: NunaUnitsView()
            case .language: NunaLanguageView()
            case .features: NunaFeaturesView()
            case .notifications: NunaNotificationsView()
            case .privacy: NunaPrivacyView()
            case .automations: NunaAutomationsView()
            case .doubleTap: NunaDoubleTapView()
            case .presence: NunaPresenceView()
            case .sessionCues: NunaSessionCuesView()
            case .sedentary: NunaSedentaryView()
            case .shortcuts: NunaShortcutsView()
            case .alarm: NunaSmartAlarmView()
            case .data: NunaDataHubView()
            case .backup: NunaBackupView()
            case .imports: NunaImportView()
            case .appleHealth: NunaAppleHealthView()
            case .strava: NunaStravaView()
            case .hevy: NunaHevyView()
            case .environment: NunaEnvironmentView()
            case .advanced: NunaAdvancedView()
            case .experiments: NunaExperimentsView()
            case .testCentre: NunaTestCentreView()
            case .about: NunaAboutView()
            case .search: NunaMeSearchView()
            case .applications: NunaApplicationsView()
            case .profile: NunaProfileView()
            case .appSettings: NunaAppSettingsView()
            case .levels: NunaLevelsView()
            case .howItWorks: NunaHowItWorksView()
            case .whatsNew: NunaWhatsNewView()
            case .dayStreak: NunaDayStreakView()
            case .settings: NunaMeView(pushed: true)
            }
        }
    }
}
#endif
