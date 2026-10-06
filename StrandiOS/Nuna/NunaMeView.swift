#if os(iOS)
import SwiftUI
import StrandDesign

/// "Saya": the Nuna settings hub (docs/nuna/mockups/Personalize.dc.html). Every row opens a Nuna screen over the same stored
/// settings the Default screens edit, and its subtitle states the current value instead of a generic description.
struct NunaMeView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var behavior: BehaviorStore
    @AppStorage(ExperienceMode.storageKey) private var experienceRaw = ExperienceMode.standard.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystem = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScale = EffortScale.hundred.rawValue
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue
    @AppStorage("notif.masterEnabled") private var wrist = false
    @AppStorage("coachBrief.enabled") private var brief = false
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetect = false
    @AppStorage(HydrationStore.enabledKey) private var hydration = false
    @AppStorage(StravaExperiment.enabledKey) private var strava = false
    @StateObject private var memory = CoachMemoryStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                NunaHeader("Me")
                profileCard
                group("Account and device") {
                    row(.persona, "Persona", "Profile, heart-rate zones, targets", "person.fill")
                    NunaDivider()
                    row(.devices, "Devices", LocalizedStringKey(deviceSubtitle), "applewatch")
                    NunaDivider()
                    row(.anya, "Anya", LocalizedStringKey(anyaSubtitle), NunaGlyph.anya)
                }
                group("Appearance") {
                    row(.appearance, "Appearance", LocalizedStringKey(appearanceSubtitle), "slider.horizontal.3")
                    NunaDivider()
                    row(.widgets, "Widgets and Lock Screen", "Home and lock screen widgets", "square.grid.2x2.fill")
                }
                group("Notifications and automation") {
                    row(.notifications, "Notifications", LocalizedStringKey(notificationsSubtitle), "bell.fill")
                    NunaDivider()
                    row(.automations, "Strap automations", LocalizedStringKey(wrist ? String(localized: "Wrist alerts on") : String(localized: "Wrist alerts off")), "applewatch.radiowaves.left.and.right")
                    NunaDivider()
                    row(.features, "Optional features", LocalizedStringKey(featuresSubtitle), "checkmark.circle.fill")
                }
                group("Data") {
                    row(.data, "Data and integrations", "Apple Health, Strava, import, export", "square.and.arrow.up")
                    NunaDivider()
                    row(.backup, "Backup", LocalizedStringKey(FolderBackup.lastBackupMs > 0 ? String(localized: "Last \(NunaDataHubView.when(FolderBackup.lastBackupMs))") : String(localized: "Not backed up yet")), "clock.arrow.circlepath")
                    NunaDivider()
                    row(.privacy, "Privacy", "Everything stays on this iPhone", "lock.shield.fill")
                }
                group("More") {
                    row(.advanced, "Advanced and experiments", "Baseline, HRV, Test Centre", "flame.fill")
                    NunaDivider()
                    row(.about, "About and help", "Version, how it works, credits", "info.circle.fill")
                }
                Text("PHMNOOP · a fork of NOOP. Not a medical device.")
                    .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).frame(maxWidth: .infinity).multilineTextAlignment(.center).textCase(nil)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 14).padding(.bottom, 24)
        }
        .nunaScreenBackground()
    }

    // MARK: Subtitles

    private var deviceSubtitle: String {
        if live.connected, let pct = live.batteryPct { return String(localized: "Connected · \(Int(pct.rounded()))%") }
        return live.connected ? String(localized: "Connected") : String(localized: "Not connected")
    }
    private var anyaSubtitle: String {
        guard coach.isConfigured else { return String(localized: "Not connected") }
        let n = memory.memories.filter(\.isActive).count
        return coach.provider.nunaSubtitle(model: "") + (n > 0 ? " · " + String(localized: "Memory · \(n)") : "")
    }
    private var appearanceSubtitle: String {
        let exp = ExperienceMode(rawValue: experienceRaw)?.displayName ?? ""
        let u = (UnitSystem(rawValue: unitSystem) ?? .metric) == .imperial ? String(localized: "Imperial") : String(localized: "Metric")
        let code = AppLanguage.activeLocale.identifier.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init) ?? "en"
        let lang = (Locale(identifier: code).localizedString(forLanguageCode: code) ?? code).capitalized
        return "\(exp) · \(lang) · \(u)"
    }
    private var notificationsSubtitle: String {
        let n = [brief, behavior.illnessWatch, behavior.batteryAlerts, behavior.strainTargetNudge].filter { $0 }.count
        return n == 0 ? String(localized: "Nothing scheduled") : String(localized: "\(n) active")
    }
    private var featuresSubtitle: String {
        let on = [hydration ? String(localized: "Water") : nil, autoDetect ? String(localized: "Auto workouts") : nil].compactMap { $0 }
        return on.isEmpty ? String(localized: "Water, journal, auto workouts") : on.joined(separator: " · ")
    }

    // MARK: Pieces

    private var profileCard: some View {
        NavigationLink(value: NunaMeRoute.persona) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        ProfileAvatarView(imageData: profile.avatarImageData, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Profile").font(.nuna(size: NunaTypeSize.h2 - 1, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: "\(profile.age) · \(Int(profile.heightCm.rounded())) cm · \(String(format: "%.1f", locale: AppLanguage.activeLocale, profile.weightKg)) kg").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    NunaDivider()
                    HStack {
                        stat("Max heart rate", "\(profile.hrMax)")
                        stat("Data", String(localized: "\(repo.days.count) days"))
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private func stat(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func group<Rows: View>(_ title: LocalizedStringKey, @ViewBuilder _ rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NunaSectionHeader(title)
            NunaCard(small: true) { VStack(spacing: 0) { rows() } }
        }
    }

    @ViewBuilder private func row(_ route: NunaMeRoute, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ icon: String) -> some View {
        if route == .anya {
            // Anya's name is never set in capitals.
            NavigationLink(value: route) { NunaListRow(title, subtitle: subtitle, systemImage: icon, showsChevron: true).textCase(nil) }.buttonStyle(.plain)
        } else {
            NavigationLink(value: route) { NunaListRow(title, subtitle: subtitle, systemImage: icon, showsChevron: true) }.buttonStyle(.plain)
        }
    }
}

enum NunaMeRoute: Hashable {
    case persona, zones, goals, devices, anya, appearance, widgets, theme
    case units, language, features, notifications, privacy
    case automations, doubleTap, presence, sessionCues, sedentary, shortcuts, alarm
    case data, backup, imports, appleHealth, strava
    case advanced, experiments, testCentre, about
}

extension View {
    func nunaMeDestinations() -> some View {
        navigationDestination(for: NunaMeRoute.self) { r in
            switch r {
            case .persona: NunaPersonaView()
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
            case .advanced: NunaAdvancedView()
            case .experiments: NunaExperimentsView()
            case .testCentre: NunaTestCentreView()
            case .about: NunaAboutView()
            }
        }
    }
}
#endif
