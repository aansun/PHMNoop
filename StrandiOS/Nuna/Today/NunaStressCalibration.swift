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
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Stress monitor").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Spacer(minLength: 8)
                    if opensStress { Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted) }
                }
                NunaStressCalibrationBody(nights: nights, boxed: false)
            }
        }
    }
}

/// The message and the 14 segments, shared by the card and the page.
struct NunaStressCalibrationBody: View {
    let nights: Int
    /// A panel of its own (on the page); off inside the card, which is the panel.
    var boxed = true

    private var needed: Int { StressEngine.requiredNights }
    private var left: Int { max(needed - nights, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass").font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.effortModerate)
                Text("Calibrating").font(.nuna(size: 15, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            }
            Text(left == 1 ? "Wear your strap to sleep for 1 more night to unlock stress."
                 : "Wear your strap to sleep for \(left) more nights to unlock stress.")
                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                ForEach(0..<needed, id: \.self) { i in
                    Capsule().fill(i < nights ? NunaPalette.effortModerate : NunaPalette.hairline).frame(height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(min(nights, needed)) of \(needed) nights"))
            Text("Stress is read against your own baseline from your last 14 nights, so it stays hidden until they are in. That keeps every figure accurate.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
        }
        .padding(boxed ? 14 : 0).frame(maxWidth: .infinity, alignment: .leading)
        .background(boxed ? NunaPalette.glassStrong : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
#endif
