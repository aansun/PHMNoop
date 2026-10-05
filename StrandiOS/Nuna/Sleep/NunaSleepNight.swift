#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics
import WhoopStore

extension NunaNight {
    /// The clock span of the recorded stages (the first stage block to the last), which is the span every chart of the night
    /// shares. Falls back to onset and wake when there is no stage timeline.
    var chartWindow: (start: Date, end: Date) {
        guard let lo = intervals.map(\.start).min(), let hi = intervals.map(\.end).max(), hi > lo else { return (onset, wake) }
        return (onset.addingTimeInterval(lo), onset.addingTimeInterval(hi))
    }
}

// MARK: - A line over the sleep window

/// A reading over the night, drawn on a time axis that is exactly the sleep window (onset to wake), with dashed rules at both
/// ends. Same line style as every other chart in the app. A gap longer than `gap` seconds breaks the line instead of being
/// bridged. `washes` tints the time spans of the selected sleep stage and `emphasis` redraws the line inside them.
struct NunaNightLineChart: View {
    let start: Date
    let end: Date
    let points: [(date: Date, value: Double)]
    var color: Color = NunaPalette.rest
    var decimals = 0
    var height: CGFloat = 130
    var gap: TimeInterval = 600
    var lineWidth: CGFloat = 2
    var washes: [(from: Date, to: Date)] = []
    var washColor: Color = NunaPalette.rest
    var average: Double?

