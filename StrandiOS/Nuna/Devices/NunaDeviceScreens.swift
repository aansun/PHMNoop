#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import StrandAnalytics
import WhoopStore

private func openSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}

// MARK: - Battery (DeviceBattery.dc)

/// The strap's charge as it reports it, the session's readings as a line, and an estimate of the time left. The estimate is
/// `BatteryEstimator`'s, fitted to the readings this session has banked, so it says so and stays blank without enough of them.
struct NunaDeviceBatteryView: View {
    @EnvironmentObject private var live: LiveState

    var body: some View {
        let pct = live.batteryPct
        let est = live.batteryEstimate
        let samples = live.batterySamples
        NunaDetailScreen("Battery") {
            NunaCard(highlight: live.charging == true) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { nunaTrendsCap("Now"); Spacer(); NunaChip(live.charging == true ? "Charging" : (live.connected ? "Not charging" : "Not connected"), color: live.charging == true ? NunaPalette.charge : nil) }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: pct.map { "\(Int($0.rounded()))" } ?? "–").font(.nuna(size: 64, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(64)).foregroundStyle(NunaPalette.textPrimary)
                        if pct != nil { Text("%").font(.nuna(size: 22, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                    }
                    if let est, live.charging != true {
                        Text(verbatim: String(localized: "About \(NunaDeviceFormat.remaining(est.remainingHours)) left.")).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    } else if pct == nil {
                        Text("Connect the strap to read its battery.").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    if let mv = live.batteryMv {
                        NunaDivider()
                        HStack { stat("Voltage", String(format: "%.2f V", locale: AppLanguage.activeLocale, Double(mv) / 1000)); Spacer() }
                    }
                }
            }
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { nunaTrendsCap("This session"); Spacer()
                        if let a = samples.first, let b = samples.last, samples.count >= 2 { Text(verbatim: "\(NunaDeviceFormat.clock(TimeInterval(a.ts))) – \(NunaDeviceFormat.clock(TimeInterval(b.ts)))").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) } }
                    if samples.count >= 2 {
                        NunaLine2Chart(points: samples.map { (Date(timeIntervalSince1970: TimeInterval($0.ts)), $0.soc) }, decimals: 0, height: 150)
                    } else {
                        Text("Readings appear here as the strap reports them. Keep it connected for a while to see the trend.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                nunaRuledHeader("Looking after the battery")
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        NunaListRow("Charge while you are awake", description: "In the shower or at your desk, so no sleep data is lost", systemImage: "moon.zzz")
                        NunaDivider()
                        NunaListRow("Avoid heat", description: "Do not charge in direct sunlight", systemImage: "sun.max")
                        NunaDivider()
                        NunaListRow("Dry the contacts", description: "Clean and dry them before charging", systemImage: "drop")
                    }
                }
            }
            Text("The percentage is read from the strap. The time left is estimated from the readings of this session only and gets better the longer the strap stays connected.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
    }

    private func stat(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
    }
}

// MARK: - Sync (DeviceSync.dc, DeviceSyncIsland.dc)

struct NunaDeviceSyncView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @AppStorage(UnitPrefs.syncLiveActivityKey) private var island = true

