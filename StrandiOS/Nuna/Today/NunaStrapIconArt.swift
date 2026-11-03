#if os(iOS)
// Generated from the design reference: the strap picture of the connection chip, traced from the image into a unit square (the longer side is 1),
// with its size in points and where the status dot sits on it. Filled with the even-odd rule.

import SwiftUI

enum NunaStrapIconArt {
    static let width: CGFloat = 18.0
    static let height: CGFloat = 23.96
    /// The status dot: its centre on the picture, and its diameter, in points.
    static let dotCenter = CGPoint(x: 16.58, y: 5.83)
    static let dotDiameter: CGFloat = 6.0
    static let contours: [[CGPoint]] = [
        [CGPoint(x: 0.099, y: 0.675), CGPoint(x: 0.101, y: 0.690), CGPoint(x: 0.120, y: 0.703), CGPoint(x: 0.348, y: 0.703), CGPoint(x: 0.360, y: 0.697), CGPoint(x: 0.370, y: 0.683), CGPoint(x: 0.370, y: 0.675), CGPoint(x: 0.358, y: 0.657), CGPoint(x: 0.336, y: 0.654), CGPoint(x: 0.127, y: 0.654), CGPoint(x: 0.106, y: 0.661)],
        [CGPoint(x: 0.209, y: 0.004), CGPoint(x: 0.164, y: 0.028), CGPoint(x: 0.143, y: 0.049), CGPoint(x: 0.103, y: 0.103), CGPoint(x: 0.061, y: 0.179), CGPoint(x: 0.019, y: 0.306), CGPoint(x: 0.004, y: 0.417), CGPoint(x: 0.000, y: 0.548), CGPoint(x: 0.005, y: 0.652), CGPoint(x: 0.021, y: 0.756), CGPoint(x: 0.036, y: 0.779), CGPoint(x: 0.054, y: 0.788), CGPoint(x: 0.068, y: 0.802), CGPoint(x: 0.075, y: 0.828), CGPoint(x: 0.085, y: 0.845), CGPoint(x: 0.103, y: 0.894), CGPoint(x: 0.134, y: 0.941), CGPoint(x: 0.164, y: 0.972), CGPoint(x: 0.209, y: 0.997), CGPoint(x: 0.223, y: 1.000), CGPoint(x: 0.548, y: 1.000), CGPoint(x: 0.564, y: 0.997), CGPoint(x: 0.607, y: 0.974), CGPoint(x: 0.636, y: 0.944), CGPoint(x: 0.666, y: 0.903), CGPoint(x: 0.710, y: 0.802), CGPoint(x: 0.737, y: 0.671), CGPoint(x: 0.751, y: 0.518), CGPoint(x: 0.748, y: 0.504), CGPoint(x: 0.722, y: 0.499), CGPoint(x: 0.710, y: 0.501), CGPoint(x: 0.703, y: 0.508), CGPoint(x: 0.697, y: 0.623), CGPoint(x: 0.680, y: 0.727), CGPoint(x: 0.668, y: 0.781), CGPoint(x: 0.631, y: 0.873), CGPoint(x: 0.609, y: 0.908), CGPoint(x: 0.583, y: 0.936), CGPoint(x: 0.551, y: 0.951), CGPoint(x: 0.233, y: 0.953), CGPoint(x: 0.209, y: 0.946), CGPoint(x: 0.172, y: 0.915), CGPoint(x: 0.143, y: 0.871), CGPoint(x: 0.099, y: 0.755), CGPoint(x: 0.090, y: 0.746), CGPoint(x: 0.070, y: 0.739), CGPoint(x: 0.061, y: 0.729), CGPoint(x: 0.045, y: 0.579), CGPoint(x: 0.045, y: 0.457), CGPoint(x: 0.057, y: 0.343), CGPoint(x: 0.073, y: 0.280), CGPoint(x: 0.082, y: 0.263), CGPoint(x: 0.099, y: 0.203), CGPoint(x: 0.139, y: 0.130), CGPoint(x: 0.167, y: 0.092), CGPoint(x: 0.198, y: 0.059), CGPoint(x: 0.224, y: 0.049), CGPoint(x: 0.497, y: 0.049), CGPoint(x: 0.503, y: 0.061), CGPoint(x: 0.478, y: 0.104), CGPoint(x: 0.440, y: 0.233), CGPoint(x: 0.421, y: 0.353), CGPoint(x: 0.409, y: 0.489), CGPoint(x: 0.409, y: 0.623), CGPoint(x: 0.419, y: 0.730), CGPoint(x: 0.410, y: 0.741), CGPoint(x: 0.398, y: 0.744), CGPoint(x: 0.384, y: 0.758), CGPoint(x: 0.384, y: 0.790), CGPoint(x: 0.393, y: 0.830), CGPoint(x: 0.412, y: 0.866), CGPoint(x: 0.430, y: 0.882), CGPoint(x: 0.444, y: 0.880), CGPoint(x: 0.457, y: 0.866), CGPoint(x: 0.457, y: 0.854), CGPoint(x: 0.435, y: 0.816), CGPoint(x: 0.431, y: 0.800), CGPoint(x: 0.435, y: 0.790), CGPoint(x: 0.459, y: 0.769), CGPoint(x: 0.464, y: 0.753), CGPoint(x: 0.454, y: 0.532), CGPoint(x: 0.461, y: 0.400), CGPoint(x: 0.476, y: 0.275), CGPoint(x: 0.504, y: 0.164), CGPoint(x: 0.532, y: 0.097), CGPoint(x: 0.555, y: 0.070), CGPoint(x: 0.588, y: 0.052), CGPoint(x: 0.609, y: 0.031), CGPoint(x: 0.595, y: 0.017), CGPoint(x: 0.555, y: 0.002), CGPoint(x: 0.223, y: 0.000)],
    ]
}

/// The strap picture, drawn at the size it has in the reference.
struct NunaStrapIcon: View {
    var body: some View {
        NunaStrapIconShape().fill(style: FillStyle(eoFill: true)).frame(width: NunaStrapIconArt.width, height: NunaStrapIconArt.height)
    }
}

private struct NunaStrapIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = max(rect.width, rect.height)
        var p = Path()
        for c in NunaStrapIconArt.contours {
            guard let first = c.first else { continue }
            p.move(to: CGPoint(x: rect.minX + first.x * side, y: rect.minY + first.y * side))
            for pt in c.dropFirst() { p.addLine(to: CGPoint(x: rect.minX + pt.x * side, y: rect.minY + pt.y * side)) }
            p.closeSubpath()
        }
        return p
    }
}
#endif
