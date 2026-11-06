#if os(iOS)
import SwiftUI
import PhotosUI
import StrandDesign
import StrandAnalytics

// MARK: - Shared pieces of the Me screens

/// A label with a value and a minus / plus pair, for numbers that are nudged rather than typed.
struct NunaStepRow: View {
    let label: LocalizedStringKey
    let value: String
    var note: LocalizedStringKey?
    var canDecrement = true
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                if let note { Text(note).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil) }
            }
            Spacer(minLength: 6)
            Button(action: onMinus) { glyph("minus") }.buttonStyle(.plain).disabled(!canDecrement).opacity(canDecrement ? 1 : 0.35)
            Text(verbatim: value).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit().frame(minWidth: 64)
            Button(action: onPlus) { glyph("plus") }.buttonStyle(.plain)
        }.padding(.vertical, 12)
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 34, height: 34)
    }
}

/// A group of rows in a card with a small caption above.
struct NunaSettingsGroup<Content: View>: View {
    let title: LocalizedStringKey?
    let content: Content
    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { nunaRuledHeader(title) }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) { VStack(spacing: 0) { content } }
        }
    }
}

func nunaFootnote(_ key: LocalizedStringKey) -> some View {
    Text(key).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
}

// MARK: - Goals (kept in the app's own preferences, read by Anya)

enum NunaGoals {
    static let weeklyEffort = "nuna.goal.weeklyEffort"
    static let sleepMinutes = "nuna.goal.sleepMinutes"
    static let steps = "nuna.goal.steps"
    /// Weekly minutes in heart-rate zones 1 to 3 and in zones 4 and 5; 0 is not set.
    static let zonesEasyMinutes = "nuna.goal.zones13Min"
    static let zonesHardMinutes = "nuna.goal.zones45Min"
    /// Weekly minutes of strength activity; 0 is not set.
    static let strengthMinutes = "nuna.goal.strengthMin"
    /// Weekly average sleep consistency and sleep performance, in percent; 0 is not set. Only a plan sets them.
    static let sleepConsistency = "nuna.goal.sleepConsistency"
    static let sleepPerformance = "nuna.goal.sleepPerformance"
    static let waterLitres = "nuna.goal.waterL"
    static let targetWeightKg = "nuna.goal.targetWeightKg"

    /// The daily step target: the one set under Targets in Persona, or 10,000 until one is set. Every reader (the Steps pages, the widgets) goes through here,
    /// so the line on a chart, the figure beside it and the widget's ring cannot name different targets.
    static let defaultSteps = 10_000
    static func stepTarget(_ stored: Int) -> Int { stored > 0 ? stored : defaultSteps }
    static var stepTarget: Int { stepTarget(UserDefaults.standard.integer(forKey: steps)) }

    /// Health once kept its own weight target ("nuna.weightTarget"). Carry it into the shared one when that is still empty, then drop it.
    static func migrateWeightTarget() {
        let d = UserDefaults.standard
        guard let old = d.object(forKey: "nuna.weightTarget") as? Double else { return }
        if d.double(forKey: targetWeightKg) <= 0, old > 0 { d.set(old, forKey: targetWeightKg) }
        d.removeObject(forKey: "nuna.weightTarget")
    }
}

// MARK: - Persona (Persona.dc)

