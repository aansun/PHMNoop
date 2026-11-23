#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Auto-detect settings (WorkoutAutoDetect / WorkoutAutoDetectOff): the switch, the fixed rules it applies and the current
/// suggestion. It only ever suggests; saving or dismissing is always the wearer's choice.
struct NunaAutoDetectView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var on = PuffinExperiment.autoDetectWorkoutsDefault
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
                    NunaListRow("Heart-rate threshold", description: "Above your resting heart rate", systemImage: NunaIcons.heartRate) { value("+\(AutoWorkoutDetector.elevatedMarginBPM) bpm") }
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
                        NunaListRow(nunaSportKey(s.sport + " · " + String(localized: "\(s.durationMin) min")),
                                    subtitle: LocalizedStringKey(NunaWorkoutFormat.day(s.startSec) + " " + NunaWorkoutFormat.clock(s.startSec) + " · " + String(localized: "average \(s.avgBpm) bpm")), systemImage: "figure.run") { NunaChip("Waiting") }
                    } else {
                        NunaListRow("Nothing waiting", subtitle: "No unlogged workout was found in the last two days", systemImage: "checkmark")
                    }
                }
            }
            detectionCheck
        }
        .task(id: "\(on)|\(repo.refreshSeq)") { suggestion = on ? await repo.autoDetectSuggestion() : nil }
    }

    // MARK: Detection check (diagnostic)

    @State private var check: Repository.WorkoutReplayResult?
    @State private var checking = false

    /// A read-only diagnostic: how often the shape classifier would have named the workouts you saved yourself. It is English only on purpose, like
    /// the Test Centre, and it changes nothing about what is detected.
    @ViewBuilder private var detectionCheck: some View {
        Text(verbatim: "Detection check").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
            .foregroundStyle(NunaPalette.textMuted).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "Runs the sport naming over the workouts you saved and shows how often it was right. Read only: nothing here changes what is detected.")
                    .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                Button {
                    guard !checking else { return }
                    checking = true
                    Task { check = await repo.workoutClassReplay(); checking = false }
                } label: {
                    Text(verbatim: checking ? "Checking..." : "Check against my workouts").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(checking)
                if let c = check {
                    ForEach(Array(Self.checkLines(c).enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The result as plain lines: where the workouts went (used, or left out and why), then the classifier's numbers, with and without motion apart.
    static func checkLines(_ c: Repository.WorkoutReplayResult) -> [String] {
        func n(_ o: WorkoutLabelOrigin) -> Int { c.notTheirLabel[o] ?? 0 }
        var lines = ["Saved workouts: \(c.savedWorkouts)",
                     "Used (your own label, with strap data): \(c.windows.count), of which from Strava: \(c.stravaUsed)"]
        lines.append("Left out: saved from a suggestion \(n(.savedFromSuggestion)), named by the strap \(n(.strapOwn)), old detected \(n(.legacyDetected)), "
                     + "name too vague \(c.unusableName), no strap data \(c.noStrapData)")
        if c.beforeLogUsed > 0 {
            lines.append("\(c.beforeLogUsed) used workouts were saved before this log began; a few may have been saved suggestions.")
        }
        lines.append("")
        lines.append("With motion data (\(c.fullWindows.count) windows)")
        lines += WorkoutClassReplay.summaryLines(c.fullReport)
        lines.append("")
        lines.append("Heart rate only, no motion from the strap (\(c.heartRateOnlyWindows.count) windows)")
        lines += WorkoutClassReplay.summaryLines(c.heartRateOnlyReport)
        if !c.heartRateOnlyWindows.isEmpty {
            lines.append("Heart-rate-only windows are a weaker kind of evidence. Do not learn from them as if they carried gait.")
        }
        return lines
    }

    private func value(_ t: String) -> some View {
        Text(verbatim: t).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
    }
}
#endif
