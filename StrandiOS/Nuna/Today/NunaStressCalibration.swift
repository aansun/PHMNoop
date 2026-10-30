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
                NunaStressCalibrationBody(nights: nights, explains: false)
            }
        }
    }
}

/// The three bands where the figures will be, each an empty tile: the same locked look the other monitors take before their first night.
private struct NunaStressLockedBands: View {
    private let bands: [(icon: String, name: String)] = [("leaf", "Low"), ("waveform.path", "Medium"), ("bolt", "High")]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(bands.enumerated()), id: \.offset) { i, b in
                if i > 0 { Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 74) }
                VStack(spacing: 10) {
                    Image(systemName: b.icon).font(.nuna(size: 22, weight: .regular)).foregroundStyle(NunaPalette.textMuted).frame(height: 26)
                    Text(b.name).font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(NunaPalette.tile).frame(width: 30, height: 30)
                        .overlay(Circle().fill(NunaPalette.textMuted).frame(width: 10, height: 10))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Low, Medium and High stress are locked"))
    }
}

/// The message and the 14 segments, shared by the card and the page.
struct NunaStressCalibrationBody: View {
    let nights: Int
    /// The line saying why stress waits for the nights; the card leaves it to its page.
    var explains = true

    /// The fill of the nights already in.
    private static let filled = Color(red: 0.74, green: 0.35, blue: 0.80)
    private var needed: Int { StressEngine.requiredNights }
    private var left: Int { max(needed - nights, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(left == 1 ? "Wear your strap to sleep for 1 more night to unlock."
                 : "Wear your strap to sleep for \(left) more nights to unlock.")
                .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                ForEach(0..<needed, id: \.self) { i in
                    Capsule().fill(i < nights ? Self.filled : NunaPalette.hairline).frame(height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(min(nights, needed)) of \(needed) nights"))
            if explains {
                Text("Stress is read against your own baseline from your last 14 nights, so it stays hidden until they are in. That keeps every figure accurate.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.shade.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
#endif