struct NunaPersonaView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var model: AppModel
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(DayCycleMode.storageKey) private var dayCycleRaw = DayCycleMode.sleepOnset.rawValue
    @State private var confirmRecalibrate = false
    @State private var recalibrated = false
    @State private var photoItem: PhotosPickerItem?

    private var imperial: Bool { (UnitSystem(rawValue: unitSystemRaw) ?? .metric) == .imperial }

    var body: some View {
        NunaDetailScreen("Persona") {
            Text("Used for heart-rate zones, calorie estimates and your recovery baseline. Keep it accurate.")
                .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            NunaCard(small: true) {
                HStack(spacing: 16) {
                    ProfileAvatarView(imageData: profile.avatarImageData, size: 64)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile photo").font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        HStack(spacing: 10) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Text(profile.hasAvatar ? "Change photo" : "Choose photo").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 36).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                            }
                            if profile.hasAvatar {
                                Button { profile.clearAvatar() } label: { Image(systemName: "trash").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 36, height: 36) }.buttonStyle(.plain).accessibilityLabel(Text("Remove photo"))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            NunaSettingsGroup("About you") {
                HStack(spacing: 12) {
                    Text("Name").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    TextField("", text: $profile.displayName, prompt: Text("What should we call you?").foregroundStyle(NunaPalette.textMuted))
                        .multilineTextAlignment(.trailing).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .textInputAutocapitalization(.words).autocorrectionDisabled()
                }.padding(.vertical, 12)
                NunaDivider()
                HStack {
                    Text("Date of birth").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Text(verbatim: String(localized: "\(profile.age) years")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    DatePicker("", selection: $profile.dateOfBirth, in: ProfileStore.dateOfBirthRange, displayedComponents: .date).labelsHidden().colorScheme(.dark)
                }.padding(.vertical, 8)
                NunaDivider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sex").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    NunaSegmented([(value: "male", title: "Male"), (value: "female", title: "Female"), (value: "nonbinary", title: "Non-binary")], selection: Binding(get: { let v = profile.sex.lowercased().replacingOccurrences(of: "-", with: ""); return ["male", "female", "nonbinary"].contains(v) ? v : "male" }, set: { profile.sex = $0 }))
                }.padding(.vertical, 12)
                NunaDivider()
                NunaStepRow(label: "Waist (optional)", value: profile.waistCm > 0 ? (imperial ? String(format: "%.0f in", profile.waistCm / 2.54) : String(format: "%.0f cm", profile.waistCm)) : "–",
                            note: "Unlocks the VO₂max estimate", canDecrement: profile.waistCm > 0,
                            onMinus: { profile.waistCm = profile.waistCm <= 50 ? 0 : profile.waistCm - (imperial ? 2.54 : 1) },
                            onPlus: { profile.waistCm = profile.waistCm <= 0 ? 80 : min(200, profile.waistCm + (imperial ? 2.54 : 1)) })
            }
            NunaSettingsGroup("Day and steps") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The day starts").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    NunaSegmented([(value: DayCycleMode.sleepOnset.rawValue, title: "With main sleep"), (value: DayCycleMode.midnight.rawValue, title: "At 00:00")], selection: $dayCycleRaw)
                        .onChange(of: dayCycleRaw) { _, _ in Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() } }
                }.padding(.vertical, 12)
                NunaDivider()
                NunaStepRow(label: "Step calibration", value: String(format: "%.1f", locale: AppLanguage.activeLocale, profile.stepTicksPerStep), note: "Raise it if the step count runs too high",
                            onMinus: { profile.stepTicksPerStep = ProfileStore.steppedStepScale(profile.stepTicksPerStep, up: false) },
                            onPlus: { profile.stepTicksPerStep = ProfileStore.steppedStepScale(profile.stepTicksPerStep, up: true) })
            }
            NunaSettingsGroup("Recovery baseline") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Built from your first 4 nights. Restart it if the first week threw the baseline off.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    Button { confirmRecalibrate = true } label: {
                        Text(recalibrated ? "Restarted from tonight" : "Restart the baseline").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 48).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(recalibrated)
                }.padding(.vertical, 14)
            }
            nunaFootnote("Weight, height and waist are read from Apple Health. Heart-rate zones have their own page, under Activity Settings.")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { let data = try? await item.loadTransferable(type: Data.self); if let data { profile.setAvatar(data) }; photoItem = nil }
        }
        .confirmationDialog("Restart the baseline?", isPresented: $confirmRecalibrate, titleVisibility: .visible) {
            Button("Restart", role: .destructive) {
                Baselines.recalibrateRecoveryBaselines()
                Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
                recalibrated = true
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Recovery and your HRV baseline are learned again from tonight, which takes about 4 nights. Your history stays.") }
    }
}

// MARK: - Heart rate settings

