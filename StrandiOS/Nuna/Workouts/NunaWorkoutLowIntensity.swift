#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The log of a session in which the heart rate stayed in zone 0 and zone 1 (stretching, yoga, a slow walk without a map): there are no zones
// worth a list, so it is read for the stress it kept or lifted, with its heart rate on the second tab, the sessions of the activity counted
// toward a milestone, the heart-rate figures against the wearer's own usual, and what the activity does to the next day's Charge.

// MARK: - What counts as a low-intensity session

enum NunaLowIntensity {
    /// Time in zones 2 to 5 is under a minute (or 5% of the session, if that is longer), and it was not strength work or a mapped one.
    static func applies(row: WorkoutRow, zoneMinutes: [Double]?, hasHeartRate: Bool, hasRoute: Bool) -> Bool {
        // No minutes at all in the zones, with a heart rate on file, means it never reached zone 1: that is the lowest-intensity case.
        let z = zoneMinutes ?? Array(repeating: 0, count: 5)
        guard hasHeartRate, !hasRoute, !NunaWorkoutKind.isStrength(row), z.count >= 5 else { return false }
        let minutes = (row.durationS ?? Double(row.endTs - row.startTs)) / 60
        guard minutes > 0 else { return false }
        return z.dropFirst().reduce(0, +) < max(1, minutes * 0.05)
    }
}

// MARK: - Stress through the session

enum NunaWorkoutStress {
    struct Point: Equatable { let ts: Int; let level: Double }

    /// The 0 to 3 stress through the window, one reading a minute, from the heart rate against the wearer's own calibration. Empty while the
    /// calibration is still being built or the window has too little heart rate.
    @MainActor static func series(repo: Repository, from: Int, to: Int) async -> [Point] {
        guard to - from >= 120, let cal = await StressEngine.shared.calibration(repo: repo) else { return [] }
        let hr = await repo.hrSamples(from: from - 300, to: to, limit: 50_000)
        guard hr.count > 30 else { return [] }
        let rr = await repo.rrIntervals(from: from - 300, to: to, limit: 50_000)
        var tuning = cal.tuning
        tuning.epochSeconds = 60; tuning.windowSeconds = 240; tuning.minHRSamples = 30
        let baseline = cal.baseline
        let result = await Task.detached(priority: .utility) {
            WhoopStress.analyze(hr: hr, rr: rr, baseline: baseline, from: from, to: to, tuning: tuning)
        }.value
        return result.epochs.compactMap { e in e.level.map { Point(ts: e.ts + 30, level: $0) } }
    }

    static func word(_ level: Double) -> LocalizedStringKey { level < 1 ? "Low" : (level < 2 ? "Medium" : "High") }
    static func text(_ v: Double) -> String { String(format: "%.1f", locale: AppLanguage.activeLocale, v) }
}

// MARK: - Tabs

