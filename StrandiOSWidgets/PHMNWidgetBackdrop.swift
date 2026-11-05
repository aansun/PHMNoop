import SwiftUI

/// The background of the PHMN widgets: the app's own in the WHP style (`NunaBackdrop`), so a widget and the screen behind it are the same colour.
///
/// From iOS 26 the system lays a light sheen over every widget on the Home Screen, strongest at the top. Measured on a widget painted pure black, it adds
/// about 33 levels (of 255) at the top, falling in a straight line to about 12 at the bottom. Painting the app's colours as they are would therefore show
/// lighter and greyer than the screen, so the sheen is taken off the colour first and the system puts it back.
enum PHMNWidgetBackdrop {
    /// The stops of `NunaBackdrop` in the WHP style: where (0 top, 1 bottom) and the colour.
    private static let stops: [(at: Double, hex: UInt32)] = [
        (0, 0x263137), (0.10, 0x232E33), (0.15, 0x212B31), (0.45, 0x161A1E), (0.85, 0x0F1415), (1, 0x0E1313)]

    private static func color(_ hex: UInt32, at t: Double) -> Color {
        var sheen = 0.0
        if #available(iOS 26.0, *) { sheen = 0.129 - 0.0863 * t }
        // What the widget must paint so that, with the sheen on top, the screen shows `v`.
        func paint(_ v: UInt32) -> Double { max(0, (Double(v) / 255 - sheen) / (1 - sheen)) }
        return Color(red: paint((hex >> 16) & 0xFF), green: paint((hex >> 8) & 0xFF), blue: paint(hex & 0xFF))
    }

    static let gradient = LinearGradient(
        stops: stops.map { .init(color: color($0.hex, at: $0.at), location: $0.at) },
        startPoint: .top, endPoint: .bottom)
}