/// Heart rate zones: the maximum heart rate, the zones as a share of it (each with its percentage range) and, once "Manual" is on, where each
/// one starts. Nothing is kept until SAVE; the cross and CANCEL leave things as they were. Zone n ends one beat below the start of zone n + 1,
/// so editing a zone's end moves the next zone's start, and the end of zone 5 is the maximum itself.
struct NunaZonesView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var maxHR = 0
    @State private var manual = false
    @State private var mins: [Int] = []
    @State private var loaded = false

    private static let pcts = ["50–60%", "60–70%", "70–80%", "80–90%", "90–100%"]
    private var resting: Int? { repo.days.last(where: { $0.restingHr != nil })?.restingHr }
    private var tanaka: Int { Int((208 - 0.7 * Double(profile.age)).rounded()) }

    /// The zone starts being shown: the typed ones when manual, otherwise the percentages of the typed maximum.
    private var starts: [Int] { manual && mins.count == 5 ? mins : percentZones.map { Int($0.lower.rounded()) } }
    /// The zones as the rest of the app draws them from the typed maximum (the same rounding as the workout screens).
    private var percentZones: [HRZone] { HRZones.zones(maxHR: Double(max(maxHR, 1))).zones }
    private var valid: Bool {
        guard HRZones.customBPMRange.contains(maxHR) else { return false }
        return !manual || (ProfileStore.validZoneThresholds(mins) && (mins.last ?? 0) <= maxHR)
    }
    private var changed: Bool {
        maxHR != profile.hrMax || manual != profile.hasCustomHRZones || (manual && mins != profile.hrZoneThresholds)
    }

    var body: some View {
        ZStack(alignment: .top) {
            NunaBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 52)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Heart Rate Zones").font(.nuna(size: 22, weight: .semibold)).textCase(nil).foregroundStyle(NunaPalette.textPrimary)
                        Text("Zones are set as a share of your maximum heart rate. Change the maximum, or turn on manual zones to choose where each one starts.")
                            .font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        labelled("Resting HR") { field(.constant(resting ?? 0), editable: false, blank: resting == nil) }
                        labelled("Max HR") { field(Binding(get: { maxHR }, set: { maxHR = $0 }), editable: true) }
                    }
                    manualToggle
                    table
                    VStack(spacing: 14) {
                        Button(action: save) {
                            Text("Save HR zones").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1)).textCase(.uppercase)
                                .foregroundStyle(changed && valid ? NunaPalette.textPrimary : NunaPalette.textMuted)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .overlay(Capsule().strokeBorder(changed && valid ? NunaPalette.textPrimary.opacity(0.8) : NunaPalette.textPrimary.opacity(0.18), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain).disabled(!(changed && valid))
                        Button { dismiss() } label: {
                            Text("Cancel").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingHead(1)).textCase(.uppercase)
                                .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity).frame(height: 40)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24).padding(.top, 8)
                    nunaFootnote("Zones are used in Workouts, live sessions and zone alerts. Changing them does not change history that is already recorded.")
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 60)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            header
        }
        .toolbar(.hidden, for: .navigationBar)
        .nunaKeyboardDone()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            maxHR = profile.hrMax; manual = profile.hasCustomHRZones
            mins = profile.hasCustomHRZones ? profile.hrZoneThresholds : HRZones.defaultLowerBounds(maxHR: Double(profile.hrMax))
        }
    }

    // MARK: Pieces

    private var header: some View {
        ZStack {
            Text("Heart rate settings").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1.2)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 52, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Close"))
                Spacer()
            }
        }
        .padding(.horizontal, 8).padding(.top, 4).frame(height: 52).frame(maxWidth: .infinity)
        .background(NunaPalette.canvas)
    }

    private func labelled<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingHead(1)).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A number with "bpm" at the right, in a dark rounded field; a field that cannot be changed is dimmer.
    private func field(_ value: Binding<Int>, editable: Bool, blank: Bool = false) -> some View {
        HStack(spacing: 6) {
            if editable {
                TextField("", text: Binding(get: { value.wrappedValue == 0 ? "" : String(value.wrappedValue) },
                                            set: { value.wrappedValue = Int($0.filter(\.isNumber).prefix(3)) ?? 0 }))
                    .keyboardType(.numberPad)
                    .font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            } else {
                Text(verbatim: blank ? "–" : String(value.wrappedValue)).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary.opacity(editable ? 1 : 0.55))
                Spacer(minLength: 0)
            }
            Text(verbatim: "bpm").font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary.opacity(editable ? 1 : 0.7)).textCase(nil)
        }
        .padding(.horizontal, 14).frame(height: 48)
        .background(Color.black.opacity(editable ? 0.32 : 0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NunaPalette.textPrimary.opacity(editable ? 0.12 : 0.06), lineWidth: 1))
    }

    private var manualToggle: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Manual Heart Rate Zones").font(.nuna(size: 17, weight: .medium)).textCase(nil).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Toggle("", isOn: Binding(get: { manual }, set: { on in
                    if on { mins = starts }
                    manual = on
                })).labelsHidden().tint(NunaPalette.effortModerate)
            }
            Text("As your fitness changes, the ranges follow your maximum heart rate. You can set them by hand if they do not feel right to you.")
                .font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var table: some View {
        let lows = starts
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Zone").frame(width: 110, alignment: .leading)
                Text("Zone min").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6)
                Text("Zone max").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6)
            }
            .font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingHead(1)).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            .padding(.leading, 6)
            ForEach((0..<5).reversed(), id: \.self) { i in
                HStack(spacing: 10) {
                    zoneLabel(i)
                    field(Binding(get: { lows.indices.contains(i) ? lows[i] : 0 }, set: { if manual, mins.indices.contains(i) { mins[i] = $0 } }), editable: manual)
                    field(Binding(get: { manual ? (i < 4 ? (lows[i + 1] - 1) : maxHR) : Int(percentZones[i].upper.rounded()) },
                                  set: { v in if i < 4 { if manual { mins[i + 1] = v + 1 } } else if manual { maxHR = v } }), editable: manual)
                }
            }
        }
    }

    /// "Zone 3" over its percentage range, on a band of the zone's colour fading to the right with a bright edge at the left.
    private func zoneLabel(_ i: Int) -> some View {
        let color = NunaWorkoutLogZones.colors[i]
        return HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: String(localized: "Zone \(i + 1)")).font(.nuna(size: 16, weight: .medium)).textCase(nil).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: Self.pcts[i]).font(.nuna(size: 11.5, weight: .semibold)).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
            }
            .padding(.leading, 12)
            Spacer(minLength: 0)
        }
        .frame(width: 104, height: 48)
        .background(LinearGradient(colors: [color.opacity(0.30), color.opacity(0.0)], startPoint: .leading, endPoint: .trailing))
    }

    // MARK: Save

    private func save() {
        guard valid else { return }
        profile.hrMaxOverride = maxHR == tanaka ? 0 : maxHR
        profile.hrZoneThresholds = manual ? mins : []
        dismiss()
    }
}
#endif
