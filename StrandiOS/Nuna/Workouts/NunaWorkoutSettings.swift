#if os(iOS)
import SwiftUI
import StrandDesign

/// The shortcut from the top right of Workouts: the two switches that decide what happens around a workout. Auto-detect and the
/// Strava upload are the same settings as in Me, so changing them here changes them there.
struct NunaWorkoutSettingsView: View {
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetect = false
    @AppStorage(StravaExperiment.enabledKey) private var strava = false
    @AppStorage(AudioCoachingPreferences.enabledKey) private var audioCoach = false

    var body: some View {
        NunaDetailScreen("Workout settings") {
            NunaSettingsGroup("Detection") {
                NunaToggleRow("Auto-detect workouts", subtitle: "Only suggests, never saves on its own", systemImage: "sparkles", isOn: $autoDetect).padding(.vertical, 8)
                NunaDivider()
                NavigationLink(value: NunaWorkoutRoute.autoDetect) {
                    NunaListRow("How detection works", subtitle: "Rules, thresholds and the latest suggestion", systemImage: "info.circle", showsChevron: true)
                }.buttonStyle(.plain)
            }
            NunaSettingsGroup("Audio") {
                NavigationLink(value: NunaAnyaRoute.voiceCoach) {
                    NunaListRow("Audio coach", subtitle: "Spoken cues in workouts and gym sessions: heart-rate zones, distance, rest", systemImage: "speaker.wave.2", showsChevron: true) {
                        NunaChip(audioCoach ? "On" : "Off", color: audioCoach ? NunaPalette.charge : nil)
                    }
                }.buttonStyle(.plain)
            }
            NunaSettingsGroup("Share") {
                NavigationLink(value: NunaMeRoute.strava) {
                    NunaListRow("Strava", subtitle: "Upload GPS and treadmill workouts. Off by default", systemImage: "figure.run.circle", showsChevron: true) {
                        NunaChip(strava ? "On" : "Off", color: strava ? NunaPalette.charge : nil)
                    }
                }.buttonStyle(.plain)
            }
            nunaFootnote("These are the same settings as in Me. Detection only suggests a workout; you decide whether to save it.")
        }
        .nunaAnyaDestinations()
    }
}
#endif
