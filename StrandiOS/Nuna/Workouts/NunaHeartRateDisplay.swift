#if os(iOS)
import SwiftUI
import StrandDesign

/// Keeps the beat continuous while the heart rate changes: the phase advances by the smoothed rate each frame, so a new reading speeds the
/// trace up or slows it down gradually and never makes it jump. With no reading it settles into a quiet, slow idle trace.
final class NunaPulseClock: ObservableObject {
    private var last: Date?
    /// Beats since the screen appeared (continuous, not wrapped).
    private(set) var phase = 0.0
    /// The rate the trace runs at, eased towards the live reading.
    private(set) var bpm = 60.0
    /// How tall the trace is: small while waiting, full with a reading.
    private(set) var amplitude = 0.22
    /// 0 while waiting, 1 with a reading; fades the colour in.
    private(set) var presence = 0.0

    func advance(to date: Date, target: Double?) {
        guard let previous = last else { last = date; return }
        let dt = min(max(date.timeIntervalSince(previous), 0), 0.1)
        last = date
        bpm += ((target ?? 60) - bpm) * (1 - exp(-dt / 1.4))
        amplitude += ((target == nil ? 0.22 : 1.0) - amplitude) * (1 - exp(-dt / 0.8))
        presence += ((target == nil ? 0.0 : 1.0) - presence) * (1 - exp(-dt / 0.8))
        phase += dt * bpm / 60
    }
}

extension NunaHeartRateDisplay {
    /// Zone 1 is a light grey, not the dark track colour, so a trace or a label in it stays readable.
    static let zoneColors: [Color] = [NunaPalette.textSecondary, NunaPalette.charge, NunaPalette.effort, NunaPalette.warning, NunaPalette.alert]

    /// The colour of a heart-rate zone (1...5); muted for 0, no reading.
    static func zoneColor(_ zone: Int) -> Color { zone > 0 ? zoneColors[min(zone, 5) - 1] : NunaPalette.textMuted }
}

/// One beat of an ECG as a sum of Gaussians (P, Q, R, S, T), `p` in 0...1 (wraps), the R peak at 0.33.
enum NunaECG {
    static func value(_ p: Double) -> Double {
        let x = p - floor(p)
        func g(_ c: Double, _ w: Double) -> Double { exp(-pow((x - c) / w, 2) / 2) }
        return 0.13 * g(0.17, 0.035) - 0.13 * g(0.295, 0.011) + 1.0 * g(0.33, 0.012) - 0.24 * g(0.365, 0.013) + 0.30 * g(0.60, 0.06)
    }

    /// The beat's pulse for the heart icon: a quick swell at the R peak and a smaller one with the T wave.
    static func swell(_ p: Double) -> Double {
        let x = p - floor(p)
        return exp(-pow((x - 0.33) / 0.055, 2) / 2) + 0.35 * exp(-pow((x - 0.62) / 0.09, 2) / 2)
    }
}

/// The heart rate as a moving trace and a number, in the colour of the zone it is in. No ring: the trace runs at the pace of the heart,
/// its colour eases from zone to zone, and with no reading yet it idles quietly under "Waiting for WHOOP".
struct NunaHeartRateDisplay: View {
    let bpm: Int?
    /// The zone colour (nil or muted while there is no reading).
    let color: Color
    /// A change of zone eases the colour over this value.
    let zone: Int
    var numberText: String?
    var unit: LocalizedStringKey = "bpm"
    var caption: String?
    var waitingText: LocalizedStringKey = "Waiting for WHOOP"
    var traceHeight: CGFloat = 130
    var numberSize: CGFloat = 76
    /// Text over a map or photo: white, with a soft scrim behind the trace.
    var onMap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var clock = NunaPulseClock()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let _ = clock.advance(to: timeline.date, target: bpm.map(Double.init))
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.nuna(size: numberSize * 0.34, weight: .bold))
                        .foregroundStyle(color)
                        .scaleEffect(1 + 0.16 * NunaECG.swell(clock.phase) * clock.presence)
                        .opacity(0.45 + 0.55 * clock.presence)
                    Text(verbatim: numberText ?? bpm.map(String.init) ?? "–")
                        .font(.nuna(size: numberSize, weight: .bold, design: NunaType.design))
                        .tracking(nunaTrackingNumber(numberSize))
                        .monospacedDigit()
                        .foregroundStyle(onMap ? NunaPalette.mapOverlayText : NunaPalette.textPrimary)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(onMap ? NunaPalette.mapOverlayText.opacity(0.8) : NunaPalette.textSecondary)
                }
                trace(timeline.date)
                Group {
                    if bpm == nil { Text(waitingText) } else { Text(verbatim: caption ?? "") }
                }
                    .font(.nuna(size: 13, weight: .semibold))
                    .foregroundStyle(onMap ? NunaPalette.mapOverlayText.opacity(0.85) : NunaPalette.textSecondary)
                    .textCase(nil)
                    .frame(minHeight: 18)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: zone)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(bpm.map { "Heart rate \($0) bpm" } ?? String(localized: "Heart rate unavailable")))
    }

    private func trace(_ date: Date) -> some View {
        Canvas { ctx, size in
            let mid = size.height * 0.56
            let amp = size.height * 0.40 * clock.amplitude
            let beats = 2.3
            let beatWidth = size.width / beats
            func y(at x: CGFloat) -> CGFloat {
                let ph = clock.phase - (size.width - x) / beatWidth
                return mid - CGFloat(NunaECG.value(ph)) * amp
            }
            // The baseline the trace rides on, barely there.
            var base = Path(); base.move(to: CGPoint(x: 0, y: mid)); base.addLine(to: CGPoint(x: size.width, y: mid))
            ctx.stroke(base, with: .foreground, style: StrokeStyle(lineWidth: 1, dash: [2, 5]))

            var path = Path()
            var x: CGFloat = 0
            path.move(to: CGPoint(x: 0, y: y(at: 0)))
            while x < size.width {
                x += 2
                path.addLine(to: CGPoint(x: min(x, size.width), y: y(at: min(x, size.width))))
            }
            // Glow, then the line itself.
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 7))
                layer.opacity = 0.55 * (0.4 + 0.6 * clock.presence)
                layer.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            ctx.opacity = 0.5 + 0.5 * clock.presence
            ctx.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            // The head of the trace.
            let head = CGPoint(x: size.width - 3, y: y(at: size.width - 3))
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - 4.5, y: head.y - 4.5, width: 9, height: 9)), with: .foreground)
        }
        .foregroundStyle(color)
        .frame(height: traceHeight)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.28), .init(color: .black, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .background {
            if onMap {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(NunaPalette.mapOverlay.opacity(0.42))
            }
        }
    }
}
#endif
