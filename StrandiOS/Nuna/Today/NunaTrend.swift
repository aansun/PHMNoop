#if os(iOS)
import SwiftUI
import StrandDesign

/// How a figure compares with the one before it, for Your cards and Key Metrics. Every figure carries one: a triangle when it moved (coloured
/// when the direction is known to be good or bad), a small dot when it did not move or there is nothing earlier to compare with, and the
/// earlier figure underneath either way ("–" when there is none).
///
/// Moved or not is decided on the figures as shown (rounded to the decimals on screen), so a row never claims a change its two numbers do
/// not display.
struct NunaTrend: Equatable {
    /// 1 up, -1 down, 0 the same or nothing earlier.
    var direction: Int
    /// The earlier figure, formatted the way the current one is; "–" when there is none.
    var previous: String
    var hasPrevious: Bool
    /// How far it moved, in the figure's own decimals, for the chip layout.
    var magnitude: String
    /// Whether going up is good: nil leaves the triangle neutral.
    var upIsGood: Bool?

    static func make(current: Double?, previous: Double?, decimals: Int = 0, upIsGood: Bool? = nil,
                     format: ((Double) -> String)? = nil) -> NunaTrend? {
        guard let current else { return nil }
        func plain(_ v: Double) -> String { String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, v) }
        guard let previous else { return NunaTrend(direction: 0, previous: "–", hasPrevious: false, magnitude: "–", upIsGood: upIsGood) }
        // Both sides are rounded the way the screen rounds them (printf style), so "36" over "36" can never carry a triangle.
        func shown(_ v: Double) -> Double { Double(String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), v)) ?? v }
        let now = shown(current), before = shown(previous)
        return NunaTrend(direction: now > before ? 1 : (now < before ? -1 : 0), previous: (format ?? plain)(previous), hasPrevious: true,
                         magnitude: plain(abs(now - before)), upIsGood: upIsGood)
    }

    var tint: Color {
        guard direction != 0, let upIsGood else { return NunaPalette.textSecondary }
        return (direction > 0) == upIsGood ? NunaPalette.charge : NunaPalette.warning
    }

    /// "▲ 4", "▼ 4", or "● 0" (a dot and "–" when there is nothing earlier), for the chip of the card layout.
    var chipText: String {
        if direction > 0 { return "▲ " + magnitude }
        if direction < 0 { return "▼ " + magnitude }
        return "● " + magnitude
    }
}

/// A figure with its comparison: the number, the triangle or dot beside it, the earlier number under it. The marker's slot is always there, so
/// the figures of every row end on the same line.
struct NunaTrendFigure: View {
    let value: String
    let trend: NunaTrend?
    var size: CGFloat = 17
    var minimumScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .center, spacing: 5) {
                Text(verbatim: value).font(.nuna(size: size, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(minimumScale)
                marker.frame(width: 10, height: 10)
            }
            if let trend {
                Text(verbatim: trend.previous).font(.nuna(size: 12, weight: .semibold, design: NunaType.design))
                    .foregroundStyle(NunaPalette.textSecondary).monospacedDigit().padding(.trailing, 15)
            }
        }
    }

    @ViewBuilder private var marker: some View {
        if let trend {
            if trend.direction == 0 {
                Circle().fill(NunaPalette.textSecondary).frame(width: 4.5, height: 4.5)
            } else {
                Image(systemName: trend.direction > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(trend.tint)
            }
        } else {
            Color.clear
        }
    }
}
#endif
