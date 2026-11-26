#if os(iOS)
import SwiftUI
import Foundation
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

// The Lab Book as a summary: how many markers sit where, then every marker as a card under its status. Lab Book gives no verdicts of its own, so the
// three statuses are only about the range the person copied from their own report (or the WHO reference for weight and waist): inside it, outside it,
// or no range to judge by. A marker in the catalog with no reading yet sits last, as "No data available".

// MARK: - Status

enum NunaLabStatus: CaseIterable, Hashable {
    case outside, within, noRange, noData

    var title: LocalizedStringKey {
        switch self {
        case .outside: return "Out of range"
        case .within: return "Within range"
        case .noRange: return "No range"
        case .noData: return "No data available"
        }
    }

    /// The name as it is written on a card and over a section of the list.
    var cardTitle: LocalizedStringKey {
        switch self {
        case .outside: return "Out of Range"
        case .within: return "Within Range"
        case .noRange: return "No Range"
        case .noData: return "No Data Available"
        }
    }

    var tint: Color {
        switch self {
        case .outside: return NunaPalette.caution
        case .within: return NunaPalette.charge
        case .noRange: return NunaPalette.rest
        case .noData: return NunaPalette.textMuted
        }
    }

    /// The tints on the small range bar of a card: the same orange, a softer mint and a steel blue.
    var stripTint: Color {
        switch self {
        case .outside: return NunaPalette.caution
        case .within: return NunaPalette.rangeMint
        case .noRange: return NunaPalette.rangeSteel
        case .noData: return NunaPalette.textMuted
        }
    }

    var symbol: String {
        switch self {
        case .outside: return "exclamationmark"
        case .within: return "checkmark"
        case .noRange: return "circle.fill"
        case .noData: return "minus"
        }
    }

    /// The statuses a reading can have, in the order the summary lists them.
    static let readable: [NunaLabStatus] = [.within, .noRange, .outside]
}

extension NunaLabMarker {
    var status: NunaLabStatus {
        switch latestStatus {
        case .some(.within): return .within
        case .some: return .outside
        case .none: return .noRange
        }
    }
}

/// A status as a small tinted tag: a mark and its name, 18 pt high. The name has a capital on each word ("Out of Range") and is set in the figure face
/// (DIN Bold in the WHP skin), the same on the Health card, the summary tiles, the marker cards and the list.
struct NunaLabStatusChip: View {
    let status: NunaLabStatus
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: status.symbol).font(.nuna(size: status == .noRange ? 5.5 : 9, weight: .heavy))
            Text(status.cardTitle).font(.nunaBoldFigure(size: 10.5)).tracking(0.1).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(status.tint).padding(.leading, 7).padding(.trailing, 5).frame(height: 18)
        .background(status.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .fixedSize()
    }
}

// MARK: - Ring

/// Markers as a ring of one arc each, in the order given, with a thin dark gap between two arcs, a soft haze of each arc's colour just inside it and a
/// dark disc in the middle. The first arc is centred on the top, as on the ring it follows. With `onPick` the arcs can be touched: the arc picked
/// grows into a bright wedge that reaches the middle and the others dim.
struct NunaLabStatusRing<Center: View>: View {
    /// One colour for each marker, the ones that are within their range first.
    let tints: [Color]
    var lineWidth: CGFloat = 10
    /// The arc picked out, if any.
    var selected: Int?
    /// A touch on the ring: the arc under it, or nil for a touch in the middle or on the arc that is already picked.
    var onPick: ((Int?) -> Void)?
    let center: Center

    init(tints: [Color], lineWidth: CGFloat = 10, selected: Int? = nil, onPick: ((Int?) -> Void)? = nil, @ViewBuilder center: () -> Center) {
        self.tints = tints; self.lineWidth = lineWidth; self.selected = selected; self.onPick = onPick; self.center = center()
    }