/// A dark capsule with the chosen tab raised in it.
struct NunaCapsuleTabs<Value: Hashable>: View {
    let options: [(value: Value, title: LocalizedStringKey)]
    @Binding var selection: Value
    @Namespace private var raised

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].value
                let on = selection == value
                Button { withAnimation(.easeInOut(duration: 0.2)) { selection = value } } label: {
                    Text(options[i].title).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel + 0.8).textCase(.uppercase)
                        .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background { if on { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NunaPalette.tile).matchedGeometryEffect(id: "raised", in: raised) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NunaPalette.textPrimary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Figures

/// The two figures a low-intensity log opens with: the minutes (the seconds smaller, the usual of the activity beside it) and the stress
/// change from the first reading to the last.
struct NunaLowFigures: View {
    let row: WorkoutRow
    let averages: NunaWorkoutAverages?
    let stress: [NunaWorkoutStress.Point]

    var body: some View {
        let secs = row.durationS ?? Double(row.endTs - row.startTs)
        let t = Int(secs.rounded())
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    (Text(verbatim: String(format: "%d:%02d", t / 3600, (t % 3600) / 60)).font(.nuna(size: 40, weight: .bold, design: NunaType.design))
                        + Text(verbatim: String(format: ":%02d", t % 60)).font(.nuna(size: 24, weight: .bold, design: NunaType.design)))
                        .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    if let avg = averages?.durationS {
                        NunaAveragePill(value: secs, average: avg, text: Self.clock(avg))
                    }
                }
                caption("Minutes")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: change.map { NunaWorkoutStress.text($0) } ?? "–").font(.nuna(size: 36, weight: .bold, design: NunaType.design))
                    .foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                caption("Stress change")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var change: Double? {
        guard let a = stress.first, let b = stress.last, stress.count >= 2 else { return nil }
        return b.level - a.level
    }

    private func caption(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
    }

    private static func clock(_ s: Double) -> String {
        let t = Int(s.rounded()); return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
}

// MARK: - Stress chart

/// The stress through the session as a line between the same two dashed marks as the heart-rate chart, coloured by band, the scale 0 to 3 at
/// the left, and the first and last reading with their band above it.
struct NunaWorkoutStressArea: View {
    let points: [NunaWorkoutStress.Point]
    let start: Int
    let end: Int

    private static let plotHeight: CGFloat = 200
    private static let inset: CGFloat = 28

    var body: some View {
        let span = max(Double(end - start), 1)
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let first = points.first { reading(first.level, leading: true) }
                Spacer()
                if let last = points.last { reading(last.level, leading: false) }
            }
            .padding(.horizontal, Self.inset - 4)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let left = Self.inset, width = size.width - 2 * Self.inset
                    func pt(_ p: NunaWorkoutStress.Point) -> CGPoint {
                        CGPoint(x: left + width * CGFloat(min(max(Double(p.ts - start) / span, 0), 1)), y: size.height * CGFloat(1 - min(max(p.level, 0), 3) / 3))
                    }
                    let grid = NunaPalette.ink.opacity(0.07)
                    for v in 0...3 {
                        var g = Path(); let y = size.height * CGFloat(1 - Double(v) / 3)
                        g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(g, with: .color(grid), lineWidth: 1)
                    }
                    for q in 1...3 {
                        var g = Path(); let x = left + width * CGFloat(q) / 4
                        g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(g, with: .color(grid), lineWidth: 1)
                    }
                    for (a, b) in zip(points, points.dropFirst()) {
                        var seg = Path(); seg.move(to: pt(a)); seg.addLine(to: pt(b))
                        ctx.stroke(seg, with: .color(NunaStressBand.color(for: (a.level + b.level) / 2)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                    for x in [left, left + width] {
                        var m = Path(); m.move(to: CGPoint(x: x, y: 0)); m.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(m, with: .color(NunaPalette.textPrimary.opacity(0.75)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: size.height - 3, width: 6, height: 6)), with: .color(NunaPalette.textPrimary))
                    }
                }
                ForEach(0...3, id: \.self) { v in
                    Text(verbatim: String(format: "%.1f", Double(v))).font(.nuna(size: 10.5, weight: .bold)).foregroundStyle(NunaPalette.textMuted).monospacedDigit()
                        .position(x: 18, y: Self.plotHeight * CGFloat(1 - Double(v) / 3) - (v == 3 ? -8 : 8))
                }
            }
            .frame(height: Self.plotHeight)
            GeometryReader { geo in
                Text(verbatim: NunaWorkoutFormat.clock(start)).position(x: Self.inset, y: 8)
                Text(verbatim: NunaWorkoutFormat.clock(end)).position(x: geo.size.width - Self.inset, y: 8)
            }
            .font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(height: 16)
        }
        .padding(.horizontal, -NunaSpacing.screenH)
        .accessibilityHidden(true)
    }

    /// "0.8 LOW" at the left, "MEDIUM 2.0" at the right.
    private func reading(_ level: Double, leading: Bool) -> some View {
        HStack(spacing: 8) {
            if leading { value(level) }
            Text(NunaWorkoutStress.word(level)).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel + 0.6).textCase(.uppercase)
                .foregroundStyle(NunaStressBand.color(for: level))
            if !leading { value(level) }
        }
    }

    private func value(_ level: Double) -> some View {
        Text(verbatim: NunaWorkoutStress.text(level)).font(.nuna(size: 18, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
    }
}

// MARK: - Milestone

/// "4/5, 1 more until your next milestone": the sessions of this activity so far against the next round number, in an outlined card with a
/// locked badge at the left.
struct NunaActivityMilestoneCard: View {
    let count: Int
    private static let marks = [5, 10, 25, 50, 100, 250, 500, 1000]

    var body: some View {
        let next = Self.marks.first { $0 > count } ?? (count + 1)
        HStack(spacing: 18) {
            badge.frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 8) {
                (Text(verbatim: "\(count)").foregroundStyle(NunaPalette.effortModerate) + Text(verbatim: "/\(next)").foregroundStyle(NunaPalette.textPrimary))
                    .font(.nuna(size: 20, weight: .heavy))
                Text(verbatim: String(localized: "\(next - count) more until your next milestone")).font(.nuna(size: 14, weight: .regular)).textCase(nil)
                    .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(NunaPalette.textPrimary.opacity(0.14))
                        Rectangle().fill(NunaPalette.effortModerate).frame(width: geo.size.width * CGFloat(min(1, Double(count) / Double(next))))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 18)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NunaPalette.textPrimary.opacity(0.16), lineWidth: 1.5))
    }

    /// A scalloped dark disc with a lock: the badge is not earned yet.
    private var badge: some View {
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2), r = size.width / 2 - 1
                var p = Path()
                for i in 0...180 {
                    let a = Double(i) / 180 * 2 * Double.pi
                    let rr = r * (1 + 0.035 * sin(28 * a)) * 0.96
                    let pt = CGPoint(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a)))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                p.closeSubpath()
                ctx.fill(p, with: .color(Color(white: 0.05)))
                ctx.stroke(p, with: .color(NunaPalette.textPrimary.opacity(0.15)), lineWidth: 1)
            }
            Image(systemName: "lock.fill").font(.system(size: 24, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
        }
    }
}

