#if os(iOS)
import SwiftUI
import StrandDesign

private func rescore(_ model: AppModel) { Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() } }

// MARK: - Advanced (Advanced.dc)

struct NunaAdvancedView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(PuffinExperiment.keepRealtimeForDataKey) private var continuous = false
    @AppStorage(PuffinExperiment.continuousHrvOvernightOnlyKey) private var overnight = true
    @AppStorage(UnitPrefs.hrvWindowKey) private var window = HrvWindow.whole.rawValue
    @AppStorage(PuffinExperiment.banisterEffortKey) private var banister = false
    @AppStorage(PuffinExperiment.powerSavingKey) private var powerSaving = false

    var body: some View {
        NunaDetailScreen("Advanced") {
            Text("For fine tuning. Daily settings are on the Me page.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            NunaSettingsGroup("Recovery") {
                NavigationLink(value: NunaMeRoute.persona) { NunaListRow("Restart the baseline", subtitle: "Under Persona. History stays", systemImage: "arrow.triangle.2.circlepath", showsChevron: true) }.buttonStyle(.plain)
            }
            NunaSettingsGroup("HRV") {
                NunaToggleRow("Continuous HRV", subtitle: "Record R-R all day", systemImage: "waveform.path.ecg", isOn: Binding(get: { continuous }, set: { continuous = $0; model.ble.setKeepRealtimeForData($0) })).padding(.vertical, 8)
                if continuous {
                    NunaDivider()
                    NunaToggleRow("Overnight only", subtitle: "Saves power, only while asleep", systemImage: "moon", isOn: Binding(get: { overnight }, set: { overnight = $0; model.ble.setKeepRealtimeForData(PuffinExperiment.keepRealtimeForDataEnabled) })).padding(.vertical, 8)
                }
                NunaDivider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("HRV window").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    NunaSegmented([(value: HrvWindow.whole.rawValue, title: "Whole night"), (value: HrvWindow.deep.rawValue, title: "Deep sleep")], selection: $window)
                        .onChange(of: window) { _, _ in rescore(model) }
                    Text("Deep sleep pools HRV over slow-wave sleep only. It reads lower and re-scores your history.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }.padding(.vertical, 12)
            }
            NunaSettingsGroup("Effort") {
                NunaToggleRow("Exponential intensity scale", subtitle: "Scores Effort with Banister TRIMP instead of heart-rate zones. Re-scores history", systemImage: "chart.line.uptrend.xyaxis",
                              isOn: Binding(get: { banister }, set: { banister = $0; rescore(model) })).padding(.vertical, 8)
            }
            NunaSettingsGroup("Power") {
                NunaToggleRow("Power saving", subtitle: "Pauses extra capture when the phone or strap battery is low", systemImage: "leaf", isOn: $powerSaving).padding(.vertical, 8)
            }
            NunaSettingsGroup("Tools") {
                NavigationLink(value: NunaMeRoute.experiments) { NunaListRow("Experiments", subtitle: "Trial and beta features", systemImage: "flask", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.testCentre) { NunaListRow("Test Centre", subtitle: "Probes and diagnostics for developers", systemImage: "stethoscope", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaDeviceRoute.log) { NunaListRow("Strap log", subtitle: "Connection and sync notes", systemImage: "doc.text", showsChevron: true) }.buttonStyle(.plain)
            }
            NunaSettingsGroup("Delete data") {
                NavigationLink(value: NunaMeRoute.imports) { NunaListRow("Apple Health imports or all data", subtitle: "Permanent", systemImage: "trash", showsChevron: true) }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Experiments (Experiments.dc)

struct NunaExperimentsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: NavRouter
    @AppStorage(RhythmConsent.enabledKey) private var rhythm = false
    @AppStorage(LiveSessionPrefs.betaKey) private var liveSessions = true
    @AppStorage(PuffinExperiment.experimentalSleepV2Key) private var sleepV2 = true
    @AppStorage(PuffinExperiment.spo2CandidateDisplayKey) private var spo2 = false
    @AppStorage(PuffinExperiment.motionAwareWakeKey) private var motionWake = false
    @AppStorage(PuffinExperiment.stressPersonalBaselineKey) private var stressBaseline = false

    private var on: Int { [rhythm, liveSessions, sleepV2, spo2, motionWake, stressBaseline].filter { $0 }.count }

    var body: some View {
        NunaDetailScreen("Experiments") {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("Still being tested").font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary); Spacer(); NunaChip(verbatim: String(localized: "\(on) on")) }
                    Text("These can change or be less accurate, and none is medical. Turn one off to go back to the standard behaviour.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            NunaSettingsGroup("Daily features") {
                Button { router.requestedDestination = .rhythm } label: { NunaListRow("Rhythm", subtitle: "A look at the timing between beats. Off until you agree", systemImage: "waveform.path", showsChevron: true) { NunaChip(rhythm ? "On" : "Off") } }.buttonStyle(.plain)
                NunaDivider()
                NunaToggleRow("Live Sessions", subtitle: "A quiet coach during a workout. The strap only vibrates to correct you · beta", systemImage: "figure.run", isOn: $liveSessions).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Sleep staging V2", subtitle: "Cardiorespiratory recipe, better at separating deep and REM", systemImage: "moon.zzz", isOn: $sleepV2).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Estimated SpO₂ from the strap", subtitle: "WHOOP 5/MG. Not verified", systemImage: "drop", isOn: Binding(get: { spo2 }, set: { spo2 = $0; rescore(model) })).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Wake refinement from motion", subtitle: "Uses motion to refine the wake time", systemImage: "alarm", isOn: $motionWake).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Personal stress baseline", subtitle: "Scores the day's stress against your own baseline", systemImage: "waveform.path.ecg", isOn: $stressBaseline).padding(.vertical, 8)
            }
            NunaSettingsGroup("Device research") {
                NavigationLink(value: NunaMeRoute.testCentre) { NunaListRow("Test Centre", subtitle: "WHOOP 5/MG probes, ECG and diagnostics", systemImage: "stethoscope", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.strava) { NunaListRow("Strava", subtitle: "Upload GPS and treadmill workouts. Off by default", systemImage: "figure.run.circle", showsChevron: true) }.buttonStyle(.plain)
            }
            nunaFootnote("Some features need a particular strap and only work after a few days of wear.")
        }
    }
}

// MARK: - About and help (About.dc)

struct NunaAboutView: View {
    private var version: String { UpdateWatch.installedVersion }
    private var build: String { (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "–" }

    var body: some View {
        NunaDetailScreen("About and help") {
            NunaCard(highlight: true) {
                HStack(spacing: 14) {
                    NunaIconTile("waveform.path.ecg")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("PHMNOOP").font(.nuna(size: 22, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: "v\(version) · build \(build)").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer()
                    NavigationLink { NunaWhatsNewView() } label: { Text("What's new").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 36).background(NunaPalette.glassStrong, in: Capsule()) }.buttonStyle(.plain)
                }
            }
            NunaSettingsGroup("How it works") {
                NavigationLink { NunaHowItWorksView() } label: { NunaListRow("How the app works", subtitle: "Sleep detection, scores, recording and where numbers come from", systemImage: "questionmark.circle", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink { NunaScoringGuideView() } label: { NunaListRow("How scores are worked out", subtitle: "Charge, Effort and Rest", systemImage: "chart.bar.doc.horizontal", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaDeviceRoute.models) { NunaListRow("Models and support", subtitle: "WHOOP 4.0, 5.0 and MG", systemImage: "square.stack.3d.up", showsChevron: true) }.buttonStyle(.plain)
            }
            NunaSettingsGroup("Help") {
                NavigationLink(value: NunaDeviceRoute.log) { NunaListRow("Strap log", subtitle: "Copy it when reporting a problem", systemImage: "doc.text", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaDeviceRoute.help) { NunaListRow("Connection help", subtitle: "Strap not found", systemImage: "questionmark.circle", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                Link(destination: URL(string: "https://github.com/aansun/PHMNoop")!) { NunaListRow("Report a problem", subtitle: "Open on GitHub", systemImage: "arrow.up.right.square", showsChevron: true) }.buttonStyle(.plain)
            }
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 8) {
                    nunaTrendsCap("Credits")
                    Text("PHMNOOP is an internal fork of NOOP by ryanbr, with an iOS layer, Apple Health integration and on-device Anya. The Nes 2011 (HUNT) non-exercise model is used for fitness age.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            nunaFootnote("Not a medical device. It does not diagnose or detect disease and does not replace a professional. Not affiliated with WHOOP, Inc.")
        }
    }
}
#endif
