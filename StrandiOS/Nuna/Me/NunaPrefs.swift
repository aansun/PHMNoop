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
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScale = EffortScale.whoop.rawValue

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
            NunaSettingsSection("Temperature") {
                NunaSettingsCard {
                    NunaChoiceRow("Follow the body setting or pick one", systemImage: "thermometer.medium",
                                  options: [(value: "", title: "Follow body"), (value: TemperatureUnit.celsius.rawValue, title: "°C"), (value: TemperatureUnit.fahrenheit.rawValue, title: "°F")],
                                  selection: $temperature)
                }
            }
            group("Skin temperature", "How Health shows it") {
                NunaSegmented([(value: "", title: "Temperature"), (value: SkinTempDisplay.Kind.deviation.rawValue, title: "Vs baseline")], selection: $skinTemp)
            }
            group("Strain scale", "The 0 to 21 scale is like WHOOP's") {
                NunaSegmented([(value: EffortScale.hundred.rawValue, title: "0 to 100"), (value: EffortScale.whoop.rawValue, title: "0 to 21")], selection: $effortScale)
            }
            NunaSettingsSection("Preview") {
                NunaSettingsCard {
                    HStack {
                        preview("Weight", bodyUnits == .imperial ? String(format: "%.1f lb", locale: AppLanguage.activeLocale, profile.weightKg * 2.20462) : String(format: "%.1f kg", locale: AppLanguage.activeLocale, profile.weightKg))
                        preview("Run", distUnits == .imperial ? "3.2 mi" : "5.2 km")
                        preview("Strain", UnitFormatter.effortDisplay(12.4, scale: scale))
                    }.padding(.vertical, 12)
                }
            }
            nunaFootnote("Only the display changes. Your data is always stored the same way.")
        }
    }

    /// A heading, and under it one card holding what the setting is for and its choice.
    private func group<C: View>(_ title: LocalizedStringKey, _ note: LocalizedStringKey, @ViewBuilder _ c: () -> C) -> some View {
        NunaSettingsSection(title) {
            NunaSettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(note).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    c()
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
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

// MARK: - Optional features (Features.dc)

struct NunaFeaturesView: View {
    @AppStorage(HydrationStore.enabledKey) private var hydration = false
    @AppStorage(ScreenIdle.strapSyncKeepAwakeKey) private var syncKeepOn = false
    @AppStorage(AppModel.cycleAwarenessKey) private var cycle = false
    @AppStorage(AppModel.cycleAwarenessHiddenKey) private var cycleHidden = false
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        NunaDetailScreen("Optional features") {
            Text("Turn on what you use. What is off does not appear in Today.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            NunaSettingsSection("Water") {
                NunaSettingsSwitch("Water tracker", subtitle: "A drink log with a daily target", systemImage: "drop", isOn: $hydration)
            }
            NunaSettingsSection("Strap sync") {
                NunaSettingsSwitch("Screen on while syncing", subtitle: "So a long sync finishes without locking", systemImage: "arrow.triangle.2.circlepath", isOn: $syncKeepOn)
            }
            if profile.cycleAwarenessApplies {
                NunaSettingsSection("Menstrual cycle") {
                    NunaSettingsSwitch("Cycle awareness", subtitle: "Optional, only on this iPhone", systemImage: "circle.dotted", isOn: $cycle)
                }
            }
            nunaFootnote("Everything here stays on this iPhone.")
        }
    }
}

// MARK: - Activity settings

/// What happens around a workout: whether the app suggests one by itself, the heart-rate zones, and how the phone behaves while one is recorded.
struct NunaActivitySettingsView: View {
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetect = PuffinExperiment.autoDetectWorkoutsDefault
    @AppStorage("workoutKeepScreenOn") private var keepOn = false
    @AppStorage(UnitPrefs.liveActivityKey) private var liveActivity = true
    @AppStorage(LiveActivityController.designKey) private var liveDesign = "standard"

    var body: some View {
        NunaDetailScreen("Activity Settings", centersTitle: true) {
            NunaSettingsSection("Detection") {
                NunaSettingsSwitch("Activity detection", subtitle: "Suggests a workout when your heart rate stays up. Never saves on its own", systemImage: "figure.run", isOn: $autoDetect)
            }
            NunaSettingsSection("Heart rate") {
                NunaSettingsCard {
                    NavigationLink(value: NunaMeRoute.zones) { NunaListRow("Heart rate settings", subtitle: "Maximum heart rate and zones", systemImage: NunaIcons.heartRate, showsChevron: true) }.buttonStyle(.plain)
                }
            }
            NunaSettingsSection("During a workout") {
                NunaSettingsSwitch("Screen on during workouts", subtitle: "Heart rate stays visible while recording", systemImage: "sun.max", isOn: $keepOn)
                NunaSettingsSwitch("Live Activity", subtitle: "Heart rate and your session on the Lock Screen and Dynamic Island", systemImage: "iphone.gen3", isOn: $liveActivity)
            }
            // The workout's own Live Activity does not depend on the switch above, so its design is always here to choose.
            NunaSettingsSection("Lock Screen design") {
                NunaSettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        NunaSegmented([(value: "standard", title: "Default"), (value: "banner", title: "Banner")], selection: $liveDesign)
                        // The Banner as it will look on the Lock Screen, with made-up figures, at the height the system allows.
                        NOOPBannerLockScreen(state: .bannerDemo())
                            .frame(height: 156).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .opacity(liveDesign == "banner" ? 1 : 0.55)
                        Text("Banner: the heart rate and the clock on top; the five zones and two figures below.")
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }.padding(.vertical, 14)
                }
            }
        }
    }
}