// MARK: - Session metrics

/// The heart-rate figures of the session, each beside the wearer's usual for the activity, scrolling sideways.
struct NunaSessionMetrics: View {
    struct Item: Identifiable {
        let id: String; let icon: String; let label: LocalizedStringKey; let value: String
        var pill: (value: Double, average: Double, text: String)?
    }
    let items: [Item]
    var showsRange = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                nunaTrendsCap("Session metrics")
                Spacer()
                if showsRange { Text("vs. 30 day range").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textMuted) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) { ForEach(items) { tile($0).frame(width: 168) } }
                    .padding(.horizontal, NunaSpacing.screenH)
            }
            .padding(.horizontal, -NunaSpacing.screenH)
        }
    }

    private func tile(_ t: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: t.icon).font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                Text(t.label).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel + 0.4).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            }
            .padding(.bottom, 6)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: t.value).font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                if t.value != "–" { Text(verbatim: "bpm").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil) }
            }
            .padding(.bottom, 4)
            if let p = t.pill { NunaAveragePill(value: p.value, average: p.average, text: p.text) } else { Color.clear.frame(height: 28) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Impact on recovery

/// What an activity does to the next day's Charge: the days it was done and the days it was not, counted toward five each, and once both
/// are there, the difference between them. Nothing is claimed before that.
struct NunaActivityImpact {
    let withDays: Int
    let withoutDays: Int
    let percent: Double?

    static let needed = BehaviorSummary.answersNeeded

    /// From the saved sessions and the daily rows, over the last 90 days. The outcome of a day is the Charge of the day after it.
    @MainActor static func compute(row: WorkoutRow, rows: [WorkoutRow], days: [DailyMetric]) -> NunaActivityImpact {
        let cal = Calendar.current
        let since = row.startTs - 90 * 86_400
        func key(_ ts: Int) -> String { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(ts))) }
        let done = Set(rows.filter { $0.sport == row.sport && $0.startTs >= since && $0.startTs <= row.endTs + 86_400 }.map { key($0.startTs) })
        let known = days.filter { $0.day >= key(since) && $0.day <= key(row.startTs) }.map(\.day)
        let without = Set(known).subtracting(done)
        var next: [String: Double] = [:]
        let byDay = Dictionary(days.compactMap { d in d.recovery.map { (d.day, $0) } }, uniquingKeysWith: { a, _ in a })
        for d in Set(known).union(done) {
            guard let date = DateFormatter.dayKey.date(from: d), let after = cal.date(byAdding: .day, value: 1, to: date),
                  let r = byDay[Repository.localDayKey(after)] else { continue }
            next[d] = r
        }
        var pct: Double?
        if done.count >= needed, without.count >= needed,
           let e = BehaviorInsights.effect(behaviorDays: done, controlDays: without, outcomeByDay: next, behavior: row.sport, outcome: "Charge"), e.significant {
            pct = e.pctChange
        }
        return NunaActivityImpact(withDays: done.count, withoutDays: without.count, percent: pct)
    }
}

