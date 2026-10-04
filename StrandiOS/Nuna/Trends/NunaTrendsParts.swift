#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

typealias NunaDaySeries = [(day: String, value: Double)]

/// Maps a window of `count` calendar days onto 0...1 along the x axis; `index` is the day offset from the window start.
private func unitX(_ index: Int, _ count: Int) -> CGFloat { count <= 1 ? 0.5 : CGFloat(index) / CGFloat(count - 1) }

/// Day offset of `day` from `start` (both yyyy-MM-dd).
private func dayIndex(_ day: String, from start: String) -> Int? {
    guard let a = NunaDayFormat.parse(start), let b = NunaDayFormat.parse(day) else { return nil }
    return Calendar(identifier: .gregorian).dateComponents([.day], from: a, to: b).day
}

enum NunaDayFormat {
    static let parser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
    static func parse(_ s: String) -> Date? { parser.date(from: s) }
}

/// Start, middle and end dates under a chart, in day and month.
struct NunaDayAxis: View {
    let first: String
    let last: String
    var body: some View {
        if let a = NunaDayFormat.parse(first), let b = NunaDayFormat.parse(last) {
            let mid = Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2)
            HStack {
                Text(verbatim: nunaAxisDate(a)); Spacer(); Text(verbatim: nunaAxisDate(mid)); Spacer(); Text(verbatim: nunaAxisDate(b))
            }
            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
        }
    }
}

/// Bars (one per day, e.g. Effort) with a line over them (e.g. Charge) on one shared day axis. Every mark is a
/// stored reading; a day without a reading has no bar and the line skips it. Touch or drag to read a day.
struct NunaComboChart: View {
    let start: String
    let days: Int
    let bars: NunaDaySeries
    let barMax: Double
    let line: NunaDaySeries
    let lineMax: Double
    var barColor: Color = NunaPalette.effort
    var lineColor: Color = NunaPalette.charge
    @Binding var selected: String?
    var height: CGFloat = 150
    var interactive = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Canvas { ctx, size in
                var grid = Path()
                for i in 1...2 { let y = size.height * CGFloat(i) / 3; grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
                ctx.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)
                let slot = size.width / CGFloat(max(days, 1))
                let bw = max(2, min(10, slot * 0.62))
                for b in bars {
                    guard let i = dayIndex(b.day, from: start), i >= 0, i < days else { continue }
                    let x = (CGFloat(i) + 0.5) * slot
                    let bh = max(2, size.height * CGFloat(min(b.value / max(barMax, 0.0001), 1)))
                    let r = CGRect(x: x - bw / 2, y: size.height - bh, width: bw, height: bh)
                    ctx.fill(Path(roundedRect: r, cornerRadius: min(3, bw / 2)), with: .color(barColor.opacity(b.day == selected ? 1 : 0.55)))
                }
                var p = Path(); var started = false
                var last: CGPoint?
                for l in line {
                    guard let i = dayIndex(l.day, from: start), i >= 0, i < days else { continue }
                    let pt = CGPoint(x: (CGFloat(i) + 0.5) * slot, y: size.height * (1 - CGFloat(min(max(l.value / max(lineMax, 0.0001), 0), 1))))
                    if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                    last = pt
                }
                ctx.stroke(p, with: .color(lineColor), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                if let s = selected, let i = dayIndex(s, from: start) {
                    let x = (CGFloat(i) + 0.5) * slot
                    var v = Path(); v.move(to: CGPoint(x: x, y: 0)); v.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(v, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                } else if let last {
                    ctx.fill(Path(ellipseIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10)), with: .color(.white))
                }
            }
            .contentShape(Rectangle())
            .gesture(interactive ? DragGesture(minimumDistance: 0).onChanged { v in
                let slot = w / CGFloat(max(days, 1))
                let i = Int((v.location.x / max(slot, 1)).rounded(.down))
                guard i >= 0, i < days, let d0 = NunaDayFormat.parse(start),
                      let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: i, to: d0) else { return }
                selected = NunaDayFormat.parser.string(from: d)
            } : nil)
            .frame(width: w, height: h)
        }
        .frame(height: height)
    }
}