// MARK: - Notifications (Notifications.dc)

/// The alerts PHMN sends. They are all made on this iPhone (no server): the switches here choose which ones the app schedules, and the iOS permission
/// at the top is the master that lets any of them through. Vibration on the strap is a different thing and lives under Strap automations.
struct NunaNotificationsView: View {
    @EnvironmentObject private var behavior: BehaviorStore
    @EnvironmentObject private var model: AppModel
    @AppStorage("coachBrief.enabled") private var brief = false
    @AppStorage(PuffinExperiment.journalReminderKey) private var journal = true
    @AppStorage(JournalReminderNotifier.minuteKey) private var journalMinute = JournalReminderNotifier.defaultMinute
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
            Text("Choose which alerts PHMN sends. If the iOS permission is off, none of them arrive.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            NunaSettingsSection("Reminders") {
                NunaSettingsCard {
                    NavigationLink(value: NunaAnyaRoute.brief) { NunaListRow("Morning brief", subtitle: LocalizedStringKey(brief ? String(localized: "Every day at \(NunaAnyaSettingsView.clock(CoachBriefScheduler.timeMinutes))") : String(localized: "Off")), systemImage: "sunrise", showsChevron: true) }.buttonStyle(.plain)
                }
            }
            NunaSettingsSection("Alerts") {
                NunaSettingsSwitch("Early-illness warning", subtitle: "When two signals drift together", systemImage: NunaIcons.earlyWarning, isOn: Binding(get: { behavior.illnessWatch }, set: { behavior.illnessWatch = $0; if $0 { IllnessNotifier.requestAuthorization() } }))
                NunaSettingsSwitch("Strain target reached", subtitle: "Once a day, after the strap syncs", systemImage: "target", isOn: Binding(get: { behavior.strainTargetNudge }, set: { behavior.strainTargetNudge = $0; if $0 { StrainTargetNotifier.requestAuthorization(); model.evaluateStrainTarget() } }))
                NunaSettingsSwitch("Summary after a workout", subtitle: "Strain, duration and heart rate", systemImage: "list.bullet.clipboard", isOn: Binding(get: { workoutReport }, set: { workoutReport = $0; if $0 { WorkoutReportNotifier.requestAuthorization() } }))
                NunaSettingsSwitch("Strap battery", subtitle: "Low and full, plus the estimate", systemImage: "battery.25percent", isOn: Binding(get: { behavior.batteryAlerts }, set: { behavior.batteryAlerts = $0; if $0 { BatteryNotifier.requestAuthorization() } }))
            }
            NunaSettingsSection("Journal") {
                NunaSettingsSwitch("Journal reminder", subtitle: "A notification in the evening and a card in Today", systemImage: NunaIcons.journal, isOn: $journal)
                if journal {
                    NunaSettingsCard {
                        HStack {
                            Text("Reminder time").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            DatePicker("", selection: Binding(
                                get: { Calendar.current.date(bySettingHour: journalMinute / 60, minute: journalMinute % 60, second: 0, of: Date()) ?? Date() },
                                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); journalMinute = (c.hour ?? 21) * 60 + (c.minute ?? 0) }),
                                       displayedComponents: .hourAndMinute).labelsHidden()
                        }.padding(.vertical, 14)
                    }
                }
            }
            nunaFootnote("Vibration on the strap, with its quiet hours, is under Strap automations. The alarm is set from Tonight's sleep in Today.")
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

    var body: some View {
        NunaDetailScreen("Privacy", centersTitle: true) {
            info
            section("Phone permissions", "What PHMN may use on this iPhone. Tap one to change it in iOS Settings.") {
                permission("Bluetooth", bluetooth)
                permission("Notifications", notifications)
                permission("Location", location)
                permission("Microphone and speech", microphone)
            }
            rule
            section("What can leave the iPhone", "Only when you turn it on or ask for it.") {
                NavigationLink(value: NunaAnyaRoute.settings) {
                    PrivacyRowLabel(title: "AI summary", value: coach.isConfigured && coach.dataConsent ? String(localized: "On, when you ask") : String(localized: "Off"))
                }.buttonStyle(.plain)
                NavigationLink(value: NunaMeRoute.strava) {
                    PrivacyRowLabel(title: "Strava", value: stravaOn && StravaTokenStore.isConnected ? String(localized: "On") : String(localized: "Off"))
                }.buttonStyle(.plain)
                NavigationLink(value: NunaMeRoute.appleHealth) {
                    PrivacyRowLabel(title: "Apple Health", value: health.auth == .authorized ? String(localized: "On") : String(localized: "Off"))
                }.buttonStyle(.plain)
                NavigationLink(value: NunaMeRoute.backup) {
                    PrivacyRowLabel(title: "Export and backup", value: String(localized: "When you ask"))
                }.buttonStyle(.plain)
                PrivacyRowLabel(title: "Exercise videos", value: String(localized: "Only when you tap"))
                PrivacyRowLabel(title: "Other apps", value: String(localized: "None"))
            }
            rule
            section("Your data", "Remove what PHMN imported. Strap data is not touched.") {
                NavigationLink(value: NunaMeRoute.imports) {
                    PrivacyRowLabel(title: "Delete Apple Health data", value: String(localized: "Manage"))
                }.buttonStyle(.plain)
            }
            rule
            additional
        }
        .task { await refresh() }
    }

    // MARK: Parts

    /// The page's one sentence: where the data lives, and what this page is for.
    private var info: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "info").font(.nuna(size: 17, weight: .heavy)).foregroundStyle(NunaPalette.insightBlue).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text("Configure what leaves your iPhone").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text("There is no account and no server. Scores are computed on the iPhone from the strap and Apple Health. Below is what PHMN may use, and the few things that can leave only when you ask.")
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.insightBlue).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(NunaPalette.insightBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
    }

    /// A heading in sentence case, what it covers, and its rows one under the other.
    private func section<Rows: View>(_ title: LocalizedStringKey, _ blurb: LocalizedStringKey, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .accessibilityAddTraits(.isHeader)
            Text(blurb).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 8).padding(.bottom, 18)
            VStack(spacing: 12) { rows() }
        }
    }

    private var rule: some View { NunaDivider().padding(.vertical, 12) }

    private func permission(_ title: LocalizedStringKey, _ state: String) -> some View {
        Button { openIOSSettings() } label: { PrivacyRowLabel(title: title, value: state) }.buttonStyle(.plain)
    }

    /// What holds whatever the settings above say.
    private var additional: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Additional privacy settings").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Image(systemName: "eye").font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
            }
            .frame(maxWidth: .infinity).padding(.top, 18).padding(.bottom, 26)
            Text("PHMN has no account and no server, and it never sells your data. These are never sent to an AI provider:")
                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(["Raw heartbeat intervals (R-R)", "PPG signal", "Motion data"], id: \.self) { item in
                    Text(LocalizedStringKey(item)).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }.padding(.top, 20)
            Text("Your health data is never attached to a feedback report.")
                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true).padding(.top, 20)
        }
    }

    private func refresh() async {
        switch CBManager.authorization { case .allowedAlways: bluetooth = String(localized: "Allowed"); case .denied, .restricted: bluetooth = String(localized: "Off"); default: bluetooth = String(localized: "Not asked") }
        let n = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notifications = (n == .authorized || n == .provisional) ? String(localized: "Allowed") : (n == .denied ? String(localized: "Off") : String(localized: "Not asked"))
        switch CLLocationManager().authorizationStatus { case .authorizedAlways: location = String(localized: "Always"); case .authorizedWhenInUse: location = String(localized: "While in use"); case .denied, .restricted: location = String(localized: "Off"); default: location = String(localized: "Not asked") }
        switch AVAudioApplication.shared.recordPermission { case .granted: microphone = String(localized: "Allowed"); case .denied: microphone = String(localized: "Off"); default: microphone = String(localized: "Optional") }
    }
}

/// One row of the Privacy page: the name on the left, what it is set to on the right, on a card of its own.
private struct PrivacyRowLabel: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).multilineTextAlignment(.leading)
            Spacer(minLength: 12)
            Text(verbatim: value).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 22).padding(.vertical, 18).frame(maxWidth: .infinity, minHeight: 64)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
#endif
