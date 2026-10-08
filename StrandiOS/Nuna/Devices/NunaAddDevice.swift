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
        Button { whoopModel = m; step = .prep } label: {
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

    private var prepSteps: [String] {
        whoopModel == .whoop4
            ? [String(localized: "Put your WHOOP 4.0 on your wrist and make sure it's awake."),
               String(localized: "Make sure it's not connected to the official WHOOP app right now.")]
            : [String(localized: "WHOOP 5.0 / MG bonds to one device at a time. Unpair it from the official WHOOP app first."),
               String(localized: "Put the band into pairing mode, on your wrist and awake.")]
    }

    private var prepStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(verbatim: modelTitle).font(.nuna(size: 26, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(26)).foregroundStyle(NunaPalette.textPrimary)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(prepSteps.enumerated()), id: \.offset) { i, text in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(verbatim: "\(i + 1)").font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary).frame(width: 18)
                        Text(verbatim: text).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
            }
            Button { model.presentWhoopScan(model: whoopModel); step = .pick } label: { Text("Search nearby") }
                .buttonStyle(.nuna(.primary, fullWidth: true))
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
                Text("Keep the strap close to this iPhone, awake and out of the WHOOP app.")
                    .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
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
