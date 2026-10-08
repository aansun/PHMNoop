#if os(iOS)
import SwiftUI
import UIKit
import CoreBluetooth
import CoreLocation
import UserNotifications
import AVFoundation
import StrandDesign
import StrandAnalytics

private func openIOSSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }

// MARK: - Units (Units.dc)

struct NunaUnitsView: View {
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.systemKey) private var system = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distance = ""
    @AppStorage(UnitPrefs.temperatureKey) private var temperature = ""
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinTemp = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScale = EffortScale.hundred.rawValue

    private var bodyUnits: UnitSystem { UnitSystem(rawValue: system) ?? .metric }
    private var distUnits: UnitSystem { UnitPrefs.resolveDistance(system: bodyUnits, override: distance) }
    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScale) }

    var body: some View {
        NunaDetailScreen("Units") {
            group("Body measurements", "Weight, height and waist") {
                NunaSegmented([(value: UnitSystem.metric.rawValue, title: "Metric"), (value: UnitSystem.imperial.rawValue, title: "Imperial")], selection: $system)
            }
            group("Distance and pace", "Workouts and live sessions") {
                NunaSegmented<String>([(value: UnitSystem.metric.rawValue, title: "Kilometres"), (value: UnitSystem.imperial.rawValue, title: "Miles")],
                                      selection: Binding<String>(get: { distance.isEmpty ? system : distance }, set: { distance = $0 }))
            }
            group("Temperature", "Follow the body setting or pick one") {
                NunaSegmented([(value: "", title: "Follow body"), (value: TemperatureUnit.celsius.rawValue, title: "°C"), (value: TemperatureUnit.fahrenheit.rawValue, title: "°F")], selection: $temperature)
            }
            group("Skin temperature", "How Health shows it") {
                NunaSegmented([(value: "", title: "Temperature"), (value: SkinTempDisplay.Kind.deviation.rawValue, title: "Vs baseline")], selection: $skinTemp)
            }
            group("Effort scale", "The 0 to 21 scale is like WHOOP's") {
                NunaSegmented([(value: EffortScale.hundred.rawValue, title: "0 to 100"), (value: EffortScale.whoop.rawValue, title: "0 to 21")], selection: $effortScale)
            }
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    nunaTrendsCap("Preview")
                    HStack {
                        preview("Weight", bodyUnits == .imperial ? String(format: "%.1f lb", locale: AppLanguage.activeLocale, profile.weightKg * 2.20462) : String(format: "%.1f kg", locale: AppLanguage.activeLocale, profile.weightKg))
                        preview("Run", distUnits == .imperial ? "3.2 mi" : "5.2 km")
                        preview("Effort", UnitFormatter.effortDisplay(12.4, scale: scale))
                    }
                }
            }
            nunaFootnote("Only the display changes. Your data is always stored the same way.")
        }
    }

    private func group<C: View>(_ title: LocalizedStringKey, _ note: LocalizedStringKey, @ViewBuilder _ c: () -> C) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text(note).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                c()
            }
        }
    }
    private func preview(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.nuna(size: 19, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Language (Language.dc)

/// Everything the Language screen needs to show a language in that language: its bundle for translated copy and its locale for
/// dates and numbers. The sample strings are read from the language's own `.lproj`, so a preview never depends on the language the
/// app is currently running in.
private extension AppLanguage {
    /// The language the iPhone asks for, if the app has it, otherwise English.
    static var systemResolved: AppLanguage {
        let have = Bundle.main.localizations
        let pick = Bundle.preferredLocalizations(from: have, forPreferences: Locale.preferredLanguages).first ?? "en"
        return from(code: pick) ?? .english
    }
    static func from(code: String) -> AppLanguage? {
        let c = code.lowercased()
        if c.hasPrefix("zh") { return .chinese }
        if c.hasPrefix("pt") { return .portuguese }
        let base = c.split(separator: "-").first.map(String.init) ?? c
        return allCases.first { $0 != .system && $0.rawValue.lowercased().split(separator: "-").first.map(String.init) == base }
    }
    /// The language that is really in use when this choice is made.
    var effective: AppLanguage { self == .system ? Self.systemResolved : self }
    var lprojName: String { self == .chinese ? "zh-Hans" : rawValue }
    var bundle: Bundle {
        let l = effective
        guard let path = Bundle.main.path(forResource: l.lprojName, ofType: "lproj"), let b = Bundle(path: path) else { return Bundle.main }
        return b
    }
    var sampleLocale: Locale { Locale(identifier: effective == .chinese ? "zh-Hans" : effective.rawValue) }
    var code: String {
        switch self {
        case .system: return "AUTO"
        case .chinese: return "ZH"
        case .portuguese: return "PT"
        default: return rawValue.uppercased()
        }
    }
    func say(_ key: String) -> String { bundle.localizedString(forKey: key, value: key, table: nil) }
}

struct NunaLanguageView: View {
    @AppStorage(AppLanguage.storageKey) private var raw = AppLanguage.system.rawValue
    @AppStorage("ai.responseLanguage") private var anyaLanguage = "app"
    private var picked: AppLanguage { AppLanguage.resolve(raw) }
    /// The language this running copy of the app was started in.
    private var running: AppLanguage { AppLanguage.from(code: Bundle.main.preferredLocalizations.first ?? "en") ?? .english }
    private var choices: [AppLanguage] { AppLanguage.allCases.filter { $0 != .system } }

    var body: some View {
        NunaDetailScreen("Language") {
            Text("The app is available in \(choices.count) languages. Dates and numbers follow the language.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            option(.system)
            ForEach(choices) { option($0) }
            if picked.effective != running {
                NunaCard(small: true) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.clockwise").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.top, 2)
                        Text("Fully quit and reopen NOOP to switch to \(picked.effective.autonym).").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
                preview(running, title: String(localized: "Preview"))
                preview(picked.effective, title: String(localized: "If \(picked.effective.autonym)"))
            } else {
                preview(running, title: String(localized: "Preview"))
            }
            NunaCard(small: true) {
                VStack(spacing: 0) {
                    NavigationLink(value: NunaAnyaRoute.settings) {
                        NunaListRow("Anya's reply language", subtitle: LocalizedStringKey(anyaLanguage == "id" ? String(localized: "Always Indonesian") : (anyaLanguage == "en" ? String(localized: "Always English") : String(localized: "Follows the app language"))), systemImage: NunaGlyph.anya, showsChevron: true)
                    }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaMeRoute.units) { NunaListRow("Units are set separately", description: "Km or miles, kg or lb, °C or °F", systemImage: "ruler.fill", showsChevron: true) }.buttonStyle(.plain)
                }
            }
            Button { openIOSSettings() } label: {
                Text("Open language in iOS Settings").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 50).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
            nunaFootnote("Changing the language reloads the app for a moment. Dates and numbers follow the language. The language can also be set per app in iOS Settings.")
        }
    }

    private func option(_ l: AppLanguage) -> some View {
        let on = picked == l
        return Button { raw = l.rawValue; AppLanguage.apply(l.rawValue) } label: {
            NunaCard(highlight: on) {
                HStack(spacing: 14) {
                    Text(verbatim: l.code).font(.nuna(size: 12.5, weight: .heavy)).tracking(0.5).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 44, height: 44).background(NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: l == .system ? String(localized: "Follow iPhone") : l.autonym).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: l == .system ? String(localized: "Now: \(AppLanguage.systemResolved.autonym). If the iPhone uses a language the app does not have, the app uses English.") : l.say("All screens, notifications, and Anya replies"))
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.nuna(size: 22)).foregroundStyle(on ? NunaPalette.accent : NunaPalette.textMuted)
                }
            }
        }.buttonStyle(.plain)
    }

    /// Score, button, date and number as they read in `l`, from its own strings and locale.
    private func preview(_ l: AppLanguage, title: String) -> some View {
        let f = DateFormatter(); f.locale = l.sampleLocale; f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let n = NumberFormatter(); n.locale = l.sampleLocale; n.numberStyle = .decimal; n.minimumFractionDigits = 1; n.maximumFractionDigits = 1
        let g = NumberFormatter(); g.locale = l.sampleLocale; g.numberStyle = .decimal; g.maximumFractionDigits = 0
        let unit = l.effective == .indonesian ? "kkal" : "kcal"
        return NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(verbatim: title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Text(verbatim: l.effective.autonym).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                }
                row(l.say("Score"), "Charge 78% · \(l.say("Ready"))")
                row(l.say("Button"), l.say("Start workout"))
                row(l.say("Date"), f.string(from: Date()))
                row(l.say("Number"), "\(n.string(from: 12.4) ?? "12.4") Effort · \(g.string(from: 1240) ?? "1240") \(unit)")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: label).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer(minLength: 12)
            Text(verbatim: value).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Optional features (Features.dc)

