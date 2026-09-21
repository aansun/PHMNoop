import SwiftUI
import StrandDesign

/// Shared Lock Screen components used by the live-HR and Lift activities.
struct NOOPHeartRateZoneRail: View {
    let zone: Int?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { index in
                    ZStack {
                        Capsule()
                            .fill(StrandPalette.hrZoneColor(index).opacity(zone == index ? 1 : 0.42))
                            .frame(height: 4)
                        if zone == index {
                            Circle()
                                .fill(StrandPalette.textPrimary)
                                .frame(width: 9, height: 9)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { index in
                    Text("Zone \(index)")
                        .font(.caption2)
                        .foregroundStyle(zone == index
                                         ? StrandPalette.hrZoneColor(index)
                                         : StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct NOOPLiveMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.caption2)
                .tracking(0.8)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }
}
