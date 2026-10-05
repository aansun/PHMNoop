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

    /// "3.42 km" -> ("3.42", "km"); a value with no unit comes back whole.
    static func split(_ s: String?) -> (String, String) {
        guard let s, !s.isEmpty else { return ("–", "") }
        guard let i = s.lastIndex(of: " ") else { return (s, "") }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }
}

/// One slim bar of five zones. A pointer sits under the heart rate: inside its own zone's segment, as far along as the bpm is in that range.
struct NOOPZoneBar: View {
    let zone: Int?
    let position: Double?
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: gap) {
                    ForEach(1...5, id: \.self) { n in
                        Capsule().fill(NOOPLive.zoneColor(n).opacity(zone == nil || zone == n ? 1 : 0.45)).frame(height: height)
                    }
                }
                if let position {
                    Triangle().fill(NunaPalette.textPrimary).frame(width: 9, height: 7)
                        .offset(x: min(max(CGFloat(position) * w - 5, 0), w - 10), y: height + 2)
                }
            }
        }
        .frame(height: height + 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(zone.map { Text("Zone \($0)") } ?? Text("No data"))
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath(); return p
    }
}

/// A label over its value with the unit small beside it. The Lock Screen and the expanded Island set three of these left, centre and right.
struct NOOPLiveMetric<Value: View>: View {
    let label: LocalizedStringKey
    var text: Value
    var unit: String = ""
    var size: CGFloat = 22
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label).font(.nuna(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(NunaPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                text.font(.nuna(size: size, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: size * 0.42, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
    }
}

/// A sport's symbol inside a small progress ring in the zone's colour.
struct NOOPLiveRing: View {
    let symbol: String
    var tint: Color = NunaPalette.charge
    var progress: Double?
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 2.6)
            if let progress { Circle().trim(from: 0, to: max(CGFloat(progress), 0.02)).stroke(tint, style: StrokeStyle(lineWidth: 2.6, lineCap: .round)).rotationEffect(.degrees(-90)) }
            Image(systemName: symbol).font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
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

/// A small pill in the Nuna chip style, with an optional leading symbol.
struct NOOPLiveChip: View {
    let text: Text
    var color: Color = NunaPalette.textSecondary
    var systemImage: String?
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            text.font(.nuna(size: 12, weight: .heavy))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).frame(height: 24)
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
