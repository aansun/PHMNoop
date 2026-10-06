import StrandDesign
import SwiftUI
import WidgetKit

/// Home-screen widget: today's high stress as a time, the comparison with a typical day of the week, and today's stress curve with a
/// marker on the latest reading (#2040). The drawing is a stroked `Path` placed by `StressTrace`, the fixed 0 to 3 domain and the gap rule
/// shared with the Android twin.
///
/// Honest-blank: an unscored hour is a GAP rather than an interpolation, and a day with nothing scored shows no line at all rather
/// than a flat one at zero.
struct StressEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct StressProvider: TimelineProvider {
    func placeholder(in context: Context) -> StressEntry {
        StressEntry(date: Date(), snap: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (StressEntry) -> Void) {
        completion(StressEntry(date: Date(), snap: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StressEntry>) -> Void) {
        let entry = StressEntry(date: Date(), snap: WidgetSnapshot.load())
        // Half an hour, where the heart-rate widget takes fifteen minutes. This curve gains at most one
        // point an hour, so a tighter net would spend budget on entries identical to the one before it.
        // The app reloads timelines when it scores an hour, so this is only the safety net for when it
        // is not running — and it also carries the card across midnight, when the day number changes and
        // yesterday's curve stops being drawn.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}


/// The curve with its marker: one stroked run per contiguous stretch of scored hours, a dashed line at the latest reading and a dot on it.
private struct StressDayLine: View {
    let series: [StressPoint]
    let gradient: LinearGradient

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let inset: CGFloat = 6
            let box = CGSize(width: max(w - 2 * inset, 1), height: max(h - 2 * inset, 1))
            let runs = StressTrace.segments(series, width: box.width, height: box.height)
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Rectangle().fill(NunaPalette.hairline.opacity(0.7)).frame(height: 1).position(x: w / 2, y: inset + CGFloat(i) / 3 * box.height)
                }
                if runs.contains(where: { $0.count > 1 }) {
                    Path { path in
                        for run in runs {
                            guard let first = run.first else { continue }
                            path.move(to: CGPoint(x: inset + first.x, y: inset + first.y))
                            for p in run.dropFirst() { path.addLine(to: CGPoint(x: inset + p.x, y: inset + p.y)) }
                        }
                    }
                    .stroke(gradient, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    if let end = StressTrace.latestPoint(series, width: box.width, height: box.height) {
                        let x = inset + end.x, y = inset + end.y
                        Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h)) }
                            .stroke(NunaPalette.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Circle().fill(NunaPalette.textPrimary).frame(width: 11, height: 11).position(x: x, y: y)
                    }
                } else {
                    Text("No data").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).position(x: w / 2, y: h / 2)
                }
            }
        }
    }
}

struct StressWidgetView: View {
    let entry: StressEntry

    /// Resolved on read, so a curve scored for a day that is over is dropped rather than drawn. Measured from `entry.date` rather than
    /// `Date()` because WidgetKit renders an entry at ITS date.
    private var series: [StressPoint] {
        let all = entry.snap?.stressCurve(now: entry.date) ?? []
        // Start and end on a scored reading, so the line fills the width and the latest reading sits at the right edge.
        guard let lo = all.firstIndex(where: { $0.level != nil }), let hi = all.lastIndex(where: { $0.level != nil }) else { return [] }
        return Array(all[lo...hi])
    }

    private var high: Int? { series.isEmpty ? nil : entry.snap?.stressHighMin }

    /// Blue calm, green steady, amber high: height already encodes level, so one top-to-bottom gradient paints every stretch the colour its
    /// own score deserves.
    private var ramp: LinearGradient {
        LinearGradient(colors: [StrandPalette.statusWarning, StrandPalette.statusPositive, StrandPalette.accent], startPoint: .top, endPoint: .bottom)
    }

    private var weekday: String { entry.date.formatted(.dateTime.weekday(.abbreviated)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NunaWCap(text: Text("Stress monitor"))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    NunaWCap(text: Text("Today's high stress"), size: 9.5)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: high.map { StressTrace.clock(minutes: $0) } ?? "–")
                            .font(.nuna(size: 32, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                            .minimumScaleFactor(0.7).lineLimit(1)
                        if high != nil { Text("hrs").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                    }
                    if let high, let typical = entry.snap?.stressTypicalMin {
                        let diff = high - typical
                        let tint: Color = diff < 0 ? NunaPalette.charge : (diff > 0 ? NunaPalette.warning : NunaPalette.textSecondary)
                        HStack(spacing: 4) {
                            Image(systemName: diff < 0 ? "arrowtriangle.down.fill" : (diff > 0 ? "arrowtriangle.up.fill" : "equal")).font(.system(size: 8))
                            Text("vs. typical \(weekday)").font(.nuna(size: 10.5, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(tint).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .frame(width: 124, alignment: .leading)
                StressDayLine(series: series, gradient: ramp)
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// One spoken sentence rather than a run of loose numbers.
    private var accessibilityText: String {
        guard let high else { return String(localized: "Stress, no reading today") }
        return String(localized: "Today's high stress \(StressTrace.clock(minutes: high)) hours")
    }
}

struct StressWidget: Widget {
    static let kind = "StressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: StressProvider()) { entry in
            StressWidgetView(entry: entry).padding(14).widgetURL(NunaWLink.today).nunaWidgetBackground()
        }
        .configurationDisplayName("Stress")
        .description("Today's high stress and its curve.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
