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
                        Text("Prompt types")
                            .strandOverline()
                        Toggle("Workout start, pause and finish", isOn: $lifecycle)
                        Toggle("Heart-rate target", isOn: $heartRate)
                        Toggle("Distance milestones", isOn: $distance)
                        Divider().overlay(StrandPalette.hairline)
                        Picker("Target zone", selection: $targetZone) {
                            Text("Off").tag(0)
                            ForEach(1...5, id: \.self) { zone in
                                Text("Zone \(zone)").tag(zone)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("Heart-rate alerts use the selected personalized zone and require a sustained violation; a short spike stays silent.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Picker("Frequency", selection: $frequencyRaw) {
                            ForEach(AudioPromptFrequency.allCases) { value in
                                Text(value.title).tag(value.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
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
                            Text("With Every 5 km selected, audio is announced at 5 km, 10 km, 15 km, and so on.")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Test audio")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Plays a sample distance milestone with distance, heart-rate zone and duration so you can verify the speech route.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        audioCoaching.testAudio()
                    } label: {
                        Label("Play sample", systemImage: "play.circle.fill")
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

            NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Local-first")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("The V1 coach uses deterministic rules, native iOS speech and the existing WHOOP/GPS live feed. It does not call AI, cloud TTS or a NOOP server.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
#endif