/// Two or more lines scaled to the same 0...1 box (each by its own maximum), for "two lines moving together".
struct NunaMultiLineChart: View {
    struct Line { let series: NunaDaySeries; let max: Double; let color: Color }
    let start: String
    let days: Int
    let lines: [Line]
    var height: CGFloat = 130

    var body: some View {
        Canvas { ctx, size in
            var grid = Path()
            for i in 1...2 { let y = size.height * CGFloat(i) / 3; grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
            ctx.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)
            let slot = size.width / CGFloat(max(days, 1))
            for line in lines {
                var p = Path(); var started = false; var last: CGPoint?
                for r in line.series {
                    guard let i = dayIndex(r.day, from: start), i >= 0, i < days else { continue }
                    let pt = CGPoint(x: (CGFloat(i) + 0.5) * slot, y: size.height * (1 - CGFloat(min(max(r.value / max(line.max, 0.0001), 0), 1))))
                    if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                    last = pt
                }
                ctx.stroke(p, with: .color(line.color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                if let last { ctx.fill(Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)), with: .color(.white)) }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A tiny line with its newest point marked.
struct NunaSpark: View {
    let values: [Double]
    var color: Color = .white
    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return }
            let span = max(hi - lo, 0.0001)
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: 4 + (size.height - 8) * (1 - CGFloat((values[i] - lo) / span)))
            }
            var p = Path(); p.move(to: pt(0))
            for i in 1..<values.count { p.addLine(to: pt(i)) }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            let e = pt(values.count - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - 3.5, y: e.y - 3.5, width: 7, height: 7)), with: .color(.white))
        }
        .accessibilityHidden(true)
    }
}

/// One dot per day (x, y) with the straight line the correlation fits. Axis meaning is given by the caption.
struct NunaScatter: View {
    let points: [(x: Double, y: Double)]
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    var slope: Double?
    var intercept: Double?
    var color: Color = NunaPalette.charge
    var body: some View {
        Canvas { ctx, size in
            let pad: CGFloat = 10
            func mx(_ v: Double) -> CGFloat { pad + CGFloat((v - xRange.lowerBound) / max(xRange.upperBound - xRange.lowerBound, 0.0001)) * (size.width - pad * 2) }
            func my(_ v: Double) -> CGFloat { size.height - pad - CGFloat((v - yRange.lowerBound) / max(yRange.upperBound - yRange.lowerBound, 0.0001)) * (size.height - pad * 2) }
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14), with: .color(.black.opacity(0.28)))
            var grid = Path()
            for i in 1...3 {
                let y = size.height * CGFloat(i) / 4, x = size.width * CGFloat(i) / 4
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            ctx.stroke(grid, with: .color(.white.opacity(0.06)), lineWidth: 1)
            if let slope, let intercept {
                var p = Path()
                p.move(to: CGPoint(x: mx(xRange.lowerBound), y: my(slope * xRange.lowerBound + intercept)))
                p.addLine(to: CGPoint(x: mx(xRange.upperBound), y: my(slope * xRange.upperBound + intercept)))
                ctx.stroke(p, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }
            for p in points {
                ctx.fill(Path(ellipseIn: CGRect(x: mx(p.x) - 3.5, y: my(p.y) - 3.5, width: 7, height: 7)), with: .color(color.opacity(0.85)))
            }
        }
        .aspectRatio(1.35, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Legend entry: coloured bar or dot with a label.
struct NunaLegendItem: View {
    let color: Color
    let text: LocalizedStringKey
    var dot = false
    var body: some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: dot ? 10 : 14, height: dot ? 10 : 8)
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
        }
    }
}

/// Small caption used above cards.
func nunaTrendsCap(_ t: LocalizedStringKey) -> some View {
    Text(t).font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
}

/// Charge zone colour (green 67+, yellow 34 to 66, red below).
func nunaZoneColor(_ v: Double) -> Color { nunaChargeColor(v) }
#endif
