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
        Image(systemName: name).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 34, height: 34).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
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
    static let waterLitres = "nuna.goal.waterL"
    static let targetWeightKg = "nuna.goal.targetWeightKg"

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
                                Button { profile.clearAvatar() } label: { Image(systemName: "trash").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 36, height: 36).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous)) }.buttonStyle(.plain).accessibilityLabel(Text("Remove photo"))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            NunaSettingsGroup("About you") {
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
                if imperial {
                    NunaStepRow(label: "Weight", value: String(format: "%.1f lb", locale: AppLanguage.activeLocale, profile.weightKg * 2.20462),
                                onMinus: { profile.weightKg = max(30, profile.weightKg - 0.45359) }, onPlus: { profile.weightKg = min(250, profile.weightKg + 0.45359) })
                    NunaDivider()
                    NunaStepRow(label: "Height", value: Self.feetInches(profile.heightCm),
                                onMinus: { profile.heightCm = max(120, profile.heightCm - 2.54) }, onPlus: { profile.heightCm = min(230, profile.heightCm + 2.54) })
                } else {
                    NunaStepRow(label: "Weight", value: String(format: "%.1f kg", locale: AppLanguage.activeLocale, profile.weightKg),
                                onMinus: { profile.weightKg = max(30, profile.weightKg - 0.5) }, onPlus: { profile.weightKg = min(250, profile.weightKg + 0.5) })
                    NunaDivider()
                    NunaStepRow(label: "Height", value: String(format: "%.0f cm", profile.heightCm),
                                onMinus: { profile.heightCm = max(120, profile.heightCm - 1) }, onPlus: { profile.heightCm = min(230, profile.heightCm + 1) })
                }
                NunaDivider()
                NunaStepRow(label: "Waist (optional)", value: profile.waistCm > 0 ? (imperial ? String(format: "%.0f in", profile.waistCm / 2.54) : String(format: "%.0f cm", profile.waistCm)) : "–",
                            note: "Unlocks the VO₂max estimate", canDecrement: profile.waistCm > 0,
                            onMinus: { profile.waistCm = profile.waistCm <= 50 ? 0 : profile.waistCm - (imperial ? 2.54 : 1) },
                            onPlus: { profile.waistCm = profile.waistCm <= 0 ? 80 : min(200, profile.waistCm + (imperial ? 2.54 : 1)) })
            }
            NunaSettingsGroup("Heart rate") {
                NunaStepRow(label: "Maximum heart rate", value: "\(profile.hrMax) bpm",
                            note: LocalizedStringKey(profile.hrMaxOverride > 0 ? String(localized: "Set by you") : String(localized: "Automatic from your age")),
                            onMinus: { profile.hrMaxOverride = max(100, profile.hrMax - 1) }, onPlus: { profile.hrMaxOverride = min(230, profile.hrMax + 1) })
                if profile.hrMaxOverride > 0 {
                    NunaDivider()
                    Button { profile.hrMaxOverride = 0 } label: { NunaListRow("Back to automatic", subtitle: "Use the estimate from your age", systemImage: "arrow.uturn.backward", showsChevron: true) }.buttonStyle(.plain)
                }
                NunaDivider()
                NavigationLink(value: NunaMeRoute.zones) { NunaListRow("Heart-rate zones", subtitle: LocalizedStringKey(profile.hasCustomHRZones ? String(localized: "Your own limits") : String(localized: "5 zones, percentages of your maximum")), systemImage: "heart.text.square", showsChevron: true) }.buttonStyle(.plain)
            }
            NunaSettingsGroup("Targets") {
                NavigationLink(value: NunaMeRoute.goals) { NunaListRow("Targets", subtitle: "Weekly and daily goals", systemImage: "target", showsChevron: true) }.buttonStyle(.plain)
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
            nunaFootnote("Fitness age only needs resting heart rate and activity. Weight, height and waist only unlock the VO₂max estimate.")
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
        } message: { Text("Charge and your HRV baseline are learned again from tonight, which takes about 4 nights. Your history stays.") }
    }

    private static func feetInches(_ cm: Double) -> String {
        let total = Int((cm / 2.54).rounded()); return "\(total / 12)′ \(total % 12)″"
    }
}

// MARK: - Zones (PersonaZones.dc)

struct NunaZonesView: View {
    @EnvironmentObject private var profile: ProfileStore
    private let names: [LocalizedStringKey] = ["Zone 1 · Recovery", "Zone 2 · Easy, fat burning", "Zone 3 · Aerobic", "Zone 4 · Threshold", "Zone 5 · Maximum"]
    private let pcts = ["50 – 60%", "60 – 70%", "70 – 80%", "80 – 90%", "90 – 100%"]

