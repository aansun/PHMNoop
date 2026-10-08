#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Add a WHOOP, in the Nuna look. Only WHOOP straps are offered: pick the model, get the strap ready, wait for it to show up nearby, name it,
/// add it. It uses the same scan and the same registration the Default wizard does (`presentWhoopScan`, `registerDevice`), so a strap added
/// here is the one the rest of the app connects to.
struct NunaAddDeviceSheet: View {
    @EnvironmentObject private var model: AppModel
    let onClose: () -> Void

    private enum Step { case model, prep, pick, name }

    @State private var step = Step.model
    @State private var whoopModel: WhoopModel = .whoop5mg
    @State private var picked: (uuid: String, name: String, rssi: Int)?
    @State private var nameDraft = ""
    @State private var askActive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                switch step {
                case .model: modelStep
                case .prep: prepStep
                case .pick: NunaWhoopPickStep(ble: model.ble, onRescan: { model.presentWhoopScan(model: whoopModel) }) { strap in
                    picked = strap; nameDraft = strap.name.isEmpty ? modelTitle : strap.name; model.stopWhoopScan(); step = .name
                }
                case .name: nameStep
                }
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .transition(.opacity)
            Spacer(minLength: 0)
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .animation(.easeInOut(duration: 0.18), value: step)
        .onDisappear { model.stopWhoopScan() }
        .alert("Make this your active device?", isPresented: $askActive) {
            Button("Not now", role: .cancel) { add(makeActive: false) }
            Button("Make active") { add(makeActive: true) }
        } message: { Text("It will provide your live data from now on. You can change this any time.") }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if step != .model {
                Button { back() } label: { NunaBareIcon("chevron.left") }.buttonStyle(.plain).accessibilityLabel(Text("Back"))
            }
            Text("Add a WHOOP").font(.nuna(size: 18, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Button(action: onClose) { NunaBareIcon("xmark") }.buttonStyle(.plain).accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, step == .model ? NunaSpacing.screenH : NunaSpacing.screenH - 8).padding(.top, 20).padding(.bottom, 14)
    }

    private func back() {
        switch step {
        case .prep: step = .model
        case .pick: model.stopWhoopScan(); step = .prep
        case .name: model.presentWhoopScan(model: whoopModel); step = .pick
        case .model: break
        }
    }

    private var modelTitle: String { whoopModel == .whoop4 ? "WHOOP 4.0" : "WHOOP 5.0 / MG" }