    var body: some View {
        NunaDetailScreen("History sync") {
            NunaCard(highlight: live.backfilling) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { nunaTrendsCap(live.backfilling ? "Syncing" : "Status"); Spacer()
                        NunaChip(live.backfilling ? "Syncing" : (live.lastSyncError == nil ? "Up to date" : "Failed"), color: live.backfilling || live.lastSyncError != nil ? nil : NunaPalette.charge) }
                    if live.backfilling {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: "\(live.syncChunksThisSession)").font(.nuna(size: 56, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(56)).foregroundStyle(NunaPalette.textPrimary)
                            Text("packets so far").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        if let behind = live.pagesBehindAtConnect, behind > 0 {
                            Text(verbatim: String(localized: "\(behind) pages were waiting on the strap when it connected.")).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        Button { model.ble.abortBackfill() } label: {
                            Text("Stop sync").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 20).frame(height: 42).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain)
                    } else {
                        Text(verbatim: live.lastSyncedAt.map { NunaDeviceFormat.clock($0) } ?? "–").font(.nuna(size: 52, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(52)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: live.lastSyncError ?? (live.lastSyncedAt != nil ? String(localized: "All the history on the strap has been pulled. The next sync runs on its own when the strap is nearby.") : String(localized: "No sync has run since the app opened.")))
                            .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(live.lastSyncError == nil ? NunaPalette.textSecondary : NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                    if !live.backfilling {
                        Button { model.ble.syncNow() } label: {
                            Text("Sync now").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain).disabled(!live.connected).opacity(live.connected ? 1 : 0.4)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                nunaRuledHeader("How sync happens")
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        NunaListRow("Manual", description: "Tap Sync now at any time", systemImage: "hand.tap")
                        NunaDivider()
                        NunaListRow("In the background", description: "Whenever the strap is detected", systemImage: "arrow.triangle.2.circlepath")
                        NunaDivider()
                        NunaListRow("Siri or Shortcuts", description: "The Sync Strap command", systemImage: "mic")
                    }
                }
                NunaCard(small: true) {
                    NunaToggleRow("Progress in the Dynamic Island", subtitle: "And on the Lock Screen while a sync runs", systemImage: "iphone.gen3", isOn: $island).padding(.vertical, 8)
                }
            }
            Text("The strap keeps its history until it is pulled. If a sync is delayed for a long time, today's scores wait for the data to arrive.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
    }
}

// MARK: - Strap not found (DeviceHelp.dc)

struct NunaDeviceHelpView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @State private var confirmRestart = false

    var body: some View {
        NunaDetailScreen("Strap not found?") {
            Text("Try these one by one, from the top. It is usually solved by step 3.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            step(1, "Bring the strap close", "Within 1 metre and nothing blocking it.")
            step(2, "Check Bluetooth on the iPhone", "Turn it off and on again if needed.") { button("Open Settings", openSettings) }
            step(3, "Scan again", "Disconnect, then scan once more.") { button("Scan again") { model.disconnect(); model.ble.connect() } }
            step(4, "Charge the strap", "A very low battery makes the strap stop advertising.") {
                NavigationLink(value: NunaDeviceRoute.battery) { pill("Battery") }.buttonStyle(.plain)
            }
            if live.connected && !model.ble.isWhoop4 {
                step(5, "Restart the strap", "Disconnects for about 30 seconds, then reconnects by itself.") { button("Restart") { confirmRestart = true } }
            }
            step(live.connected && !model.ble.isWhoop4 ? 6 : 5, "Pair it again", "Remove the strap from the list and add it again. Your data stays safe.") {
                NavigationLink(value: NunaDeviceRoute.repair) { pill("See how") }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 10) {
                nunaRuledHeader("Connection states")
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        NunaListRow("Connected", description: "Data arrives live", systemImage: "checkmark.circle")
                        NunaDivider()
                        NunaListRow("Reconnecting", description: "Trying again on its own", systemImage: "arrow.triangle.2.circlepath")
                        NunaDivider()
                        NunaListRow("Disconnected", description: "Tap Scan again", systemImage: "wifi.slash")
                    }
                }
            }
            NavigationLink(value: NunaDeviceRoute.log) {
                NunaCard(small: true) { NunaListRow("Still failing? Send the log", subtitle: "It records what the app sees from the strap", systemImage: "doc.text", showsChevron: true) }
            }.buttonStyle(.plain)
        }
        .alert("Restart this strap?", isPresented: $confirmRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Restart") { model.rebootStrap() }
        } message: { Text("It disconnects for about 30 seconds, then reconnects on its own. Your recorded data is kept.") }
    }

    @ViewBuilder private func step<C: View>(_ n: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey, @ViewBuilder _ action: () -> C = { EmptyView() }) -> some View {
        NunaCard(small: true) {
            HStack(alignment: .top, spacing: 14) {
                Text(verbatim: "\(n)").font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(width: 32, height: 32).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text(detail).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    action().padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func button(_ t: LocalizedStringKey, _ run: @escaping () -> Void) -> some View { Button(action: run) { pill(t) }.buttonStyle(.plain) }
    private func pill(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 16).frame(height: 36).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
    }
}

// MARK: - Pair again (DeviceRepair.dc)

struct NunaDeviceRepairView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var confirmRemove = false

    var body: some View {
        NunaDetailScreen("Pair again") {
            NunaCard(highlight: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Can't connect").font(.nuna(size: 22, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text("The strap's pairing with this iPhone seems to have been reset.").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    Text("This happens when the strap was paired to another phone or app. iOS still keeps the old pairing, so it has to be forgotten first.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            step(1, "Forget the strap in iOS", "Settings, Bluetooth, tap the i next to WHOOP, then Forget This Device.", "Open Settings", openSettings)
            step(2, "Remove it from NOOP's list", "Data already recorded stays.", "Remove from the list") { confirmRemove = true }
            step(3, "Add it again", "Turn the strap on and follow the pairing steps.", "Add WHOOP") { showAdd = true }
            Text("The last 14 days are pulled from the strap again if they are still on it.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
        .sheet(isPresented: $showAdd) { AddDeviceWizard(live: live) { showAdd = false }.environmentObject(model).environmentObject(live) }
        .alert("Remove this device?", isPresented: $confirmRemove) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { if let id = model.deviceRegistry?.activeDeviceId { model.deviceRegistry?.archive(id) } }
        } message: { Text("NOOP stops connecting to it. Its recorded data is kept and you can add it back.") }
    }

    private func step(_ n: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey, _ button: LocalizedStringKey, _ run: @escaping () -> Void) -> some View {
        NunaCard(small: true) {
            HStack(alignment: .top, spacing: 14) {
                Text(verbatim: "\(n)").font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(width: 32, height: 32).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text(detail).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    Button(action: run) { Text(button).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 16).frame(height: 36).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous)) }.buttonStyle(.plain).padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Strap log (DeviceLog.dc)

struct NunaDeviceLogView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @State private var copied = false
    @State private var buzzed = false

    private var lines: [String] { Array(live.log.suffix(120)) }

    var body: some View {
        NunaDetailScreen("Strap log") {
            Text("Take this when reporting a problem. It holds what the app sees from the strap.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            NunaCard(small: true) {
                if lines.isEmpty {
                    Text("Nothing logged yet.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                            Text(verbatim: l).font(.nuna(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(NunaPalette.textPrimary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button { UIPasteboard.general.string = live.log.joined(separator: "\n"); copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false } } label: {
                    Text(copied ? "Copied" : "Copy").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(lines.isEmpty)
                ShareLink(item: live.log.joined(separator: "\n")) {
                    Text("Share").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                nunaRuledHeader("Test")
                NunaCard(small: true) {
                    Button { model.buzzStrapOnce(); buzzed = true; DispatchQueue.main.asyncAfter(deadline: .now() + 3) { buzzed = false } } label: {
                        NunaListRow("Test vibration", subtitle: LocalizedStringKey(buzzed ? String(localized: "Sent") : String(localized: "The strap vibrates once")), systemImage: "waveform", showsChevron: true)
                    }.buttonStyle(.plain).disabled(!(live.connected && live.bonded)).opacity(live.connected && live.bonded ? 1 : 0.4)
                }
            }
            Text("The log only holds connection and sync events. No health data is in it.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
    }
}

// MARK: - Models and support (DeviceModels.dc, DeviceModel.dc)

struct NunaDeviceModelsView: View {
    private struct Row: Identifiable { let id = UUID(); let feature: LocalizedStringKey; let four: String; let five: String }
    private let rows: [Row] = [
        Row(feature: "Live heart rate", four: "Yes", five: "Yes"), Row(feature: "HRV and R-R", four: "Yes", five: "Limited"),
        Row(feature: "History and sync", four: "Yes", five: "Yes"), Row(feature: "Sleep and stages", four: "Yes", five: "Basic"),
        Row(feature: "Vibration and alarm", four: "Yes", five: "Yes"), Row(feature: "SpO₂", four: "Yes", five: "Estimate"),
        Row(feature: "Skin temperature", four: "Yes", five: "Estimate"), Row(feature: "ECG", four: "None", five: "MG, research"),
        Row(feature: "Rename the strap", four: "Yes", five: "No")]

    var body: some View {
        NunaDetailScreen("Models and support") {
            Text("WHOOP 4.0 is the fully supported path. The deeper metrics on 5.0 and MG are still being researched.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            HStack(spacing: 12) {
                badge("WHOOP 4.0", "Fully supported"); badge("5.0 and MG", "Experimental")
            }
            NunaCard(small: true, padding: EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)) {
                VStack(spacing: 0) {
                    HStack {
                        Text("").frame(maxWidth: .infinity, alignment: .leading)
                        Text("4.0").frame(width: 80); Text("5.0 / MG").frame(width: 90)
                    }.font(.nuna(size: 11.5, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary).padding(.vertical, 8)
                    ForEach(rows) { r in
                        NunaDivider()
                        HStack {
                            Text(r.feature).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
                            Text(LocalizedStringKey(r.four)).frame(width: 80); Text(LocalizedStringKey(r.five)).frame(width: 90)
                        }.font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).padding(.vertical, 12)
                    }
                }
            }
            Text("Support for 5.0 and MG grows as their protocol is mapped. Research features are under Experiments.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
    }

    private func badge(_ t: String, _ s: LocalizedStringKey) -> some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: t).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text(s).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