    var body: some View {
        NunaDetailScreen("Heart-rate zones") {
            NunaCard(small: true) {
                HStack { Text("Maximum heart rate").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary); Spacer()
                    Text(verbatim: "\(profile.hrMax) bpm").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary) }
            }
            NunaCard(small: true) {
                NunaToggleRow("Your own zones", subtitle: "Set where each zone starts. Turn off to return to percentages", systemImage: "slider.horizontal.3",
                              isOn: Binding(get: { profile.hasCustomHRZones }, set: { profile.setCustomHRZonesEnabled($0) })).padding(.vertical, 8)
            }
            NunaSettingsGroup("Zone starts at") {
                ForEach(0..<5, id: \.self) { i in
                    if i > 0 { NunaDivider() }
                    let bpm = Int(profile.hrZoneSet.zones.first { $0.number == i + 1 }?.lower.rounded() ?? 0)
                    if profile.hasCustomHRZones, profile.hrZoneThresholds.indices.contains(i) {
                        NunaStepRow(label: names[i], value: "\(profile.hrZoneThresholds[i]) bpm", note: LocalizedStringKey(pcts[i] + " " + String(localized: "of maximum")),
                                    onMinus: { profile.stepHRZoneThreshold(at: i, up: false) }, onPlus: { profile.stepHRZoneThreshold(at: i, up: true) })
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(names[i]).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: pcts[i] + " " + String(localized: "of maximum")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            }
                            Spacer()
                            Text(verbatim: "\(bpm) bpm").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        }.padding(.vertical, 14)
                    }
                }
            }
            if profile.hasCustomHRZones {
                Button { profile.setCustomHRZonesEnabled(false) } label: {
                    Text("Restore defaults").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
            nunaFootnote("Zones are used in Workouts, live sessions and zone alerts. Changing them does not change history that is already recorded.")
        }
    }
}

// MARK: - Goals (PersonaGoals.dc)

struct NunaGoalsView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(NunaGoals.weeklyEffort) private var effort = 0.0
    @AppStorage(NunaGoals.sleepMinutes) private var sleep = 0
    @AppStorage(NunaGoals.steps) private var steps = 0
    @AppStorage(NunaGoals.waterLitres) private var water = 0.0
    @AppStorage(NunaGoals.targetWeightKg) private var targetWeight = 0.0
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var weekAvg: Double? {
        let v = repo.days.suffix(7).compactMap(\.strain); return v.isEmpty ? nil : v.reduce(0, +)
    }
    private var avgSteps: Int? {
        let v = repo.days.suffix(7).compactMap { $0.steps }; return v.isEmpty ? nil : v.reduce(0, +) / v.count
    }

    var body: some View {
        NunaDetailScreen("Targets") {
            if let w = weekAvg, effort == 0 {
                NunaCard(highlight: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        nunaTrendsCap("Suggested from your numbers")
                        Text(verbatim: String(localized: "Your Effort over the last 7 days was \(UnitFormatter.effortDisplay(w, scale: scale)). A weekly target of \(UnitFormatter.effortDisplay(w * 1.1, scale: scale)) to \(UnitFormatter.effortDisplay(w * 1.2, scale: scale)) is a realistic step up."))
                            .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                        Button { effort = (w * 1.15).rounded() } label: {
                            Text("Use it").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 20).frame(height: 40).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            NunaSettingsGroup("Training and recovery") {
                NunaStepRow(label: "Weekly Effort", value: effort > 0 ? UnitFormatter.effortDisplay(effort, scale: scale) : "–", note: LocalizedStringKey(weekAvg.map { String(localized: "Last 7 days: \(UnitFormatter.effortDisplay($0, scale: scale))") } ?? ""), canDecrement: effort > 0,
                            onMinus: { effort = max(0, effort - 5) }, onPlus: { effort = effort + 5 })
                NunaDivider()
                NunaStepRow(label: "Sleep", value: sleep > 0 ? "\(sleep / 60)h \(String(format: "%02d", sleep % 60))m" : "–", note: "Same as your sleep need", canDecrement: sleep > 0,
                            onMinus: { sleep = max(0, sleep - 15) }, onPlus: { sleep = sleep == 0 ? 480 : min(720, sleep + 15) })
            }
            NunaSettingsGroup("Body and nutrition") {
                NunaStepRow(label: "Steps per day", value: steps > 0 ? NunaTrendsFormat.num(Double(steps)) : "–", note: LocalizedStringKey(avgSteps.map { String(localized: "Average \(NunaTrendsFormat.num(Double($0)))") } ?? ""), canDecrement: steps > 0,
                            onMinus: { steps = max(0, steps - 500) }, onPlus: { steps = steps == 0 ? 8000 : steps + 500 })
                NunaDivider()
                NunaStepRow(label: "Water per day", value: water > 0 ? String(format: "%.1f L", locale: AppLanguage.activeLocale, water) : "–", note: "Water tracking adjusts it with Effort", canDecrement: water > 0,
                            onMinus: { water = max(0, water - 0.25) }, onPlus: { water = water == 0 ? 2.0 : water + 0.25 })
                NunaDivider()
                NunaStepRow(label: "Target weight", value: targetWeight > 0 ? String(format: "%.1f kg", locale: AppLanguage.activeLocale, targetWeight) : "–",
                            note: LocalizedStringKey(targetWeight > 0 ? String(format: String(localized: "%.1f kg to go"), abs(profile.weightKg - targetWeight)) : ""), canDecrement: targetWeight > 0,
                            onMinus: { targetWeight = max(0, targetWeight - 0.5) }, onPlus: { targetWeight = targetWeight == 0 ? profile.weightKg : targetWeight + 0.5 })
            }
            if effort > 0 || sleep > 0 || steps > 0 || water > 0 || targetWeight > 0 {
                Button { effort = 0; sleep = 0; steps = 0; water = 0; targetWeight = 0 } label: {
                    Text("Clear all targets").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
            nunaFootnote("Your targets stay on this iPhone. Anya reads them when you ask for advice, once you allow it to use your numbers.")
        }
    }
}
#endif
