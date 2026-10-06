#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The sleep-stage chart on the Sleep page can be drawn five ways. Classic is the hatched row per stage; Fitbit is one lane per
// stage in a rounded track with thin connectors where the night moves from one stage to another, and a lane of restlessness; Fill,
// Garmin and Ribbon are the three stepped hypnograms NOOP's own Sleep tab offers. Only the drawing changes: the stages, the
// totals and the comparison with the usual are the same in every style.

enum NunaSleepChartStyle: String, CaseIterable, Identifiable {
    case classic, fitbit, fill, garmin, ribbon

    var id: String { rawValue }
    static let storageKey = "nuna.sleep.chartStyle"

    var label: LocalizedStringKey {
        switch self {
        case .classic: return "Classic"
        case .fitbit: return "Fitbit"
        case .fill: return "Fill"
        case .garmin: return "Garmin"
        case .ribbon: return "Ribbon"
        }
    }

    /// One line under the name in the settings.
    var summary: LocalizedStringKey {
        switch self {
        case .classic: return "A row for each stage"
        case .fitbit: return "A lane for each stage, with the restlessness"
        case .fill: return "One stepped chart, filled to the baseline"
        case .garmin: return "The same stepped chart in Garmin's colours"
        case .ribbon: return "One stepped chart as a slim band"
        }
    }

    static func resolve(_ raw: String) -> NunaSleepChartStyle { NunaSleepChartStyle(rawValue: raw) ?? .classic }

    /// The stepped hypnogram NOOP draws for this style, or nil for the two that Nuna draws itself.
    var hypnogram: (filled: Bool, palette: SleepStagePalette)? {
        switch self {
        case .classic, .fitbit: return nil
        case .fill: return (true, .noop)
        case .garmin: return (true, .garmin)
        case .ribbon: return (false, .oura)
        }
    }
}

extension NunaNight {
    /// Minutes with movement above the threshold, from the movement epochs (each counts for the usual gap between two of them).
    var restlessMinutes: Double? {
        guard motion.count >= 10 else { return nil }
        let t = motion.map(\.t).sorted()
        let gaps = zip(t, t.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }.sorted()
        let step = min(max(gaps.isEmpty ? 30 : gaps[gaps.count / 2], 5), 120)
        let moving = motion.filter { $0.v > NunaMovementSummary.moveThreshold }.count
        return Double(moving) * step / 60
    }
}

// MARK: - Fitbit

/// One lane per stage (Awake, Restlessness, REM, Light, Deep) in a rounded track, a block where the night was in that stage and a
/// thin line wherever it moved from one stage to the next. Tapping a lane selects its stage.
struct NunaFitbitStageChart: View {
    let intervals: [SleepInterval]
    let origin: TimeInterval
    let span: TimeInterval
    let motion: [NunaMotionEpoch]
    let restlessMin: Double?
    let minutes: (SleepStage) -> Double
    @Binding var selected: SleepStage?

    private enum Lane: Hashable { case stage(SleepStage), restless }

    private let headerH: CGFloat = 22
    private let laneH: CGFloat = 30
    private let gap: CGFloat = 8
    private var pitch: CGFloat { headerH + laneH + gap }

    private var lanes: [Lane] {
        [.stage(.awake)] + (restlessMin != nil ? [.restless] : []) + [.stage(.rem), .stage(.light), .stage(.deep)]
    }

    private func color(_ lane: Lane) -> Color {
        switch lane {
        case .restless: return NunaPalette.charge
        case .stage(let s):
            if let sel = selected, sel != s { return NunaPalette.textMuted.opacity(0.55) }
            return s == .awake ? NunaPalette.alertText : s.nunaColor
        }
    }

    private func header(_ lane: Lane) -> Text {
        switch lane {
        case .restless: return Text("Restlessness") + Text(verbatim: " • \(NunaSleepFormat.duration(restlessMin ?? 0))")
        case .stage(let s): return Text(s.nunaName) + Text(verbatim: " • \(NunaSleepFormat.duration(minutes(s)))")
        }
    }

    private func laneIndex(_ s: SleepStage) -> Int { lanes.firstIndex(of: .stage(s)) ?? 0 }
    private func top(_ i: Int) -> CGFloat { CGFloat(i) * pitch + headerH }