    /// The tints for markers counted by status: within range, then no range, then outside it.
    static func tints(within: Int, noRange: Int, outside: Int) -> [Color] {
        Array(repeating: NunaLabStatus.within.tint, count: within) + Array(repeating: NunaLabStatus.noRange.tint, count: noRange)
            + Array(repeating: NunaLabStatus.outside.tint, count: outside)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                NunaLabRingCanvas(tints: tints, lineWidth: lineWidth, emph: NunaLabVector(tints.indices.map { $0 == selected ? 1.0 : 0.0 }))
                if onPick != nil {
                    Color.clear.contentShape(Circle()).onTapGesture(coordinateSpace: .local) { pick($0, geo.size) }
                }
                center
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pick(_ p: CGPoint, _ size: CGSize) {
        let n = tints.count
        guard n > 0 else { return }
        let dx = p.x - size.width / 2, dy = p.y - size.height / 2
        let outer = min(size.width, size.height) / 2
        let d = (dx * dx + dy * dy).squareRoot()
        guard d <= outer + 6 else { return }
        if d < outer * 0.3 { onPick?(nil); return }
        let step = 2 * Double.pi / Double(n)
        var t = atan2(Double(dy), Double(dx)) - (-Double.pi / 2 - step / 2)
        t = t.truncatingRemainder(dividingBy: 2 * .pi); if t < 0 { t += 2 * .pi }
        let i = min(Int(t / step), n - 1)
        onPick?(i == selected ? nil : i)
    }
}

/// A list of numbers that SwiftUI can animate from one list to another of the same length (the emphasis of each arc of the ring).
struct NunaLabVector: VectorArithmetic {
    var values: [Double]
    init(_ values: [Double]) { self.values = values }
    var count: Int { values.count }
    subscript(i: Int) -> Double { values[i] }
    var max: Double? { values.max() }

    static var zero: NunaLabVector { NunaLabVector([]) }
    private static func combine(_ a: NunaLabVector, _ b: NunaLabVector, _ f: (Double, Double) -> Double) -> NunaLabVector {
        let n = Swift.max(a.count, b.count)
        return NunaLabVector((0..<n).map { f($0 < a.count ? a.values[$0] : 0, $0 < b.count ? b.values[$0] : 0) })
    }
    static func + (a: NunaLabVector, b: NunaLabVector) -> NunaLabVector { combine(a, b, +) }
    static func - (a: NunaLabVector, b: NunaLabVector) -> NunaLabVector { combine(a, b, -) }
    static func += (a: inout NunaLabVector, b: NunaLabVector) { a = a + b }
    static func -= (a: inout NunaLabVector, b: NunaLabVector) { a = a - b }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

/// The drawing of the ring. Its emphasis (one number from 0 to 1 for each arc) is animatable, so a picked arc grows and the others fade as it changes.
private struct NunaLabRingCanvas: View, Animatable {
    let tints: [Color]
    let lineWidth: CGFloat
    var emph: NunaLabVector
    var animatableData: NunaLabVector {
        get { emph }
        set { emph = newValue }
    }

