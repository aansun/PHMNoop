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
    @State private var hr: [HRBucket] = []

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
                    heartRate
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
        .task(id: night.dayKey) {
            selected = nil
            hr = await repo.hrBuckets(from: Int(night.chartWindow.start.timeIntervalSince1970), to: Int(night.chartWindow.end.timeIntervalSince1970), bucketSeconds: 60)
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

    @ViewBuilder private var heartRate: some View {
        let pts = hr.filter { Double($0.ts) >= night.onset.timeIntervalSince1970 + origin - 60 && Double($0.ts) <= night.onset.timeIntervalSince1970 + origin + span + 60 }
            .map { (date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: $0.bpm) }
        if pts.count >= 2 {
            let washes: [(from: Date, to: Date)] = selected.map { s in
                smoothed.filter { $0.stage == s }.map { (night.onset.addingTimeInterval($0.start), night.onset.addingTimeInterval($0.end)) }
            } ?? []
            VStack(alignment: .leading, spacing: 4) {
                Text("Heart rate through the night").font(.nuna(size: 11.5, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                NunaNightLineChart(start: windowStart, end: windowEnd, points: pts,
                                   color: selected == nil ? NunaPalette.rest : NunaPalette.textMuted.opacity(0.7),
                                   height: 124, lineWidth: 1.6, washes: washes, washColor: selected?.nunaColor ?? NunaPalette.rest)
                    .padding(.horizontal, 10)
            }
        } else {
            Text("No heart-rate detail for this night").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
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

// MARK: - Overnight vitals

/// Overnight vitals on the sleep clock. The summary row shows last night's figures (only those that exist). Below it, one card
/// per vital that was actually recorded through the night, drawn from onset to wake. A vital with no data has no card.
/// SpO₂ and breathing are only drawn for a ring, whose readings are real percentages and rates; a strap's raw optical and
/// respiration signals are not, so they are not charted here.
struct NunaOvernightVitals: View {
    let night: NunaNight
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""

    private struct Vital: Identifiable {
        let id: String; let title: LocalizedStringKey; let unit: String; let decimals: Int; let color: Color
        var points: [(date: Date, value: Double)]
    }
    @State private var vitals: [Vital] = []
    @State private var loadedKey = ""

    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: temperatureRaw)
    }

    var body: some View {
        VStack(spacing: 12) {
            summary
            ForEach(vitals) { card($0) }
        }
        .task(id: "\(night.dayKey)-\(temperatureRaw)-\(unitSystemRaw)") { await load() }
    }

    // MARK: Summary

    @ViewBuilder private var summary: some View {
        let items: [(LocalizedStringKey, String)] = [
            ("HRV", night.daily?.avgHrv.map { String(format: "%.0f", locale: AppLanguage.activeLocale, $0) }),
            ("Resting HR", night.daily?.restingHr.map { "\($0)" }),
            ("SpO₂", night.daily?.spo2Pct.map { "\(Int($0.rounded()))%" }),
            ("Breathing", night.daily?.respRateBpm.map { String(format: "%.1f", locale: AppLanguage.activeLocale, $0) }),
        ].compactMap { l, v in v.map { (l, $0) } }
        if !items.isEmpty {
            NavigationLink(value: NunaTodayRoute.sleepVitals(0)) {
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            nunaTrendsCap("Overnight vitals")
                            Spacer()
                            Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }
                        HStack(alignment: .top) {
                            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(it.0).font(.nuna(size: 11, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                                    Text(verbatim: it.1).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }.buttonStyle(.plain)
        }
    }

    // MARK: A vital over the night

    private func card(_ v: Vital) -> some View {
        let vals = v.points.map(\.value)
        let avg = vals.reduce(0, +) / Double(max(vals.count, 1))
        let lo = vals.min() ?? 0, hi = vals.max() ?? 0
        func f(_ x: Double) -> String { String(format: "%.\(v.decimals)f", locale: AppLanguage.activeLocale, x) }
        return NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(v.title).font(.nuna(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    Text(verbatim: "\(f(lo)) – \(f(hi)) \(v.unit)").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: f(avg)).font(.nuna(size: NunaTypeSize.numberM, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: v.unit).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    Text("average").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                }
                NunaNightLineChart(start: night.chartWindow.start, end: night.chartWindow.end, points: v.points, color: v.color, decimals: v.decimals, height: 118, gap: 1800, average: avg)
                NunaTimeAxis(start: night.chartWindow.start, end: night.chartWindow.end)
            }
        }
    }

    // MARK: Data

    private func load() async {
        let from = Int(night.chartWindow.start.timeIntervalSince1970), to = Int(night.chartWindow.end.timeIntervalSince1970)
        guard to > from else { vitals = []; return }
        var out: [Vital] = []
        let hrv = await repo.timelineSeries(metric: .hrv, from: from, to: to, targetPoints: 240)
        if hrv.points.count >= 8 {
            out.append(Vital(id: "hrv", title: "HRV through the night", unit: "ms", decimals: 0, color: NunaPalette.charge, points: hrv.points.map { ($0.date, $0.value) }))
        }
        let temp = await repo.timelineSeries(metric: .skinTemp, from: from, to: to, targetPoints: 240)
        if temp.points.count >= 8 {
            let f = temperatureUnit == .fahrenheit
            out.append(Vital(id: "skin", title: "Skin temperature", unit: UnitFormatter.temperatureUnit(temperatureUnit), decimals: 1, color: NunaPalette.warning,
                             points: temp.points.map { ($0.date, f ? UnitFormatter.celsiusToFahrenheit($0.value) : $0.value) }))
        }
        if repo.activeDeviceIsOura {
            let spo2 = await repo.timelineSeries(metric: .spo2, from: from, to: to, targetPoints: 240)
            if spo2.points.count >= 8 { out.append(Vital(id: "spo2", title: "Blood oxygen", unit: "%", decimals: 0, color: NunaPalette.effort, points: spo2.points.map { ($0.date, $0.value) })) }
            let resp = await repo.timelineSeries(metric: .respiration, from: from, to: to, targetPoints: 240)
            if resp.points.count >= 8 { out.append(Vital(id: "resp", title: "Breathing", unit: "/min", decimals: 1, color: NunaPalette.rest, points: resp.points.map { ($0.date, $0.value) })) }
        }
        vitals = out
    }
}
#endif
