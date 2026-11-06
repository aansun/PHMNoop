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

/// A dart board seen edge-on, with a green dart in it: the card's picture, drawn in the greys of the page.
struct NunaDartBoard: View {
    var body: some View {
        ZStack {
            // The disc, a little in perspective.
            Capsule().fill(LinearGradient(colors: [Color(hex: "#4A4F55"), Color(hex: "#2D3136")], startPoint: .leading, endPoint: .trailing))
                .frame(width: 44, height: 82).offset(x: -18)
            Ellipse().fill(Color(hex: "#3B4046")).frame(width: 26, height: 56).offset(x: -16)
            Ellipse().strokeBorder(Color(hex: "#24272B"), lineWidth: 2).frame(width: 15, height: 32).offset(x: -15)
            Ellipse().fill(Color(hex: "#24272B")).frame(width: 5, height: 9).offset(x: -14)
            // The dart: shaft in green, barrel, tail and flight in grey.
            Capsule().fill(Color(hex: "#5BE08A")).frame(width: 34, height: 4).rotationEffect(.degrees(-18)).offset(x: 6, y: -5)
            Capsule().fill(LinearGradient(colors: [Color(hex: "#7A8087"), Color(hex: "#4A4F55")], startPoint: .top, endPoint: .bottom))
                .frame(width: 22, height: 8).rotationEffect(.degrees(-18)).offset(x: 28, y: -12)
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(LinearGradient(colors: [Color(hex: "#6E8C77"), Color(hex: "#3C4A41")], startPoint: .top, endPoint: .bottom))
                .frame(width: 20, height: 18).rotationEffect(.degrees(-18)).offset(x: 42, y: -17)
        }
        .accessibilityHidden(true)
    }
}
#endif