struct NunaFeaturesView: View {
    @AppStorage(HydrationStore.enabledKey) private var hydration = false
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetect = false
    @AppStorage(PuffinExperiment.journalReminderKey) private var journal = true
    @AppStorage(JournalReminderNotifier.minuteKey) private var journalMinute = JournalReminderNotifier.defaultMinute
    @AppStorage("workoutKeepScreenOn") private var keepOn = false
    @AppStorage(ScreenIdle.strapSyncKeepAwakeKey) private var syncKeepOn = false
    @AppStorage(UnitPrefs.liveActivityKey) private var liveActivity = true
    @AppStorage(AppModel.cycleAwarenessKey) private var cycle = false
    @AppStorage(AppModel.cycleAwarenessHiddenKey) private var cycleHidden = false
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        NunaDetailScreen("Optional features") {
            Text("Turn on what you use. What is off does not appear in Today.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            NunaSettingsGroup {
                NunaToggleRow("Water tracker", subtitle: "A drink log with a daily target", systemImage: "drop", isOn: $hydration).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Auto-detect workouts", subtitle: "Only suggests, never saves on its own", systemImage: "figure.run", isOn: $autoDetect).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Journal reminder", subtitle: "A notification in the evening and a card in Today", systemImage: "book", isOn: $journal).padding(.vertical, 8)
                if journal {
                    NunaDivider()
                    HStack {
                        Text("Reminder time").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        DatePicker("", selection: Binding(
                            get: { Calendar.current.date(bySettingHour: journalMinute / 60, minute: journalMinute % 60, second: 0, of: Date()) ?? Date() },
                            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); journalMinute = (c.hour ?? 21) * 60 + (c.minute ?? 0) }),
                                   displayedComponents: .hourAndMinute).labelsHidden()
                    }.padding(.vertical, 8)
                }
                NunaDivider()
                NunaToggleRow("Screen on during workouts", subtitle: "Heart rate stays visible while recording", systemImage: "sun.max", isOn: $keepOn).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Live Activity", subtitle: "Heart rate and your session on the Lock Screen and Dynamic Island", systemImage: "iphone.gen3", isOn: $liveActivity).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Screen on while syncing", subtitle: "So a long sync finishes without locking", systemImage: "arrow.triangle.2.circlepath", isOn: $syncKeepOn).padding(.vertical, 8)
                if profile.cycleAwarenessApplies {
                    NunaDivider()
                    NunaToggleRow("Cycle awareness", subtitle: "Optional, only on this iPhone", systemImage: "circle.dotted", isOn: $cycle).padding(.vertical, 8)
                }
            }
            nunaFootnote("Everything here stays on this iPhone.")
        }
    }
}

