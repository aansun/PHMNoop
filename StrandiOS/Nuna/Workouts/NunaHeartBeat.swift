#if os(iOS)
import SwiftUI
import StrandDesign

/// Keeps the beat continuous while the heart rate changes: the phase advances by the smoothed rate each frame, so a new reading speeds the
/// beat up or slows it down gradually and never makes it jump. With no reading it settles into a slow, quiet idle.
final class NunaPulseClock: ObservableObject {
    private var last: Date?
    /// Beats since the screen appeared (continuous, not wrapped).
    private(set) var phase = 0.0
    /// The rate the beat runs at, eased towards the live reading.
    private(set) var bpm = 60.0
    /// 0 while waiting, 1 with a reading; the swell grows in with it.
    private(set) var presence = 0.0

    func advance(to date: Date, target: Double?) {
        guard let previous = last else { last = date; return }
        let dt = min(max(date.timeIntervalSince(previous), 0), 0.1)
        last = date
        bpm += ((target ?? 60) - bpm) * (1 - exp(-dt / 1.4))
        presence += ((target == nil ? 0.0 : 1.0) - presence) * (1 - exp(-dt / 0.8))
        phase += dt * bpm / 60
    }
}

enum NunaBeat {
    /// The pulse of one beat, `p` in 0...1 (wraps): a quick swell and a smaller second one, like the lub-dub, with no hard edges.
    static func swell(_ p: Double) -> Double {
        let x = p - floor(p)
        return exp(-pow((x - 0.18) / 0.075, 2) / 2) + 0.55 * exp(-pow((x - 0.42) / 0.09, 2) / 2)
    }
}

/// The heart rate as a beating disc: the disc and the heart swell with every beat at the pace of the real heart, in the colour of the
/// zone the heart rate is in, with the number inside. The colour eases from zone to zone; with no reading the disc keeps a slow idle beat.
/// The same design opens the screen before an activity and fills the Heart rate tab during it.
struct NunaHeartBeat: View {
    let bpm: Int?
    /// Fill colour: the zone colour, or the Effort blue while there is no reading.
    let color: Color
    /// A change of zone eases the colour over this value.
    let zone: Int
    var numberText: String?
    var size: CGFloat = 238
    var battery: Double?
    /// Under the disc: the zone and its range with a reading, "Waiting for WHOOP" without.
    var caption: String?
    var captionColor: Color = NunaPalette.textSecondary
    /// How far up the five zones the heart rate sits, 0 to 1, for the tempo. Without it the middle of the zone is used.
    var level: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var clock = NunaPulseClock()

    /// The beat is slow on purpose and follows the zone, not the heart: about 26 beats a minute in the lowest zone, rising to about 66 in the highest,
    /// so a climbing heart rate reads as a quickening, never as a flutter.
    private var tempo: Double? {
        guard bpm != nil else { return nil }
        let l = level ?? (zone > 0 ? (Double(zone) - 0.5) / 5 : 0.1)
        return 26 + 40 * min(max(l, 0), 1)
    }

    /// Rings that leave the disc: none in zone 1, one more with each zone above it.
    private var rings: Int { bpm == nil ? 0 : max(0, min(zone, 5) - 1) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let _ = clock.advance(to: timeline.date, target: tempo)
            let calm = zone <= 1
            let swell = NunaBeat.swell(clock.phase) * (0.7 + 0.3 * clock.presence)
            VStack(spacing: 14) {
                ZStack {
                    ForEach(0..<rings, id: \.self) { k in
                        // Each ring starts a little after the one before and widens as it fades; higher zones have more of them.
                        let p = (clock.phase * 0.5 + Double(k) / Double(max(rings, 1))).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(color.opacity(0.7 * (1 - p)), lineWidth: 3)
                            .frame(width: size, height: size)
                            .scaleEffect(1.02 + (0.10 + 0.04 * Double(rings)) * p)
                    }
                    Circle()
                        .fill(color.opacity(0.93))
                        .frame(width: size, height: size)
                        .scaleEffect(calm ? 0.97 + 0.04 * swell : 0.95 + 0.09 * swell)
                    VStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.nuna(size: size * 0.16, weight: .bold))
                            .scaleEffect(calm ? 0.97 + 0.08 * swell : 0.94 + 0.2 * swell)
                        Text(verbatim: numberText ?? bpm.map(String.init) ?? "–")
                            .font(.nuna(size: size * 0.336, weight: .bold, design: NunaType.design))
                            .tracking(nunaTrackingNumber(size * 0.336))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6).lineLimit(1)
                            .contentTransition(.numericText())
                        Text("bpm")
                            .font(.nuna(size: 12, weight: .heavy))
                            .textCase(.uppercase)
                            .tracking(nunaTrackingLabel)
                        if let battery {
                            HStack(spacing: 5) {
                                Image(systemName: "battery.75percent")
                                Text(verbatim: "\(Int(battery.rounded()))%")
                            }
                            .font(.nuna(size: 13, weight: .bold))
                            .padding(.top, 4)
                        }
                    }
                    .foregroundStyle(Self.inkColor(zone: zone, hasReading: bpm != nil))
                }
                .frame(width: size * 1.1, height: size * 1.1)
                if caption != nil || bpm == nil {
                    Group {
                        if bpm == nil { Text("Waiting for WHOOP") } else { Text(verbatim: caption ?? "") }
                    }
                    .font(.nuna(size: 13, weight: .semibold))
                    .foregroundStyle(captionColor)
                    .textCase(nil)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: zone)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(bpm.map { "Heart rate \($0) bpm" } ?? String(localized: "Heart rate unavailable")))
    }
}

extension NunaHeartBeat {
    /// Zone 1 is a light grey, not the dark track colour, so a disc or a label in it stays readable.
    static let zoneColors: [Color] = [NunaPalette.textSecondary, NunaPalette.charge, NunaPalette.effort, NunaPalette.warning, NunaPalette.alert]

    /// Text on the disc: dark on the light zone colours (grey, green, lime, amber), white on the blue idle disc and on the red of zone 5.
    static func inkColor(zone: Int, hasReading: Bool) -> Color {
        guard hasReading, zone >= 1, zone <= 4 else { return NunaPalette.mapOverlayText }
        return NunaPalette.onAccent
    }

    /// The colour of a heart-rate zone (1...5); the Effort blue for 0, no reading.
    static func zoneColor(_ zone: Int) -> Color { zone > 0 ? zoneColors[min(zone, 5) - 1] : NunaPalette.effortModerate }
}
#endif
