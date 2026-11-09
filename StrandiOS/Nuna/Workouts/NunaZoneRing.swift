#if os(iOS)
import SwiftUI
import StrandDesign

/// The heart rate of a running activity as a ring round a disc. The ring is the five heart-rate zones, each an arc in its own colour, filled as far as
/// the heart rate has climbed through them, with a white mark at the heart rate itself. The disc inside is the colour of the zone the heart is in, with
/// the number on it, and a soft aura of the same colour swells behind it with every beat. The colour eases from zone to zone; with no reading the
/// ring stays dark and the disc is the idle blue.
struct NunaZoneRing: View {
    let bpm: Int?
    /// The zone the heart rate is in (0 when it is below the first).
    let zone: Int
    /// How far round the five zones the heart rate is, 0 to 1; nil leaves only the current zone lit (the heart rate is hidden).
    let level: Double?
    var numberText: String?
    /// Under the number: the zone and its range.
    var caption: String?
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var clock = NunaPulseClock()

    private let gapDegrees = 8.0

    private var tint: Color { bpm == nil ? NunaPalette.effortModerate : NunaHeartBeat.zoneColors[min(max(zone, 1), 5) - 1] }

    /// Dark text on a light zone colour, white on a dark one: the zone colours change with the skin, so the choice is made from the colour itself.
    private var ink: Color {
        guard bpm != nil else { return NunaPalette.mapOverlayText }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(tint).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.58 ? NunaPalette.onAccent : NunaPalette.mapOverlayText
    }

    /// The beat follows the zone, not the heart, as on the disc it replaces: slow in the lowest zone, quicker in the highest.
    private var tempo: Double? {
        guard bpm != nil else { return nil }
        let l = level ?? (zone > 0 ? (Double(zone) - 0.5) / 5 : 0.1)
        return 26 + 40 * min(max(l, 0), 1)
    }

    /// How much of the arc of zone `z` (0...4) is lit.
    private func lit(_ z: Int) -> Double {
        guard bpm != nil else { return 0 }
        guard let level else { return z + 1 == min(zone, 5) ? 1 : 0 }
        return min(max(level * 5 - Double(z), 0), 1)
    }

    private func arcStart(_ z: Int) -> Double { (72 * Double(z) + gapDegrees / 2) / 360 }
    private var arcLength: Double { (72 - gapDegrees) / 360 }

    var body: some View {
        let lineWidth = size * 0.03
        let ringRadius = (size - lineWidth) / 2
        let disc = size * 0.80
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let _ = clock.advance(to: timeline.date, target: tempo)
            let swell = NunaBeat.swell(clock.phase) * (0.7 + 0.3 * clock.presence)
            ZStack {
                // The aura: the zone colour, soft, a little wider with every beat and stronger in the higher zones.
                Circle().fill(tint).frame(width: disc * 1.04, height: disc * 1.04).blur(radius: size * 0.085)
                    .opacity(bpm == nil ? 0.18 : 0.26 + 0.05 * Double(min(zone, 5)) + 0.22 * swell)
                    .scaleEffect(1 + 0.05 * swell)
                // The ring: five zones, each dim until the heart rate has been through it.
                ForEach(0..<5, id: \.self) { z in
                    let color = NunaHeartBeat.zoneColors[z]
                    Circle().inset(by: lineWidth / 2).trim(from: arcStart(z), to: arcStart(z) + arcLength)
                        .stroke(color.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle().inset(by: lineWidth / 2).trim(from: arcStart(z), to: arcStart(z) + arcLength * lit(z))
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .opacity(lit(z) > 0 ? 1 : 0)
                }
                // The mark where the heart rate is.
                if let level, bpm != nil {
                    let scaled = min(max(level, 0), 1) * 5
                    let z = min(Int(scaled), 4)
                    let angle = (72 * Double(z) + gapDegrees / 2 + (scaled - Double(z)) * (72 - gapDegrees) - 90) * .pi / 180
                    Circle().fill(Color.white).frame(width: lineWidth * 1.9, height: lineWidth * 1.9)
                        .shadow(color: tint.opacity(0.7), radius: 6)
                        .offset(x: ringRadius * cos(angle), y: ringRadius * sin(angle))
                }
                // The disc.
                Circle()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.62)], startPoint: .topTrailing, endPoint: .bottomLeading))
                    .frame(width: disc, height: disc)
                    .scaleEffect(0.985 + 0.03 * swell)
                VStack(spacing: 4) {
                    Text(verbatim: numberText ?? bpm.map(String.init) ?? "–")
                        .font(.nuna(size: size * 0.27, weight: .bold, design: NunaType.design))
                        .tracking(nunaTrackingNumber(size * 0.27))
                        .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(.numericText())
                    Text("bpm").font(.nuna(size: 12, weight: .heavy)).textCase(.uppercase).tracking(nunaTrackingLabel)
                    Group {
                        if bpm == nil { Text("Waiting for WHOOP") } else if let caption { Text(verbatim: caption) }
                    }
                    .font(.nuna(size: 13, weight: .semibold)).textCase(nil).padding(.top, 6).multilineTextAlignment(.center)
                }
                .foregroundStyle(ink)
                .frame(width: disc * 0.84)
            }
            .frame(width: size, height: size)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: zone)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(bpm.map { "Heart rate \($0) bpm" } ?? String(localized: "Heart rate unavailable")))
    }
}
#endif