// MARK: - Notifications (Notifications.dc)

struct NunaNotificationsView: View {
    @EnvironmentObject private var behavior: BehaviorStore
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var model: AppModel
    @AppStorage("coachBrief.enabled") private var brief = false
    @AppStorage(PuffinExperiment.journalReminderKey) private var journal = true
    @AppStorage("notif.masterEnabled") private var wrist = false
    @AppStorage(WorkoutReportNotifier.enabledKey) private var workoutReport = false
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NunaDetailScreen("Notifications") {
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    Image(systemName: status == .authorized || status == .provisional ? "checkmark.circle.fill" : "bell.slash").font(.nuna(size: 20)).foregroundStyle(status == .authorized ? NunaPalette.charge : NunaPalette.textSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(status == .authorized || status == .provisional ? "iOS permission is on" : (status == .denied ? "iOS permission is off" : "iOS has not been asked yet")).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Every notification is made on this iPhone, with no server.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    if status == .denied { Button("Open") { openIOSSettings() }.font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }
                }
            }
            NunaSettingsGroup("Recovery and sleep") {
                NavigationLink(value: NunaAnyaRoute.brief) { NunaListRow("Morning brief", subtitle: LocalizedStringKey(brief ? String(localized: "Every day at \(NunaAnyaSettingsView.clock(CoachBriefScheduler.timeMinutes))") : String(localized: "Off")), systemImage: "sunrise", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.alarm) { NunaListRow("Alarms and bedtime", description: "Smart alarm and wind-down", systemImage: "alarm", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NunaToggleRow("Early-illness warning", subtitle: "When two signals drift together", systemImage: "waveform.path.ecg", isOn: Binding(get: { behavior.illnessWatch }, set: { behavior.illnessWatch = $0; if $0 { IllnessNotifier.requestAuthorization() } })).padding(.vertical, 8)
            }
            NunaSettingsGroup("Workouts and notes") {
                NunaToggleRow("Summary after a workout", subtitle: "Effort, duration and heart rate", systemImage: "list.bullet.clipboard", isOn: Binding(get: { workoutReport }, set: { workoutReport = $0; if $0 { WorkoutReportNotifier.requestAuthorization() } })).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Journal reminder", subtitle: "A card in Today", systemImage: "book", isOn: $journal).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Effort target reached", subtitle: "Once a day, after the strap syncs", systemImage: "target", isOn: Binding(get: { behavior.strainTargetNudge }, set: { behavior.strainTargetNudge = $0; if $0 { StrainTargetNotifier.requestAuthorization(); model.evaluateStrainTarget() } })).padding(.vertical, 8)
            }
            NunaSettingsGroup("Device") {
                NunaToggleRow("Strap battery", subtitle: "Low and full, plus the estimate", systemImage: "battery.25percent", isOn: Binding(get: { behavior.batteryAlerts }, set: { behavior.batteryAlerts = $0; if $0 { BatteryNotifier.requestAuthorization() } })).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Wrist alerts", subtitle: "The master switch for every strap vibration", systemImage: "applewatch.radiowaves.left.and.right", isOn: $wrist).padding(.vertical, 8)
            }
            nunaFootnote("Quiet hours for the wrist reminders are under Strap automations > Sitting too long.")
        }
        .task { status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    }
}

// MARK: - Privacy (Privacy.dc)

struct NunaPrivacyView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var health: HealthKitBridge
    @AppStorage(StravaExperiment.enabledKey) private var stravaOn = false
    @State private var bluetooth = ""
    @State private var notifications = ""
    @State private var location = ""
    @State private var microphone = ""
    @State private var confirmDeleteAll = false

