#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The heart-rate day across the whole screen, turned on its side the way a landscape view reads. The app is portrait-only on iPhone, so the
/// view is rotated rather than waiting for the phone to rotate; turn the phone a quarter turn and it reads upright.
///
/// From the top: close, the day with its arrows and when the data last arrived; the night (a moon and how long it lasted) and each workout
/// (its glyph and how long) above a bar and a shaded band over their hours; the Charge that morning at the line where the night ends and
/// Effort so far at the line where the data ends; then the heart rate, steel blue through the night and the workout and grey the rest of the
/// day. The magnifier on the right narrows the day to its last six hours and back.
struct NunaHRFullScreen: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    let onClose: () -> Void

    @State private var dayStart = Repository.logicalDayStart(Date())
    @State private var zoomed = false
    @State private var points: [(ts: Int, bpm: Double)] = []
    @State private var window: ClosedRange<Int> = 0...1
    @State private var sleep: ClosedRange<Int>?
    @State private var workouts: [WorkoutRow] = []
    @State private var charge: Double?
    @State private var effort: Double?
    @State private var lastData: Int?
    @State private var loading = true
    @State private var didLand = false
    @State private var scrubX: CGFloat?

    /// How much of the day the magnifier keeps.
    private static let zoomSeconds = 6 * 3_600
    private var isLatest: Bool { dayStart >= Repository.logicalDayStart(Date()) }
    private var shown: ClosedRange<Int> { zoomed ? max(window.lowerBound, window.upperBound - Self.zoomSeconds)...window.upperBound : window }

    var body: some View {
        GeometryReader { geo in
            screen(CGSize(width: geo.size.height, height: geo.size.width))
                .frame(width: geo.size.height, height: geo.size.width)
                .rotationEffect(.degrees(90))
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
        .task(id: "\(Int(dayStart.timeIntervalSince1970))|\(zoomed)|\(repo.refreshSeq)") { await load() }
        .task {
            guard !didLand else { return }
            didLand = true
            if let latest = await repo.latestDataDayStart(), latest < dayStart { dayStart = latest }
        }
    }

    // MARK: Layout (in the landscape space, before the turn)

    private func screen(_ size: CGSize) -> some View {
        let lead: CGFloat = 64, trail: CGFloat = 34
        let barH: CGFloat = 48, annoH: CGFloat = 64, axisH: CGFloat = 30, bottom: CGFloat = 12
        let plot = CGRect(x: lead + 44, y: barH + annoH, width: size.width - lead - 44 - trail - 74,
                          height: size.height - barH - annoH - axisH - bottom)
        let (lo, hi) = valueRange
        let t0 = shown.lowerBound, t1 = max(shown.upperBound, shown.lowerBound + 1)
        let x: (Int) -> CGFloat = { plot.minX + CGFloat($0 - t0) / CGFloat(t1 - t0) * plot.width }
        let y: (Double) -> CGFloat = { plot.maxY - CGFloat((min(max($0, lo), hi) - lo) / (hi - lo)) * plot.height }
        return ZStack(alignment: .topLeading) {
            topBar(width: size.width, lead: lead, trail: trail).frame(width: size.width, height: barH)
            Rectangle().fill(NunaPalette.hairline).frame(width: size.width, height: 1).position(x: size.width / 2, y: barH)
            grid(plot: plot, lo: lo, hi: hi, y: y).allowsHitTesting(false)
            if points.count >= 2 {
                // What is drawn takes no touches (the line's canvas spans the whole screen and would cover the bar); only the plot reads them.
                Group {
                    bands(plot: plot, t0: t0, t1: t1, x: x)
                    hourMarks(plot: plot, t0: t0, t1: t1, x: x)
                    trace(t0: t0, t1: t1, x: x, y: y)
                    markers(plot: plot, t0: t0, t1: t1, x: x)
                }
                .allowsHitTesting(false)
                scrub(plot: plot, t0: t0, t1: t1, x: x, y: y)
            } else {
                Text(loading ? "" : String(localized: "Nothing recorded for this window"))
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    .position(x: plot.midX, y: plot.midY)
            }
            zoomButton.position(x: size.width - trail - 24, y: plot.midY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var valueRange: (Double, Double) {
        let vals = points.map(\.bpm)
        let lo = min(40, (((vals.min() ?? 40) / 40).rounded(.down)) * 40)
        let hi = max(200, (((vals.max() ?? 200) / 40).rounded(.up)) * 40)
        return (lo, hi)
    }

    // MARK: Top bar

    private func topBar(width: CGFloat, lead: CGFloat, trail: CGFloat) -> some View {
        ZStack {
            HStack(spacing: 18) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Close"))
                Text("Heart rate").font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer(minLength: 8)
                if let t = lastData {
                    Text(verbatim: String(localized: "Data synced to \(Self.clock(t))"))
                        .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).lineLimit(1)
                }
            }
            .padding(.leading, lead - 10).padding(.trailing, trail)
            dayNav
        }
    }

    private var dayNav: some View {
        HStack(spacing: 14) {
            Button { stepDay(-1) } label: {
                Image(systemName: "chevron.left").font(.nuna(size: 16, weight: .bold)).frame(width: 36, height: 44).contentShape(Rectangle())
            }
            Text(verbatim: dayLabel).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).frame(minWidth: 70)
            Button { stepDay(1) } label: {
                Image(systemName: "chevron.right").font(.nuna(size: 16, weight: .bold)).frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .disabled(isLatest).opacity(isLatest ? 0.35 : 1)
        }
        .foregroundStyle(NunaPalette.textPrimary)
    }

    private func stepDay(_ d: Int) {
        let next = dayStart.addingTimeInterval(Double(d) * 86_400)
        if d > 0 && next > Repository.logicalDayStart(Date()) { return }
        dayStart = next; zoomed = false; scrubX = nil
    }

    private var dayLabel: String {
        let today = Repository.logicalDayStart(Date())
        if Calendar.current.isDate(dayStart, inSameDayAs: today) { return String(localized: "Today") }
        if Calendar.current.isDate(dayStart, inSameDayAs: today.addingTimeInterval(-86_400)) { return String(localized: "Yesterday") }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: dayStart)
    }

    // MARK: Plot

    private func grid(plot: CGRect, lo: Double, hi: Double, y: @escaping (Double) -> CGFloat) -> some View {
        ZStack {
            ForEach(Array(stride(from: lo, through: hi, by: 40)), id: \.self) { v in
                Rectangle().fill(NunaPalette.hairline.opacity(0.6)).frame(width: plot.width, height: 1).position(x: plot.midX, y: y(v))
                Text(verbatim: String(Int(v))).font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle(NunaPalette.textMuted)
                    .frame(width: 40, alignment: .trailing).position(x: plot.minX - 28, y: y(v))
            }
        }
    }

    /// The shaded hours of the night and of each workout, with a steel bar along the top edge.
    private func bands(plot: CGRect, t0: Int, t1: Int, x: @escaping (Int) -> CGFloat) -> some View {
        ZStack {
            if let sleep, let span = clamped(sleep, t0, t1) {
                let x0 = x(span.lowerBound), w = max(x(span.upperBound) - x0, 4)
                Rectangle().fill(LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: plot.height).position(x: x0 + w / 2, y: plot.midY)
                Rectangle().fill(NunaRestChart.steel).frame(width: w, height: 3).position(x: x0 + w / 2, y: plot.minY)
            }
            ForEach(Array(workouts.enumerated()), id: \.offset) { _, wo in
                if let span = clamped(wo.startTs...wo.endTs, t0, t1) {
                    let x0 = x(span.lowerBound), w = max(x(span.upperBound) - x0, 4)
                    Rectangle().fill(LinearGradient(colors: [NunaPalette.effortModerate.opacity(0.22), NunaPalette.effortModerate.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                        .frame(width: w, height: plot.height).position(x: x0 + w / 2, y: plot.midY)
                    Rectangle().fill(NunaPalette.effortModerate).frame(width: w, height: 3).position(x: x0 + w / 2, y: plot.minY)
                }
            }
        }
    }

    private func hourMarks(plot: CGRect, t0: Int, t1: Int, x: @escaping (Int) -> CGFloat) -> some View {
        let marks = Self.hourTicks(t0, t1, plotWidth: plot.width)
        return ZStack {
            ForEach(marks, id: \.self) { ts in
                Text(verbatim: Self.clock(ts)).font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle(NunaPalette.textMuted).fixedSize()
                    .position(x: x(ts), y: plot.maxY + 20)
            }
            Text(verbatim: Self.clock(t0)).font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle(NunaPalette.textMuted).fixedSize()
                .position(x: plot.minX + 14, y: plot.maxY + 20)
            Text(verbatim: Self.clock(t1)).font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).fixedSize()
                .position(x: plot.maxX - 8, y: plot.maxY + 20)
        }
    }

    /// Whole hours that suit the span, kept clear of both ends: every hour up to about six hours, every two to twelve, otherwise every four.
    private static func hourTicks(_ t0: Int, _ t1: Int, plotWidth: CGFloat) -> [Int] {
        let span = Double(t1 - t0) / 3_600
        let step = span <= 7 ? 1 : (span <= 13 ? 2 : 4)
        let cal = Calendar.current
        var out: [Int] = []
        var d = cal.date(bySetting: .minute, value: 0, of: Date(timeIntervalSince1970: TimeInterval(t0))) ?? Date(timeIntervalSince1970: TimeInterval(t0))
        d = cal.date(bySetting: .second, value: 0, of: d) ?? d
        if Int(d.timeIntervalSince1970) < t0 { d = d.addingTimeInterval(3_600) }
        while Int(d.timeIntervalSince1970) < t1 {
            let h = cal.component(.hour, from: d)
            let ts = Int(d.timeIntervalSince1970)
            // Clear of the time written at each end (about 44 pt wide, with the gap before the next).
            let room = max(plotWidth * 0.07, 56)
            let px = CGFloat(ts - t0) / CGFloat(t1 - t0) * plotWidth
            if h % step == 0, px > room, px < plotWidth - room { out.append(ts) }
            d = d.addingTimeInterval(3_600)
        }
        return out
    }

    /// The heart rate: steel blue through the night, bright blue through a workout, grey the rest of the day. A gap in the readings breaks the line.
    private func trace(t0: Int, t1: Int, x: @escaping (Int) -> CGFloat, y: @escaping (Double) -> CGFloat) -> some View {
        let visible = points.filter { $0.ts >= t0 && $0.ts <= t1 }
        let gap = max(600, ((t1 - t0) / 120) * 4)
        return Canvas { ctx, _ in
            func colour(_ ts: Int) -> Color {
                if workouts.contains(where: { ts >= $0.startTs && ts <= $0.endTs }) { return NunaPalette.effortModerate }
                if let sleep, sleep.contains(ts) { return NunaRestChart.steel }
                return NunaPalette.textMuted
            }
            var runs: [(Color, [CGPoint])] = []
            for i in 1..<max(visible.count, 1) {
                let a = visible[i - 1], b = visible[i]
                guard b.ts - a.ts <= gap else { continue }
                let c = colour((a.ts + b.ts) / 2)
                let pa = CGPoint(x: x(a.ts), y: y(a.bpm)), pb = CGPoint(x: x(b.ts), y: y(b.bpm))
                if let last = runs.last, last.0 == c, last.1.last == pa { runs[runs.count - 1].1.append(pb) } else { runs.append((c, [pa, pb])) }
            }
            for (c, pts) in runs {
                var path = Path(); path.addLines(pts)
                ctx.stroke(path, with: .color(c), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// One label above the plot: a glyph or a caption, and the figure under it.
    private struct Mark: Identifiable {
        enum Kind { case sleep, workout(WorkoutRow), charge(Double), strain(Double) }
        let id: Int
        let kind: Kind
        /// Where it would sit if nothing else were in the way, and how wide it is.
        let want: CGFloat
        let width: CGFloat
    }

    /// Everything that is written above the plot, laid out in one row from the left: each label keeps to its place over its hours, and a label that
    /// would touch the one before it moves to the right of it. If that pushes the last ones past the edge, they are pulled back from the right.
    private func laidOut(_ marks: [Mark], from lo: CGFloat, to hi: CGFloat) -> [(Mark, CGFloat)] {
        let gap: CGFloat = 6
        var xs: [CGFloat] = []
        for (i, m) in marks.enumerated() {
            var cx = max(m.want, lo + m.width / 2)
            if i > 0 { cx = max(cx, xs[i - 1] + marks[i - 1].width / 2 + gap + m.width / 2) }
            xs.append(cx)
        }
        if let last = marks.indices.last, xs[last] + marks[last].width / 2 > hi {
            xs[last] = hi - marks[last].width / 2
            for i in stride(from: last - 1, through: 0, by: -1) { xs[i] = min(xs[i], xs[i + 1] - marks[i + 1].width / 2 - gap - marks[i].width / 2) }
        }
        return Array(zip(marks, xs))
    }

    private static func figureWidth(_ s: String) -> CGFloat { CGFloat(s.count) * 10 + 4 }

    /// The moon and its duration, the workouts' glyphs and durations, Charge at the wake-up line and Effort at the line where the data ends.
    private func markers(plot: CGRect, t0: Int, t1: Int, x: @escaping (Int) -> CGFloat) -> some View {
        let iconY = plot.minY - 40, textY = plot.minY - 16
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        var marks: [Mark] = []
        var wakeX: CGFloat?
        if let sleep, let span = clamped(sleep, t0, t1) {
            marks.append(Mark(id: marks.count, kind: .sleep, want: (x(span.lowerBound) + x(span.upperBound)) / 2, width: Self.figureWidth(Self.duration(sleep.upperBound - sleep.lowerBound))))
            if sleep.upperBound > t0, sleep.upperBound < t1 {
                wakeX = x(sleep.upperBound)
                if let charge, let wx = wakeX {
                    // Charge is written to the left of the line it belongs to, ending just short of it.
                    let w = Self.figureWidth(String(format: "%.0f%%", charge))
                    marks.append(Mark(id: marks.count, kind: .charge(charge), want: wx - 6 - w / 2, width: w))
                }
            }
        }
        for wo in workouts.sorted(by: { $0.startTs < $1.startTs }) {
            guard let span = clamped(wo.startTs...wo.endTs, t0, t1) else { continue }
            marks.append(Mark(id: marks.count, kind: .workout(wo), want: (x(span.lowerBound) + x(span.upperBound)) / 2, width: Self.figureWidth(Self.duration(wo.endTs - wo.startTs))))
        }
        var strainX: CGFloat?
        if isLatest, let effort, window.upperBound >= t1 {
            strainX = x(t1)
            let text = UnitFormatter.effortDisplay(effort, scale: scale)
            marks.append(Mark(id: marks.count, kind: .strain(effort), want: x(t1), width: max(Self.figureWidth(text), 52)))
        }
        marks.sort { $0.want < $1.want }
        let placed = laidOut(marks, from: plot.minX, to: plot.maxX + 40)
        return ZStack {
            if let wx = wakeX {
                Path { p in p.move(to: CGPoint(x: wx, y: plot.minY)); p.addLine(to: CGPoint(x: wx, y: plot.maxY)) }
                    .stroke(NunaPalette.scoreMid, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            if let ex = strainX {
                Path { p in p.move(to: CGPoint(x: ex, y: plot.minY - 22)); p.addLine(to: CGPoint(x: ex, y: plot.maxY)) }
                    .stroke(NunaPalette.effortModerate, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            ForEach(placed, id: \.0.id) { m, cx in
                switch m.kind {
                case .sleep:
                    if let sleep {
                        Image(systemName: "moon.fill").font(.nuna(size: 19, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).position(x: cx, y: iconY)
                        figure(Self.duration(sleep.upperBound - sleep.lowerBound), NunaPalette.textPrimary).position(x: cx, y: textY)
                    }
                case .charge(let c):
                    figure(String(format: "%.0f%%", locale: AppLanguage.activeLocale, c), NunaScoreStyle.chargeColor(c)).position(x: cx, y: textY)
                case .workout(let wo):
                    // The same picture the activity has on Today.
                    NunaActivityGlyph(name: wo.sport, size: 25).foregroundStyle(NunaPalette.textSecondary).position(x: cx, y: iconY)
                    figure(Self.duration(wo.endTs - wo.startTs), NunaPalette.textPrimary).position(x: cx, y: textY)
                case .strain(let e):
                    Text("Strain").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.effortModerate).fixedSize().position(x: cx, y: iconY + 2)
                    figure(UnitFormatter.effortDisplay(e, scale: scale), NunaPalette.effortModerate).position(x: cx, y: textY)
                }
            }
        }
    }

    private func figure(_ text: String, _ color: Color) -> some View {
        Text(verbatim: text).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(color).fixedSize()
    }

    /// Hold and drag to read the heart rate at a time.
    private func scrub(plot: CGRect, t0: Int, t1: Int, x: @escaping (Int) -> CGFloat, y: @escaping (Double) -> CGFloat) -> some View {
        ZStack {
            if let sx = scrubX, let p = nearest(to: sx, plot: plot, t0: t0, t1: t1) {
                let px = x(p.ts)
                Rectangle().fill(NunaPalette.textPrimary.opacity(0.6)).frame(width: 1, height: plot.height).position(x: px, y: plot.midY)
                Circle().fill(NunaPalette.textPrimary).frame(width: 9, height: 9).position(x: px, y: y(p.bpm))
                Text(verbatim: "\(Int(p.bpm.rounded())) bpm · \(Self.clock(p.ts))").font(.nuna(size: 13, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(NunaPalette.glassStrong, in: Capsule())
                    .position(x: min(max(px, plot.minX + 60), plot.maxX - 60), y: plot.minY + 18)
            }
            Color.clear.contentShape(Rectangle()).frame(width: plot.width, height: plot.height).position(x: plot.midX, y: plot.midY)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { scrubX = $0.location.x + plot.minX }
                    .onEnded { _ in scrubX = nil })
        }
    }

    private func nearest(to px: CGFloat, plot: CGRect, t0: Int, t1: Int) -> (ts: Int, bpm: Double)? {
        let ts = Double(t0) + Double((px - plot.minX) / plot.width) * Double(t1 - t0)
        return points.filter { $0.ts >= t0 && $0.ts <= t1 }.min { abs(Double($0.ts) - ts) < abs(Double($1.ts) - ts) }
    }

    private var zoomButton: some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { zoomed.toggle() } } label: {
            Image(systemName: zoomed ? "minus.magnifyingglass" : "plus.magnifyingglass").font(.nuna(size: 24, weight: .regular))
                .foregroundStyle(NunaPalette.textPrimary).frame(width: 52, height: 52).contentShape(Rectangle())
        }
        .accessibilityLabel(Text(zoomed ? "Zoom out" : "Zoom in"))
    }

    // MARK: Data

    private func clamped(_ r: ClosedRange<Int>, _ t0: Int, _ t1: Int) -> ClosedRange<Int>? {
        let a = max(r.lowerBound, t0), b = min(r.upperBound, t1)
        return b > a ? a...b : nil
    }

    private func load() async {
        loading = true
        let dayFrom = Int(dayStart.timeIntervalSince1970), dayTo = dayFrom + 86_400
        let now = Int(Date().timeIntervalSince1970)
        let daysBack = max(0, Int(Date().timeIntervalSince(dayStart) / 86_400)) + 2

        // The night that ended on this day opens the picture; without one the day opens at midnight.
        let sessions = await repo.allSleepSessions(days: daysBack)
        let main = sessions.filter { $0.endTs >= dayFrom && $0.endTs <= dayTo && $0.endTs - $0.effectiveStartTs >= 3 * 3_600 }
            .max { $0.endTs - $0.effectiveStartTs < $1.endTs - $1.effectiveStartTs }
        let start = min(main?.effectiveStartTs ?? dayFrom, dayFrom)
        let fp = await repo.hrFingerprint(from: start, to: dayTo)
        let end: Int = {
            let last = fp?.maxTs
            return isLatest ? max(min(now, last ?? now), start + 3_600) : min(dayTo, max(last ?? dayTo, start + 3_600))
        }()
        let whole = start...end
        let w = zoomed ? max(start, end - Self.zoomSeconds)...end : whole

        let series = await repo.timelineSeries(metric: .hr, from: w.lowerBound, to: w.upperBound, targetPoints: 700)
        let works = await repo.workoutRows(days: daysBack).filter { $0.endTs > $0.startTs && $0.startTs < whole.upperBound && $0.endTs > whole.lowerBound }
        let row = repo.days.first { $0.day == Repository.localDayKey(dayStart) }
        guard !Task.isCancelled else { return }
        window = whole
        sleep = main.map { $0.effectiveStartTs...$0.endTs }
        workouts = works
        points = series.points.map { (Int($0.date.timeIntervalSince1970), $0.value) }
        lastData = fp?.maxTs
        charge = row?.recovery
        effort = row?.strain
        loading = false
    }

    private static func clock(_ ts: Int) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// Hours and minutes: 6:19.
    private static func duration(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}
#endif
