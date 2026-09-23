#if os(iOS)
import SwiftUI
import StrandDesign

/// iOS-only control surface for the experimental local audio coach.
struct AudioCoachingSettingsView: View {
    @EnvironmentObject private var audioCoaching: AudioCoachingCoordinator
    @AppStorage(AudioCoachingPreferences.enabledKey) private var enabled = false
    @AppStorage(AudioCoachingPreferences.lifecycleKey) private var lifecycle = true
    @AppStorage(AudioCoachingPreferences.heartRateKey) private var heartRate = true
    @AppStorage(AudioCoachingPreferences.distanceKey) private var distance = true
    @AppStorage(AudioCoachingPreferences.distanceIncludesDistanceKey) private var distanceIncludesDistance = true
    @AppStorage(AudioCoachingPreferences.distanceIncludesDurationKey) private var distanceIncludesDuration = true
    @AppStorage(AudioCoachingPreferences.distanceIncludesHeartRateKey) private var distanceIncludesHeartRate = true
    @AppStorage(AudioCoachingPreferences.distanceMilestoneKilometersKey) private var distanceMilestoneKilometers = 1
    @AppStorage(AudioCoachingPreferences.targetZoneKey) private var targetZone = 3
    @AppStorage(AudioCoachingPreferences.frequencyKey) private var frequencyRaw = AudioPromptFrequency.normal.rawValue
    @AppStorage(AudioCoachingPreferences.speechRateKey) private var speechRateRaw = AudioSpeechRate.normal.rawValue

    var body: some View {
        ScreenScaffold(title: "Audio coaching",
                       subtitle: "Short offline prompts while a workout is active.",
                       topBackground: liquidScaffoldSky()) {
            NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
                HStack(spacing: 10) {
                    Image(systemName: enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundStyle(enabled ? StrandPalette.accent : StrandPalette.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Activity prompts")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(enabled
                             ? "On: NOOP uses native on-device speech and ducks music briefly."
                             : "Off by default. Enable when you want spoken workout cues.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("Activity prompts", isOn: $enabled)
                        .labelsHidden()
                        .tint(StrandPalette.accent)
                }
            }

            if enabled {
                NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Announcements")
                            .strandOverline()
                        Toggle("Workout start, pause and finish", isOn: $lifecycle)
                        Toggle("Heart-rate target", isOn: $heartRate)
                        Toggle("Distance milestones", isOn: $distance)
                    }
                }

                if heartRate {
                    NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Heart-rate alerts")
                                .strandOverline()
                            Picker("Target zone", selection: $targetZone) {
                                Text("Off").tag(0)
                                ForEach(1...5, id: \.self) { zone in
                                    Text("Zone \(zone)").tag(zone)
                                }
                            }
                            .pickerStyle(.menu)
                            Picker("Alert spacing", selection: $frequencyRaw) {
                                ForEach(AudioPromptFrequency.allCases) { value in
                                    Text(value.title).tag(value.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text("Spacing controls repeated heart-rate alerts: Low 45s, Normal 20s, High 10s.")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if distance {
                    NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Distance milestone details")
                                .strandOverline()
                            Toggle("Distance", isOn: $distanceIncludesDistance)
                            Toggle("Time", isOn: $distanceIncludesDuration)
                            Toggle("Heart rate", isOn: $distanceIncludesHeartRate)
                            Divider().overlay(StrandPalette.hairline)
                            Picker("Announce every", selection: $distanceMilestoneKilometers) {
                                ForEach(1...10, id: \.self) { kilometres in
                                    Text("Every \(kilometres) km").tag(kilometres)
                                }
                            }
                            .pickerStyle(.menu)
                            Text("Audio announces every \(distanceMilestoneKilometers) km: \(distanceMilestoneKilometers), \(distanceMilestoneKilometers * 2), \(distanceMilestoneKilometers * 3) km, and so on.")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Voice")
                            .strandOverline()
                        Picker("Speech speed", selection: $speechRateRaw) {
                            ForEach(AudioSpeechRate.allCases) { value in
                                Text(value.title).tag(value.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Applies to the next announcement. Normal is recommended for clear workout cues.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Test audio")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Uses the current distance interval, selected statistics and voice speed.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        audioCoaching.testAudio()
                    } label: {
                        Label("Test current settings", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StrandPalette.accent)
                    if let decision = audioCoaching.lastDecision {
                        Text(decision)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    if let prompt = audioCoaching.lastPromptText {
                        Text("Last prompt: \(prompt)")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        }
    }
}
#endif