    var body: some View {
        NunaDetailScreen("Privacy") {
            NunaCard(highlight: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "lock.shield").font(.nuna(size: 22, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text("Your data stays on this iPhone").font(.nuna(size: 20, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text("There is no account and no server. Scores are computed on the device from the strap and Apple Health.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            NunaSettingsGroup("iOS permissions") {
                perm("Bluetooth", "Connects to the WHOOP strap", "antenna.radiowaves.left.and.right", bluetooth)
                NunaDivider()
                perm("Notifications", "Briefs, reminders and alerts", "bell", notifications)
                NunaDivider()
                perm("Location", "Only during a GPS workout, never in the background", "location", location)
                NunaDivider()
                perm("Microphone and speech", "Voice input for Anya, recognised on the iPhone", "mic", microphone)
                NunaDivider()
                Button { openIOSSettings() } label: { NunaListRow("Open iOS Settings", description: "Change any permission", systemImage: "gearshape", showsChevron: true) }.buttonStyle(.plain)
            }
            NunaSettingsGroup("What can leave the iPhone") {
                NavigationLink(value: NunaAnyaRoute.settings) {
                    NunaListRow("Text summary to an AI provider", subtitle: LocalizedStringKey(coach.isConfigured && coach.dataConsent ? String(localized: "On, only when you ask") : String(localized: "Off. Only after you allow Anya and ask")), systemImage: NunaGlyph.anya, showsChevron: true)
                }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.strava) {
                    NunaListRow("Strava", subtitle: LocalizedStringKey(stravaSubtitle), systemImage: "figure.run", showsChevron: true)
                }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.appleHealth) {
                    NunaListRow("Apple Health", subtitle: LocalizedStringKey(health.auth == .authorized ? String(localized: "On. Steps, heart rate, vitals, sleep and workouts are written to Health on this iPhone") : String(localized: "Off. Nothing is written to Health")), systemImage: "heart.text.square", showsChevron: true)
                }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.backup) { NunaListRow("Export and backup", description: "Only when you ask for it", systemImage: "square.and.arrow.up", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NunaListRow("Anything else", subtitle: "No other app receives your data", systemImage: "nosign") { NunaChip("None") }
            }
            nunaFootnote("Raw heartbeat intervals, PPG and motion are never sent to an AI provider.")
            NunaSettingsGroup("Delete data") {
                NavigationLink(value: NunaMeRoute.imports) { NunaListRow("Delete imported Apple Health data", subtitle: "Strap data is not touched", systemImage: "trash", showsChevron: true) }.buttonStyle(.plain)
            }
        }
        .task { await refresh() }
    }

    /// What Strava gets, in words: workouts only, and only when it is connected.
    private var stravaSubtitle: String {
        guard stravaOn, StravaTokenStore.isConnected else { return String(localized: "Off. Nothing is uploaded") }
        return StravaExperiment.isAutomaticUploadEnabled
            ? String(localized: "On. GPS, treadmill and your own gym workouts upload automatically")
            : String(localized: "On. A workout uploads only when you choose")
    }

    private func perm(_ title: LocalizedStringKey, _ sub: LocalizedStringKey, _ icon: String, _ state: String) -> some View {
        NunaListRow(title, description: sub, systemImage: icon) { if !state.isEmpty { NunaChip(verbatim: state) } }
    }

    private func refresh() async {
        switch CBManager.authorization { case .allowedAlways: bluetooth = String(localized: "Allowed"); case .denied, .restricted: bluetooth = String(localized: "Off"); default: bluetooth = String(localized: "Not asked") }
        let n = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notifications = (n == .authorized || n == .provisional) ? String(localized: "Allowed") : (n == .denied ? String(localized: "Off") : String(localized: "Not asked"))
        switch CLLocationManager().authorizationStatus { case .authorizedAlways: location = String(localized: "Always"); case .authorizedWhenInUse: location = String(localized: "While in use"); case .denied, .restricted: location = String(localized: "Off"); default: location = String(localized: "Not asked") }
        switch AVAudioApplication.shared.recordPermission { case .granted: microphone = String(localized: "Allowed"); case .denied: microphone = String(localized: "Off"); default: microphone = String(localized: "Optional") }
    }
}
#endif