    // MARK: 1. Model

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which strap are you adding?").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).padding(.bottom, 4)
            modelRow(.whoop5mg, "WHOOP 5.0 / MG")
            modelRow(.whoop4, "WHOOP 4.0")
        }
    }

    private func modelRow(_ m: WhoopModel, _ title: String) -> some View {
        Button { whoopModel = m; ticked = []; step = .prep } label: {
            HStack(spacing: 14) {
                Image(systemName: "applewatch").font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
                Text(verbatim: title).font(.nuna(size: 14.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
            .padding(.horizontal, 16).frame(height: 60)
            .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: 2. Prepare

    /// What has to be true before the search can find the strap: a strap bonded to another phone or app never shows up here, because a WHOOP
    /// talks to one device at a time. Each line is ticked by the person, and the search starts only when all are.
    private var checks: [(title: String, detail: String)] {
        if whoopModel == .whoop4 {
            return [
                (String(localized: "Close the WHOOP app"), String(localized: "Swipe it away on this iPhone and on any other phone that has it.")),
                (String(localized: "Unpair it from the WHOOP app"), String(localized: "WHOOP app > your profile > Device Settings > Advanced > Unpair Device.")),
                (String(localized: "Wake the strap"), String(localized: "Wear it, or tap the sensor, so it is awake and close to this iPhone.")),
            ]
        }
        return [
            (String(localized: "Unpair it from the WHOOP app"), String(localized: "WHOOP app > your profile > Device Settings > Advanced > Unpair Device. Then close the app, here and on any other phone.")),
            (String(localized: "Forget it in iPhone Bluetooth"), String(localized: "Settings > Bluetooth > tap the i beside the WHOOP > Forget This Device. Skip this if it is not listed.")),
            (String(localized: "Put the strap in pairing mode"), String(localized: "Take it off your wrist. If it is asleep, put it on the charger for a few minutes first. Then tap the top of the sensor firmly with two fingers until only blue lights flash.")),
        ]
    }

    @State private var ticked: Set<Int> = []

    private var prepStep: some View {
        let list = checks
        return VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: modelTitle).font(.nuna(size: 26, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(26)).foregroundStyle(NunaPalette.textPrimary)
                Text("A WHOOP pairs with one device at a time. It will not show up here while another app or phone holds it.")
                    .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, item in
                    if i > 0 { NunaDivider() }
                    Button {
                        if ticked.contains(i) { ticked.remove(i) } else { ticked.insert(i) }
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: ticked.contains(i) ? "checkmark.square.fill" : "square")
                                .font(.nuna(size: 20, weight: .regular)).foregroundStyle(ticked.contains(i) ? NunaPalette.charge : NunaPalette.textMuted).frame(width: 26)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: item.title).font(.nuna(size: 14.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).multilineTextAlignment(.leading)
                                Text(verbatim: item.detail).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 14).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            Button { model.presentWhoopScan(model: whoopModel); step = .pick } label: { Text("Search nearby") }
                .buttonStyle(.nuna(.primary, fullWidth: true))
                .disabled(ticked.count < list.count).opacity(ticked.count < list.count ? 0.4 : 1)
        }
    }

    // MARK: 4. Name

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Found").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Text(verbatim: modelTitle).font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            }
            NunaFormField("Name") { TextField("", text: $nameDraft).submitLabel(.done) }
            Button { askActive = true } label: { Text("Add") }
                .buttonStyle(.nuna(.primary, fullWidth: true))
                .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func add(makeActive: Bool) {
        guard let picked else { return }
        model.stopWhoopScan()
        let now = Int(Date().timeIntervalSince1970)
        let label = whoopModel == .whoop4 ? "4.0" : "5.0 MG"
        let device = PairedDevice(
            id: "whoop-\(picked.uuid)", brand: "WHOOP", model: label,
            nickname: nameDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            peripheralId: picked.uuid, sourceKind: .liveBLE,
            capabilities: WhoopLiveCapabilities.metrics(forModel: label),
            status: .paired, addedAt: now, lastSeenAt: now)
        model.registerDevice(device, makeActive: makeActive)
        onClose()
    }
}

/// The straps the present-scan has found so far, strongest first. Observes the BLE manager so the list fills in while you look at it.
private struct NunaWhoopPickStep: View {
    @ObservedObject var ble: BLEManager
    let onRescan: () -> Void
    let onSelect: ((uuid: String, name: String, rssi: Int)) -> Void

    var body: some View {
        let found = ble.discoveredWhoops.sorted { $0.rssi > $1.rssi }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if found.isEmpty { ProgressView().controlSize(.small).tint(NunaPalette.textSecondary) }
                Text(found.isEmpty ? "Looking for your strap…" : "Pick your strap")
                    .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                Spacer()
                Button(action: onRescan) {
                    Text("Search again").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(LinearGradient(colors: NunaAnyaWing.colors, startPoint: .leading, endPoint: .trailing)).frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
            if found.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing yet? Check these:").font(.nuna(size: 13, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    ForEach([String(localized: "The strap shows only blue lights. Tap the top of the sensor again if it went back to sleep."),
                             String(localized: "It is within a metre of this iPhone."),
                             String(localized: "The WHOOP app is closed and the strap is unpaired from it."),
                             String(localized: "Bluetooth is on for PHMN in Settings.")], id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(verbatim: "·").foregroundStyle(NunaPalette.textMuted)
                            Text(verbatim: line).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(found, id: \.uuid) { strap in
                        Button { onSelect(strap) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "applewatch").font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: strap.name.isEmpty ? "WHOOP" : strap.name).font(.nuna(size: 14.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                                    Text(verbatim: signal(strap.rssi)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                            }
                            .padding(.horizontal, 16).frame(height: 64)
                            .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func signal(_ rssi: Int) -> String {
        rssi > -60 ? String(localized: "Very close") : (rssi > -75 ? String(localized: "Close") : String(localized: "Far"))
    }
}
#endif
