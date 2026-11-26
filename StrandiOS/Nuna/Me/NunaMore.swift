#if os(iOS)
import SwiftUI
import StrandDesign

private func rescore(_ model: AppModel) { Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() } }

// MARK: - Advanced (Advanced.dc)

struct NunaAdvancedView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(PuffinExperiment.keepRealtimeForDataKey) private var continuous = PuffinExperiment.keepRealtimeForDataDefault
    @AppStorage(PuffinExperiment.continuousHrvOvernightOnlyKey) private var overnight = true
    @AppStorage(UnitPrefs.hrvWindowKey) private var window = HrvWindow.whole.rawValue
    @AppStorage(PuffinExperiment.banisterEffortKey) private var banister = PuffinExperiment.banisterEffortDefault
    @AppStorage(PuffinExperiment.powerSavingKey) private var powerSaving = false

    var body: some View {
        NunaDetailScreen("Advanced") {
            Text("For fine tuning. Daily settings are on the Me page.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            NunaSettingsSection("Recovery") {
                NunaSettingsCard {
                    NavigationLink(value: NunaMeRoute.persona) { NunaListRow("Restart the baseline", description: "Under Persona. History stays", systemImage: "arrow.triangle.2.circlepath", showsChevron: true) }.buttonStyle(.plain)
                }
            }
            NunaSettingsSection("HRV") {
                NunaSettingsSwitch("Continuous HRV", subtitle: "Record R-R all day", systemImage: NunaIcons.hrv, isOn: Binding(get: { continuous }, set: { continuous = $0; model.ble.setKeepRealtimeForData($0) }))
                if continuous {
                    NunaSettingsSwitch("Overnight only", subtitle: "Saves power, only while asleep", systemImage: NunaIcons.sleep, isOn: Binding(get: { overnight }, set: { overnight = $0; model.ble.setKeepRealtimeForData(PuffinExperiment.keepRealtimeForDataEnabled) }))
                }
                NunaSettingsCard {
                    NunaChoiceRow("HRV window", subtitle: "Deep sleep pools HRV over slow-wave sleep only. It reads lower and re-scores your history.", systemImage: NunaIcons.hrv,
                                  options: [(value: HrvWindow.whole.rawValue, title: "Whole night"), (value: HrvWindow.deep.rawValue, title: "Deep sleep")], selection: $window)
                        .onChange(of: window) { _, _ in rescore(model) }
                }
            }
            NunaSettingsSection("Strain") {
                NunaSettingsSwitch("Exponential intensity scale", subtitle: "Scores Strain with Banister TRIMP instead of heart-rate zones. Re-scores history", systemImage: "chart.line.uptrend.xyaxis",
                                   isOn: Binding(get: { banister }, set: { banister = $0; rescore(model) }))
            }
            NunaSettingsSection("Power") {
                NunaSettingsSwitch("Power saving", subtitle: "Pauses extra capture when the phone or strap battery is low", systemImage: "leaf", isOn: $powerSaving)
            }
            NunaSettingsSection("Tools") {
                NunaSettingsCard {
                    NavigationLink(value: NunaMeRoute.experiments) { NunaListRow("Experiments", description: "Trial and beta features", systemImage: "flask", showsChevron: true) }.buttonStyle(.plain)
                }
                NunaSettingsCard {
                    NavigationLink(value: NunaMeRoute.testCentre) { NunaListRow("Test Centre", description: "Probes and diagnostics for developers", systemImage: "stethoscope", showsChevron: true) }.buttonStyle(.plain)
                }
                NunaSettingsCard {
                    NavigationLink(value: NunaDeviceRoute.log) { NunaListRow("Strap log", description: "Connection and sync notes", systemImage: "doc.text", showsChevron: true) }.buttonStyle(.plain)
                }
            }
            NunaSettingsSection("Delete data") {
                NunaSettingsCard {
                    NavigationLink(value: NunaMeRoute.imports) { NunaListRow("Apple Health imports or all data", subtitle: "Permanent", systemImage: "trash", showsChevron: true) }.buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Experiments (Experiments.dc)

struct NunaExperimentsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(RhythmConsent.enabledKey) private var rhythm = false
    @AppStorage(LiveSessionPrefs.betaKey) private var liveSessions = true
    @AppStorage(PuffinExperiment.experimentalSleepV2Key) private var sleepV2 = true
    @AppStorage(PuffinExperiment.spo2CandidateDisplayKey) private var spo2 = false
    @AppStorage(PuffinExperiment.motionAwareWakeKey) private var motionWake = false
    @AppStorage(PuffinExperiment.stressPersonalBaselineKey) private var stressBaseline = false
    /// The WHOOP 5/MG wake alarm: the strap is sent the wake time only while this is on (it is the flag `BLEManager.armStrapAlarm` reads).
    @AppStorage(PuffinExperiment.defaultsKey) private var strapAlarm5 = PuffinExperiment.defaultsDefault
    @AppStorage(EarlyWake.enabledKey) private var earlyWake = false

    private var on: Int { [rhythm, liveSessions, sleepV2, spo2, motionWake, stressBaseline, strapAlarm5, earlyWake].filter { $0 }.count }

    var body: some View {
        NunaDetailScreen("Experiments") {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("Still being tested").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary); Spacer(); NunaChip(verbatim: String(localized: "\(on) on")) }
                    Text("These can change or be less accurate, and none is medical. Turn one off to go back to the standard behaviour.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
            NunaSettingsSection("Daily features") {
                NunaSettingsCard {
                    NavigationLink(value: NunaMeRoute.rhythm) { NunaListRow("Beat rhythm", description: "A look at the timing between beats. Off until you agree", systemImage: NunaIcons.beatRhythm, showsChevron: true) { NunaChip(rhythm ? "On" : "Off") } }.buttonStyle(.plain)
                }
                NunaSettingsSwitch("Live Sessions", subtitle: "A quiet coach during a workout. The strap only vibrates to correct you · beta", systemImage: "figure.run", isOn: $liveSessions)
                NunaSettingsSwitch("Sleep staging V2", subtitle: "Cardiorespiratory recipe, better at separating deep and REM", systemImage: NunaIcons.sleep, isOn: $sleepV2)
                NunaSettingsSwitch("Estimated SpO₂ from the strap", subtitle: "WHOOP 5/MG. Not verified", systemImage: "drop", isOn: Binding(get: { spo2 }, set: { spo2 = $0; rescore(model) }))
                NunaSettingsSwitch("Wake refinement from motion", subtitle: "Uses motion to refine the wake time", systemImage: "alarm", isOn: $motionWake)
                NunaSettingsSwitch("WHOOP 5/MG wake alarm", subtitle: "Sends your wake time to a 5/MG strap so it vibrates. Not yet confirmed on every strap, so keep a backup alarm", systemImage: "alarm.waves.left.and.right",
                                   isOn: Binding(get: { strapAlarm5 }, set: { strapAlarm5 = $0; model.applySmartAlarm() }))
                NunaSettingsSwitch("Early wake alarm", subtitle: "Sleep goal and In the green may buzz up to an hour before your wake time. Not yet proven on a strap, so keep a backup alarm", systemImage: "alarm.fill",
                                   isOn: Binding(get: { earlyWake }, set: { earlyWake = $0; model.applySmartAlarm() }))
                NunaSettingsSwitch("Personal stress baseline", subtitle: "Scores the day's stress against your own baseline", systemImage: NunaIcons.stress, isOn: $stressBaseline)
            }
            NunaSettingsSection("Device research") {
                NunaSettingsCard {
                    NavigationLink(value: NunaMeRoute.testCentre) { NunaListRow("Test Centre", description: "WHOOP 5/MG probes, ECG and diagnostics", systemImage: "stethoscope", showsChevron: true) }.buttonStyle(.plain)
                }
                NunaSettingsCard {
                    NavigationLink(value: NunaMeRoute.strava) { NunaListRow("Strava", subtitle: "Upload GPS and treadmill workouts. Off by default", systemImage: "figure.run.circle", showsChevron: true) }.buttonStyle(.plain)
                }
            }
            nunaFootnote("Some features need a particular strap and only work after a few days of wear.")
        }
    }
}

// MARK: - About (About.dc)
#endif
