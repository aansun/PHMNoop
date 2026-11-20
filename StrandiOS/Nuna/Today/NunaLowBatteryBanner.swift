#if os(iOS)
import SwiftUI
import StrandDesign

/// The strap is nearly flat: a black card under the day row, as the sync banner is, with the charge left, what to do, and a cross to put it
/// away. It comes back at the next level down (20%, then 10%) and is forgotten once the strap is charging or above 25%.
struct NunaLowBatteryBanner: View {
    let pct: Int
    let onDismiss: () -> Void
    static let height: CGFloat = 76

    /// The level a reading belongs to: 10 for 10% or less, 20 for 20% or less, nil when there is nothing to warn about. A strap that is
    /// charging, or has no reading yet, never warns.
    static func level(pct: Double?, charging: Bool?) -> Int? {
        guard charging != true, let pct else { return nil }
        let p = Int(pct.rounded())
        return p <= 10 ? 10 : (p <= 20 ? 20 : nil)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "battery.0percent").font(.system(size: 15.5, weight: .light)).foregroundStyle(Color.white.opacity(0.85))
                .overlay(alignment: .topLeading) { Circle().fill(NunaPalette.alert).frame(width: 8, height: 8).offset(x: -3, y: -3) }
                .frame(width: 21)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "\(pct)% \(String(localized: "charge remaining"))").font(.nunaWords(size: 11.3, semibold: true)).tracking(1.13).textCase(.uppercase)
                    .foregroundStyle(Color.white).lineLimit(1).minimumScaleFactor(0.7)
                Text("Charge your WHOOP to ensure uninterrupted data collection").font(.nunaWords(size: 12.5)).tracking(0).foregroundStyle(Color.white.opacity(0.78))
                    .textCase(nil).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.white).frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(Text("Dismiss"))
        }
        .padding(.leading, 14).padding(.trailing, 4).frame(height: Self.height)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Mirrors the strap's low charge into the screen, writing only when the figure changes. Today itself does not observe the live state, which
/// ticks with every heartbeat.
struct NunaLowBatteryWatcher: View {
    @Binding var pct: Int?
    /// The strap is charging or well above the warning range again (over 25%), so a banner put away may come back next time it runs low. A reading that
    /// is only missing for a moment, or that wobbles around a level, is not a recovery.
    let onRecovered: () -> Void
    @EnvironmentObject private var live: LiveState
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { update() }
            .onChange(of: live.batteryPct) { _, _ in update() }
            .onChange(of: live.charging) { _, _ in update() }
    }
    private func update() {
        if live.isCharging || (live.batteryPct ?? 0) > 25 { onRecovered() }
        let low = NunaLowBatteryBanner.level(pct: live.batteryPct, charging: live.isCharging ? true : live.charging) != nil ? live.batteryPct.map { Int($0.rounded()) } : nil
        if low != pct { pct = low }
    }
}
#endif
