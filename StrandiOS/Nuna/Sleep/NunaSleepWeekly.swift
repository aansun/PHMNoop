#if os(iOS)
import SwiftUI
import StrandDesign

/// The colours the Rest page's charts share: one steel blue for the sleep figures, a green for the need, and the two restorative stages.
enum NunaRestChart {
    static var steel: Color { Color(hex: "#7BA1BB") }
    static let need = Color(hex: "#19D9A0")
    static let deep = Color(hex: "#F78CF5")
    static let rem = Color(hex: "#A55AE8")
    static let paleGrey = Color(hex: "#C9CCD1")
    static let strain = Color(hex: "#0A86F0")

    /// "6:18" from minutes.
    static func hm(_ minutes: Double) -> String {
        let m = max(0, Int(minutes.rounded()))
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// "23:05" from an hour that may run past 24.
    static func clock(_ hour: Double) -> String {
        let h = hour.truncatingRemainder(dividingBy: 24)
        let total = Int(((h < 0 ? h + 24 : h) * 60).rounded()) % (24 * 60)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// The seven days a weekly card draws, ending `endingDaysAgo` days before today.
private func nunaWeekSlots(endingDaysAgo: Int) -> [(date: Date, key: String)] {
    let cal = Calendar.current
    let today = Date()
    return (0..<7).reversed().map { i in
        let d = cal.date(byAdding: .day, value: -(i + endingDaysAgo), to: today) ?? today
        return (d, Repository.localDayKey(d))
    }
}

/// The weekday and date under each column, the last day bold on its lighter column.
private struct NunaWeekLabels: View {
    let dates: [Date]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(dates.enumerated()), id: \.offset) { i, date in
                let last = i == dates.count - 1
                let f = DateFormatter()
                VStack(spacing: 2) {
                    Text(verbatim: { f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE"); return f.string(from: date) }())
                        .font(.nuna(size: 13, weight: last ? .semibold : .regular)).textCase(nil)
                    Text(verbatim: String(Calendar.current.component(.day, from: date))).font(.nuna(size: 13, weight: last ? .heavy : .semibold)).textCase(nil)
                }
                .foregroundStyle(last ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The card shell the sleep weekly cards share: a title and chevron, an optional key, the plot and the labels, the last day lifted.
private struct NunaSleepWeekShell<Plot: View>: View {
    let title: LocalizedStringKey
    var legend: AnyView?
    let dates: [Date]
    var destination: (() -> AnyView)?
    var plotHeight: CGFloat = 148
    @ViewBuilder let plot: Plot

    private let labelHeight: CGFloat = 44

    var body: some View {
        let card = NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                NunaWeeklyTitle(title: title)
                if let legend { legend }
                VStack(spacing: 6) {
                    plot.frame(height: plotHeight)
                    NunaWeekLabels(dates: dates).frame(height: labelHeight)
                }
                .background(GeometryReader { g in
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NunaPalette.glassStrong.opacity(0.55))
                        .frame(width: g.size.width / 7 - 4, height: g.size.height).offset(x: g.size.width * 6 / 7 + 2)
                })
            }
        }
        if let destination { NavigationLink { destination() } label: { card }.buttonStyle(.plain) } else { card }
    }
}

private func nunaGrid(_ size: CGSize) -> some View {
    ZStack {
        ForEach(0..<4, id: \.self) { i in
            let bottom = i == 3
            Rectangle().fill(NunaPalette.hairline.opacity(bottom ? 1 : 0.55)).frame(height: 1)
                .position(x: size.width / 2, y: bottom ? size.height - 0.5 : size.height * CGFloat(i) / 3 + 0.5)
        }
    }
}

private func nunaKey(_ items: [(LocalizedStringKey, Color, Bool)]) -> some View {
    HStack(spacing: 14) {
        Spacer(minLength: 0)
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            HStack(spacing: 6) {
                if item.2 { Circle().strokeBorder(item.1, lineWidth: 2).frame(width: 8, height: 8) }
                else { RoundedRectangle(cornerRadius: 2, style: .continuous).fill(item.1).frame(width: 9, height: 9) }
                Text(item.0).font(.nuna(size: 11, weight: .heavy)).tracking(1.1).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            }
        }
    }
}

// MARK: - Two lines

/// Hours of sleep and sleep needed, night by night: two lines with rings, the need in green above the sleep in blue, each figure written beside its point.
struct NunaTwoLineWeeklyCard: View {
    let title: LocalizedStringKey
    /// Minutes by day key: the hours slept and the hours needed.
    let slept: [String: Double]
    let needed: [String: Double]
    var endingDaysAgo = 0
    var destination: (() -> AnyView)?

    var body: some View {
        let slots = nunaWeekSlots(endingDaysAgo: endingDaysAgo)
        NunaSleepWeekShell(title: title,
                           legend: AnyView(nunaKey([("Hours of sleep", NunaRestChart.steel, true), ("Sleep needed", NunaRestChart.need, true)])),
                           dates: slots.map(\.date), destination: destination, plotHeight: 180) {
            NunaTwoLinePlot(a: slots.map { slept[$0.key] }, b: slots.map { needed[$0.key] })
        }
    }
}

private struct NunaTwoLinePlot: View {
    let a: [Double?]
    let b: [Double?]

    private var all: [Double] { (a + b).compactMap { $0 } }

    var body: some View {
        GeometryReader { g in
            let size = g.size
            ZStack(alignment: .topLeading) {
                nunaGrid(size)
                path(b, size).stroke(NunaRestChart.need, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                path(a, size).stroke(NunaRestChart.steel, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                points(b, NunaRestChart.need, above: true, size)
                points(a, NunaRestChart.steel, above: false, size)
            }
        }
    }

    private func x(_ i: Int, _ size: CGSize) -> CGFloat { size.width / 7 * (CGFloat(i) + 0.5) }

    private func y(_ v: Double, _ size: CGSize) -> CGFloat {
        let lo = all.min() ?? 0, hi = all.max() ?? 1
        let t: Double = hi - lo < 0.0001 ? 0.5 : (v - lo) / (hi - lo)
        return size.height * (0.78 - 0.56 * CGFloat(t))
    }

    private func path(_ values: [Double?], _ size: CGSize) -> Path {
        var p = Path()
        var open = false
        for (i, value) in values.enumerated() {
            guard let v = value else { open = false; continue }
            let pt = CGPoint(x: x(i, size), y: y(v, size))
            if open { p.addLine(to: pt) } else { p.move(to: pt); open = true }
        }
        return p
    }

    private func points(_ values: [Double?], _ color: Color, above: Bool, _ size: CGSize) -> some View {
        ZStack {
            ForEach(Array(values.enumerated()), id: \.offset) { i, value in
                if let v = value {
                    let py = y(v, size)
                    Circle().fill(NunaPalette.canvas).overlay(Circle().strokeBorder(color, lineWidth: 2.5)).frame(width: 11, height: 11).position(x: x(i, size), y: py)
                    Text(verbatim: NunaRestChart.hm(v)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(color)
                        .fixedSize().position(x: x(i, size), y: above ? max(9, py - 17) : min(size.height - 9, py + 17))
                }
            }
        }
    }
}

// MARK: - Stacked

/// A night's time in two stages, stacked: the first colour at the bottom, the total in hours and minutes over the bar, a key in the corner.
struct NunaStackedWeeklyCard: View {
    let title: LocalizedStringKey
    /// Names and colours for the key, left to right.
    let legend: [(LocalizedStringKey, Color)]
    /// Colours from the bottom of a bar upwards, and the minutes of each by day key.
    let colors: [Color]
    let byDay: [String: [Double]]
    var endingDaysAgo = 0
    var destination: (() -> AnyView)?

    var body: some View {
        let slots = nunaWeekSlots(endingDaysAgo: endingDaysAgo)
        NunaSleepWeekShell(title: title, legend: AnyView(nunaKey(legend.map { ($0.0, $0.1, false) })),
                           dates: slots.map(\.date), destination: destination) {
            NunaZonePlot(days: slots.map { byDay[$0.key] }, colors: colors)
        }
    }
}

// MARK: - Time in bed

/// When each night began and ended as a floating bar, the time you got into bed above it and the time you got up under it.
struct NunaTimeInBedWeeklyCard: View {
    let title: LocalizedStringKey
    /// Bed and wake time by day key, in hours from the evening the night began (a time after midnight is 24 and more).
    let nights: [String: (bed: Double, wake: Double)]
    var endingDaysAgo = 0
    var destination: (() -> AnyView)?

    var body: some View {
        let slots = nunaWeekSlots(endingDaysAgo: endingDaysAgo)
        NunaSleepWeekShell(title: title, dates: slots.map(\.date), destination: destination, plotHeight: 190) {
            NunaTimeInBedPlot(nights: slots.map { nights[$0.key] })
        }
    }
}

private struct NunaTimeInBedPlot: View {
    let nights: [(bed: Double, wake: Double)?]

    private var low: Double { (nights.compactMap { $0?.bed }.min() ?? 21) - 0.5 }
    private var high: Double { (nights.compactMap { $0?.wake }.max() ?? 31) + 0.5 }

    private func y(_ h: Double, _ size: CGSize) -> CGFloat { size.height * (0.14 + 0.72 * CGFloat((h - low) / max(high - low, 1))) }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                nunaGrid(g.size)
                ForEach(Array(nights.enumerated()), id: \.offset) { i, night in
                    if let night { column(i, night, g.size) }
                }
            }
        }
    }

    @ViewBuilder private func column(_ i: Int, _ night: (bed: Double, wake: Double), _ size: CGSize) -> some View {
        let cx = size.width / 7 * (CGFloat(i) + 0.5)
        let top = y(night.bed, size), bottom = y(night.wake, size)
        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(NunaRestChart.steel)
            .frame(width: size.width / 7 * 0.36, height: max(bottom - top, 3)).position(x: cx, y: (top + bottom) / 2)
        Text(verbatim: NunaRestChart.clock(night.bed)).font(.nuna(size: 12.5, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaRestChart.steel)
            .fixedSize().position(x: cx, y: max(9, top - 14))
        Text(verbatim: NunaRestChart.clock(night.wake)).font(.nuna(size: 12.5, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaRestChart.steel)
            .fixedSize().position(x: cx, y: min(size.height - 9, bottom + 14))
    }
}

// MARK: - The page the Sleep performance card opens

/// Sleep performance over a week, a month and six months, drawn like the other sleep trend pages with the days per level under it.
struct NunaRestTrendView: View {
    var endingDaysAgo = 0

    var body: some View {
        NunaPctTrendView(
            name: "Sleep performance", icon: "met:sleep-performance", noun: "average Sleep Performance",
            bands: [
                .init(color: NunaRestChart.need, name: "Optimal", range: ">85%") { $0 > 85 },
                .init(color: Color(hex: "#8A8D93"), name: "Sufficient", range: "70–85%") { $0 >= 70 && $0 <= 85 },
                .init(color: Color(hex: "#F5A623"), name: "Poor", range: "<70%") { $0 < 70 },
            ],
            breakdownTitle: "Sleep breakdown",
            value: { $0.performance[$1] }, endingDaysAgo: endingDaysAgo)
    }
}
#endif