    var body: some View {
        let total = CGFloat(lanes.count) * pitch - gap
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in draw(ctx, size) }
                .frame(height: total).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: gap) {
                ForEach(lanes, id: \.self) { lane in
                    VStack(alignment: .leading, spacing: 0) {
                        header(lane).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                            .frame(height: headerH, alignment: .leading)
                        Color.clear.frame(height: laneH)
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: total)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap in
            let i = Int(tap.location.y / pitch)
            guard i >= 0, i < lanes.count, case .stage(let s) = lanes[i] else { return }
            withAnimation(.easeInOut(duration: 0.2)) { selected = selected == s ? nil : s }
        })
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width
        func x(_ t: TimeInterval) -> CGFloat { w * CGFloat(min(max((t - origin) / span, 0), 1)) }
        // Tracks.
        for i in lanes.indices {
            let track = Path(roundedRect: CGRect(x: 0, y: top(i), width: w, height: laneH), cornerRadius: laneH / 2)
            ctx.fill(track, with: .color(NunaPalette.ink.opacity(0.06)))
        }
        // Connectors under the blocks, from the edge of one lane to the edge of the next.
        let sorted = intervals.sorted { $0.start < $1.start }
        for (a, b) in zip(sorted, sorted.dropFirst()) where a.stage != b.stage {
            let ia = laneIndex(a.stage), ib = laneIndex(b.stage)
            let cx = x((a.end + b.start) / 2)
            let y0 = ib > ia ? top(ia) + laneH : top(ia)
            let y1 = ib > ia ? top(ib) : top(ib) + laneH
            var line = Path(); line.move(to: CGPoint(x: cx, y: y0)); line.addLine(to: CGPoint(x: cx, y: y1))
            let ca = color(.stage(a.stage)), cb = color(.stage(b.stage))
            ctx.stroke(line, with: .linearGradient(Gradient(colors: [ca.opacity(0.6), cb.opacity(0.6)]), startPoint: CGPoint(x: cx, y: y0), endPoint: CGPoint(x: cx, y: y1)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        // Blocks.
        for iv in sorted {
            let i = laneIndex(iv.stage)
            let x0 = x(iv.start), x1 = x(iv.end)
            let bw = max(3, x1 - x0)
            let rect = CGRect(x: min(x0, w - bw), y: top(i), width: bw, height: laneH)
            ctx.fill(Path(roundedRect: rect, cornerRadius: min(laneH / 2.5, bw / 2)), with: .color(color(.stage(iv.stage))))
        }
        // Restlessness: one thin tick per movement.
        if let r = lanes.firstIndex(of: .restless) {
            var ticks = Path()
            for e in motion where e.v > NunaMovementSummary.moveThreshold {
                let cx = x(e.t)
                ticks.move(to: CGPoint(x: cx, y: top(r) + 4)); ticks.addLine(to: CGPoint(x: cx, y: top(r) + laneH - 4))
            }
            ctx.stroke(ticks, with: .color(color(.restless)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }
}

// MARK: - Hourly labels under a night chart

/// A label for every full hour inside the sleep window, placed where the hour falls. Every second hour when the night is long
/// enough that the labels would touch.
struct NunaHourAxis: View {
    let start: Date
    let end: Date

    private var hours: [Date] {
        let cal = Calendar.current
        guard let first = cal.nextDate(after: start.addingTimeInterval(-1), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) else { return [] }
        var out: [Date] = []
        var d = first
        while d <= end { out.append(d); guard let n = cal.date(byAdding: .hour, value: 1, to: d) else { break }; d = n }
        return out
    }

    var body: some View {
        let span = max(end.timeIntervalSince(start), 1)
        let all = hours
        let stride = all.count > 8 ? 2 : 1
        GeometryReader { geo in
            ForEach(Array(all.enumerated()), id: \.offset) { i, d in
                if i % stride == 0 {
                    let fx = CGFloat(d.timeIntervalSince(start) / span)
                    Text(verbatim: NunaSleepFormat.clock(d)).font(.nuna(size: 10.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .fixedSize().position(x: min(max(fx * geo.size.width, 14), geo.size.width - 14), y: 8)
                }
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}
#endif
