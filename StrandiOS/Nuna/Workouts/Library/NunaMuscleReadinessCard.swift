#if os(iOS)
import SwiftUI
import MuscleMap
import StrandDesign
import WhoopStore

/// The body with each muscle coloured by how loaded it still is from the last days of training (see `NunaMuscleReadiness`), and
/// the most loaded ones named under it.
struct NunaMuscleReadinessCard: View {
    let readings: [LiftMuscle: Double]

    private var ordered: [(muscle: LiftMuscle, load: Double)] {
        readings.map { ($0.key, $0.value) }.sorted { $0.load > $1.load }
    }

    /// A body part can hold several of the app's muscles (the three shoulder heads); it takes the highest reading.
    private var intensities: [MuscleIntensity] {
        var byMap: [Muscle: Double] = [:]
        for (m, v) in readings { byMap[m.bodyMap] = max(byMap[m.bodyMap] ?? 0, v) }
        return byMap.map { MuscleIntensity(muscle: $0.key, intensity: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "Muscle map") { EmptyView() }
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    if readings.isEmpty {
                        Text("Once you log a session, this shows which muscles are still loaded and which are ready.")
                            .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(BodySide.allCases, id: \.self) { side in
                                BodyView(gender: .male, side: side)
                                    .heatmap(intensities, colorScale: .workout)
                                    .heatmapThreshold(0.05)
                                    .frame(maxWidth: .infinity).frame(height: 250)
                            }
                        }
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(ordered.prefix(4).enumerated()), id: \.offset) { _, r in row(r.muscle, r.load) }
                        }
                        Text("A reading of the sets you logged, fading over about two days. Not a measurement.")
                            .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    }
                }
            }
        }
    }

    private func row(_ m: LiftMuscle, _ load: Double) -> some View {
        let state = NunaMuscleReadiness.state(load)
        let (label, color): (LocalizedStringKey, Color) = switch state {
        case .ready: ("Ready", NunaPalette.charge)
        case .recovering: ("Recovering", NunaPalette.warning)
        case .fatigued: ("Fatigued", NunaPalette.alertText)
        }
        return HStack {
            Text(verbatim: m.displayName).font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Text(label).font(.nuna(size: 13, weight: .bold)).foregroundStyle(color)
            Text(verbatim: "\(Int((load * 100).rounded()))%").font(.nuna(size: 13, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary).frame(width: 42, alignment: .trailing)
        }
    }
}
#endif
