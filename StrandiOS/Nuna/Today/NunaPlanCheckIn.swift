#if os(iOS)
import SwiftUI
import StrandDesign

/// When the Weekly Plan Check-In joins the highlights: with a plan set, once the night's sleep is in, and before the evening review takes over.
enum NunaCheckInGate {
    static func visible(woke: Bool, hasPlan: Bool, now: Date = Date()) -> Bool {
#if DEBUG
        // `--demo-checkin=on` / `=off` forces the card, whatever the clock and the night say.
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-checkin=") }) { return arg.hasSuffix("on") && hasPlan }
#endif
        return woke && hasPlan && !NunaReviewGate.isEvening(now: now)
    }
}

/// A dart board turned a little away, with a green dart in the bull: the check-in's picture, drawn in the greys of the page.
struct NunaDartBoard: View {
    private let w: CGFloat = 120, h: CGFloat = 104

    var body: some View {
        let cx: CGFloat = 52, cy: CGFloat = 54
        ZStack {
            // The thickness: the back of the disc, shifted left, and the band that joins it to the face.
            Ellipse().fill(LinearGradient(colors: [Color(hex: "#3F454B"), Color(hex: "#555C63")], startPoint: .leading, endPoint: .trailing))
                .frame(width: 50, height: 90).position(x: cx - 14, y: cy)
            Rectangle().fill(LinearGradient(colors: [Color(hex: "#4A5056"), Color(hex: "#5F666D")], startPoint: .leading, endPoint: .trailing))
                .frame(width: 14, height: 90).position(x: cx - 7, y: cy)
            // The face and its rings.
            Ellipse().fill(Color(hex: "#6A7178")).frame(width: 50, height: 90).position(x: cx, y: cy)
            Ellipse().stroke(Color(hex: "#7A8188"), lineWidth: 1.5).frame(width: 46, height: 83).position(x: cx, y: cy)
            Ellipse().fill(Color(hex: "#5E656C")).frame(width: 32, height: 58).position(x: cx + 1, y: cy)
            Ellipse().fill(Color(hex: "#737A81")).frame(width: 19, height: 34).position(x: cx + 1.5, y: cy)
            Ellipse().fill(Color(hex: "#4B5157")).frame(width: 9, height: 16).position(x: cx + 2, y: cy)
            Ellipse().fill(Color(hex: "#2E3338")).frame(width: 4, height: 7).position(x: cx + 2, y: cy)
            // The dart, from its tip in the bull toward the upper right: barrel, shaft, flight.
            HStack(spacing: 0) {
                Capsule().fill(Color(hex: "#9AA1A8")).frame(width: 6, height: 2)
                ZStack {
                    Capsule().fill(LinearGradient(colors: [Color(hex: "#4BE08A"), Color(hex: "#2BB86A")], startPoint: .top, endPoint: .bottom))
                    HStack(spacing: 3) { ForEach(0..<5, id: \.self) { _ in Rectangle().fill(Color(hex: "#1E7A47")).frame(width: 1, height: 6) } }
                }
                .frame(width: 30, height: 6)
                Capsule().fill(Color(hex: "#2A2E33")).frame(width: 16, height: 3.5)
                // The flight: a rounded fin with a green rim.
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(LinearGradient(colors: [Color(hex: "#3A4046"), Color(hex: "#23272B")], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color(hex: "#3FD77F"), lineWidth: 1.6))
                    .frame(width: 24, height: 24)
            }
            .rotationEffect(.degrees(-22), anchor: .leading)
            .position(x: cx + 2 + 38, y: cy - 14)
        }
        .frame(width: w, height: h)
        .accessibilityHidden(true)
    }
}
#endif