    /// The canvas reaches this far past the ring's frame on every side, so the glow and a grown wedge are not cut off at the edge.
    private static var bleed: CGFloat { 12 }

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - Self.bleed - lineWidth / 2 - 3   // the frame is 6 pt larger than the ring's outer diameter
            let inner = r - lineWidth / 2
            let disc = Path(ellipseIn: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
            ctx.fill(disc, with: .color(NunaPalette.canvas.opacity(0.28)))
            let n = tints.count
            func pt(_ radius: CGFloat, _ a: Double) -> CGPoint { CGPoint(x: c.x + radius * CGFloat(cos(a)), y: c.y + radius * CGFloat(sin(a))) }
            func arc(_ a0: Double, _ a1: Double, radius: CGFloat) -> Path {
                var p = Path(); p.addArc(center: c, radius: radius, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false); return p
            }
            func annulus(_ a0: Double, _ a1: Double, _ rIn: CGFloat, _ rOut: CGFloat) -> Path {
                var p = Path()
                p.addArc(center: c, radius: rOut, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                p.addArc(center: c, radius: rIn, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
                p.closeSubpath()
                return p
            }
            guard n > 0 else {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(NunaPalette.ringTrack), lineWidth: lineWidth)
                return
            }
            let e: [Double] = (0..<n).map { $0 < emph.count ? min(max(emph[$0], 0), 1) : 0 }
            let top = e.max() ?? 0
            /// How much of an arc's own brightness stays: all of it for the arc picked, a third for the others while one is picked.
            func keep(_ i: Int) -> Double { 1 - 0.68 * (top - e[i]) }
            let step = 2 * Double.pi / Double(n)
            let start = -Double.pi / 2 - step / 2
            let gap = Double(1.8 / r)
            // The haze just inside each arc.
            ctx.drawLayer { outer in
                outer.clip(to: disc)
                outer.drawLayer { layer in
                    layer.addFilter(.blur(radius: lineWidth * 1.1))
                    for (i, tint) in tints.enumerated() {
                        let a0 = start + Double(i) * step, a1 = a0 + step
                        layer.stroke(arc(a0, a1, radius: r - lineWidth * 0.5), with: .color(tint.opacity(0.32 * keep(i))), style: StrokeStyle(lineWidth: lineWidth * 2.2, lineCap: .butt))
                    }
                }
            }
            // The gap between two arcs is a soft shadow rather than a line: dark where it cuts the ring, thinning out and fading as it reaches into the haze.
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 1.1))
                for i in 0..<n {
                    let a = start + Double(i) * step
                    let outerPt = pt(r + lineWidth / 2 + 0.5, a), innerPt = pt(inner - lineWidth * 0.75, a)
                    var p = Path()
                    p.move(to: outerPt); p.addLine(to: innerPt)
                    layer.stroke(p, with: .linearGradient(Gradient(stops: [
                        .init(color: NunaPalette.canvas.opacity(0.85), location: 0),
                        .init(color: NunaPalette.canvas.opacity(0.6), location: 0.45),
                        .init(color: NunaPalette.canvas.opacity(0), location: 1)
                    ]), startPoint: outerPt, endPoint: innerPt), style: StrokeStyle(lineWidth: 2.2, lineCap: .butt))
                }
            }
            // The arcs: the one picked grows outward and inward into a bright wedge, with a fan of its colour down to the middle.
            for (i, tint) in tints.enumerated() {
                let a0 = start + Double(i) * step + gap / 2, a1 = max(start + Double(i + 1) * step - gap / 2, a0 + 0.001)
                let grow = CGFloat(e[i])
                let rOut = r + lineWidth / 2 + 7 * grow
                let rIn = rOut - (lineWidth + 30 * grow)
                if e[i] > 0.01 {
                    var fan = Path()
                    fan.move(to: c); fan.addLine(to: pt(rIn, a0)); fan.addArc(center: c, radius: rIn, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false); fan.closeSubpath()
                    ctx.fill(fan, with: .radialGradient(Gradient(colors: [tint.opacity(0), tint.opacity(0.34 * e[i])]), center: c, startRadius: 0, endRadius: rIn))
                }
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: tint.opacity(0.35 * keep(i)), radius: 5))
                    layer.fill(annulus(a0, a1, rIn, rOut), with: .color(tint.opacity(keep(i))))
                }
            }
        }
        .padding(-Self.bleed)
    }
}

