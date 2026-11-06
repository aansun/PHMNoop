#if os(iOS)
import SwiftUI
import StrandDesign

// The first run in the Nuna look: the terms, then four short pages (welcome, connect the strap, about you, done). What the older wizard also asked
// (importing history, notifications, appearance) is left to Settings and to the moment it is needed.

// MARK: - Pieces

private struct NunaOnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase)
                .foregroundStyle(enabled ? NunaPalette.onAccent : NunaPalette.textMuted)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(enabled ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

private struct NunaOnboardingTextButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity).frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}

private func nunaOnboardingTitle(_ s: LocalizedStringKey) -> some View {
    Text(s).font(.nunaWords(size: 27)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
}

private func nunaOnboardingBody(_ s: LocalizedStringKey) -> some View {
    Text(s).font(.nunaWords(size: 15.5)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
}

// MARK: - Terms

/// "Before you start": the points, then each statement to confirm. The wording is the app's terms (`Terms`), unchanged; only the look is new.
struct NunaTermsGate: View {
    let onAccept: () -> Void
    @State private var checks: [Bool] = Array(repeating: false, count: Terms.attestations.count)
    private var allChecked: Bool { checks.allSatisfy { $0 } }

    var body: some View {
        ZStack {
            NunaBackdrop().ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        PHMNMark(.puck, size: 54, color: NunaPalette.textPrimary).padding(.top, 36)
                        nunaOnboardingTitle("Before you start")
                        nunaOnboardingBody("Read the points below, then confirm each statement.")
                        ForEach(Terms.points, id: \.0) { point in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: point.0).font(.nuna(size: 15.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                                Text(verbatim: point.1).font(.nunaWords(size: 14)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(2).textCase(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        nunaRuledHeader("Please confirm").padding(.top, 6)
                        ForEach(Array(Terms.attestations.enumerated()), id: \.offset) { i, line in
                            Button { checks[i].toggle() } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: checks[i] ? "checkmark.square.fill" : "square").font(.system(size: 22, weight: .regular))
                                        .foregroundStyle(checks[i] ? NunaPalette.recoveryBlue : NunaPalette.textSecondary)
                                    Text(verbatim: line).font(.nunaWords(size: 14)).tracking(0).foregroundStyle(NunaPalette.textPrimary).lineSpacing(2).textCase(nil)
                                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityAddTraits(checks[i] ? .isSelected : [])
                        }
                        Text("The full terms are in TERMS.md, shipped with the app. This is not legal advice.")
                            .font(.nunaWords(size: 12.5)).tracking(0).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    }
                    .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                NunaOnboardingPrimaryButton(title: "Accept & continue", enabled: allChecked, action: onAccept)
                    .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 14)
            }
        }
    }
}

// MARK: - Wizard

struct NunaOnboardingWizard: View {
    let onFinished: () -> Void
    private enum Step: Int, CaseIterable { case welcome, connect, about, done }
    @State private var step = Step.welcome
    @EnvironmentObject private var live: LiveState

    var body: some View {
        ZStack {
            NunaBackdrop().ignoresSafeArea()
            VStack(spacing: 0) {
                chrome
                Group {
                    switch step {
                    case .welcome: NunaOnboardingWelcome(next: advance)
                    case .connect: NunaOnboardingConnect(next: advance)
                    case .about: NunaOnboardingAbout(next: advance)
                    case .done: NunaOnboardingDone(connected: live.bonded, finish: onFinished)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private func advance() { if let n = Step(rawValue: step.rawValue + 1) { step = n } }

    /// A back arrow and four dots, so there is always a way back and a sense of how short it is.
    private var chrome: some View {
        HStack {
            Button { if let p = Step(rawValue: step.rawValue - 1) { step = p } } label: {
                Image(systemName: "chevron.left").font(.system(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 48, height: 44, alignment: .leading)
            }
            .buttonStyle(.plain).opacity(step == .welcome || step == .done ? 0 : 1).disabled(step == .welcome || step == .done)
            .accessibilityLabel(Text("Back"))
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? NunaPalette.textPrimary : NunaPalette.textMuted.opacity(0.4)).frame(width: s == step ? 22 : 7, height: 7)
                }
            }
            Spacer()
            Color.clear.frame(width: 48, height: 44)
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }
}

private struct NunaOnboardingWelcome: View {
    let next: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            PHMNMark(.puck, size: 84, color: NunaPalette.textPrimary).padding(.bottom, 10)
            nunaOnboardingTitle("Your data stays on your iPhone")
            nunaOnboardingBody("PHMN reads your Recovery, sleep and Strain straight from your strap. No account, no server.")
            Spacer(minLength: 0)
            NunaOnboardingPrimaryButton(title: "Get started", action: next).padding(.bottom, 14)
        }
        .padding(.horizontal, NunaSpacing.screenH)
    }
}

// MARK: Connect

private struct NunaOnboardingConnect: View {
    let next: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue
    @State private var scanning = false
    @State private var showHelp = false
    private var selectedModel: WhoopModel { WhoopModel(rawValue: selectedModelRaw) ?? .whoop4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nunaOnboardingTitle(live.bonded ? "Your strap is connected" : "Connect your strap").padding(.top, 14)
                    nunaOnboardingBody(live.bonded ? "PHMN is reading it now." : "Wear it, keep it close, and tap Scan. iOS will ask for Bluetooth: choose Allow.")
                    status
                    if !live.bonded {
                        NunaSegmented(WhoopModel.allCases.map { (value: $0.rawValue, title: LocalizedStringKey($0.displayName)) },
                                      selection: Binding(get: { selectedModelRaw }, set: { restart(for: WhoopModel(rawValue: $0) ?? .whoop4) }))
                        if selectedModel == .whoop5mg {
                            Text("WHOOP 5.0 / MG pairs with one app at a time. If nothing is found, unpair it in the WHOOP app and close that app first.")
                                .font(.nunaWords(size: 13.5)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                        }
                        Button { withAnimation(.easeInOut(duration: 0.2)) { showHelp.toggle() } } label: {
                            HStack(spacing: 6) {
                                Text("Can't find it?").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase)
                                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).rotationEffect(.degrees(showHelp ? 180 : 0))
                            }
                            .foregroundStyle(NunaPalette.textSecondary)
                        }
                        .buttonStyle(.plain)
                        if showHelp { help }
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            VStack(spacing: 2) {
                if live.bonded {
                    NunaOnboardingPrimaryButton(title: "Continue", action: next)
                } else {
                    NunaOnboardingPrimaryButton(title: scanning ? "Scanning…" : "Scan", enabled: !scanning, action: { startScan() })
                    NunaOnboardingTextButton(title: "I'll do this later", action: next)
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 10)
        }
        .onDisappear { scanning = false }
    }

    private var status: some View {
        HStack(spacing: 14) {
            Image(systemName: live.bonded ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right").font(.system(size: 26, weight: .regular))
                .foregroundStyle(live.bonded ? NunaPalette.charge : NunaPalette.textSecondary)
                .symbolEffect(.variableColor.iterative, isActive: scanning && !live.bonded)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(live.bonded ? "Connected" : (live.connected ? "Connecting…" : (scanning ? "Searching…" : "Ready to scan")))
                    .font(.nuna(size: 15.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                if live.bonded, let pct = live.batteryPct {
                    Text(verbatim: String(localized: "\(Int(pct))% battery")).font(.nunaWords(size: 13.5)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).frame(height: 66).frame(maxWidth: .infinity)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A WHOOP strap does not show in iOS Bluetooth settings. Only an app like PHMN can find it, so there is nothing to pair there.")
            Text("Check that it is charged and worn, that the WHOOP app is closed (a strap talks to one app at a time), and that it is within a metre of the phone.")
            Text("No strap yet? Continue and connect later from Today.")
        }
        .font(.nunaWords(size: 13.5)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(2).textCase(nil).fixedSize(horizontal: false, vertical: true)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func startScan(for m: WhoopModel? = nil) {
        scanning = true
        showHelp = false
        model.scan(model: m ?? selectedModel)
        // If nothing bonded after a calm beat, the help opens by itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if !live.bonded { scanning = false; withAnimation(.easeInOut(duration: 0.2)) { showHelp = true } }
        }
    }

    private func restart(for m: WhoopModel) {
        selectedModelRaw = m.rawValue
        guard !live.bonded else { return }
        model.disconnect()
        startScan(for: m)
    }
}

// MARK: About you

private struct NunaOnboardingAbout: View {
    let next: () -> Void
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nunaOnboardingTitle("About you").padding(.top, 14)
                    nunaOnboardingBody("So your heart-rate zones, calories and baselines fit you. You can change this in Settings.")
                    NunaCard(small: true) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Date of birth").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Spacer()
                                DatePicker("", selection: $profile.dateOfBirth, in: ProfileStore.dateOfBirthRange, displayedComponents: .date).labelsHidden()
                            }.padding(.vertical, 10)
                            NunaDivider()
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Sex").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                NunaSegmented([(value: "male", title: "Male"), (value: "female", title: "Female"), (value: "nonbinary", title: "Other")],
                                              selection: Binding(get: { let v = profile.sex.lowercased().replacingOccurrences(of: "-", with: ""); return ["male", "female", "nonbinary"].contains(v) ? v : "male" },
                                                                 set: { profile.sex = $0 }))
                            }.padding(.vertical, 12)
                            NunaDivider()
                            NunaStepRow(label: "Weight", value: UnitFormatter.massFromKilograms(profile.weightKg, system: unitSystem),
                                        onMinus: { profile.weightKg = max(30, profile.weightKg - 0.5) }, onPlus: { profile.weightKg = min(250, profile.weightKg + 0.5) })
                            NunaDivider()
                            NunaStepRow(label: "Height", value: UnitFormatter.heightFromCentimeters(profile.heightCm, system: unitSystem),
                                        onMinus: { profile.heightCm = max(120, profile.heightCm - 1) }, onPlus: { profile.heightCm = min(230, profile.heightCm + 1) })
                            NunaDivider()
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Units").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                NunaSegmented([(value: UnitSystem.metric.rawValue, title: "Metric"), (value: UnitSystem.imperial.rawValue, title: "Imperial")], selection: $unitSystemRaw)
                            }.padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            NunaOnboardingPrimaryButton(title: "Continue", action: next).padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 14)
        }
    }
}

// MARK: Done

private struct NunaOnboardingDone: View {
    let connected: Bool
    let finish: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: connected ? "checkmark.circle.fill" : "sparkles").font(.system(size: 54, weight: .regular))
                .foregroundStyle(connected ? NunaPalette.charge : NunaPalette.textPrimary).padding(.bottom, 10)
            nunaOnboardingTitle("You're all set")
            nunaOnboardingBody(connected
                ? "Your strap is connected. Recovery needs a few nights of wear to learn your normal."
                : "Connect your strap any time in Settings, under Device Settings. Until then you can log activities by hand.")
            Spacer(minLength: 0)
            NunaOnboardingPrimaryButton(title: "Open PHMN", action: finish).padding(.bottom, 14)
        }
        .padding(.horizontal, NunaSpacing.screenH)
    }
}
#endif
