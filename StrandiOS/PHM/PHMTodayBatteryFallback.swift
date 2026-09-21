#if os(iOS)
import SwiftUI
import StrandDesign

/// iOS-only battery affordance for a non-WHOOP active source.
///
/// The original Liquid Today header intentionally omits the strap control when a ring is active.
/// This keeps that core decision unchanged while ensuring Today still exposes the active device's
/// battery slot consistently. A missing reading is shown as an em dash, never as the other device's
/// stale percentage.
struct PHMTodayBatteryFallback: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter

    private var batteryPct: Int? {
        LiveConsoleReadout.batteryPercent(
            activeIsWhoop: live.activeIsWhoop,
            whoopPct: live.batteryPct,
            ringPct: live.ouraBatteryPct
        )
    }

    private var batterySymbol: String {
        guard let batteryPct else { return "battery.0" }
        switch batteryPct {
        case 0..<25: return "battery.0"
        case 25..<50: return "battery.25"
        case 50..<75: return "battery.50"
        case 75..<100: return "battery.75"
        default: return "battery.100"
        }
    }

    var body: some View {
        Group {
            if !live.activeIsWhoop {
                Button { router.openDevices() } label: {
                    HStack(spacing: NoopMetrics.spaceHalf) {
                        Image(systemName: batterySymbol)
                            .font(.system(size: 14, weight: .semibold))
                        Text(batteryPct.map { "\($0)%" } ?? "—")
                            .font(StrandFont.rounded(12, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.horizontal, NoopMetrics.space2)
                    .frame(minHeight: NoopMetrics.compactControlSize)
                    .background(StrandPalette.surfaceRaised.opacity(0.92), in: Capsule())
                    .overlay(Capsule().stroke(StrandPalette.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    String(localized: "Active device battery") + ": " + (batteryPct.map { "\($0)%" } ?? "—")
                )
                .accessibilityHint(String(localized: "Opens Devices"))
            }
        }
    }
}
#endif
