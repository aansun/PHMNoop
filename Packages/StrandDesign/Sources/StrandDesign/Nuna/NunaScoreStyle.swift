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

    /// Today's Effort aim from Charge, as a stretch of the ring (0...1): 14 to 18 of 21 from Charge 67, 10 to 14 from 34, 4 to 10
    /// below. nil while Charge is unknown.
    public static func effortTarget(charge: Double?) -> ClosedRange<Double>? {
        guard let charge else { return nil }
        let band: ClosedRange<Double> = charge >= 67 ? 14...18 : (charge >= 34 ? 10...14 : 4...10)
        return (band.lowerBound / 21.0)...(band.upperBound / 21.0)
    }

    /// Rest: excellent green from 85, good lime from 70, fair amber from 50, low red below.
    public static func restColor(_ v: Double) -> Color {
        v >= 85 ? NunaPalette.charge : (v >= 70 ? NunaPalette.effort : (v >= 50 ? NunaPalette.warning : NunaPalette.alert))
    }

    public static func restTextColor(_ v: Double) -> Color {
        v >= 85 ? NunaPalette.charge : (v >= 70 ? NunaPalette.effortText : (v >= 50 ? NunaPalette.warning : NunaPalette.alertText))
    }
}
