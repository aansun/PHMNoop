#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Charge and Effort, one capsule per day. The tall capsule is Charge: a faint track over 0 to 100 that fills from the bottom up to the
/// day's value in the colour its ring had that day. The short line across it is Effort, at its own value on the same 0 to 100 height, in
/// the blue of its level. A line above the fill means the day asked for more than the morning had; below it, there was room to spare.
///
/// Touching a capsule (or dragging across) selects a day, and its two figures appear above it; nothing else is written on the chart, so
/// a week and a year read the same way. Past about six weeks the tracks are dropped and the capsules thin out into bars with a tick,
/// which keeps a year readable.
struct NunaCapsuleChart: View {
    let start: String
    let days: Int
    let charge: NunaDaySeries
    let effort: NunaDaySeries          // stored 0-100
    let effortScale: EffortScale
    var plotHeight: CGFloat = 118
    /// The day picked by touch. nil leaves the chart read-only, with no room kept for the figures.
    var selected: Binding<String?>?
    /// Stresses the newest day with a soft backdrop (the week on Today).
    var highlightLast = false

    private let labelBand: CGFloat = 38
    private let axisBand: CGFloat = 24
    /// Room at both ends so the first and last Effort lines are not cut off.
    private let sidePad: CGFloat = 8

    private var dense: Bool { days > 45 }
    private var keys: [String] { (0..<max(days, 1)).map { TrendInsights.shift(start, by: $0) ?? start } }
    private var chargeBy: [String: Double] { Dictionary(charge.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l }) }
    private var effortBy: [String: Double] { Dictionary(effort.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l }) }

    private var hasLabelBand: Bool { selected != nil }
    private var topInset: CGFloat { hasLabelBand ? labelBand : 6 }

    var body: some View {
        let ks = keys, cb = chargeBy, eb = effortBy
        let sel = selected?.wrappedValue
        let h = topInset + plotHeight + axisBand
        GeometryReader { geo in
            Canvas { ctx, size in
                draw(&ctx, size: size, keys: ks, charge: cb, effort: eb, selected: sel)
            }
            .contentShape(Rectangle())
            // Alongside the scroll view, not instead of it: a swipe that starts on the chart still scrolls the page.
            .simultaneousGesture(selection(width: geo.size.width))
        }
        .frame(height: h)
        .accessibilityElement()
        .accessibilityLabel(Text("Charge and Effort"))
    }

    // MARK: Touch

    private func selection(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { v in
            guard let selected else { return }
            // A mostly vertical drag is the page being scrolled, not a day being picked.
            if abs(v.translation.height) > 10, abs(v.translation.height) > abs(v.translation.width) { return }
            let slot = (width - sidePad * 2) / CGFloat(max(days, 1))
            let i = Int(min(max((v.location.x - sidePad) / max(slot, 1), 0), CGFloat(days - 1)))
            let day = TrendInsights.shift(start, by: i)
            if selected.wrappedValue != day { selected.wrappedValue = day }
        }
    }

    // MARK: Drawing

    private func zoneColor(_ v: Double) -> Color { nunaChargeColor(v) }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, keys: [String], charge: [String: Double], effort: [String: Double], selected: String?) {
        let n = max(keys.count, 1)
        let slot = (size.width - sidePad * 2) / CGFloat(n)
        let top = topInset, base = top + plotHeight
        let capW = min(max(slot * (dense ? 0.7 : 0.62), 1.4), 24)
        func y(_ v: Double) -> CGFloat { base - plotHeight * CGFloat(min(max(v, 0), 100)) / 100 }

        // The zone edges of Charge, so the fill colour has something to be read against.
        for edge in [33.0, 67.0] {
            var p = Path(); p.move(to: CGPoint(x: 0, y: y(edge))); p.addLine(to: CGPoint(x: size.width, y: y(edge)))
            ctx.stroke(p, with: .color(NunaPalette.hairline.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
        var floor = Path(); floor.move(to: CGPoint(x: 0, y: base)); floor.addLine(to: CGPoint(x: size.width, y: base))
        ctx.stroke(floor, with: .color(NunaPalette.hairline), lineWidth: 1.5)

        if highlightLast, let last = keys.indices.last {
            let r = CGRect(x: sidePad + slot * CGFloat(last) + 3, y: top - (hasLabelBand ? labelBand - 4 : 0), width: slot - 6,
                           height: plotHeight + (hasLabelBand ? labelBand - 4 : 0) + axisBand - 2)
            ctx.fill(Path(roundedRect: r, cornerRadius: 14), with: .color(NunaPalette.ink.opacity(0.06)))
        }
        if let selected, let i = keys.firstIndex(of: selected) {
            let r = CGRect(x: sidePad + slot * CGFloat(i) + (slot > 12 ? 2 : -1), y: top - (labelBand - 4), width: max(slot - (slot > 12 ? 4 : -2), 4),
                           height: plotHeight + labelBand - 4 + axisBand - 2)
            ctx.fill(Path(roundedRect: r, cornerRadius: min(14, r.width / 2)), with: .color(NunaPalette.ink.opacity(0.06)))
        }

        for (i, key) in keys.enumerated() {
            let cx = sidePad + slot * CGFloat(i) + slot / 2
            let capRect = CGRect(x: cx - capW / 2, y: top, width: capW, height: plotHeight)
            let radius = dense ? min(capW / 2, 2) : capW / 2
            if !dense { ctx.fill(Path(roundedRect: capRect, cornerRadius: radius), with: .color(NunaPalette.ink.opacity(0.08))) }
            let c = charge[key], e = effort[key]
            if let c {
                let fillH = max(dense ? 1.5 : capW, plotHeight * CGFloat(min(max(c, 0), 100)) / 100)
                var layer = ctx
                layer.clip(to: Path(roundedRect: capRect, cornerRadius: radius))
                let isSel = selected == nil || selected == key
                layer.fill(Path(CGRect(x: capRect.minX, y: base - fillH, width: capW, height: fillH)), with: .color(zoneColor(c).opacity(isSel ? 1 : 0.55)))
            }
            if let e {
                let markW = capW + (dense ? 2 : (slot < 20 ? 6 : 10)), markH: CGFloat = dense ? 2.5 : 5
                if !dense {
                    let halo = CGRect(x: cx - markW / 2 - 2, y: y(e) - markH / 2 - 2, width: markW + 4, height: markH + 4)
                    ctx.fill(Path(roundedRect: halo, cornerRadius: halo.height / 2), with: .color(NunaPalette.canvas.opacity(0.9)))
                }
                let r = CGRect(x: cx - markW / 2, y: y(e) - markH / 2, width: markW, height: markH)
                ctx.fill(Path(roundedRect: r, cornerRadius: markH / 2), with: .color(nunaEffortColor(e)))
            }
            if selected == key { figures(&ctx, at: cx, width: size.width, charge: c, effort: e) }
        }
        if selected == nil && hasLabelBand {
            ctx.draw(Text("Touch a day for its figures").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted),
                     at: CGPoint(x: sidePad, y: 14), anchor: .leading)
        }
        axis(&ctx, size: size, keys: keys, slot: slot, base: base)
    }

    /// The two figures of a day, stacked above the capsule. Both are written in the main text colour, so they read on any card; a dot in the
    /// colour of the score (Charge's zone, Effort's blue) says which is which.
    private func figures(_ ctx: inout GraphicsContext, at cx: CGFloat, width: CGFloat, charge: Double?, effort: Double?) {
        let cText = charge.map { "\(Int($0.rounded()))%" } ?? "–"
        let eText = effort.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "–"
        let rows: [(String, Color, CGFloat)] = [(cText, charge.map(zoneColor) ?? NunaPalette.textMuted, 9), (eText, effort.map(nunaEffortColor) ?? NunaPalette.textMuted, 25)]
        for (text, dot, y) in rows {
            let resolved = ctx.resolve(Text(verbatim: text).font(.nuna(size: 13, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary))
            let w = resolved.measure(in: CGSize(width: 120, height: 20)).width
            let total = w + 13
            let left = min(max(cx - total / 2, 2), width - total - 2)
            ctx.fill(Path(ellipseIn: CGRect(x: left, y: y - 3.5, width: 7, height: 7)), with: .color(dot))
            ctx.draw(resolved, at: CGPoint(x: left + 13, y: y), anchor: .leading)
        }
    }

    private func axis(_ ctx: inout GraphicsContext, size: CGSize, keys: [String], slot: CGFloat, base: CGFloat) {
        let n = keys.count
        let labelled: [(Int, String)]
        if n <= 7 {
            labelled = keys.enumerated().map { ($0.offset, Self.weekday($0.element)) }
        } else if n <= 45 {
            labelled = keys.enumerated().filter { (n - 1 - $0.offset) % 7 == 0 }.map { ($0.offset, Self.dayMonth($0.element)) }
        } else {
            let firsts = keys.enumerated().filter { $0.element.hasSuffix("-01") }
            let step = firsts.count > 8 ? 2 : 1
            labelled = firsts.enumerated().filter { (firsts.count - 1 - $0.offset) % step == 0 }.map { ($0.element.offset, Self.month($0.element.element)) }
        }
        for (i, text) in labelled {
            let x = min(max(sidePad + slot * CGFloat(i) + slot / 2, 18), size.width - 18)
            let latest = (i == n - 1) && highlightLast
            ctx.draw(Text(verbatim: text).font(.nuna(size: 11.5, weight: latest ? .bold : .semibold))
                .foregroundStyle(latest ? NunaPalette.textPrimary : NunaPalette.textMuted), at: CGPoint(x: x, y: base + 14), anchor: .center)
        }
    }

    // MARK: Labels

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template); return f
    }
    private static func weekday(_ key: String) -> String { NunaDayFormat.parse(key).map { formatter("EEE").string(from: $0) } ?? "" }
    private static func dayMonth(_ key: String) -> String { NunaDayFormat.parse(key).map { formatter("d MMM").string(from: $0) } ?? "" }
    private static func month(_ key: String) -> String { NunaDayFormat.parse(key).map { formatter("MMM").string(from: $0) } ?? "" }
}

/// What the capsule and the line mean, drawn the way they appear in the chart.
struct NunaCapsuleLegend: View {
    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(stops: [.init(color: NunaPalette.scoreHigh, location: 0.34), .init(color: NunaPalette.scoreMid, location: 0.34),
                                                 .init(color: NunaPalette.scoreMid, location: 0.67), .init(color: NunaPalette.scoreLow, location: 0.67)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 9, height: 16)
                Text("Charge").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(NunaScoreStyle.effortSeries).frame(width: 16, height: 4)
                Text("Effort").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
    }
}
#endif
