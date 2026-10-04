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
                    Text(note).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                c()
            }
        }
    }
    private func preview(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.nuna(size: 19, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Language (Language.dc)

struct NunaLanguageView: View {
    @AppStorage(AppLanguage.storageKey) private var raw = AppLanguage.system.rawValue
    @AppStorage("ai.responseLanguage") private var anyaLanguage = "app"
    private var current: AppLanguage { AppLanguage.resolve(raw) }

    var body: some View {
        NunaDetailScreen("Language") {
            Text("The app is available in Indonesian, English and more. Dates and numbers follow the language.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { i, l in
                        if i > 0 { NunaDivider() }
                        Button { raw = l.rawValue; AppLanguage.apply(l.rawValue) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: l == .system ? String(localized: "Follow iPhone") : l.autonym).font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                    if l == .system { Text("Uses the iPhone's language when the app has it, otherwise English").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                                }
                                Spacer()
                                Image(systemName: current == l ? "checkmark.circle.fill" : "circle").font(.nuna(size: 21)).foregroundStyle(current == l ? NunaPalette.textPrimary : NunaPalette.textMuted)
                            }.padding(.vertical, 14).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            NunaCard(small: true) {
                NavigationLink(value: NunaAnyaRoute.settings) {
                    NunaListRow("Anya's reply language", subtitle: LocalizedStringKey(anyaLanguage == "id" ? String(localized: "Always Indonesian") : (anyaLanguage == "en" ? String(localized: "Always English") : String(localized: "Follows the app language"))), systemImage: "sparkles", showsChevron: true)
                }.buttonStyle(.plain)
            }
            Button { openIOSSettings() } label: {
                Text("Open language in iOS Settings").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 50).background(NunaPalette.glassStrong, in: Capsule())
            }.buttonStyle(.plain)
            nunaFootnote("Changing the language reloads the app for a moment. Units are set separately.")
        }
    }
}

// MARK: - Optional features (Features.dc)

struct NunaFeaturesView: View {
    @AppStorage(HydrationStore.enabledKey) private var hydration = false
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetect = false
    @AppStorage(PuffinExperiment.journalReminderKey) private var journal = true
    @AppStorage("workoutKeepScreenOn") private var keepOn = false
    @AppStorage(ScreenIdle.strapSyncKeepAwakeKey) private var syncKeepOn = false
    @AppStorage(UnitPrefs.liveActivityKey) private var liveActivity = true
    @AppStorage(AppModel.cycleAwarenessKey) private var cycle = false
    @AppStorage(AppModel.cycleAwarenessHiddenKey) private var cycleHidden = false
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        NunaDetailScreen("Optional features") {
            Text("Turn on what you use. What is off does not appear in Today.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            NunaSettingsGroup {
                NunaToggleRow("Water tracker", subtitle: "A drink log with a daily target", systemImage: "drop", isOn: $hydration).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Auto-detect workouts", subtitle: "Only suggests, never saves on its own", systemImage: "figure.run", isOn: $autoDetect).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Journal reminder", subtitle: "A reminder card in Today", systemImage: "book", isOn: $journal).padding(.vertical, 8)
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
                        Text("Every notification is made on this iPhone, with no server.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer()
                    if status == .denied { Button("Open") { openIOSSettings() }.font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }
                }
            }
            NunaSettingsGroup("Recovery and sleep") {
                NavigationLink(value: NunaAnyaRoute.brief) { NunaListRow("Morning brief", subtitle: LocalizedStringKey(brief ? String(localized: "Every day at \(NunaAnyaSettingsView.clock(CoachBriefScheduler.timeMinutes))") : String(localized: "Off")), systemImage: "sunrise", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.alarm) { NunaListRow("Alarms and bedtime", subtitle: "Smart alarm and wind-down", systemImage: "alarm", showsChevron: true) }.buttonStyle(.plain)
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
                    Text("There is no account and no server. Scores are computed on the device from the strap and Apple Health.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
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
                Button { openIOSSettings() } label: { NunaListRow("Open iOS Settings", subtitle: "Change any permission", systemImage: "gearshape", showsChevron: true) }.buttonStyle(.plain)
            }
            NunaSettingsGroup("What can leave the iPhone") {
                NavigationLink(value: NunaAnyaRoute.settings) {
                    NunaListRow("Text summary to an AI provider", subtitle: LocalizedStringKey(coach.isConfigured && coach.dataConsent ? String(localized: "On, to \(coach.provider.displayName)") : String(localized: "Off. Only after you allow Anya and ask")), systemImage: "sparkles", showsChevron: true)
                }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.backup) { NunaListRow("Export and backup", subtitle: "Only when you ask for it", systemImage: "square.and.arrow.up", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NunaListRow("Anything else", subtitle: "No health data is sent anywhere", systemImage: "nosign") { NunaChip("None") }
            }
            nunaFootnote("Raw heartbeat intervals, PPG and motion are never sent to an AI provider.")
            NunaSettingsGroup("Delete data") {
                NavigationLink(value: NunaMeRoute.imports) { NunaListRow("Delete imported Apple Health data", subtitle: "Strap data is not touched", systemImage: "trash", showsChevron: true) }.buttonStyle(.plain)
            }
        }
        .task { await refresh() }
    }

    private func perm(_ title: LocalizedStringKey, _ sub: LocalizedStringKey, _ icon: String, _ state: String) -> some View {
        NunaListRow(title, subtitle: sub, systemImage: icon) { if !state.isEmpty { NunaChip(verbatim: state) } }
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
