#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import StrandAnalytics
import WhoopStore

enum NunaDeviceRoute: Hashable {
    case detail(String)      // PairedDevice.id
    case battery, sync, help, helpHub, repair, log, models
}

extension View {
    func nunaDeviceDestinations() -> some View {
        navigationDestination(for: NunaDeviceRoute.self) { r in
            // The device pages sit under Settings > Device Settings: the Settings page title and type scale.
            Group { switch r {
            case .detail(let id): NunaDeviceDetailView(deviceId: id)
            case .battery: NunaDeviceBatteryView()
            case .sync: NunaDeviceSyncView()
            case .help: NunaDeviceHelpView()
            case .helpHub: NunaDeviceHelpHubView()
            case .repair: NunaDeviceRepairView()
            case .log: NunaDeviceLogView()
            case .models: NunaDeviceModelsView()
            } }
            .environment(\.nunaSettingsPage, true)
        }
    }
}

/// What the Nuna device screens say about the connection, from the same state the Default screens read.
enum NunaDeviceFormat {
    static func clock(_ ts: TimeInterval) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("HH:mm"); return f.string(from: Date(timeIntervalSince1970: ts))
    }
    static func ago(_ ts: TimeInterval) -> String {
        let f = RelativeDateTimeFormatter(); f.locale = AppLanguage.activeLocale; f.unitsStyle = .short
        return f.localizedString(for: Date(timeIntervalSince1970: ts), relativeTo: Date())
    }
    /// "3 days 4 hours" from a battery estimate.
    static func remaining(_ hours: Double) -> String {
        let h = Int(hours.rounded())
        if h >= 48 { return String(localized: "\(h / 24) days \(h % 24) hours") }
        return String(localized: "\(h) hours")
    }
    /// The line under the charge on the Status tab: the time to full while charging (when the pace is known), else the runtime left. The runtime
    /// is not shown while charging: it comes from the discharge, which is not what is going on, so it stood still all through a charge.
    @MainActor static func batteryLine(_ live: LiveState) -> String? {
        if live.isCharging { return live.chargeHoursToFull.map { "~" + fullIn($0) } }
        return live.batteryEstimate.map { "~" + remaining($0.remainingHours) }
    }
    /// "Charging" with how long until full, when that is known.
    @MainActor static func chargingLine(_ live: LiveState) -> String {
        live.chargeHoursToFull.map { String(localized: "Charging · full in about \(fullIn($0))") } ?? String(localized: "Charging")
    }
    /// "1 hr 20 min" or "45 min": the time to a full charge.
    static func fullIn(_ hours: Double) -> String {
        let m = max(5, Int((hours * 60 / 5).rounded()) * 5)
        return m >= 60 ? String(localized: "\(m / 60) hr \(m % 60) min") : String(localized: "\(m) min")
    }
    static func family(_ d: PairedDevice) -> String { d.model.isEmpty ? d.brand : d.model }
}

// MARK: - Devices (Devices.dc)

