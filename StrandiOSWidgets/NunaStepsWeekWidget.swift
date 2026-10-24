import SwiftUI
import WidgetKit
import StrandDesign

// The Steps this week widget: the week's total, one bar per day against its track, the average and the daily target as dashed lines, and
// today's initial in a dark disc. Medium, on the Home Screen.

struct NunaStepsWeekWidget: Widget {
    static let kind = "NunaStepsWeekWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NunaStepsProvider()) { entry in
            NunaStepsWeekView(snapshot: entry.snapshot).widgetURL(NunaWLink.today).nunaWidgetBackground()
        }
        .configurationDisplayName("Steps this week")
        .description("The week's steps, day by day, against your average and your target.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private struct NunaStepsWeekView: View {
    let snapshot: WidgetSnapshot
    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    private var week: [Int?] { (snapshot.weekSteps ?? []) + Array(repeating: nil, count: 7) }
    private var days: [Int?] { Array(week.prefix(7)) }
    private var total: Int { days.compactMap { $0 }.reduce(0, +) }
    private var goal: Int { max(snapshot.stepGoal ?? 10_000, 1) }
    /// Monday is 0.
    private var todayIndex: Int {
        var cal = Calendar.current; cal.firstWeekday = 2
        return max(0, min(6, cal.dateComponents([.day], from: cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date(), to: Date()).day ?? 0))
    }
    /// The average of the days that are over: today is not finished, so it is left out unless it is the only day there is.
    private var average: Int? {
        let finished = days.prefix(todayIndex).compactMap { $0 }
        if !finished.isEmpty { return finished.reduce(0, +) / finished.count }
        return days[todayIndex]
    }
    /// Today's steps so far: the snapshot's own count, which is the newest, else today's bar.
    private var today: Int? { snapshot.steps ?? days[todayIndex] }
    private var top: Double { max(Double(days.compactMap { $0 }.max() ?? 0), Double(goal), Double(average ?? 0)) * 1.08 }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: total > 0 ? NunaW.number(Double(total)) : "–")
                    .font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.restText).minimumScaleFactor(0.6).lineLimit(1)
                Text("Steps this week").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                bars.padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if average != nil || today != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let average { sideFigure("Avg", average) }
                    if let today { sideFigure("Today", today) }
                }
                .padding(.top, 34)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    /// A label over a figure, in the column at the right.
    private func sideFigure(_ label: LocalizedStringKey, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.nuna(size: 11, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: NunaW.number(Double(value))).font(.nuna(size: 17, weight: .bold, design: NunaType.design))
                .foregroundStyle(NunaPalette.restText).minimumScaleFactor(0.6).lineLimit(1)
        }
    }

    private var bars: some View {
        GeometryReader { geo in
            let h = geo.size.height - 22
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottom) {
                                Capsule().fill(Color.primary.opacity(0.07))
                                if let v = days[i], v > 0 {
                                    Capsule().fill(NunaPalette.restText).frame(height: max(8, h * CGFloat(Double(v) / top)))
                                }
                            }
                            .frame(height: h)
                            ZStack {
                                if i == todayIndex { Circle().fill(NunaPalette.textPrimary).frame(width: 18, height: 18) }
                                Text(verbatim: Self.letters[i]).font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(i == todayIndex ? NunaPalette.card : NunaPalette.textPrimary)
                            }.frame(height: 18)
                        }
                    }
                }
                if let average { line(at: h * (1 - CGFloat(Double(average) / top)), width: w, color: NunaPalette.restText) }
                line(at: h * (1 - CGFloat(Double(goal) / top)), width: w, color: NunaPalette.textMuted)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func line(at y: CGFloat, width: CGFloat, color: Color) -> some View {
        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: width, y: y)) }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }
}