/// The middle of the ring: how many biomarkers, and the way into the page. Sized from the ring's diameter.
struct NunaLabRingCenter: View {
    let count: Int
    let diameter: CGFloat
    var body: some View {
        let k = diameter / 156
        ZStack {
            Text(verbatim: "\(count)").font(.nuna(size: 28 * k, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                .offset(y: -12 * k)
            HStack(spacing: 3 * k) {
                Text("Biomarkers").font(.nuna(size: 10.5 * k, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                Image(systemName: "chevron.right").font(.nuna(size: 9 * k, weight: .bold))
            }
            .foregroundStyle(NunaPalette.textSecondary).offset(y: 19 * k)
        }
    }
}

// MARK: - Range strip

/// Where the latest reading sits against its range, on a short bar: orange below, mint inside, orange above, with a small white mark over the reading.
/// Without a range the bar is one steel-blue run and the mark shows where the reading is among the person's own. 120 x 23.7 pt: the mark takes the
/// top 7.7 pt, the bar is 16 pt high with a 4 pt line along its top, and the stretches are 0.7 pt apart.
struct NunaLabRangeStrip: View {
    /// 0...1 across the bar; the middle 60% is the range.
    let position: Double
    let ranged: Bool

    var body: some View {
        Canvas { ctx, size in
            let barTop: CGFloat = 7.7, h: CGFloat = 16, line: CGFloat = 4, gap: CGFloat = 0.7, end: CGFloat = 4, w = size.width
            func segment(_ x0: CGFloat, _ x1: CGFloat, _ color: Color, left: CGFloat, right: CGFloat) {
                let rect = CGRect(x: x0, y: barTop, width: max(x1 - x0, 1), height: h)
                let shape = UnevenRoundedRectangle(topLeadingRadius: left, bottomLeadingRadius: left, bottomTrailingRadius: right, topTrailingRadius: right, style: .continuous).path(in: rect)
                ctx.fill(shape, with: .color(color.opacity(0.15)))
                ctx.drawLayer { layer in
                    layer.clip(to: shape)
                    layer.fill(Path(CGRect(x: x0, y: barTop, width: x1 - x0, height: line)), with: .color(color))
                }
            }
            if ranged {
                let a = w * 0.2, b = w * 0.8
                segment(0, a - gap / 2, NunaLabStatus.outside.stripTint, left: end, right: 0)
                segment(a + gap / 2, b - gap / 2, NunaLabStatus.within.stripTint, left: 0, right: 0)
                segment(b + gap / 2, w, NunaLabStatus.outside.stripTint, left: 0, right: end)
            } else {
                segment(0, w, NunaLabStatus.noRange.stripTint, left: end, right: end)
            }
            // The mark: a white triangle with a dark rim, its point on the top of the bar.
            let x = min(max(CGFloat(position) * w, 6), w - 6)
            var tri = Path()
            tri.move(to: CGPoint(x: x - 4, y: 1.7)); tri.addLine(to: CGPoint(x: x + 4, y: 1.7)); tri.addLine(to: CGPoint(x: x, y: 6.4)); tri.closeSubpath()
            ctx.stroke(tri, with: .color(NunaPalette.canvas.opacity(0.9)), style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
            ctx.fill(tri, with: .color(NunaPalette.textPrimary))
        }
        .frame(width: 120, height: 23.7)
        .accessibilityHidden(true)
    }
}

// MARK: - The card on the Health tab

/// The Lab Book on the Health tab: how many markers sit inside their range, outside it, or have none to judge by, with the date of the last result and
/// the total as a ring. It opens the Lab Book.
struct NunaLabBookCard: View {
    let rows: [LabMarkerRow]

    @EnvironmentObject private var profile: ProfileStore

    private var markers: [NunaLabMarker] { NunaLabGrouping.markers(rows, reference: .init(heightCm: profile.heightCm, sex: profile.sex)) }

    /// The left column is 150 pt wide: the chips, then the counts in a column that starts 134 pt in. The ring takes the rest, up to 156 pt.
    private let leftColumn: CGFloat = 150

    var body: some View {
        let ms = markers
        let counts = Dictionary(grouping: ms, by: \.status).mapValues(\.count)
        let last = rows.map(\.takenAt).max()
        NavigationLink(value: NunaTodayRoute.labBook) {
            NunaCard(small: true, padding: EdgeInsets(top: 15, leading: 16, bottom: 14, trailing: 16)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Lab Book").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    GeometryReader { geo in
                        let ring = min(156, geo.size.width - leftColumn - 8)
                        HStack(alignment: .top, spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                VStack(alignment: .leading, spacing: 18) {
                                    ForEach(NunaLabStatus.readable, id: \.self) { s in
                                        HStack(spacing: 0) {
                                            NunaLabStatusChip(status: s)
                                            Spacer(minLength: 6)
                                            // The count is never cut: a fixed one-digit width turned 8 results into "…" at 10 or more, so the chip gives way instead.
                                            Text(verbatim: "\(counts[s] ?? 0)").font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                                .lineLimit(1).fixedSize().layoutPriority(1).frame(minWidth: 16, minHeight: 18, alignment: .trailing)
                                        }
                                        .frame(height: 18)
                                    }
                                }
                                .padding(.top, 23)
                                Spacer(minLength: 0)
                                Group {
                                    if let last {
                                        Text(verbatim: String(localized: "Last updated: \(LabBookFormat.day(last))"))
                                    } else {
                                        Text("No results yet")
                                    }
                                }
                                .font(.nuna(size: 11, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).padding(.bottom, 18)
                            }
                            .frame(width: leftColumn, height: ring + 4, alignment: .topLeading)
                            Spacer(minLength: 0)
                            NunaLabStatusRing(tints: NunaLabStatusRing<EmptyView>.tints(within: counts[.within] ?? 0, noRange: counts[.noRange] ?? 0, outside: counts[.outside] ?? 0), lineWidth: 10) {
                                NunaLabRingCenter(count: ms.count, diameter: ring)
                            }
                            .frame(width: ring + 6, height: ring + 6).padding(.top, 1).padding(.trailing, -3)
                        }
                    }
                    .frame(height: 160)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - One marker as a card

/// A marker as a card that opens its page: name, latest value with its unit, the status, and the strip that shows where the reading sits. The parts
/// sit at fixed places (name baseline 24.8 pt from the top, value baseline 61 pt, status 75.3 pt, the strip 53.5 pt) on a card 109.3 pt high, the way
/// the lab cards of the reference are laid out; a long name scales down on its one line.
struct NunaLabMarkerCard: View {
    let marker: NunaLabMarker

    var body: some View {
        let m = marker, latest = m.latest, value = latest?.value
        NavigationLink { NunaLabMarkerHost(markerKey: m.key, isBody: m.category == .bodyMeasurement) } label: {
            ZStack {
                layer(top: 24.8, baseline: true, leading: 12, trailing: 40, alignment: .leading) {
                    Text(verbatim: m.name).font(.nuna(size: 14, weight: .medium)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(1).minimumScaleFactor(0.75)
                }
                layer(top: 12.7, baseline: false, leading: 0, trailing: 16, alignment: .trailing) {
                    Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).frame(width: 16, height: 16)
                }
                layer(top: 61, baseline: true, leading: 12, trailing: 0, alignment: .leading) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: latest.map(m.text) ?? "—").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                        Text(verbatim: m.unit).font(.nuna(size: 15, weight: .medium)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1)
                    }
                }
                layer(top: 75.3, baseline: false, leading: 12, trailing: 0, alignment: .leading) { NunaLabStatusChip(status: m.status) }
                if let v = value {
                    layer(top: 53.5, baseline: false, leading: 0, trailing: 16, alignment: .trailing) { strip(m, v) }
                }
            }
            .frame(maxWidth: .infinity).frame(height: 109.3)
            .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
        }.buttonStyle(.plain)
    }

    /// One part of the card, put `top` pt from the card's top edge (or, with `baseline`, with its first baseline there).
    private func layer<Content: View>(top: CGFloat, baseline: Bool, leading: CGFloat, trailing: CGFloat, alignment: Alignment, @ViewBuilder _ content: () -> Content) -> some View {
        Group {
            if baseline { content().alignmentGuide(.top) { $0[.firstTextBaseline] } } else { content() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment == .trailing ? .topTrailing : .topLeading)
        .padding(.top, top).padding(.leading, leading).padding(.trailing, trailing)
    }

    @ViewBuilder private func strip(_ m: NunaLabMarker, _ v: Double) -> some View {
        if let r = m.range {
            NunaLabRangeStrip(position: Self.position(v, r), ranged: true)
        } else {
            let values = m.numeric.compactMap(\.value)
            if let lo = values.min(), let hi = values.max(), hi > lo {
                NunaLabRangeStrip(position: 0.1 + 0.8 * (v - lo) / (hi - lo), ranged: false)
            }
        }
    }

    /// Where a value sits on the strip: the middle 60% is the range, the sides are what is below and above it.
    static func position(_ v: Double, _ r: NunaLabRange) -> Double {
        let span = max(r.high - r.low, 0.000_1)
        if v < r.low { return max(0.02, 0.2 - 0.18 * min((r.low - v) / (span * 0.5), 1)) }
        if v > r.high { return min(0.98, 0.8 + 0.18 * min((v - r.high) / (span * 0.5), 1)) }
        return 0.2 + 0.6 * (v - r.low) / span
    }
}

// MARK: - The summary page

/// The Lab Book page, and the same page for one test (`testId`): the ring and the three counts, a line about where the markers sit, a search and the
/// filter, then the markers under their status. The whole book also shows the latest tests and the way to add a result.
struct NunaLabSummaryPage: View {
    let title: LocalizedStringKey
    /// The test to show (`NunaLabTests.key`); nil shows every reading.
    var testId: String?

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var rows: [LabMarkerRow] = []
    @State private var loaded = false
    @State private var addingMarker: MarkerDefinition?
    @State private var sort: Sort = .status
    @State private var filter: Set<NunaLabStatus> = []
    @State private var query = ""
    @State private var filtering = false
    @FocusState private var searching: Bool

    enum Sort { case status, alphabetical }

    private var shown: [LabMarkerRow] { testId.map { id in rows.filter { NunaLabTests.key($0) == id } } ?? rows }
    private var markers: [NunaLabMarker] { NunaLabGrouping.markers(shown, reference: .init(heightCm: profile.heightCm, sex: profile.sex)) }

    /// Catalog markers with no reading yet, for the "No data available" section of the whole book.
    private var missing: [MarkerDefinition] {
        guard testId == nil else { return [] }
        let have = Set(markers.map(\.key))
        return MarkerCatalog.builtIn.filter { $0.key != LabBookProjection.bpDiastolicKey && $0.category != .bodyMeasurement && !have.contains($0.key) }
    }

    var body: some View {
        let ms = markers
        NunaDetailScreen(title) {
            if !loaded {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                header(ms)
                insight(ms)
                searchField
                filterRow
                list(ms)
            }
        }
        .appears(when: loaded)
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") { rows = await NunaLabStore.load(repo); loaded = true }
        .sheet(item: $addingMarker) { def in
            NunaLabAddSheet(preselect: def.key, preselectName: def.displayName, preselectUnit: def.canonicalUnit) { drafts in
                await NunaLabStore.save(drafts, repo: repo); rows = await NunaLabStore.load(repo)
            }
            .nunaSheetChrome(detents: [.large])
        }
        .sheet(isPresented: $filtering) {
            NunaLabFilterSheet(sort: $sort, filter: $filter)
                .presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header

    private func header(_ ms: [NunaLabMarker]) -> some View {
        let counts = Dictionary(grouping: ms, by: \.status).mapValues(\.count)
        let last = shown.map(\.takenAt).max()
        return HStack(alignment: .center, spacing: 12) {
            NunaLabStatusRing(tints: NunaLabStatusRing<EmptyView>.tints(within: counts[.within] ?? 0, noRange: counts[.noRange] ?? 0, outside: counts[.outside] ?? 0), lineWidth: 10) {
                NunaLabRingCenter(count: ms.count, diameter: 156)
            }
            .frame(width: 162, height: 162).padding(-3)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(NunaLabStatus.readable, id: \.self) { s in
                    HStack(spacing: 0) {
                        NunaLabStatusChip(status: s)
                        Spacer(minLength: 6)
                        Text(verbatim: "\(counts[s] ?? 0)").font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            .lineLimit(1).fixedSize().layoutPriority(1).frame(height: 18)
                    }
                    .frame(height: 18)
                }
                if let last {
                    Text(verbatim: String(localized: "Last updated: \(LabBookFormat.day(last))")).font(.nuna(size: 11, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
        }
    }

    /// One plain sentence about where the markers sit, in an outlined card.
    private func insight(_ ms: [NunaLabMarker]) -> some View {
        let judged = ms.filter { $0.latestStatus != nil }
        let outside = judged.filter { $0.latestStatus != .within }.count
        let text: String
        if judged.isEmpty { text = String(localized: "Add the range from your own report with a result, and this page shows which markers sit inside it.") }
        else if outside == 0 { text = String(localized: "Every marker with a range sits inside it.") }
        else { text = String(localized: "\(outside) of \(judged.count) markers with a range sit outside it. The range comes from your own report; Lab Book doesn't judge it.") }
        return VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: text).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(NunaPalette.effortModerate.opacity(0.55), lineWidth: 1.5))
    }

    // MARK: Search and filter

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
            TextField("", text: $query, prompt: Text("Search for LDL, ferritin, etc.").foregroundStyle(NunaPalette.textMuted))
                .font(.nunaWords(size: 16)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .focused($searching).submitLabel(.search).autocorrectionDisabled().textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textMuted) }
                    .buttonStyle(.plain).accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 16).frame(height: 54)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
        .contentShape(Rectangle()).onTapGesture { searching = true }
    }

    private var filterRow: some View {
        Button { filtering = true } label: {
            HStack {
                Text("Filter & sort").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                if !filter.isEmpty {
                    Text(verbatim: "\(filter.count)").font(.nuna(size: 11, weight: .heavy)).foregroundStyle(NunaPalette.onAccent)
                        .frame(minWidth: 20, minHeight: 20).background(NunaPalette.accent, in: Capsule())
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            }
            .padding(.horizontal, 20).frame(height: 54).contentShape(Rectangle())
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: List

    private func visible(_ status: NunaLabStatus) -> Bool { filter.isEmpty || filter.contains(status) }

    private func list(_ ms: [NunaLabMarker]) -> some View {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ name: String) -> Bool { word.isEmpty || name.localizedCaseInsensitiveContains(word) }
        let found = ms.filter { visible($0.status) && matches($0.name) }
        let gaps = missing.filter { visible(.noData) && matches($0.displayName) }
        let byName: (NunaLabMarker, NunaLabMarker) -> Bool = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 16) {
            if sort == .alphabetical {
                let items: [(name: String, view: AnyView)] =
                    found.map { m in (m.name, AnyView(markerCard(m))) } + gaps.map { d in (d.displayName, AnyView(emptyCard(d))) }
                ForEach(items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, id: \.name) { $0.view }
            } else {
                ForEach([NunaLabStatus.outside, .within, .noRange], id: \.self) { s in
                    let group = found.filter { $0.status == s }.sorted(by: byName)
                    if !group.isEmpty {
                        section(s.cardTitle, count: group.count)
                        ForEach(group) { markerCard($0) }
                    }
                }
                if !gaps.isEmpty {
                    section(NunaLabStatus.noData.cardTitle, count: gaps.count)
                    ForEach(gaps, id: \.key) { emptyCard($0) }
                }
            }
            if found.isEmpty && gaps.isEmpty {
                Text("No marker matches.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
    }

    private func section(_ title: LocalizedStringKey, count: Int) -> some View {
        VStack(spacing: 12) {
            NunaDivider().padding(.top, 8)
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Spacer(minLength: 8)
                Text(count == 1 ? LocalizedStringKey("1 Biomarker") : LocalizedStringKey("\(count) Biomarkers")).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
    }

    private func markerCard(_ m: NunaLabMarker) -> some View { NunaLabMarkerCard(marker: m) }

    /// A catalog marker with nothing recorded yet: its name and a dash, and a touch opens the sheet to add its first reading.
    private func emptyCard(_ def: MarkerDefinition) -> some View {
        Button { addingMarker = def } label: {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(verbatim: def.key == LabBookProjection.bpSystolicKey ? String(localized: "Blood pressure") : def.displayName)
                            .font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Image(systemName: "plus").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    Text(verbatim: "--").font(.nuna(size: 34, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
    }
}

// MARK: - Filter and sort

/// How the list is sorted (by status, or A to Z) and which statuses it shows. Taking effect as the boxes are ticked.
struct NunaLabFilterSheet: View {
    @Binding var sort: NunaLabSummaryPage.Sort
    @Binding var filter: Set<NunaLabStatus>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Filter & sort").font(.nuna(size: 18, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity)
                NunaRuledHeader("Sort by")
                VStack(spacing: 10) {
                    choice("Status", on: sort == .status) { sort = .status }
                    choice("A to Z", on: sort == .alphabetical) { sort = .alphabetical }
                }
                NunaRuledHeader("Filter by status")
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(NunaLabStatus.allCases, id: \.self) { s in box(s) }
                }
                .padding(.top, 4)
                if !filter.isEmpty {
                    Button { filter = [] } label: {
                        Text("Clear all").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity).frame(height: 44)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 26).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    private func choice(_ title: LocalizedStringKey, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    private func box(_ s: NunaLabStatus) -> some View {
        let on = filter.contains(s)
        return Button { if on { filter.remove(s) } else { filter.insert(s) } } label: {
            HStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? NunaPalette.accent : NunaPalette.textPrimary, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? NunaPalette.accent : Color.clear))
                    .frame(width: 34, height: 34)
                    .overlay { if on { Image(systemName: "checkmark").font(.nuna(size: 16, weight: .heavy)).foregroundStyle(NunaPalette.onAccent) } }
                Text(s.title).font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                Spacer(minLength: 0)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
}
#endif