struct NunaDevicesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if let registry = model.deviceRegistry { NunaDevicesContent(registry: registry) }
        else { NunaDetailScreen("Devices") { NunaCard(small: true) { Text("Opening your on-device data. Your paired bands appear here in a moment.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) } } }
    }
}

private struct NunaDevicesContent: View {
    @ObservedObject var registry: DeviceRegistry
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @State private var tab = 0
    @State private var showAdd = false
    @State private var switchTarget: PairedDevice?
    @State private var renaming = false
    @State private var nameDraft = ""
    @State private var confirmRestart = false
    @State private var confirmRemove = false
    @State private var confirmDeleteData = false
    @State private var buzzed = false
    /// The strap shares its heart rate over Bluetooth (a WHOOP 5.0 / MG). The same switch the Live heart rate screen has.
    @AppStorage(PuffinExperiment.broadcastHrKey) private var broadcastOn = false

    private var devices: [PairedDevice] { registry.devices.filter { $0.status != .archived } }
    private var active: PairedDevice? { devices.first { $0.status == .active } }
    private var others: [PairedDevice] { devices.filter { $0.status != .active } }
    private var removed: [PairedDevice] { registry.devices.filter { $0.status == .archived } }

    var body: some View {
        NunaDetailScreen("Device Settings", trailing: AnyView(NavigationLink(value: NunaDeviceRoute.helpHub) { NunaBareIcon("questionmark.circle") }.buttonStyle(.plain).accessibilityLabel(Text("Help")))) {
            if tab == 0 { statusTab } else { advancedTab }
        }
        // The strap and the two tabs stay under the header while the page scrolls under them.
        .pinned {
            VStack(spacing: 14) {
                if let d = active { deviceHeader(d) }
                NunaPageTabs([(value: 0, title: "Status"), (value: 1, title: "Advanced")], selection: $tab)
            }
        }
        .sheet(isPresented: $showAdd) {
            NunaAddDeviceSheet { showAdd = false }.environmentObject(model).environmentObject(live).nunaSheetChrome(detents: [.large])
        }
        .nunaDialog("Make this your active strap?", isPresented: Binding(get: { switchTarget != nil }, set: { if !$0 { switchTarget = nil } })) {
            NunaDialogButton("Make active") { if let d = switchTarget { registry.setActive(d.id) } }
            NunaDialogButton("Cancel", role: .cancel) {}
        } message: { Text("From now on \(switchTarget?.displayName ?? "") provides your live data. The history of the other strap stays exactly as it is.") }
        .nunaDialog("Rename device", isPresented: $renaming) {
            NunaDialogField("Name", text: $nameDraft)
            NunaDialogButton("Save") { if let d = active { registry.rename(d.id, to: nameDraft) } }
            NunaDialogButton("Cancel", role: .cancel) {}
        }
        .nunaDialog("Restart this strap?", isPresented: $confirmRestart) {
            NunaDialogButton("Restart", role: .destructive) { model.rebootStrap() }
            NunaDialogButton("Cancel", role: .cancel) {}
        } message: { Text("It disconnects for about 30 seconds, then reconnects on its own. Your recorded data is kept.") }
        .nunaDialog("Remove this device?", isPresented: $confirmRemove) {
            NunaDialogButton("Remove", role: .destructive) { if let d = active { registry.archive(d.id) } }
            NunaDialogButton("Cancel", role: .cancel) {}
        } message: { Text("PHMN stops connecting to it. Its recorded data is kept and you can add it back.") }
        .nunaDialog("Delete all of this device's data?", isPresented: $confirmDeleteData) {
            NunaDialogButton("Delete data", role: .destructive) {
                guard let d = active else { return }
                Task { guard let store = await model.repo.storeHandle() else { return }; await registry.deleteDeviceData(d.id, store: store) }
            }
            NunaDialogButton("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes everything recorded from this device. It can't be undone.") }
    }

    // MARK: Status

    @ViewBuilder private var statusTab: some View {
        if let guide = live.reconnectGuide { repairBanner(guide) }
        if let d = active {
            hero(d)
            if live.lastSyncedAt != nil || live.backfilling { syncRow }
            broadcastCard
        } else {
            emptyCard
            addButton
        }
    }

    /// "Broadcast heart rate to compatible apps and devices": a heart, the two lines and the switch. Only for a 5.0 / MG (or while it is on, so it can be
    /// turned off); the write to the strap is done when it is connected, and again on every connection while the switch stays on.
    @ViewBuilder private var broadcastCard: some View {
        if model.whoop5Detected || broadcastOn {
            VStack(alignment: .leading, spacing: 10) {
                NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                    HStack(spacing: 14) {
                        Image(systemName: NunaIcons.heartRate).font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(width: 42, height: 42).background(NunaPalette.glassStrong, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Broadcast heart rate").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                            Text("To compatible apps & devices").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                .foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 8)
                        Toggle("", isOn: $broadcastOn).labelsHidden().tint(NunaPalette.charge)
                            .onChange(of: broadcastOn) { _, on in model.ble.setBroadcastHr(on) }
                            .accessibilityLabel(Text("Broadcast heart rate"))
                    }
                }
                if broadcastOn {
                    Text("Broadcast is on: the strap advertises its heart rate all the time, which uses its battery faster. Turn it off when you are not using it with another device.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Who the strap is and whether it is connected, and when it last synced. Shown above both tabs.
    private func deviceHeader(_ d: PairedDevice) -> some View {
        let connected = live.connected
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(connected ? "Connected to" : "Not connected to").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(connected ? NunaPalette.charge : NunaPalette.textSecondary)
                    Button { nameDraft = d.nickname ?? d.displayName; renaming = true } label: {
                        HStack(spacing: 7) {
                            Text(verbatim: d.displayName).font(.nuna(size: 22, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Image(systemName: "pencil").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }
                    }.buttonStyle(.plain).accessibilityLabel(Text("Rename device"))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("Last sync").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    syncPill
                }
            }
        }
    }

    /// The strap at a glance, without a card: the name and whether it is connected, when it last synced, and the strap itself with its
    /// battery beside it (or, when it is not connected, the broken line to the phone and a button to reconnect).
    private func hero(_ d: PairedDevice) -> some View {
        let connected = live.connected
        let family = NunaDeviceFormat.family(d)
        return VStack(alignment: .leading, spacing: 8) {
            NunaDeviceStage(connected: connected, batteryPct: live.batteryPct, charging: live.isCharging,
                            model: family, estimate: NunaDeviceFormat.batteryLine(live))
                .padding(.horizontal, -NunaSpacing.screenH)
            if !connected || live.backfilling {
                VStack(spacing: 6) {
                    Text(connected ? "Syncing history" : "Strap disconnected")
                        .font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Text(connected ? "Pulling what the strap recorded while it was away" : "Bring the strap close to the phone, then reconnect")
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center).textCase(nil)
                }.frame(maxWidth: .infinity)
            }
            if !connected {
                Button { model.disconnect(); model.ble.connect() } label: {
                    Text("Reconnect").font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 50)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).padding(.top, 10)
            }
        }
    }

    /// The time of the last sync and the button that runs the next one, as one pill: the arrow pulses while a sync runs, and the pill is dimmed
    /// (and does nothing) while the strap is not connected.
    private var syncPill: some View {
        Button { model.ble.syncNow() } label: {
            HStack(spacing: 8) {
                Text(verbatim: live.lastSyncedAt.map(NunaDeviceFormat.clock) ?? "–").font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                ZStack {
                    Circle().fill(NunaPalette.accent).frame(width: 26, height: 26)
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                        .symbolEffect(.pulse, isActive: live.backfilling)
                }
            }
            .padding(.leading, 14).padding(.trailing, 5).frame(height: 36)
            .background(NunaPalette.glassStrong, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!live.connected || live.backfilling).opacity(live.connected ? 1 : 0.45)
        .accessibilityLabel(Text("Sync now"))
    }

    private var addButton: some View {
        Button { showAdd = true } label: {
            HStack(spacing: 8) { Image(systemName: "plus").font(.nuna(size: 14, weight: .bold)); Text("Add a device").font(.nuna(size: 15, weight: .bold)) }
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NunaPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
        }.buttonStyle(.plain)
    }

    // MARK: Advanced

    @ViewBuilder private var advancedTab: some View {
        if let d = active {
            HStack(alignment: .top, spacing: 0) {
                idTile("Device ID", Self.deviceID(d), "applewatch")
                idTile("Firmware", live.strapFirmware ?? "–", "cpu")
            }
            .padding(.top, 8)
            Text(verbatim: NunaDeviceFormat.family(d) + (live.strapRange?.firmwareLayout.map { " · " + String(localized: "History format") + " v\($0)" } ?? "")
                    + " · " + String(localized: "Added \(NunaDeviceDetailView.addedDate(d.addedAt))"))
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 30) {
                actionButton("Add a device", String(localized: "Pair another strap or device. The one you have now keeps its history."), "plus.circle") { showAdd = true }
                if SourceCoordinator.isWhoop(d) {
                    actionButton("Reconnect", String(localized: "Close the Bluetooth link and open it again."), "dot.radiowaves.left.and.right") { model.disconnect(); model.ble.connect() }
                    actionButton("Test vibration", buzzed ? String(localized: "Sent") : String(localized: "Makes the strap vibrate once, so you know it responds."), "waveform", enabled: live.connected && live.bonded) {
                        model.buzzStrapOnce(); buzzed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { buzzed = false }
                    }
                    // A 4.0 has no safe restart frame, so the entry only exists for the 5/MG family (same rule as the strap's own detail screen).
                    if live.connected && !model.ble.isWhoop4 {
                        actionButton("Restart strap", String(localized: "Disconnects for about 30 seconds, then reconnects on its own."), "power") { confirmRestart = true }
                    }
                }
                NavigationLink(value: NunaDeviceRoute.log) {
                    actionLabel("Strap log", String(localized: "Copy it when reporting a problem."), "doc.text", enabled: true)
                }.buttonStyle(.plain)
                actionButton("Remove from the list", String(localized: "Data stays and it can be added again."), "archivebox") { confirmRemove = true }
                actionButton("Delete all data of this device", String(localized: "Permanent and cannot be undone."), "trash") { confirmDeleteData = true }
            }
            .padding(.top, 10).padding(.bottom, 10)
        } else {
            addButton
        }
        if !others.isEmpty {
            nunaRuledHeader("Other WHOOP")
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { i, d in
                        if i > 0 { NunaDivider() }
                        HStack(spacing: 12) {
                            NavigationLink(value: NunaDeviceRoute.detail(d.id)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: d.displayName).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                    Text(verbatim: NunaDeviceFormat.family(d) + " · " + String(localized: "history kept")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if !d.isImportSource {
                                Button { switchTarget = d } label: {
                                    Text("Make active").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 36)
                                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.vertical, 12)
                    }
                }
            }
        }
        if !removed.isEmpty {
            nunaRuledHeader("Removed")
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    ForEach(Array(removed.enumerated()), id: \.element.id) { i, d in
                        if i > 0 { NunaDivider() }
                        NavigationLink(value: NunaDeviceRoute.detail(d.id)) {
                            NunaListRow(LocalizedStringKey(d.displayName), description: "Data kept. Tap to add it back", systemImage: "archivebox", showsChevron: true)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// A centred fact about the strap: a quiet icon, its name and the value.
    private func idTile(_ label: LocalizedStringKey, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.nuna(size: 22, weight: .regular)).foregroundStyle(NunaPalette.textMuted).frame(height: 28)
            VStack(spacing: 4) {
                Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Text(verbatim: value).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A button with its explanation underneath.
    private func actionButton(_ title: LocalizedStringKey, _ subtitle: String?, _ icon: String, enabled: Bool = true, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { actionLabel(title, subtitle, icon, enabled: enabled) }
            .buttonStyle(.plain).disabled(!enabled)
    }

    private func actionLabel(_ title: LocalizedStringKey, _ subtitle: String?, _ icon: String, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 26)
                Text(title).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).frame(height: 56)
            .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
            if let subtitle {
                Text(verbatim: subtitle).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 14)
            }
        }
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Rectangle())
    }

    private static func deviceID(_ d: PairedDevice) -> String {
        d.id == "my-whoop" ? (d.peripheralId.map { String($0.prefix(8)).uppercased() } ?? d.id) : d.id
    }

    private var emptyCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                NunaIconTile("applewatch")
                Text("No strap yet").font(.nuna(size: 20, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Text("Add your WHOOP to record heart rate, sleep and workouts. PHMN connects directly over Bluetooth, without the WHOOP app or any cloud.")
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var syncRow: some View {
        NavigationLink(value: NunaDeviceRoute.sync) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(live.backfilling ? "Syncing history…" : "Strap history pulled").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    // The time of the last sync is in the header above; a second copy here could only disagree with it.
                    if live.backfilling {
                        Text(verbatim: String(localized: "\(live.syncChunksThisSession) packets so far")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) { NunaDivider() }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func repairBanner(_ guide: String) -> some View {
        NavigationLink(value: NunaDeviceRoute.repair) {
            NunaCard(small: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NunaPalette.warning)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Can't connect: the strap's pairing was reset").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("See how to pair it again").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }.buttonStyle(.plain)
    }

}

/// The four ways to get unstuck, behind the question mark at the top right of Devices.
struct NunaDeviceHelpHubView: View {
    var body: some View {
        NunaDetailScreen("Help") {
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    NavigationLink(value: NunaDeviceRoute.battery) { NunaListRow("Battery", description: "Level, trend and care", systemImage: "battery.75percent", showsChevron: true) }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaDeviceRoute.help) { NunaListRow("Strap not found?", description: "Steps to check, one by one", systemImage: "questionmark.circle", showsChevron: true) }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaDeviceRoute.models) { NunaListRow("Models and support", description: "WHOOP 4.0, 5.0 and MG", systemImage: "square.stack.3d.up", showsChevron: true) }.buttonStyle(.plain)
                    NunaDivider()
                    NavigationLink(value: NunaDeviceRoute.log) { NunaListRow("Strap log", description: "Copy it when reporting a problem", systemImage: "doc.text", showsChevron: true) }.buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Detail (DeviceDetail.dc, DeviceRestart.dc)

struct NunaDeviceDetailView: View {
    let deviceId: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var nameDraft = ""
    @State private var confirmRemove = false
    @State private var confirmDeleteData = false
    @State private var confirmForget = false

    private var registry: DeviceRegistry? { model.deviceRegistry }
    private var device: PairedDevice? { registry?.devices.first { $0.id == deviceId } }
    private var isActive: Bool { device?.status == .active }
    private var isWhoop: Bool { device.map(SourceCoordinator.isWhoop) ?? false }
    private var linked: Bool { isActive && live.connected }

    var body: some View {
        NunaDetailScreen(LocalizedStringKey(device?.displayName ?? String(localized: "Device"))) {
            if let d = device {
                if isActive {
                    // The active strap's name, state, battery, ids and actions are already on the Devices screen: only what it does not show is here.
                    addedLine(d)
                } else {
                    header(d)
                    info(d)
                }
                manage(d)
            } else {
                NunaCard(small: true) { Text("This device is no longer in the list.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            }
        }
        .nunaDialog("Rename device", isPresented: $renaming) {
            NunaDialogField("Name", text: $nameDraft)
            NunaDialogButton("Save") { registry?.rename(deviceId, to: nameDraft) }
            NunaDialogButton("Cancel", role: .cancel) {}
        }
        .nunaDialog("Remove this device?", isPresented: $confirmRemove) {
            NunaDialogButton("Remove", role: .destructive) { registry?.archive(deviceId); dismiss() }
            NunaDialogButton("Cancel", role: .cancel) {}
        } message: { Text("PHMN stops connecting to it. Its recorded data is kept and you can add it back.") }
        .nunaDialog("Delete all of this device's data?", isPresented: $confirmDeleteData) {
            NunaDialogButton("Delete data", role: .destructive) {
                Task { guard let store = await model.repo.storeHandle() else { return }; await registry?.deleteDeviceData(deviceId, store: store) }
            }
            NunaDialogButton("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes everything recorded from this device. It can't be undone.") }
        .nunaDialog("Remove it for good?", isPresented: $confirmForget) {
            NunaDialogButton("Remove for good", role: .destructive) {
                Task { guard let store = await model.repo.storeHandle() else { return }; await registry?.forget(deviceId, store: store); dismiss() }
            }
            NunaDialogButton("Cancel", role: .cancel) {}
        } message: { Text("The device leaves the list completely. Data already recorded is kept.") }
    }

    /// When the strap was added, the one fact the Devices screen does not carry.
    private func addedLine(_ d: PairedDevice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Added").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: Self.date(d.addedAt)).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ d: PairedDevice) -> some View {
        NunaCard(highlight: linked) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    NunaIconTile("applewatch")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: d.displayName).font(.nuna(size: 22, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: NunaDeviceFormat.family(d)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    NunaChip(d.status == .archived ? "Removed" : (linked ? "Connected" : (isActive ? "Not connected" : "Paired")), color: linked ? NunaPalette.charge : nil)
                }
                if isActive, let pct = live.batteryPct {
                    NunaDivider()
                    NavigationLink(value: NunaDeviceRoute.battery) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: String(localized: "Battery \(Int(pct.rounded()))%")).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: live.isCharging ? NunaDeviceFormat.chargingLine(live) : (live.batteryEstimate.map { String(localized: "Not charging · about \(NunaDeviceFormat.remaining($0.remainingHours))") } ?? String(localized: "Not charging")))
                                    .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func info(_ d: PairedDevice) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                row("Name", d.displayName, action: { nameDraft = d.nickname ?? d.displayName; renaming = true })
                NunaDivider()
                row("Model", NunaDeviceFormat.family(d))
                NunaDivider()
                row("Device ID", d.id == "my-whoop" ? (d.peripheralId.map { String($0.prefix(8)).uppercased() } ?? d.id) : d.id)
                if isActive, let fw = live.strapFirmware { NunaDivider(); row("Firmware", fw) }
                if isActive, let layout = live.strapRange?.firmwareLayout { NunaDivider(); row("History format", "v\(layout)") }
                NunaDivider()
                row("Added", Self.date(d.addedAt))
            }
        }
    }

    @ViewBuilder private func row(_ l: LocalizedStringKey, _ v: String, action: (() -> Void)? = nil) -> some View {
        let content = HStack {
            Text(l).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer(minLength: 12)
            Text(verbatim: v).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            if action != nil { Image(systemName: "pencil").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted) }
        }.padding(.vertical, 14).contentShape(Rectangle())
        if let action { Button(action: action) { content }.buttonStyle(.plain) } else { content }
    }

    private func action(_ title: LocalizedStringKey, _ subtitle: String, _ icon: String, enabled: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { NunaListRow(title, subtitle: LocalizedStringKey(subtitle), systemImage: icon, showsChevron: true) }
            .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }

    private func manage(_ d: PairedDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaRuledHeader("Manage")
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    if d.status == .archived {
                        action("Add it back", "Make it an active device again", "plus.circle", enabled: true) { registry?.setActive(d.id) }
                    } else if !isActive && !d.isImportSource {
                        action("Make active", "It provides your live data", "bolt", enabled: true) { registry?.setActive(d.id) }
                    }
                    if d.status != .archived {
                        if !isActive { NunaDivider() }
                        Button { confirmRemove = true } label: { NunaListRow("Remove from the list", description: "Data stays and it can be added again", systemImage: "archivebox", showsChevron: true) }.buttonStyle(.plain)
                    }
                    NunaDivider()
                    Button { confirmDeleteData = true } label: { NunaListRow("Delete all data of this device", subtitle: "Permanent and cannot be undone", systemImage: "trash", showsChevron: true) }.buttonStyle(.plain)
                    if d.status == .archived {
                        NunaDivider()
                        Button { confirmForget = true } label: { NunaListRow("Remove for good", description: "Takes it out of the list entirely", systemImage: "xmark.bin", showsChevron: true) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private static func date(_ ts: Int) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.dateStyle = .medium; return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
    /// The day a strap was added, as the detail rows and the Advanced tab write it.
    static func addedDate(_ ts: Int) -> String { date(ts) }
}
#endif
