#if os(iOS)
import SwiftUI
import StrandDesign

/// The heart rate of a running activity as a thin ring round a disc. The ring is the five heart-rate zones; only the zone the heart is in is lit, in its
/// own colour, with a white mark at the heart rate itself, and the other four are faint but visible. A zone aimed for keeps its colour like any other and has a
/// thin grey line along the outside of its arc to mark where it is. The disc inside is the colour of the zone, with the number on it, and a soft aura of the same colour swells behind it with
/// every beat. The colour eases from zone to zone; with no reading the ring stays dark and the disc is the idle blue.
struct NunaZoneRing: View {
    let bpm: Int?
    /// The zone the heart rate is in (0 when it is below the first).
    let zone: Int
    /// How far round the five zones the heart rate is, 0 to 1; nil leaves only the current zone lit (the heart rate is hidden).
    let level: Double?
    var numberText: String?
    /// Under the number, large: the zone.
    var caption: String?
    /// The zone being aimed for, if the session has a target zone.
    var targetZone: Int?
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

    /// Whether the arc of zone `z` (0...4) is the one lit: the zone the heart rate is in.
    private func isActive(_ z: Int) -> Bool { bpm != nil && z + 1 == min(max(zone, 1), 5) }

    private func arcStart(_ z: Int) -> Double { (72 * Double(z) + gapDegrees / 2) / 360 }
    private var arcLength: Double { (72 - gapDegrees) / 360 }

    var body: some View {
        let lineWidth = size * 0.014
        // Room outside the ring for the line that marks the target zone, kept whether or not there is one so that nothing moves when a target is set.
        let markWidth = max(1.5, lineWidth * 0.55)
        let ringInset = markWidth + lineWidth * 0.9
        let ringRadius = size / 2 - ringInset - lineWidth / 2
        let disc = size * 0.88
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let _ = clock.advance(to: timeline.date, target: tempo)
            let swell = NunaBeat.swell(clock.phase) * (0.7 + 0.3 * clock.presence)
            ZStack {
                // The aura: the zone colour, soft, a little wider with every beat and stronger in the higher zones.
                Circle().fill(tint).frame(width: disc * 1.04, height: disc * 1.04).blur(radius: size * 0.085)
                    .opacity(bpm == nil ? 0.18 : 0.26 + 0.05 * Double(min(zone, 5)) + 0.22 * swell)
                    .scaleEffect(1 + 0.05 * swell)
                // The ring: five thin arcs, one per zone. The zone the heart is in is lit; the rest are barely visible.
                ForEach(0..<5, id: \.self) { z in
                    let color = NunaHeartBeat.zoneColors[z]
                    if isActive(z) {
                        // The aura of the lit line: a soft, wider copy of it that swells with the beat.
                        Circle().inset(by: ringInset + lineWidth / 2).trim(from: arcStart(z), to: arcStart(z) + arcLength)
                            .stroke(color, style: StrokeStyle(lineWidth: lineWidth * 3, lineCap: .round))
                            .blur(radius: lineWidth * 2.4)
                            .opacity(0.32 + 0.42 * swell)
                            .rotationEffect(.degrees(-90))
                    }
                    Circle().inset(by: ringInset + lineWidth / 2).trim(from: arcStart(z), to: arcStart(z) + arcLength)
                        .stroke(color.opacity(isActive(z) ? 1 : 0.26), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .shadow(color: isActive(z) ? color.opacity(0.55 + 0.35 * swell) : .clear, radius: lineWidth * (1.2 + 1.6 * swell))
                        .rotationEffect(.degrees(-90))
                }
                // A white dot on each boundary between two zones, as on the ring it follows; the first sits at the top.
                ForEach(0..<5, id: \.self) { k in
                    let a = (72 * Double(k) - 90) * .pi / 180
                    Circle().fill(Color.white.opacity(0.92)).frame(width: size * 0.024, height: size * 0.024)
                        .offset(x: ringRadius * cos(a), y: ringRadius * sin(a))
                }
                // The zone aimed for: one thin grey line along the outside of its arc.
                if let target = targetZone, (1...5).contains(target) {
                    let z = target - 1
                    Circle().inset(by: markWidth / 2).trim(from: arcStart(z), to: arcStart(z) + arcLength)
                        .stroke(Color(white: 0.72).opacity(0.8), style: StrokeStyle(lineWidth: markWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                // The mark where the heart rate is.
                if let level, bpm != nil {
                    let scaled = min(max(level, 0), 1) * 5
                    let z = min(Int(scaled), 4)
                    let angle = (72 * Double(z) + gapDegrees / 2 + (scaled - Double(z)) * (72 - gapDegrees) - 90) * .pi / 180
                    let dot = size * 0.034
                    // The aura of the mark: a soft glow and a ring that spreads and fades once per two beats.
                    let spread = (clock.phase * 0.5).truncatingRemainder(dividingBy: 1)
                    ZStack {
                        Circle().fill(tint).frame(width: dot * 3.4, height: dot * 3.4).blur(radius: dot * 0.9)
                            .opacity(0.45 + 0.4 * swell).scaleEffect(1 + 0.22 * swell)
                        Circle().stroke(tint.opacity(0.7 * (1 - spread)), lineWidth: max(1.5, dot * 0.12))
                            .frame(width: dot * 1.6, height: dot * 1.6).scaleEffect(1 + 1.8 * spread)
                        Circle().fill(Color.white).frame(width: dot, height: dot)
                            .shadow(color: tint.opacity(0.8), radius: dot * (0.5 + 0.7 * swell))
                    }
                    .offset(x: ringRadius * cos(angle), y: ringRadius * sin(angle))
                }
                // The disc.
                Circle()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.62)], startPoint: .topTrailing, endPoint: .bottomLeading))
                    .frame(width: disc, height: disc)
                    .scaleEffect(0.985 + 0.03 * swell)
                VStack(spacing: 4) {
                    Text("Heart rate").font(.nuna(size: max(13, size * 0.047), weight: .heavy)).textCase(.uppercase).tracking(nunaTrackingLabel)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    // No unit under or beside the figure: the name above says what it is, and the zone below gets the room.
                    Text(verbatim: numberText ?? bpm.map(String.init) ?? "–")
                        .font(.nuna(size: size * 0.27, weight: .bold, design: NunaType.design))
                        .tracking(nunaTrackingNumber(size * 0.27))
                        .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(.numericText())
                    if bpm == nil {
                        Text("Waiting for WHOOP").font(.nuna(size: 13, weight: .semibold)).textCase(nil).padding(.top, 6).multilineTextAlignment(.center)
                    } else if let caption {
                        Text(verbatim: caption).font(.nuna(size: max(18, size * 0.085), weight: .heavy)).textCase(nil).padding(.top, 6)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
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
