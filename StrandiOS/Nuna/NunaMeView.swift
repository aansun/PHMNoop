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
                    NunaSettingsLink(route: .privacy, icon: NunaIcons.privacy, title: "Privacy Settings")
                }
                NunaSettingsHeading("Support").padding(.top, 34).padding(.bottom, 12)
                VStack(spacing: 10) {
                    NunaSettingsLink(route: .howItWorks, icon: "questionmark.circle", title: "How it works", subtitle: "How your scores are worked out")
                    NunaSettingsLink(route: .whatsNew, icon: "graduationcap", title: "What's new")
                    NunaSettingsLink(route: .feedback, icon: "bubble.left.and.bubble.right", title: "Feedback", subtitle: "Tell us what you think")
                    NunaSettingsLink(route: .about, icon: NunaIcons.about, title: "About")
                }
                Text(verbatim: NunaAppVersion.text).font(.nuna(size: 13, weight: .semibold)).tracking(0).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    .frame(maxWidth: .infinity).padding(.top, 30)
                NunaKofiButton().frame(maxWidth: .infinity).padding(.top, 18)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .nunaScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The "Support me on Ko-fi" button as Ko-fi draws it: their cup, their wording and the navy chosen there, whatever the app's skin. It opens the support
/// page in the browser. The picture is part of the app, so nothing is asked of Ko-fi until the button is tapped.
private struct NunaKofiButton: View {
    private static let page = URL(string: "https://ko-fi.com/S4U32BCYG3")!

    var body: some View {
        Link(destination: Self.page) {
            HStack(spacing: 9) {
                Image("KofiCup").resizable().scaledToFit().frame(height: 20)
                Text(verbatim: "Support me on Ko-fi").font(.system(size: 16, weight: .bold)).tracking(0).textCase(nil).foregroundStyle(Color.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 18).frame(height: 46)
            // The shadow is the button's alone: put on the whole label it would shade the wording too.
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(NunaPalette.kofiButton).shadow(color: .black.opacity(0.3), radius: 1.5, x: 1, y: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens ko-fi.com in your browser"))
    }
}

enum NunaMeRoute: Hashable {
    case persona, zones, activity, devices, anya, appearance, widgets, theme, achievements
    /// `language` has no page: it opens the app's language in iOS Settings.
    case units, language, features, notifications, privacy
    case automations, doubleTap, presence, sessionCues, sedentary, shortcuts, alarm
    case data, backup, imports, appleHealth, strava, hevy, environment
    case advanced, experiments, testCentre, about
    /// Beat rhythm, opened from Experiments.
    case rhythm
    /// Under About: the licences of what PHMN is built on, one licence, and the project documents (`NunaLegalDoc` raw values).
    case licenses, license(String), legal(String)
    /// The settings closest to the WHOOP app, with what differs from them and one button to use them.
    case recommended
    case search
    case applications
    /// The new Settings structure: the profile page, the App Settings list, the levels, and the two Support pages.
    case profile, appSettings, levels, howItWorks, whatsNew, dayStreak, feedback
    /// The Settings list, pushed from the profile page.
    case settings
}

extension View {
    func nunaMeDestinations() -> some View {
        navigationDestination(for: NunaMeRoute.self) { r in
            Group { switch r {
            case .persona: NunaPersonaView()
            case .achievements: NunaAchievementsView()
            case .zones: NunaZonesView()
            case .activity: NunaActivitySettingsView()
            case .devices: NunaDevicesView()
            case .anya: NunaAnyaSettingsView()
            case .appearance: NunaAppearanceView()
            case .theme: NunaAppearanceView()
            case .widgets: NunaWidgetSettingsView()
            case .units: NunaUnitsView()
            case .language: EmptyView()   // never pushed: Language opens iOS Settings (see `nunaMeLink`)
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
            case .recommended: NunaRecommendedView()
            case .experiments: NunaExperimentsView()
            case .rhythm: NunaRhythmView()
            case .testCentre: NunaTestCentreView()
            case .about: NunaAboutView()
            case .licenses: NunaLicensesView()
            case .license(let id): NunaLicenseDetailView(id: id)
            case .legal(let name): NunaLegalDocView(doc: NunaLegalDoc(rawValue: name) ?? .terms)
            case .search: NunaMeSearchView()
            case .applications: NunaApplicationsView()
            case .profile: NunaProfileView()
            case .appSettings: NunaAppSettingsView()
            case .levels: NunaLevelsView()
            case .howItWorks: NunaHowItWorksView()
            case .whatsNew: NunaWhatsNewView()
            case .feedback: NunaFeedbackView()
            case .dayStreak: NunaDayStreakView()
            case .settings: NunaMeView(pushed: true)
            } }
            // On the Settings pages the title is set small in the middle of the bar at 18 pt, and nothing in the body is larger. The Settings list itself
            // (pushed from the profile) keeps its own large title.
            .environment(\.nunaSettingsPage, r != .settings)
        }
    }
}
#endif
