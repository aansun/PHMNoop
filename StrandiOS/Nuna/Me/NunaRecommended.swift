#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopProtocol

/// Settings > App Settings > Recommended settings: the settings closest to the WHOOP app, what yours are now, and one button to use them.
///
/// What it holds is `WhoopDeviceConfiguration.recommended(for:)`: the WHOOP 0 to 21 Strain axis, the exponential Strain recipe, workout detection,
/// continuous HRV through the night, V2 sleep staging and the battery protection that suits the strap. Each row says what is set now and, where it
/// differs, what the profile would set. Nothing here touches an experimental control or writes to the strap, so firmware probes, raw-data capture and
/// the R22 unlock stay where they are.
struct NunaRecommendedView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(PuffinExperiment.keepRealtimeForDataKey) private var continuous = PuffinExperiment.keepRealtimeForDataDefault
    @AppStorage(PuffinExperiment.continuousHrvOvernightOnlyKey) private var overnight = true
    @AppStorage(UnitPrefs.hrvWindowKey) private var hrvWindow = HrvWindow.whole.rawValue
    @AppStorage(PuffinExperiment.experimentalSleepV2Key) private var sleepV2 = true
    @AppStorage(PuffinExperiment.motionAwareWakeKey) private var motion = false
    @AppStorage(UnitPrefs.effortScaleKey) private var scale = EffortScale.whoop.rawValue
    @AppStorage(PuffinExperiment.banisterEffortKey) private var banister = PuffinExperiment.banisterEffortDefault
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetect = PuffinExperiment.autoDetectWorkoutsDefault
    @AppStorage(PuffinExperiment.stressPersonalBaselineKey) private var stressBaseline = false
    @AppStorage(PuffinExperiment.powerSavingKey) private var powerSaving = false
    @AppStorage(PuffinExperiment.powerSavingBatteryPctKey) private var batteryPct = 20
    @AppStorage(PuffinExperiment.pauseHrvDisabledKey) private var pauseDisabled = false
    @AppStorage(PuffinExperiment.lowRefreshKey) private var lowRefresh = false
    @State private var confirm = false
    @State private var applied = false

    // MARK: What the profile is for this strap

    /// The strap in use; a phone with no WHOOP active is shown the 5/MG profile.
    private var family: DeviceFamily {
        if let reg = model.deviceRegistry, let dev = reg.devices.first(where: { $0.id == reg.activeDeviceId }),
           dev.brand.caseInsensitiveCompare("WHOOP") == .orderedSame,
           let f = DeviceFamily.forRegistryDevice(model: dev.model, brand: dev.brand) { return f }
        return .whoop5
    }
    private var rec: WhoopDeviceConfiguration { .recommended(for: family) }

    private struct Line: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let now: String
        let want: String
        let ok: Bool
    }

    private func onOff(_ b: Bool) -> String { b ? String(localized: "On") : String(localized: "Off") }

    private var sections: [(title: LocalizedStringKey, lines: [Line])] {
        let r = rec
        func axis(_ raw: String) -> String { raw == EffortScale.hundred.rawValue ? String(localized: "0 to 100") : String(localized: "0 to 21") }
        func recipe(_ b: Bool) -> String { b ? String(localized: "Exponential (Banister)") : String(localized: "Heart-rate zones (Edwards)") }
        func window(_ raw: String) -> String { raw == HrvWindow.deep.rawValue ? String(localized: "Deep sleep") : String(localized: "Whole night") }
        func staging(_ v2: Bool) -> String { v2 ? "V2" : "V1" }
        func battery(_ on: Bool, _ pct: Int) -> String { on ? String(localized: "On at \(pct)%") : String(localized: "Off") }
        let batteryOK = powerSaving == r.powerSaving && (!r.powerSaving || batteryPct == r.powerSavingBatteryPct)
        var capture: [Line] = [
            Line(id: "continuous", title: "Continuous HRV", now: onOff(continuous), want: onOff(r.continuousHrv), ok: continuous == r.continuousHrv),
        ]
        if r.continuousHrv {
            capture.append(Line(id: "overnight", title: "Overnight only", now: onOff(overnight), want: onOff(r.continuousHrvOvernightOnly),
                                ok: overnight == r.continuousHrvOvernightOnly))
        }
        return [
            ("Strain", [
                Line(id: "scale", title: "Strain scale", now: axis(scale), want: axis(r.effortScaleRaw), ok: scale == r.effortScaleRaw),
                Line(id: "recipe", title: "Strain method", now: recipe(banister), want: recipe(r.banisterEffort), ok: banister == r.banisterEffort),
                Line(id: "detect", title: "Workout detection", now: onOff(autoDetect), want: onOff(r.autoDetectWorkouts), ok: autoDetect == r.autoDetectWorkouts),
            ]),
            ("Recovery and sleep", [
                Line(id: "window", title: "HRV window", now: window(hrvWindow), want: window(r.hrvWindowRaw), ok: hrvWindow == r.hrvWindowRaw),
                Line(id: "staging", title: "Sleep staging", now: staging(sleepV2), want: staging(r.sleepStagingV2), ok: sleepV2 == r.sleepStagingV2),
                Line(id: "motion", title: "Motion-aware wake", now: onOff(motion), want: onOff(r.motionAwareWake), ok: motion == r.motionAwareWake),
                Line(id: "stress", title: "Personal stress baseline", now: onOff(stressBaseline), want: onOff(r.stressPersonalBaseline),
                     ok: stressBaseline == r.stressPersonalBaseline),
            ]),
            ("Capture", capture),
            ("Battery", [
                Line(id: "power", title: "Low-battery protection", now: battery(powerSaving, batteryPct), want: battery(r.powerSaving, r.powerSavingBatteryPct), ok: batteryOK),
                Line(id: "pause", title: "Pause HRV when low", now: onOff(!pauseDisabled), want: onOff(r.pauseHrvOnLowBattery), ok: (!pauseDisabled) == r.pauseHrvOnLowBattery),
                Line(id: "refresh", title: "Background refresh", now: lowRefresh ? String(localized: "Hourly") : String(localized: "Normal"),
                     want: r.lowRefresh ? String(localized: "Hourly") : String(localized: "Normal"), ok: lowRefresh == r.lowRefresh),
            ]),
        ]
    }

    private var differing: Int { sections.reduce(0) { $0 + $1.lines.filter { !$0.ok }.count } }

    // MARK: Page

    var body: some View {
        NunaDetailScreen("Recommended settings", centersTitle: true) {
            status
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                NunaSettingsGroup(section.title) {
                    ForEach(Array(section.lines.enumerated()), id: \.element.id) { i, line in
                        if i > 0 { NunaDivider() }
                        row(line)
                    }
                }
            }
            if differing > 0 {
                Button { confirm = true } label: {
                    Text("Use recommended settings").font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).padding(.top, 6)
            }
            if applied {
                Text("Applied. Your history is being re-scored.").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .frame(maxWidth: .infinity).textCase(nil)
            }
            Text("Firmware experiments, raw-data capture and anything that writes to the strap are never changed here.")
                .font(.nuna(size: 12.5, weight: .semibold)).tracking(0).foregroundStyle(NunaPalette.textMuted).multilineTextAlignment(.center)
                .textCase(nil).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 6).padding(.top, 4)
        }
        .nunaDialog("Use the recommended settings?", isPresented: $confirm) {
            NunaDialogButton("Apply") { apply() }
            NunaDialogButton("Cancel", role: .cancel) {}
        } message: { Text("This changes the settings that differ and re-scores your history. Nothing on your strap is changed.") }
    }

    /// The state in one glance: whether the settings are the profile, or how far from it.
    private var status: some View {
        let match = differing == 0
        return NunaCard {
            HStack(spacing: 16) {
                Image(systemName: match ? "checkmark.circle.fill" : "wand.and.stars").font(.system(size: 30, weight: .regular))
                    .foregroundStyle(match ? NunaPalette.accent : NunaPalette.textPrimary).frame(width: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(match ? "Recommended" : "Custom").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary)
                    Text(match ? "Your settings match the profile closest to the WHOOP app."
                               : "Some settings differ from the profile closest to the WHOOP app.")
                        .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ l: Line) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l.title).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text(verbatim: l.now).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 8)
            if l.ok {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20, weight: .regular)).foregroundStyle(NunaPalette.accent)
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Recommended").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textMuted)
                    Text(verbatim: l.want).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.accent).textCase(nil).multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    /// Writes the profile to the same preferences the Settings toggles use, re-arms what depends on them and re-scores the history.
    private func apply() {
        let r = rec
        r.write()
        model.ble.setKeepRealtimeForData(r.continuousHrv)
        model.applyPowerSaving()
        Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
        withAnimation(.easeOut(duration: 0.2)) { applied = true }
    }
}
#endif
