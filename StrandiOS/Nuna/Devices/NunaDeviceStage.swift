#if os(iOS)
import SwiftUI
import StrandDesign

/// The strap drawn as an object: a woven band with the sensor pod on it, cut off by the screen edge so it reads as large and close.
/// Drawn in code (no photo, no brand mark). The light blinks green while the strap is connected; when it is not, the light is red and the picture is blurred.
struct NunaStrapArt: View {
    var active: Bool
    @State private var on = true

    // Band face: centre as a fraction of the frame, size as a fraction, tilt in degrees.
    private static let cx = 0.34, cy = 0.40, fw = 0.74, fh = 0.34, tilt = 12.0

    /// A point given in the face's own coordinates (x along the band, y across it), in the frame's.
    static func point(_ dx: CGFloat, _ dy: CGFloat, in size: CGSize) -> CGPoint {
        let r = tilt * .pi / 180
        return CGPoint(x: size.width * cx + dx * cos(r) - dy * sin(r), y: size.height * cy + dx * sin(r) + dy * cos(r))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let led = Self.point(-size.width * Self.fw * 0.26, -size.height * Self.fh * 0.36, in: size)
            ZStack {
                // Not connected: the picture goes soft and a little dimmer.
                Canvas { gc, size in Self.draw(&gc, size) }
                    .blur(radius: active ? 0 : 5)
                    .opacity(active ? 1 : 0.7)
                // The light on the strap: green and blinking while connected, red and steady when not.
                Circle().fill(active ? NunaPalette.charge : NunaPalette.alert)
                    .frame(width: 8, height: 8)
                    .opacity(active ? (on ? 1 : 0.2) : 1)
                    .shadow(color: (active ? NunaPalette.charge : NunaPalette.alert).opacity(active ? (on ? 0.95 : 0) : 0.8), radius: active ? 10 : 9)
                    .position(led)
            }
            .animation(.easeInOut(duration: 0.18), value: active)
            .task(id: active) {
                on = true
                guard active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    withAnimation(.easeInOut(duration: 0.25)) { on.toggle() }
                }
            }
        }
        .accessibilityHidden(true)
    }

    // The strap's own colours: a dark woven band, not part of the app palette.
    private static let bandLight = Color(red: 0.25, green: 0.26, blue: 0.29)
    private static let bandDark = Color(red: 0.08, green: 0.09, blue: 0.10)

    private static func weave(_ gc: inout GraphicsContext, in rect: CGRect, step: CGFloat = 5) {
        var lines = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            lines.move(to: CGPoint(x: x, y: rect.maxY)); lines.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            lines.move(to: CGPoint(x: x, y: rect.minY)); lines.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            x += step
        }
        gc.stroke(lines, with: .color(.white.opacity(0.055)), lineWidth: 1)
    }

    private static func draw(_ gc: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let faceW = w * fw, faceH = h * fh
        let rot = Angle.degrees(tilt)

        // The band wrapping round underneath.
        let loop = Path(ellipseIn: CGRect(x: -w * 0.30, y: h * 0.30, width: w * 0.66, height: h * 0.44))
            .strokedPath(StrokeStyle(lineWidth: faceH * 0.90))
        gc.drawLayer { l in
            l.fill(loop, with: .linearGradient(Gradient(colors: [bandDark, bandLight.opacity(0.9), bandDark]),
                                               startPoint: CGPoint(x: 0, y: h * 0.2), endPoint: CGPoint(x: w * 0.5, y: h)))
            l.clip(to: loop)
            weave(&l, in: CGRect(origin: .zero, size: size))
        }

        // The face of the band, tilted.
        gc.drawLayer { l in
            l.translateBy(x: w * cx, y: h * cy)
            l.rotate(by: rot)
            let face = Path(roundedRect: CGRect(x: -faceW / 2, y: -faceH / 2, width: faceW, height: faceH), cornerRadius: faceH * 0.16)
            l.addFilter(.shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 8))
            l.fill(face, with: .linearGradient(Gradient(colors: [bandLight, bandDark]),
                                               startPoint: CGPoint(x: 0, y: -faceH / 2), endPoint: CGPoint(x: 0, y: faceH / 2)))
            l.drawLayer { inner in
                inner.clip(to: face)
                weave(&inner, in: CGRect(x: -faceW / 2, y: -faceH / 2, width: faceW, height: faceH))
            }
            l.stroke(face, with: .color(.white.opacity(0.10)), lineWidth: 1)

            // The sensor pod, across the band.
            let podW = faceW * 0.20, podH = faceH * 1.10
            let pod = Path(roundedRect: CGRect(x: faceW * 0.10, y: -podH / 2, width: podW, height: podH), cornerRadius: podW * 0.28)
            l.fill(pod, with: .linearGradient(Gradient(colors: [Color(red: 0.30, green: 0.31, blue: 0.34), Color(red: 0.07, green: 0.07, blue: 0.08)]),
                                              startPoint: CGPoint(x: faceW * 0.10, y: -podH / 2), endPoint: CGPoint(x: faceW * 0.10 + podW, y: podH / 2)))
            l.stroke(pod, with: .color(.white.opacity(0.16)), lineWidth: 1.2)
            // A slim groove down the pod.
            var groove = Path()
            groove.move(to: CGPoint(x: faceW * 0.10 + podW * 0.5, y: -podH * 0.36))
            groove.addLine(to: CGPoint(x: faceW * 0.10 + podW * 0.5, y: podH * 0.36))
            l.stroke(groove, with: .color(.white.opacity(0.07)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

/// A vertical battery: a thin track filled from the bottom, with the figure beside it.
struct NunaBatteryGauge: View {
    let pct: Double?
    let charging: Bool
    let model: String
    let estimate: String?

    private var tint: Color { (pct ?? 100) <= 10 ? NunaPalette.alert : ((pct ?? 100) <= 20 ? NunaPalette.warning : NunaPalette.charge) }
    private let barHeight: CGFloat = 250

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .trailing, spacing: 4) {
                if charging {
                    Image(systemName: "bolt.fill").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.charge)
                }
                if let pct {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(verbatim: "\(Int(pct.rounded()))").font(.nuna(size: 46, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text("%").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                } else {
                    Text(verbatim: "–").font(.nuna(size: 46, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textMuted)
                }
                Text(verbatim: model).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                if let estimate {
                    Text(verbatim: estimate).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
            ZStack(alignment: .bottom) {
                Capsule().fill(NunaPalette.ink.opacity(0.10)).frame(width: 6, height: barHeight)
                Capsule().fill(tint).frame(width: 6, height: max(6, barHeight * CGFloat((pct ?? 0) / 100)))
                    .animation(.easeOut(duration: 0.6), value: pct)
            }
        }
        .contentShape(Rectangle())
    }
}

/// The picture at the heart of the Status tab: the strap, large and cut off by the screen edge, with its battery beside it when it is
/// connected. When it is not, the same picture, blurred, with a red light.
struct NunaDeviceStage: View {
    let connected: Bool
    let batteryPct: Double?
    let charging: Bool
    let model: String
    let estimate: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            NunaStrapArt(active: connected)
            if connected {
                NavigationLink(value: NunaDeviceRoute.battery) {
                    NunaBatteryGauge(pct: batteryPct, charging: charging, model: model, estimate: estimate)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 20).padding(.bottom, 14)
            }
        }
        .frame(height: 340)
    }
}
#endif