private extension DateFormatter {
    static let dayKey: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
}

struct NunaActivityImpactCard: View {
    let impact: NunaActivityImpact

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Impact on recovery").font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel + 0.8).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                if let p = impact.percent {
                    Text(verbatim: String(format: "%+.0f%%", locale: AppLanguage.activeLocale, p)).font(.nuna(size: 22, weight: .bold, design: NunaType.design))
                        .foregroundStyle(p >= 0 ? NunaPalette.charge : NunaPalette.alertText)
                } else {
                    Text(verbatim: "--%").font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textMuted)
                }
            }
            Text(impact.percent != nil
                 ? "The day after you do this activity, your Charge differs by this much from the days you do not."
                 : (impact.withDays >= NunaActivityImpact.needed && impact.withoutDays >= NunaActivityImpact.needed
                    ? "There is no clear difference yet in the next day's Charge between the days you do this activity and the days you do not."
                    : "Keep logging this activity to receive insights. Once you reach 5 days with and 5 days without this activity, impacts will be unlocked."))
                .font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            dots(count: impact.withDays, mark: "checkmark", tint: NunaPalette.effortModerate)
            dots(count: impact.withoutDays, mark: "xmark", tint: NunaPalette.textPrimary)
            NavigationLink { NunaBehaviorInsightsView() } label: {
                HStack(spacing: 10) {
                    Text("View more impacts").font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel + 0.8).textCase(.uppercase)
                    Image(systemName: "arrow.right").font(.system(size: 16, weight: .regular))
                }
                .foregroundStyle(NunaPalette.textPrimary).frame(minHeight: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.tile.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Five circles filled in one by one, and "3/5" at the end of the row.
    private func dots(count: Int, mark: String, tint: Color) -> some View {
        let shown = min(count, NunaActivityImpact.needed)
        return HStack(spacing: 10) {
            ForEach(0..<NunaActivityImpact.needed, id: \.self) { i in
                ZStack {
                    Circle().strokeBorder(i < shown ? tint : tint.opacity(0.4), lineWidth: 2)
                    if i < shown {
                        Circle().fill(tint.opacity(0.22))
                        Image(systemName: mark).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                    }
                }
                .frame(width: 34, height: 34)
            }
            Spacer(minLength: 4)
            Text(verbatim: "\(shown)/\(NunaActivityImpact.needed)").font(.nuna(size: 17, weight: .heavy))
                .foregroundStyle(mark == "checkmark" ? NunaPalette.effortModerate : NunaPalette.textPrimary)
        }
    }
}
#endif
