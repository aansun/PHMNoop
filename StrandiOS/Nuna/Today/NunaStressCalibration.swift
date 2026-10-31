#if os(iOS)
import SwiftUI
import StrandDesign

/// What stands where stress would be while the reading is still learning the person. Stress compares today's heart rate and HRV with the
/// person's own baseline from their last 14 nights, so until those nights are in nothing about stress is shown: a figure from a baseline
/// that is not there yet would look exact and not be.
struct NunaStressCalibrationCard: View {
    let nights: Int
    /// Opens the Stress monitor page (which says the same at more length). Off on that page itself.
    var opensStress = true

    private var needed: Int { StressEngine.requiredNights }

    var body: some View {
        if opensStress {
            NavigationLink(value: stressRoute) { card }.buttonStyle(.plain)
        } else {
            card
        }
    }

    private var stressRoute: NunaTodayRoute {
        MetricCatalog.metric(key: "stress", source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }

    private var card: some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Stress monitor").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Spacer(minLength: 8)
                    if opensStress { Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted) }
                }
                NunaStressLockedBands()
                NunaStressCalibrationBody(nights: nights)
            }
        }
    }
}

/// The columns of a monitor card that has not unlocked yet: an icon, a label and an empty tile each, with a rule between them. The same locked
/// look for the stress bands and for the five vital signs.
struct NunaLockedColumns: View {
    let items: [(icon: String, name: LocalizedStringKey)]
    var accessibility: LocalizedStringKey = "Locked"

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, b in
                if i > 0 { Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 74) }
                VStack(spacing: 10) {
                    NunaIcon(name: b.icon, size: 25, weight: .medium).foregroundStyle(NunaPalette.textMuted).frame(height: 30)
                    Text(b.name).font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(NunaPalette.tile).frame(width: 30, height: 30)
                        .overlay(Circle().fill(NunaPalette.textMuted).frame(width: 10, height: 10))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibility))
    }
}

/// The three bands of the stress monitor, locked.
private struct NunaStressLockedBands: View {
    var body: some View {
        NunaLockedColumns(items: [("leaf", "Low"), ("waveform.path", "Medium"), ("bolt", "High")], accessibility: "Low, Medium and High stress are locked")
    }
}

/// A message over one segment a night, in the dark panel at the foot of a locked card: filled for the nights already in.
struct NunaNightsPanel: View {
    let message: LocalizedStringKey
    let nights: Int
    let needed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .fixedSize(horizontal: false, vertical: true)
            NunaNightSegments(nights: nights, needed: needed)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.shade.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// One capsule a night, purple for the nights in and grey for those to come.
struct NunaNightSegments: View {
    let nights: Int
    let needed: Int
    /// The fill of the nights already in.
    static let filled = Color(red: 0.74, green: 0.35, blue: 0.80)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<needed, id: \.self) { i in
                Capsule().fill(i < nights ? Self.filled : NunaPalette.hairline).frame(height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(min(nights, needed)) of \(needed) nights"))
    }
}

/// The message and the 14 segments of the stress monitor.
struct NunaStressCalibrationBody: View {
    let nights: Int
    private var left: Int { max(StressEngine.requiredNights - nights, 0) }

    var body: some View {
        NunaNightsPanel(message: left == 1 ? "Wear your strap to sleep for 1 more night to unlock."
                        : "Wear your strap to sleep for \(left) more nights to unlock.",
                        nights: nights, needed: StressEngine.requiredNights)
    }
}

/// The purple band across the top of a page whose figures are still calibrating (the Vital signs page): a line, and a segment a night.
struct NunaCalibrationBanner: View {
    let message: LocalizedStringKey
    let nights: Int
    let needed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(message).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .fixedSize(horizontal: false, vertical: true)
            NunaNightSegments(nights: nights, needed: needed)
        }
        .padding(.horizontal, 18).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaNightSegments.filled.opacity(0.16), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
#endif