    private var segments: [[(date: Date, value: Double)]] {
        var out: [[(date: Date, value: Double)]] = []
        var cur: [(date: Date, value: Double)] = []
        for p in points.sorted(by: { $0.date < $1.date }) {
            if let last = cur.last, p.date.timeIntervalSince(last.date) > gap { out.append(cur); cur = [] }
            cur.append(p)
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    private var domain: ClosedRange<Double> {
        let v = points.map(\.value)
        guard let lo = v.min(), let hi = v.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, decimals > 0 ? 0.1 : 2)
        // Never reach below zero for a reading that cannot be negative.
        return (lo >= 0 ? max(lo - pad, 0) : lo - pad)...(hi + pad)
    }

    /// Three round values inside the range for the grid.
    private var ticks: [Double] {
        let d = domain
        let raw = (d.upperBound - d.lowerBound) / 3
        let mag = pow(10, floor(log10(max(raw, 0.0001))))
        let step = [1.0, 2.0, 2.5, 5.0, 10.0].map { $0 * mag }.first { $0 >= raw } ?? raw
        var out: [Double] = []
        var t = (d.lowerBound / step).rounded(.up) * step
        while t < d.upperBound - step * 0.15 { out.append(t == 0 ? 0 : t); t += step }
        return out
    }

    private var mid: Date { Date(timeIntervalSince1970: (start.timeIntervalSince1970 + end.timeIntervalSince1970) / 2) }

    var body: some View {
        Chart {
            ForEach(ticks, id: \.self) { t in
                RuleMark(y: .value("Tick", t)).lineStyle(StrokeStyle(lineWidth: 1)).foregroundStyle(NunaPalette.hairline.opacity(0.4))
                    .annotation(position: .overlay, alignment: .topLeading, spacing: 0) {
                        Text(verbatim: String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, t))
                            .font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).offset(x: 2, y: -15)
                    }
            }
            RuleMark(x: .value("Middle", mid)).lineStyle(StrokeStyle(lineWidth: 1)).foregroundStyle(NunaPalette.hairline.opacity(0.4))
            ForEach(Array(washes.enumerated()), id: \.offset) { _, w in
                RectangleMark(xStart: .value("From", w.from), xEnd: .value("To", w.to)).foregroundStyle(washColor.opacity(0.16))
            }
            if let average {
                RuleMark(y: .value("Average", average)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(NunaPalette.textMuted.opacity(0.6))
            }
            ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                ForEach(Array(seg.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Time", p.date), y: .value("Value", p.value), series: .value("Segment", i))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(color)
                }
            }
            RuleMark(x: .value("Onset", start)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(NunaPalette.textMuted.opacity(0.6))
            RuleMark(x: .value("Wake", end)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(NunaPalette.textMuted.opacity(0.6))
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: domain)
        .chartPlotStyle { $0.clipped() }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Sleep stages on the Sleep page

/// The night's stages, laid out like the Default Sleep tab: hours of sleep and restorative sleep against the usual, the heart
/// rate through the night, then one hatched timeline row per stage (Awake, REM, Light, Deep) on a shared clock axis. Tapping a
/// row highlights that stage on the heart-rate line and compares it with the last 30 nights. Everything is read from the stored
/// timeline; without one, the rows fall back to the daily totals.
struct NunaSleepStageSection: View {
    let model: NunaSleepModel
    let night: NunaNight
    @EnvironmentObject private var repo: Repository
    @State private var selected: SleepStage?
    @State private var series: [String: [(date: Date, value: Double)]] = [:]
    @State private var metric = "hr"
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""

    private var smoothed: [SleepInterval] { Hypnogram.displaySmoothed(night.intervals.sorted { $0.start < $1.start }, minDuration: 90) }
    private var origin: TimeInterval { smoothed.first?.start ?? 0 }
    private var span: TimeInterval { max(1, (smoothed.map(\.end).max() ?? 1) - origin) }
    private var windowStart: Date { night.onset.addingTimeInterval(origin) }
    private var windowEnd: Date { night.onset.addingTimeInterval(origin + span) }

    /// Whole percentages that add up to 100, so the rows, the bars and the text agree.
    private func share(_ stage: SleepStage) -> Int {
        let s = night.stages
        guard let p = StagePercentages.wholePercentages([s.awake, s.light, s.deep, s.rem]) else { return 0 }
        switch stage { case .awake: return p[0]; case .light: return p[1]; case .deep: return p[2]; case .rem: return p[3] }
    }

    private func minutes(_ stage: SleepStage) -> Double {
        switch stage { case .awake: return night.stages.awake; case .light: return night.stages.light; case .deep: return night.stages.deep; case .rem: return night.stages.rem }
    }

    /// Earlier nights (up to 30) that carry a real stage split.
    private var others: [NunaNight] {
        model.nights.dropFirst(model.index + 1).prefix(30).filter { $0.stages.total > 0 }
    }

    /// The middle half of the earlier nights and their mean, or nil under five nights.
    private func typical(_ f: (NunaNight) -> Double) -> (lo: Double, hi: Double, mean: Double)? {
        let v = others.map(f).filter { $0 > 0 }.sorted()
        guard v.count >= 5 else { return nil }
        func pct(_ p: Double) -> Double {
            let idx = p * Double(v.count - 1); let l = Int(idx.rounded(.down)), u = Int(idx.rounded(.up)); let fr = idx - Double(l)
            return v[l] * (1 - fr) + v[u] * fr
        }
        return (pct(0.25), pct(0.75), v.reduce(0, +) / Double(v.count))
    }

    var body: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("Sleep stages")
                headline
                if night.intervals.isEmpty {
                    NunaStageSplitBar(stages: night.stages)
                    ForEach([SleepStage.awake, .rem, .light, .deep], id: \.self) { simpleRow($0) }
                    Text("The order of stages is not available for this night. The split comes from the daily totals.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                } else {
                    nightChart
                    ForEach([SleepStage.awake, .rem, .light, .deep], id: \.self) { timelineRow($0) }
                    NunaTimeAxis(start: windowStart, end: windowEnd).padding(.horizontal, 10)
                    insight
                    if night.motion.count >= 10 {
                        NunaMotionStrip(epochs: night.motion, total: night.wake.timeIntervalSince(night.onset))
                        NunaMovementStats(night: night)
                    }
                }
            }
        }
        .task(id: "\(night.dayKey)-\(temperatureRaw)-\(unitSystemRaw)") {
            selected = nil
            await loadSeries()
        }
    }

    // MARK: Parts

    private var headline: some View {
        let restorative = night.stages.deep + night.stages.rem
        let tAsleep = typical { $0.stages.asleep }
        let tRest = typical { $0.stages.deep + $0.stages.rem }
        return HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: NunaSleepFormat.duration(night.asleepMin)).font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Text("Hours of sleep").font(.nuna(size: 10.5, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                if let tAsleep { Text(verbatim: String(localized: "typically \(NunaSleepFormat.duration(tAsleep.mean))")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: NunaSleepFormat.duration(restorative)).font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(SleepStage.rem.nunaColor)
                Text("Restorative sleep").font(.nuna(size: 10.5, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                if let tRest { Text(verbatim: String(localized: "typically \(NunaSleepFormat.duration(tRest.mean))")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted) }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: One chart for the night

    private struct Metric: Identifiable {
        let id: String; let title: LocalizedStringKey; let chip: LocalizedStringKey; let unit: String; let decimals: Int; let color: Color
    }

    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: temperatureRaw)
    }

    /// Every reading that was recorded through the night. A reading with too little data has no entry, so it cannot be picked.
    private var metrics: [Metric] {
        var out: [Metric] = []
        func has(_ k: String, _ n: Int) -> Bool { (series[k]?.count ?? 0) >= n }
        if has("hr", 2) { out.append(Metric(id: "hr", title: "Heart rate through the night", chip: "Heart rate", unit: "bpm", decimals: 0, color: NunaPalette.rest)) }
        if has("hrv", 8) { out.append(Metric(id: "hrv", title: "HRV through the night", chip: "HRV", unit: "ms", decimals: 0, color: NunaPalette.charge)) }
        if has("skin", 8) { out.append(Metric(id: "skin", title: "Skin temperature through the night", chip: "Skin temp", unit: UnitFormatter.temperatureUnit(temperatureUnit), decimals: 1, color: NunaPalette.warning)) }
        if has("spo2", 8) { out.append(Metric(id: "spo2", title: "Blood oxygen through the night", chip: "SpO₂", unit: "%", decimals: 0, color: NunaPalette.effort)) }
        if has("resp", 8) { out.append(Metric(id: "resp", title: "Breathing through the night", chip: "Breathing", unit: "/min", decimals: 1, color: NunaPalette.rest)) }
        return out
    }

    @ViewBuilder private var nightChart: some View {
        let list = metrics
        if let m = list.first(where: { $0.id == metric }) ?? list.first {
            let pts = (series[m.id] ?? []).filter { $0.date >= windowStart.addingTimeInterval(-60) && $0.date <= windowEnd.addingTimeInterval(60) }
            let washes: [(from: Date, to: Date)] = selected.map { s in
                smoothed.filter { $0.stage == s }.map { (night.onset.addingTimeInterval($0.start), night.onset.addingTimeInterval($0.end)) }
            } ?? []
            VStack(alignment: .leading, spacing: 8) {
                Text(m.title).font(.nuna(size: 11.5, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                NunaNightLineChart(start: windowStart, end: windowEnd, points: pts,
                                   color: selected == nil ? m.color : NunaPalette.textMuted.opacity(0.7), decimals: m.decimals,
                                   height: 124, gap: m.id == "hr" ? 600 : 1800, lineWidth: m.id == "hr" ? 1.6 : 2,
                                   washes: washes, washColor: selected?.nunaColor ?? m.color)
                    .padding(.horizontal, 10)
                if list.count > 1 { picker(list, current: m.id) }
                nightSummary(pts, m)
            }
        } else {
            Text("No heart-rate detail for this night").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
        }
    }

    /// Choose which reading the chart shows.
    private func picker(_ list: [Metric], current: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(list) { m in
                    let on = m.id == current
                    Button { withAnimation(.easeInOut(duration: 0.2)) { metric = m.id } } label: {
                        Text(m.chip).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
                            .padding(.horizontal, 16).frame(height: 38).background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private func loadSeries() async {
        let from = Int(night.chartWindow.start.timeIntervalSince1970), to = Int(night.chartWindow.end.timeIntervalSince1970)
        guard to > from else { series = [:]; return }
        var out: [String: [(date: Date, value: Double)]] = [:]
        out["hr"] = await repo.hrBuckets(from: from, to: to, bucketSeconds: 60).map { (Date(timeIntervalSince1970: TimeInterval($0.ts)), $0.bpm) }
        out["hrv"] = await repo.timelineSeries(metric: .hrv, from: from, to: to, targetPoints: 240).points.map { ($0.date, $0.value) }
        let f = temperatureUnit == .fahrenheit
        out["skin"] = await repo.timelineSeries(metric: .skinTemp, from: from, to: to, targetPoints: 240).points.map { ($0.date, f ? UnitFormatter.celsiusToFahrenheit($0.value) : $0.value) }
        // A ring reports real percentages and rates; a strap's raw optical and respiration signals are not, so they are not charted.
        if repo.activeDeviceIsOura {
            out["spo2"] = await repo.timelineSeries(metric: .spo2, from: from, to: to, targetPoints: 240).points.map { ($0.date, $0.value) }
            out["resp"] = await repo.timelineSeries(metric: .respiration, from: from, to: to, targetPoints: 240).points.map { ($0.date, $0.value) }
        }
        series = out
    }

    // MARK: Heart-rate summary

    /// Seconds from onset of every block that is not Awake, so the figures describe the time actually asleep (a wake-up at the
    /// end of the night would otherwise decide the highest value).
    private func isAsleep(_ date: Date) -> Bool {
        let t = date.timeIntervalSince(night.onset)
        guard !smoothed.isEmpty else { return true }
        return smoothed.contains { $0.stage != .awake && t >= $0.start && t <= $0.end }
    }

    private enum HRStatus { case usual, higher, lower, high }

    /// Compared with the person's own earlier nights (resting heart rate of the last 14), with one fixed guard for a sleeping
    /// average over 100 bpm. It describes the number, it is not a diagnosis.
    private func hrStatus(avg: Double) -> (status: HRStatus, tint: Color)? {
        if avg > 100 { return (.high, NunaPalette.alert) }
        guard let rhr = night.daily?.restingHr.map(Double.init) else { return nil }
        let prior = model.nights.dropFirst(model.index + 1).prefix(14).compactMap { $0.daily?.restingHr.map(Double.init) }
        guard prior.count >= 5, let lo = prior.min(), let hi = prior.max() else { return nil }
        if rhr > hi + 3 { return (.higher, NunaPalette.warning) }
        if rhr < lo - 3 { return (.lower, NunaPalette.textSecondary) }
        return (.usual, NunaPalette.charge)
    }

    @ViewBuilder private func nightSummary(_ all: [(date: Date, value: Double)], _ m: Metric) -> some View {
        let asleep = all.filter { isAsleep($0.date) }
        let pts = asleep.count >= 5 ? asleep : all
        if let lo = pts.map(\.value).min(), let hi = pts.map(\.value).max(), !pts.isEmpty {
            let avg = pts.map(\.value).reduce(0, +) / Double(pts.count)
            let st = m.id == "hr" ? hrStatus(avg: avg) : nil
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    hrFigure("Average", avg, m)
                    hrFigure("Highest", hi, m)
                    hrFigure("Lowest", lo, m)
                }
                if let st {
                    HStack(spacing: 8) {
                        Image(systemName: st.status == .usual ? "checkmark.circle.fill" : "info.circle.fill").font(.nuna(size: 15, weight: .bold)).foregroundStyle(st.tint)
                        Text(statusText(st.status)).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(st.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(m.id == "hr"
                     ? "Figures cover the time you were asleep. This compares with your own recent nights and is not a medical assessment; if you feel unwell, talk to a professional."
                     : "Figures cover the time you were asleep.")
                    .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
        }
    }

    private func hrFigure(_ label: LocalizedStringKey, _ v: Double, _ m: Metric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: String(format: "%.\(m.decimals)f", locale: AppLanguage.activeLocale, v)).font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: m.unit).font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusText(_ s: HRStatus) -> LocalizedStringKey {
        switch s {
        case .usual: return "Within your usual range for sleep"
        case .higher: return "Higher than your recent nights"
        case .lower: return "Lower than your recent nights"
        case .high: return "High for sleep. If it keeps happening, check with a professional."
        }
    }

    private func timelineRow(_ stage: SleepStage) -> some View {
        let on = selected == stage
        let dimmed = selected != nil && !on
        let color = dimmed ? NunaPalette.textMuted.opacity(0.55) : stage.nunaColor
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(stage.nunaName).font(.nuna(size: 11.5, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: "\(share(stage))%").font(.nuna(size: 13, weight: .bold, design: NunaType.design)).foregroundStyle(dimmed ? NunaPalette.textMuted : stage.nunaColor)
                Spacer()
                Text(verbatim: NunaSleepFormat.duration(minutes(stage))).font(.nuna(size: 13, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            }
            Canvas { ctx, size in
                let r = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5)
                ctx.fill(r, with: .color(NunaPalette.ink.opacity(0.05)))
                ctx.clip(to: r)
                var hatch = Path(); var x = -size.height
                while x < size.width { hatch.move(to: CGPoint(x: x, y: size.height)); hatch.addLine(to: CGPoint(x: x + size.height, y: 0)); x += 5 }
                ctx.stroke(hatch, with: .color(NunaPalette.textMuted.opacity(0.18)), lineWidth: 1)
                for iv in smoothed where iv.stage == stage {
                    let x0 = CGFloat((iv.start - origin) / span) * size.width
                    let w = max(2, CGFloat((iv.end - iv.start) / span) * size.width)
                    ctx.fill(Path(roundedRect: CGRect(x: x0, y: 0, width: w, height: size.height), cornerRadius: 1.5), with: .color(color))
                }
            }
            .frame(height: 22)
        }
        .padding(.vertical, 9).padding(.horizontal, 10)
        .background(NunaPalette.ink.opacity(on ? 0.09 : 0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? NunaPalette.textMuted : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { selected = on ? nil : stage } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(minutes(stage).rounded()) min, \(share(stage))%"))
        .accessibilityAddTraits(.isButton)
    }

    /// Row without a timeline (the split comes from the daily totals).
    private func simpleRow(_ stage: SleepStage) -> some View {
        HStack(spacing: 10) {
            Circle().fill(stage.nunaColor).frame(width: 11, height: 11)
            Text(stage.nunaName).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Text(verbatim: "\(share(stage))%").font(.nuna(size: 13, weight: .bold)).foregroundStyle(stage.nunaColor)
            Spacer()
            Text(verbatim: NunaSleepFormat.duration(minutes(stage))).font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
    }

    @ViewBuilder private var insight: some View {
        Group {
            if let s = selected {
                let m = minutes(s)
                if let t = typical({ n in switch s { case .awake: return n.stages.awake; case .light: return n.stages.light; case .deep: return n.stages.deep; case .rem: return n.stages.rem } }) {
                    let phrase = m > t.hi ? String(localized: "above your usual") : (m < t.lo ? String(localized: "below your usual") : String(localized: "about your usual"))
                    Text(verbatim: String(localized: "\(NunaSleepFormat.duration(m)) · typically \(NunaSleepFormat.duration(t.lo)) to \(NunaSleepFormat.duration(t.hi)), \(phrase).")).foregroundStyle(NunaPalette.textSecondary)
                } else {
                    Text(verbatim: String(localized: "\(NunaSleepFormat.duration(m)). Not enough history yet for a typical range.")).foregroundStyle(NunaPalette.textSecondary)
                }
            } else {
                Text("Tap a stage to compare it with your usual.").foregroundStyle(NunaPalette.textMuted)
            }
        }
        .font(.nuna(size: 12.5, weight: .semibold)).padding(.horizontal, 2)
    }
}

// MARK: - Stages against usual and against the usual healthy range

/// Each stage of last night against two yardsticks: the person's own recent nights, and the range commonly quoted for healthy
/// adults as a share of time in bed (deep 13 to 23%, REM 20 to 25%, light 45 to 55%, awake up to 10%). The range is a
/// rule of thumb from sleep-lab studies, not a diagnosis, and strap staging is an estimate, so it is worded that way.
struct NunaStageCompare: View {
    let model: NunaSleepModel
    let night: NunaNight

    private struct Ref { let stage: SleepStage; let lo: Double; let hi: Double }
    private let refs: [Ref] = [
        Ref(stage: .awake, lo: 0, hi: 10), Ref(stage: .rem, lo: 20, hi: 25),
        Ref(stage: .light, lo: 45, hi: 55), Ref(stage: .deep, lo: 13, hi: 23),
    ]

    private func minutes(_ s: SleepStage, _ st: Stages) -> Double {
        switch s { case .awake: return st.awake; case .light: return st.light; case .deep: return st.deep; case .rem: return st.rem }
    }

    /// Mean minutes of the stage over the earlier nights (up to 14), nil under three nights.
    private func usual(_ s: SleepStage) -> Double? {
        let others = model.nights.dropFirst(model.index + 1).prefix(14).filter { $0.stages.total > 0 }
        guard others.count >= 3 else { return nil }
        return others.map { minutes(s, $0.stages) }.reduce(0, +) / Double(others.count)
    }

    var body: some View {
        let total = night.stages.total
        if total > 0 {
            NunaCard {
                VStack(alignment: .leading, spacing: 4) {
                    nunaTrendsCap("Compared to usual")
                    Text("Against your recent nights and the range healthy adults usually fall in.")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).padding(.bottom, 6)
                    ForEach(Array(refs.enumerated()), id: \.element.stage) { i, r in
                        if i > 0 { NunaDivider() }
                        row(r, total: total)
                    }
                    Text("The range is a rule of thumb for healthy adults, as a share of time in bed. Strap staging is an estimate, so read it as a guide, not a diagnosis.")
                        .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                }
            }
        }
    }

    private func row(_ r: Ref, total: Double) -> some View {
        let m = minutes(r.stage, night.stages)
        // Whole percentages that add up to 100, the same apportionment the stage card above prints, so the two never disagree.
        let st = night.stages
        let parts = StagePercentages.wholePercentages([st.awake, st.light, st.deep, st.rem])
        let pct: Double = parts.map { Double($0[r.stage == .awake ? 0 : (r.stage == .light ? 1 : (r.stage == .deep ? 2 : 3))]) } ?? m / total * 100
        let status: (LocalizedStringKey, Color) = pct < r.lo ? ("Below the range", NunaPalette.warning)
            : (pct > r.hi ? (r.stage == .awake ? "Above the range" : "Above the range", r.stage == .awake ? NunaPalette.warning : NunaPalette.restText)
                          : ("Within the range", NunaPalette.charge))
        let u = usual(r.stage)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(r.stage.nunaColor).frame(width: 10, height: 10)
                Text(r.stage.nunaName).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Text(verbatim: "\(NunaSleepFormat.duration(m)) · \(Int(pct.rounded()))%").font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                let scale = 70.0   // bar shows 0 to 70% of time in bed
                let x: (Double) -> CGFloat = { CGFloat(min(max($0, 0), scale) / scale) * w }
                ZStack(alignment: .leading) {
                    Capsule().fill(NunaPalette.ink.opacity(0.08))
                    Capsule().fill(NunaPalette.charge.opacity(0.28)).frame(width: max(4, x(r.hi) - x(r.lo))).offset(x: x(r.lo))
                    Capsule().fill(r.stage.nunaColor).frame(width: max(6, x(pct)))
                    if let u { Rectangle().fill(NunaPalette.textPrimary.opacity(0.8)).frame(width: 2, height: 14).offset(x: x(u / total * 100) - 1) }
                }
            }
            .frame(height: 10)
            HStack {
                Text(status.0).font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle(status.1)
                Spacer()
                Text(verbatim: String(localized: "Range \(Int(r.lo))–\(Int(r.hi))%")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
            if let u {
                Text(verbatim: String(localized: "Usually \(NunaSleepFormat.duration(u))")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Overnight vitals

/// Overnight vitals on the sleep clock. The summary row shows last night's figures (only those that exist). Below it, one card
/// per vital that was actually recorded through the night, drawn from onset to wake. A vital with no data has no card.
/// SpO₂ and breathing are only drawn for a ring, whose readings are real percentages and rates; a strap's raw optical and
/// respiration signals are not, so they are not charted here.
struct NunaOvernightVitals: View {
    let model: NunaSleepModel
    let night: NunaNight
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""

    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: temperatureRaw)
    }

    var body: some View {
        summary
    }

    // MARK: List

    private struct Row: Identifiable {
        let id: String; let title: LocalizedStringKey; let icon: String; let unit: String; let decimals: Int
        let value: Double; let prior: [Double]; let upIsGood: Bool?; let key: String
    }

    private var rows: [Row] {
        let d = night.daily
        let before = model.nights.dropFirst(model.index + 1).prefix(14).compactMap(\.daily)
        var out: [Row] = []
        if let v = d?.avgHrv { out.append(Row(id: "hrv", title: "HRV", icon: "waveform.path.ecg", unit: "ms", decimals: 0, value: v, prior: before.compactMap(\.avgHrv), upIsGood: true, key: "hrv")) }
        if let v = d?.restingHr { out.append(Row(id: "rhr", title: "RHR", icon: "heart", unit: "bpm", decimals: 0, value: Double(v), prior: before.compactMap { $0.restingHr.map(Double.init) }, upIsGood: false, key: "rhr")) }
        if let v = d?.spo2Pct { out.append(Row(id: "spo2", title: "SpO₂", icon: "drop", unit: "%", decimals: 0, value: v, prior: before.compactMap(\.spo2Pct), upIsGood: true, key: "spo2")) }
        if let v = d?.respRateBpm { out.append(Row(id: "resp", title: "Breathing", icon: "lungs", unit: "/min", decimals: 1, value: v, prior: before.compactMap(\.respRateBpm), upIsGood: nil, key: "resp_rate")) }
        if let v = d?.skinTempDevC {
            let f = temperatureUnit == .fahrenheit
            out.append(Row(id: "skin", title: "Skin temp", icon: "thermometer.medium", unit: UnitFormatter.temperatureUnit(temperatureUnit), decimals: 1,
                           value: f ? v * 1.8 : v, prior: before.compactMap(\.skinTempDevC).map { f ? $0 * 1.8 : $0 }, upIsGood: nil, key: "skin_temp"))
        }
        return out
    }

    @ViewBuilder private var summary: some View {
        let list = rows
        if !list.isEmpty {
            NunaCard(padding: EdgeInsets(top: 16, leading: 18, bottom: 6, trailing: 18)) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        nunaTrendsCap("Overnight vitals")
                        Spacer()
                        Text("vs last 14 nights").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    .padding(.bottom, 6)
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { NunaDivider() }
                        row(r)
                    }
                }
            }
        }
    }

    private func row(_ r: Row) -> some View {
        func f(_ x: Double) -> String { String(format: "%.\(r.decimals)f", locale: AppLanguage.activeLocale, x) }
        let avg = r.prior.isEmpty ? nil : r.prior.reduce(0, +) / Double(r.prior.count)
        let content = HStack(spacing: 12) {
            NunaIconTile(r.icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                if let avg, let lo = r.prior.min(), let hi = r.prior.max() {
                    Text(verbatim: String(localized: "Average \(f(avg)) · range \(f(lo))–\(f(hi))")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                } else {
                    Text("Not enough nights to compare").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: f(r.value)).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: r.unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
                if let avg { delta(r, avg: avg, f: f) }
            }
            if MetricCatalog.metric(key: r.key, source: "my-whoop") != nil {
                Image(systemName: "chevron.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        return Group {
            if let m = MetricCatalog.metric(key: r.key, source: "my-whoop") {
                NavigationLink(value: NunaTodayRoute.metric(m)) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    /// "▲ 4" against the average of the earlier nights, green when the move is the good way, amber when it is not.
    private func delta(_ r: Row, avg: Double, f: (Double) -> String) -> some View {
        let d = r.value - avg
        let step = r.decimals == 0 ? 0.5 : 0.05
        let good: Bool? = r.upIsGood.map { (d > 0) == $0 }
        let tint: Color = good.map { $0 ? NunaPalette.charge : NunaPalette.warning } ?? NunaPalette.textSecondary
        return Group {
            if abs(d) >= step {
                Text(verbatim: (d > 0 ? "▲ " : "▼ ") + f(abs(d))).font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle(tint)
            } else {
                Text("Like usual").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }
}
#endif
