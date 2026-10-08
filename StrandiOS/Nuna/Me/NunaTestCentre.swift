#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Test Centre (TestCentre.dc): test modes that log extra detail for one part of the app, the recommended configuration,
/// diagnostics and a scheduled export. The probes that write to the strap and the bug-report bundle with its review step
/// stay in the classic Test Centre, reached from the last row, so their confirmation gates are not bypassed.
struct NunaTestCentreView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("selectedWhoopModel") private var modelRaw = WhoopModel.whoop4.rawValue
    @State private var exportOn = ScheduledDebugExport.isEnabled
    @State private var exportMinutes = ScheduledDebugExport.timeMinutes
    @State private var confirmRecalibrate = false
    @State private var recalibrated = false
    @State private var tick = 0

    private var is5MG: Bool { modelRaw == WhoopModel.whoop5mg.rawValue }
    private var activeCount: Int { _ = tick; return TestCentreLayout.visibleModes(is5MG: is5MG).filter { TestCentre.active($0.domain) }.count }

    var body: some View {
        NunaDetailScreen("Test Centre") {
            NunaCard(highlight: activeCount > 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { nunaTrendsCap("For developers"); Spacer(); NunaChip(verbatim: activeCount == 0 ? String(localized: "Normal") : String(localized: "\(activeCount) on"), color: activeCount == 0 ? NunaPalette.charge : NunaPalette.warning) }
                    Text(activeCount == 0 ? "Normal state: no test mode is on." : "Test modes are on. They log extra detail while you use the strap.")
                        .font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text("Each mode records more detail about one part of the app, then bundles it for a bug report. Turn them off when you are done.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
            NunaSettingsGroup("Test modes") {
                let modes = TestCentreLayout.visibleModes(is5MG: is5MG)
                ForEach(Array(modes.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { NunaDivider() }
                    NunaModeRow(mode: m) { tick += 1 }
                }
            }
            NunaSettingsGroup("Diagnostics") {
                NavigationLink(value: NunaDeviceRoute.log) { NunaListRow("Strap log", description: "Connection and sync notes", systemImage: "doc.text", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                Button { confirmRecalibrate = true } label: { NunaListRow("Recalibrate", subtitle: LocalizedStringKey(recalibrated ? String(localized: "Restarted from tonight") : String(localized: "Restart the baseline from scratch")), systemImage: "arrow.triangle.2.circlepath", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NunaToggleRow("Scheduled export", subtitle: "Off until you turn it on", systemImage: "square.and.arrow.up", isOn: Binding(get: { exportOn }, set: { exportOn = $0; ScheduledDebugExport.setEnabled($0) })).padding(.vertical, 8)
                if exportOn {
                    NunaDivider()
                    HStack {
                        Text("Time").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        DatePicker("", selection: Binding(get: { Calendar.current.date(from: DateComponents(hour: exportMinutes / 60, minute: exportMinutes % 60)) ?? Date() },
                                                           set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); exportMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 0); ScheduledDebugExport.setTimeMinutes(exportMinutes) }),
                                   displayedComponents: .hourAndMinute).labelsHidden()
                    }.padding(.vertical, 10)
                }
            }
            NunaSettingsGroup("Report a problem") {
                NavigationLink { TestCentreView() } label: { NunaListRow("Report and strap probes", description: "The bug-report bundle with its review step, and the probes that talk to the strap", systemImage: "ladybug", showsChevron: true) }.buttonStyle(.plain)
            }
            nunaFootnote("Switch on one test, wear the strap, then open Report and strap probes to bundle it. The probes that write to the strap keep their own confirmation there.")
        }
        .confirmationDialog("Restart the baseline?", isPresented: $confirmRecalibrate, titleVisibility: .visible) {
            Button("Restart", role: .destructive) { Baselines.recalibrateRecoveryBaselines(); Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }; recalibrated = true }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Charge and your HRV baseline are learned again from tonight, which takes about 4 nights. Your history stays.") }
    }
}

private struct NunaModeRow: View {
    let mode: TestMode
    let changed: () -> Void
    @State private var on = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NunaIconTile(mode.icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: mode.title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: TestCentreLayout.statusText(for: mode, active: on, elapsedSeconds: TestCentre.startedAt(mode.domain).map { Date().timeIntervalSince($0) }, capturedUnits: nil))
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                Text(verbatim: mode.blurb).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: $on).labelsHidden().tint(NunaPalette.charge)
        }
        .padding(.vertical, 12)
        .onAppear { on = TestCentre.active(mode.domain) }
        .onChange(of: on) { _, v in
            if v { TestCentre.activate(mode.domain) } else { TestCentre.deactivate(mode.domain) }
            changed()
        }
    }
}
#endif
