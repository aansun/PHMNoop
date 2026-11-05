import SwiftUI

/// How the three score rings are coloured, in one place: the app draws its rings with these and so do the widgets, so a ring
/// cannot read differently on the Home Screen than it does in Today.
public enum NunaScoreStyle {
    /// The one colour each score keeps in a chart line or a bar, where the ring's own colour (which follows the value) cannot be used:
    /// Charge green, Effort blue, Rest the green of an excellent night. A chart marks each day's dot with the ring colour for that day.
    public static var chargeSeries: Color { NunaPalette.scoreHigh }
    public static var effortSeries: Color { NunaPalette.effortModerate }
    public static var restSeries: Color { NunaPalette.charge }

    /// Two lines on one chart (Charge and Rest, or the first two metrics in Compare) have to be told apart at a glance, so they are a grey and a blue
    /// rather than two greens. Both clear the dark and the light cards.
    public static var pairGrey: Color { Color(light: "#4C565E", dark: "#B7C0C8") }
    public static var pairBlue: Color { Color(light: "#1F6FE5", dark: "#4DA3FF") }

    /// Charge: green from 67, yellow from 34, red below.
    public static func chargeColor(_ v: Double) -> Color {
        v >= 67 ? NunaPalette.scoreHigh : (v >= 34 ? NunaPalette.scoreMid : NunaPalette.scoreLow)
    }

    /// Effort on the stored 0-100 axis: dark blue below 33, blue below 66, light blue above.
    public static func effortColor(_ stored: Double) -> Color {
        stored < 33 ? NunaPalette.effortMinimal : (stored < 66 ? NunaPalette.effortModerate : NunaPalette.effortAllOut)
    }

    /// The colours the Effort arc runs through, from dark blue up to the level reached.
    public static func effortGradient(_ stored: Double) -> [Color] {
        var c = [NunaPalette.effortMinimal]
        if stored >= 33 { c.append(NunaPalette.effortModerate) }
        if stored >= 66 { c.append(NunaPalette.effortAllOut) }
        if c.count == 1 { c.append(NunaPalette.effortMinimal) }
        return c
    }

    /// Where on the Effort ring (0...1, clockwise from the top) today's aim sits, from Charge: the place of the white mark.
    ///
    /// Read off the WHOOP rings at five Charge values, where the mark stands at 121° (Charge 10), 135° (15), 184° (42), 185° (44) and, for the
    /// highest Charge seen, 279° (about 16.3 of 21). It moves smoothly with Charge, not in three steps, so the figures below are joined by straight
    /// lines. Between Charge 44 and 85 (where the 16.3 stands) and above 85 the line is assumed, not measured: more readings would refine it.
    /// nil while Charge is unknown.
    public static func effortAim(charge: Double?) -> Double? {
        guard let charge else { return nil }
        // (Charge, Effort of 21)
        let points: [(Double, Double)] = [(0, 5.4), (10, 7.06), (15, 7.88), (42, 10.73), (44, 10.79), (85, 16.27), (100, 18.3)]
        let c = min(max(charge, 0), 100)
        for i in 1..<points.count where c <= points[i].0 {
            let (c0, e0) = points[i - 1], (c1, e1) = points[i]
            return (e0 + (e1 - e0) * (c - c0) / (c1 - c0)) / 21.0
        }
        return points[points.count - 1].1 / 21.0
    }

    /// Today's Effort aim as a stretch of the ring (0...1): the mark of `effortAim`, 36° (about 2.1 of 21) to either side, as measured on the
    /// WHOOP rings. nil while Charge is unknown.
    public static func effortTarget(charge: Double?) -> ClosedRange<Double>? {
        guard let aim = effortAim(charge: charge) else { return nil }
        return max(aim - 0.1, 0)...min(aim + 0.1, 1)
    }

    /// Rest: excellent green from 85, good lime from 70, fair amber from 50, low red below.
    public static func restColor(_ v: Double) -> Color {
        v >= 85 ? NunaPalette.charge : (v >= 70 ? NunaPalette.effort : (v >= 50 ? NunaPalette.warning : NunaPalette.alert))
    }

    public static func restTextColor(_ v: Double) -> Color {
        v >= 85 ? NunaPalette.charge : (v >= 70 ? NunaPalette.effortText : (v >= 50 ? NunaPalette.warning : NunaPalette.alertText))
    }
}
