#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Auto-detect settings (WorkoutAutoDetect / WorkoutAutoDetectOff): the switch, the fixed rules it applies and the current
/// suggestion. It only ever suggests; saving or dismissing is always the wearer's choice.
struct NunaAutoDetectView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var on = false
    @State private var suggestion: AutoWorkoutSuggestion?

    var body: some View {
        NunaDetailScreen("Auto-detect") {
            HStack { Spacer(); NunaChip(on ? "On" : "Off", systemImage: on ? "checkmark" : nil, color: on ? NunaPalette.charge : nil) }
            NunaCard {
                NunaListRow("Detect workouts automatically", subtitle: on ? "Looking for workouts you have not logged" : "Nothing is scanned", systemImage: "sparkles") {
                    Toggle("", isOn: $on).labelsHidden().tint(NunaPalette.charge)
                }
            }
            NunaCard(small: true) {
                NunaListRow("Never saves on its own", description: "Detection only suggests, through one card in Workouts. You decide: Save or Not a workout.", systemImage: "checkmark")
            }
            if !on {
                NunaCard(highlight: true) {
                    NunaListRow("Missed workouts are not recorded", subtitle: "Turn it on so sessions without Start can still be saved", systemImage: "bell")
                }
            }
            NunaTitleRow(title: "How it works") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    NunaListRow("Minimum length", description: "Heart rate must stay up", systemImage: "timer") { value("\(Int(AutoWorkoutDetector.minSustainedMin)) min") }
                    NunaDivider()
                    NunaListRow("Heart-rate threshold", description: "Above your resting heart rate", systemImage: "heart") { value("+\(AutoWorkoutDetector.elevatedMarginBPM) bpm") }
                    NunaDivider()
                    NunaListRow("Tolerated dip", description: "A short drop does not end the session", systemImage: "bolt") { value("\(AutoWorkoutDetector.maxDipS) s") }
                    NunaDivider()
                    NunaListRow("Motion", description: "Used as confirmation when it exists", systemImage: "figure.walk") { value(String(localized: "Automatic")) }
                }
            }
            Text("The rules are deliberately conservative so stress, caffeine or climbing stairs are not counted as workouts. Short or light sessions can be missed.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            if on {
                NunaTitleRow(title: "Latest suggestion") { EmptyView() }
                NunaCard(small: true) {
                    if let s = suggestion {
                        NunaListRow(LocalizedStringKey(s.sport + " · " + String(localized: "\(s.durationMin) min")),
                                    subtitle: LocalizedStringKey(NunaWorkoutFormat.day(s.startSec) + " " + NunaWorkoutFormat.clock(s.startSec) + " · " + String(localized: "average \(s.avgBpm) bpm")), systemImage: "figure.run") { NunaChip("Waiting") }
                    } else {
                        NunaListRow("Nothing waiting", subtitle: "No unlogged workout was found in the last two days", systemImage: "checkmark")
                    }
                }
            }
        }
        .task(id: "\(on)|\(repo.refreshSeq)") { suggestion = on ? await repo.autoDetectSuggestion() : nil }
    }

    private func value(_ t: String) -> some View {
        Text(verbatim: t).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
    }
}
#endif
