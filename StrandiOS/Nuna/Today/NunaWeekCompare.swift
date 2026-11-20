#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// "Charge & Effort": the last seven days of Charge and Effort for each of the seven days ending on the day shown, as a capsule (Charge) with a line across it
/// (Effort), both on the same 0 to 100 height. The colours read exactly as they do on the rings above.
struct NunaWeekCompare: View {
    let endDay: Date
    let effortScale: EffortScale

    @EnvironmentObject private var repo: Repository
    @State private var charge: [String: Double] = [:]
    @State private var effort: [String: Double] = [:]
    @State private var loaded = false
    @State private var selected: String?

    private struct Slot: Identifiable {
        let key: String
        let date: Date
        var id: String { key }
    }

    private var slots: [Slot] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: endDay)
        return (0..<7).reversed().compactMap { back in
            cal.date(byAdding: .day, value: -back, to: end).map { Slot(key: Repository.localDayKey($0), date: $0) }
        }
    }

    var body: some View {
        let days = slots
        let hasData = days.contains { charge[$0.key] != nil || effort[$0.key] != nil }
        NavigationLink(value: NunaTodayRoute.chargeEffort) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    // The same small tracked caps as the Stress monitor card, and an "i" in a ring where the arrow was.
                    HStack {
                        Text("Strain & Recovery").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textPrimary).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Text(verbatim: "i").font(.system(size: 10.5, weight: .bold, design: .serif)).foregroundStyle(NunaPalette.textSecondary)
                            .frame(width: 16, height: 16).overlay(Circle().strokeBorder(NunaPalette.textSecondary, lineWidth: 1.3))
                            .accessibilityHidden(true)
                    }
                    if loaded && !hasData {
                        Text("No readings in the last 7 days yet").font(.nuna(size: 14, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    } else if NunaThemePrefs.skin == .flow {
                        NunaCapsuleChart(start: days.first?.key ?? Repository.localDayKey(endDay), days: 7,
                                         charge: days.compactMap { s in charge[s.key].map { (s.key, $0) } },
                                         effort: days.compactMap { s in effort[s.key].map { (s.key, $0) } },
                                         effortScale: effortScale, selected: $selected, highlightLast: true)
                        NunaCapsuleLegend()
                    } else {
                        NunaChargeEffortLines(days: days.map { ($0.key, $0.date) }, charge: charge, effort: effort, effortScale: effortScale, selected: $selected)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: "\(repo.refreshSeq)-\(Repository.localDayKey(endDay))") { await load() }
    }

    private func load() async {
        async let c = repo.exploreSeries(key: "recovery", source: "my-whoop", days: 30)
        async let e = repo.exploreSeries(key: "strain", source: "my-whoop", days: 30)
        charge = Dictionary(await c.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        effort = Dictionary(await e.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        loaded = true
    }
}

/// Effort (blue, left axis) and Charge (right axis, in its three zone colours) over the last seven days as two lines with a ring on each day, the
/// day that is selected (the latest, until another is touched) standing on a lighter column with its figures in colour.
struct NunaChargeEffortLines: View {
    let days: [(key: String, date: Date)]
    let charge: [String: Double]
    let effort: [String: Double]
    let effortScale: EffortScale
    @Binding var selected: String?

    /// A softer blue than the Effort ring: it is a line on a card, and its figures are read small.
    private let blue = Color(hex: "#4890D8")

    private var effortTop: Double { effortScale == .whoop ? 21 : 100 }
    private var effortTicks: [Double] { effortScale == .whoop ? [0, 7, 14, 21] : [0, 25, 50, 75, 100] }
    private var litKey: String? { selected ?? days.last(where: { charge[$0.key] != nil || effort[$0.key] != nil })?.key ?? days.last?.key }

    private func weekday(_ d: Date, _ template: String) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: d)
    }

    var body: some View {
        GeometryReader { geo in
            // Measured on the reference: 30.6 pt in from the left and 31.6 from the right (seven columns of 39.4 pt), the 21 line 13 pt below the top
            // and the day names 15 and 29 pt under the 0 line.
            let left: CGFloat = 30.6, right: CGFloat = 31.6, top: CGFloat = 13, bottom: CGFloat = 39
            let w = geo.size.width, h = geo.size.height
            let plot = CGRect(x: left, y: top, width: w - left - right, height: h - top - bottom)
            let col = plot.width / CGFloat(max(days.count, 1))
            let cx: (Int) -> CGFloat = { plot.minX + (CGFloat($0) + 0.5) * col }
            let yc: (Double) -> CGFloat = { plot.maxY - CGFloat(min(max($0, 0), 100) / 100) * plot.height }
            let ye: (Double) -> CGFloat = { plot.maxY - CGFloat(min(max($0, 0), effortTop) / effortTop) * plot.height }
            let lit = days.firstIndex { $0.key == litKey }
            ZStack(alignment: .topLeading) {
                if let lit {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.white.opacity(0.095))
                        .frame(width: col - 8.7, height: h - plot.minY + 4.3).position(x: cx(lit), y: (plot.minY - 4.3 + h) / 2)
                }
                ForEach(0..<4, id: \.self) { i in
                    Rectangle().fill(Color.white.opacity(0.07)).frame(width: plot.width, height: 1.5)
                        .position(x: plot.midX, y: plot.minY + CGFloat(i) / 3 * plot.height)
                }
                // Effort's scale on the left in blue, Charge's on the right in the colour of each zone.
                ForEach(effortTicks, id: \.self) { t in
                    Text(verbatim: "\(Int(t))").font(.nunaBoldFigure(size: 10)).foregroundStyle(blue).position(x: 11, y: ye(t))
                }
                ForEach([(100.0, "100%", 100.0), (66.0, "66%", 50.0), (33.0, "33%", 10.0), (0.0, "0%", 10.0)], id: \.0) { t in
                    Text(verbatim: t.1).font(.nunaBoldFigure(size: 10)).foregroundStyle(zone(t.2)).position(x: w - 4, y: yc(t.0))
                }
                chargeLine(cx, yc, ye, plot)
                effortLine(cx, ye, yc, plot)
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    let on = day.key == litKey
                    // The name at 15 pt under the 0 line and the date, in DIN Bold, at 29 pt.
                    Text(verbatim: weekday(day.date, "EEE")).font(on ? .nunaStrong(size: 12) : .nuna(size: 10.5, weight: .semibold)).textCase(nil)
                        .foregroundStyle(on ? NunaPalette.textPrimary : Color(red: 0.59, green: 0.60, blue: 0.61)).fixedSize()
                        .position(x: cx(i), y: plot.maxY + 15)
                    Text(verbatim: weekday(day.date, "d")).font(.nunaBoldFigure(size: 10))
                        .foregroundStyle(on ? NunaPalette.textPrimary : Color(red: 0.59, green: 0.60, blue: 0.61)).fixedSize()
                        .position(x: cx(i), y: plot.maxY + 29)
                    Color.clear.frame(width: col, height: h).contentShape(Rectangle()).position(x: cx(i), y: h / 2)
                        .onTapGesture { selected = (selected == day.key) ? nil : day.key }
                }
            }
        }
        .frame(height: 245)
    }

    /// The zone colours of this chart, as sampled from the reference (a lime green, a soft yellow and a red a little deeper than the rings').
    private func zone(_ v: Double) -> Color {
        v >= 67 ? Color(red: 0.49, green: 0.86, blue: 0.38) : (v >= 34 ? Color(red: 0.95, green: 0.87, blue: 0.41) : Color(red: 0.84, green: 0.24, blue: 0.27))
    }

    @ViewBuilder private func chargeLine(_ cx: @escaping (Int) -> CGFloat, _ yc: @escaping (Double) -> CGFloat, _ ye: @escaping (Double) -> CGFloat, _ plot: CGRect) -> some View {
        let pts = days.enumerated().compactMap { i, d in charge[d.key].map { (i, d.key, $0) } }
        Path { p in for (n, pt) in pts.enumerated() { let c = CGPoint(x: cx(pt.0), y: yc(pt.2)); n == 0 ? p.move(to: c) : p.addLine(to: c) } }
            .stroke(NunaPalette.textSecondary.opacity(0.8), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        ForEach(pts, id: \.0) { pt in
            let on = pt.1 == litKey
            ring(zone(pt.2)).position(x: cx(pt.0), y: yc(pt.2))
            let off = labelOffsets(pt.1, yc, ye, plot).charge
            Text(verbatim: String(format: "%.0f%%", pt.2)).font(.nunaBoldFigure(size: 11.5))
                .foregroundStyle(zone(pt.2)).fixedSize().modifier(Halo())
                .position(x: cx(pt.0) + off.width, y: yc(pt.2) + off.height)
        }
    }

    @ViewBuilder private func effortLine(_ cx: @escaping (Int) -> CGFloat, _ ye: @escaping (Double) -> CGFloat, _ yc: @escaping (Double) -> CGFloat, _ plot: CGRect) -> some View {
        let pts = days.enumerated().compactMap { i, d in effort[d.key].map { (i, UnitFormatter.effortValue($0, scale: effortScale)) } }
        Path { p in for (n, pt) in pts.enumerated() { let c = CGPoint(x: cx(pt.0), y: ye(pt.1)); n == 0 ? p.move(to: c) : p.addLine(to: c) } }
            .stroke(blue.opacity(0.55), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        ForEach(pts, id: \.0) { pt in
            ring(blue).position(x: cx(pt.0), y: ye(pt.1))
            let off = labelOffsets(days[pt.0].key, yc, ye, plot).effort
            Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, pt.1)).font(.nunaBoldFigure(size: 11.5))
                .foregroundStyle(blue).fixedSize().modifier(Halo())
                .position(x: cx(pt.0) + off.width, y: ye(pt.1) + off.height)
        }
    }

    /// Where each figure sits relative to its ring. A lone figure goes above its ring (below only at the very top). With both on a day, the higher
    /// point takes its figure above and the lower one below, except near the 0 line, where "below" would land on the day names: then the lower one
    /// goes above its ring when there is room between the two, and otherwise steps out to the side of it.
    private func labelOffsets(_ key: String, _ yc: (Double) -> CGFloat, _ ye: (Double) -> CGFloat, _ plot: CGRect) -> (charge: CGSize, effort: CGSize) {
        let up = CGSize(width: 0, height: -13.5), down = CGSize(width: 0, height: 15)
        let c = charge[key].map { yc($0) }
        let e = effort[key].map { ye(UnitFormatter.effortValue($0, scale: effortScale)) }
        switch (c, e) {
        case let (c?, e?):
            let chargeUpper = c <= e
            let gap = abs(c - e), lowerY = max(c, e)
            let lower: CGSize
            if lowerY <= plot.maxY - 26 { lower = down }
            else if gap >= 28 { lower = up }
            else { lower = CGSize(width: chargeUpper ? 22 : -22, height: 0) }
            // Two rings on top of each other: the upper figure lifts a little higher so it clears both of them.
            let upper = gap < 16 ? CGSize(width: 0, height: -18) : up
            return chargeUpper ? (upper, lower) : (lower, upper)
        case let (c?, nil): return (c < plot.minY + 4 ? down : up, up)
        case let (nil, e?): return (up, e < plot.minY + 4 ? down : up)
        default: return (up, up)
        }
    }

    /// A faint dark edge behind a figure, so it stays readable where a line runs through it.
    private struct Halo: ViewModifier {
        func body(content: Content) -> some View {
            content.shadow(color: Color.black.opacity(0.7), radius: 1.5).shadow(color: Color.black.opacity(0.5), radius: 3)
        }
    }

    private func ring(_ color: Color) -> some View {
        Circle().fill(Color(hex: "#14181D")).overlay(Circle().stroke(color, lineWidth: 2.5)).frame(width: 11, height: 11)
    }
}
#endif
