import SwiftUI
import StrandDesign

// Shared pieces of the Live Activities (workout, gym, sync), drawn with the Nuna tokens so the Lock Screen and the Dynamic Island
// look like the app. Every word the extension draws is in its own string table (`Resources/id.lproj`) or arrives already translated.

enum NOOPLive {
    /// The colour of each heart-rate zone, light to hard (the same five the workout start screen uses).
    static func zoneColor(_ zone: Int) -> Color {
        [NunaPalette.zoneBase, NunaPalette.charge, NunaPalette.effort, NunaPalette.warning, NunaPalette.alert][min(max(zone, 1), 5) - 1]
    }
    /// The colour a session reads in: its zone's colour, or the Charge green before a heart rate arrives.
    static func tint(zone: Int?) -> Color { zone.map(zoneColor) ?? NunaPalette.charge }
}

/// One slim bar of five zones with a pointer under the current one and "Zone N" in its colour.
struct NOOPHeartRateZoneRail: View {
    let zone: Int?
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 3 : 4) {
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { n in
                    Capsule()
                        .fill(NOOPLive.zoneColor(n).opacity(zone == n ? 1 : 0.4))
                        .frame(height: compact ? 6 : 8)
                }
            }
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { n in
                    Group {
                        if zone == n {
                            VStack(spacing: 2) {
                                Triangle().fill(NunaPalette.textPrimary).frame(width: 8, height: 5)
                                if !compact { Text("Zone \(n)").font(.nuna(size: 11, weight: .heavy)).foregroundStyle(NOOPLive.zoneColor(n)) }
                            }
                        } else { Color.clear.frame(height: compact || zone == nil ? 5 : 18) }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(zone.map { Text("Zone \($0)") } ?? Text("No data"))
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath(); return p
    }
}

/// A label over its value, centred so the value sits under its own label.
struct NOOPLiveMetric: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(0.5).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value).font(.nuna(size: 19, weight: .bold, design: NunaType.design)).monospacedDigit()
                .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

struct NOOPLiveDivider: View {
    var body: some View { Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 30) }
}

/// A rounded tile with a symbol, in the zone's colour.
struct NOOPLiveGlyph: View {
    let symbol: String
    var tint: Color = NunaPalette.charge
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: symbol).font(.nuna(size: size * 0.45, weight: .bold)).foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// A small pill in the Nuna chip style.
struct NOOPLiveChip: View {
    let text: Text
    var color: Color = NunaPalette.textSecondary
    var body: some View {
        text.font(.nuna(size: 11.5, weight: .heavy)).foregroundStyle(color)
            .padding(.horizontal, 9).frame(height: 24)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The strap battery as a small ring.
struct NOOPBatteryRing: View {
    let percent: Int?
    var size: CGFloat = 34

    private var progress: CGFloat { percent.map { CGFloat(min(max($0, 0), 100)) / 100 } ?? 0 }

    var body: some View {
        ZStack {
            Circle().stroke(NunaPalette.hairline, lineWidth: 3)
            Circle().trim(from: 0, to: progress).stroke(NunaPalette.charge.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(percent.map { "\($0)" } ?? "–").font(.nuna(size: size * 0.32, weight: .bold)).monospacedDigit().foregroundStyle(NunaPalette.textSecondary)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(percent.map { Text("Battery \($0) percent") } ?? Text("Battery unavailable"))
    }
}
