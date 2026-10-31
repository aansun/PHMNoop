#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The session log of one saved workout, laid out like a log and not like a stack of cards: the Effort and the time on top, the
// heart-rate curve, the key statistics together on one screen (each against the wearer's own 30-day average of the same sport), then the
// zones. The header carries the three actions: share (a file, or Strava when it is available), edit the time, delete.

// MARK: - Averages of the same sport

/// The wearer's own 30-day average of one sport, taken from the other saved sessions of that sport. nil under two sessions: an average
/// of one is the session itself.
struct NunaWorkoutAverages {
    let effort: Double?, durationS: Double?, kcal: Double?, avgHr: Double?, maxHr: Double?, distanceM: Double?, steps: Double?
    /// How many other sessions of the sport the averages are taken from.
    let count: Int

    init?(for row: WorkoutRow, in rows: [WorkoutRow]) {
        let from = row.startTs - 30 * 86_400
        let others = rows.filter { $0.sport == row.sport && $0.startTs != row.startTs && $0.startTs >= from && $0.startTs < row.startTs }
        guard others.count >= 2 else { return nil }
        count = others.count
        func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        effort = mean(others.compactMap(\.strain))
        durationS = mean(others.map { $0.durationS ?? Double($0.endTs - $0.startTs) })
        kcal = mean(others.compactMap(\.energyKcal))
        avgHr = mean(others.compactMap { $0.avgHr.map(Double.init) })
        maxHr = mean(others.compactMap { $0.maxHr.map(Double.init) })
        distanceM = mean(others.compactMap(\.distanceM))
        steps = mean(others.compactMap { $0.steps.map(Double.init) })
    }
}

/// "▼ 147 bpm": which side of the average this session sits on, and the average itself.
struct NunaAveragePill: View {
    let value: Double
    let average: Double
    let text: String
    /// A smaller pill, beside the figure at the top of the gym session.
    var compact = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: value >= average ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: compact ? 8 : 10, weight: .bold))
            Text(verbatim: text).font(.nuna(size: compact ? 11.5 : 13.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        .padding(.horizontal, compact ? 7 : 10).frame(height: compact ? 22 : 28)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Header

/// When it ran, under the screen title (the sport's symbol sits beside the title).
struct NunaWorkoutLogHeader: View {
    let row: WorkoutRow
    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: NunaWorkoutFormat.day(row.startTs) + " · " + NunaWorkoutFormat.clock(row.startTs) + " – " + NunaWorkoutFormat.clock(row.endTs))
                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
        }
    }
}

// MARK: - Effort and time

/// The two figures the log opens with: the Effort the session added and how long it ran, each with the 30-day average beside it.
struct NunaWorkoutLogFigures: View {
    let row: WorkoutRow
    let averages: NunaWorkoutAverages?
    /// With the steps known they take the second place (the duration then moves to the head of the zones, see `NunaWorkoutLogZones`).
    var steps: Int? = nil
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        let secs = row.durationS ?? Double(row.endTs - row.startTs)
        HStack(alignment: .top, spacing: 16) {
            figure(label: "Activity Effort",
                   value: row.strain.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–",
                   color: row.strain.map(nunaEffortColor) ?? NunaPalette.textPrimary,
                   pill: row.strain.flatMap { s in averages?.effort.map { avg in
                       NunaAveragePill(value: s, average: avg, text: UnitFormatter.effortDisplay(avg, scale: scale)) } })
            if let steps {
                figure(label: "Activity Steps", value: NunaTrendsFormat.num(Double(steps)), color: NunaPalette.textPrimary,
                       pill: averages?.steps.map { avg in NunaAveragePill(value: Double(steps), average: avg, text: NunaTrendsFormat.num(avg)) })
            } else {
                figure(label: "Duration", value: Self.clock(secs), color: NunaPalette.textPrimary,
                       pill: averages?.durationS.map { avg in NunaAveragePill(value: secs, average: avg, text: Self.clock(avg)) })
            }
        }
    }

    private func figure(label: LocalizedStringKey, value: String, color: Color, pill: NunaAveragePill?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(verbatim: value).font(.nuna(size: 40, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(40))
                    .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
                if let pill { pill }
            }
            Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func clock(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Heart rate

/// The heart rate through the session as a filled curve between two dashed marks (the start and the end, a dot at the foot of each, their times
/// under them). The beats-per-minute scale sits on the faint grid at the left. The curve goes on a little past both marks in grey, as the minutes
/// around the session, so the two margins are alike. With a zone picked, the whole session goes grey and the stretches spent in the zone are lit
/// in its colour, at their time and length.
struct NunaWorkoutHRArea: View {
    /// The session itself.
    let buckets: [HRBucket]
    let start: Int
    let end: Int
    /// The same curve with a few minutes either side (see `NunaWorkoutDetailData.hrAround`); the session alone when empty.
    var around: [HRBucket] = []
    /// A zone (1...5) picked in the zone list.
    var highlightZone: Int? = nil
    var zoneSet: HRZoneSet? = nil
    /// Stretches of the session (start and end times) to light in green, such as the sets of the exercise on the card below the chart.
    var rangeHighlight: [ClosedRange<Int>] = []

    /// The height of the plot itself (the gym session, which has more under it, draws it lower).
    var plotHeight: CGFloat = 150
    /// The room either side of the dashed marks: the scale at the left, the minutes around the session at both.
    private static let inset: CGFloat = 28

    var body: some View {
        let session = buckets.sorted { $0.ts < $1.ts }
        let pts = (around.count >= 2 ? around : buckets).sorted { $0.ts < $1.ts }
        let lo = floor((pts.map(\.bpm).min() ?? 0) / 25) * 25
        let hi = max(ceil((pts.map(\.bpm).max() ?? 25) / 25) * 25, lo + 25)
        let span = max(Double(end - start), 1)
        let lit = (highlightZone != nil && zoneSet != nil) || !rangeHighlight.isEmpty
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let left = Self.inset, width = size.width - 2 * Self.inset
                    func pt(_ b: HRBucket) -> CGPoint {
                        CGPoint(x: left + width * CGFloat(Double(b.ts - start) / span), y: size.height * CGFloat(1 - (b.bpm - lo) / (hi - lo)))
                    }
                    let grid = NunaPalette.ink.opacity(0.07)
                    for v in stride(from: lo, through: hi, by: 25) {
                        var g = Path(); let y = size.height * CGFloat(1 - (v - lo) / (hi - lo))
                        g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(g, with: .color(grid), lineWidth: 1)
                    }
                    for q in 1...3 {
                        var g = Path(); let x = left + width * CGFloat(q) / 4
                        g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(g, with: .color(grid), lineWidth: 1)
                    }
                    if pts.count >= 2 {
                        var line = Path()
                        for (i, b) in pts.enumerated() { i == 0 ? line.move(to: pt(b)) : line.addLine(to: pt(b)) }
                        // Around the session: the line only, grey.
                        ctx.stroke(line, with: .color(NunaPalette.textSecondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        // The session: the area and the line, inside the two marks.
                        var inner = ctx
                        inner.clip(to: Path(CGRect(x: left, y: 0, width: width, height: size.height)))
                        var area = line
                        area.addLine(to: CGPoint(x: pt(pts[pts.count - 1]).x, y: size.height))
                        area.addLine(to: CGPoint(x: pt(pts[0]).x, y: size.height))
                        area.closeSubpath()
                        inner.fill(area, with: .linearGradient(Gradient(colors: [NunaWorkoutLogZones.hrBlue.opacity(lit ? 0.10 : 0.36), NunaPalette.effortMinimal.opacity(lit ? 0.02 : 0.05)]),
                                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                        inner.stroke(line, with: .color(lit ? NunaPalette.textSecondary.opacity(0.55) : NunaWorkoutLogZones.hrBlue),
                                     style: StrokeStyle(lineWidth: lit ? 1.6 : 2.2, lineCap: .round, lineJoin: .round))
                        if let zone = highlightZone, let zoneSet {
                            let color = NunaWorkoutLogZones.color(zone)
                            // The stretches spent in the zone, broken wherever the heart rate left it (or a gap in the readings): each one
                            // is the area under the curve itself, so the colour follows the line instead of standing in columns over it.
                            var runs: [[CGPoint]] = []
                            var current: [CGPoint] = []
                            for i in session.indices {
                                let inZone = zoneSet.zoneNumber(forBPM: session[i].bpm) == zone
                                let gap = i > 0 && session[i].ts - session[i - 1].ts > 300
                                if inZone, !gap { current.append(pt(session[i])) }
                                else {
                                    if current.count >= 2 { runs.append(current) }
                                    current = inZone ? [pt(session[i])] : []
                                }
                            }
                            if current.count >= 2 { runs.append(current) }
                            for run in runs {
                                var fill = Path()
                                fill.move(to: CGPoint(x: run[0].x, y: size.height))
                                for q in run { fill.addLine(to: q) }
                                fill.addLine(to: CGPoint(x: run[run.count - 1].x, y: size.height))
                                fill.closeSubpath()
                                inner.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.6), color.opacity(0.1)]),
                                                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                                var seg = Path(); seg.move(to: run[0])
                                for q in run.dropFirst() { seg.addLine(to: q) }
                                inner.stroke(seg, with: .color(color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                            }
                        }
                    }
                    if !rangeHighlight.isEmpty, pts.count >= 2 {
                        var inner = ctx
                        inner.clip(to: Path(CGRect(x: left, y: 0, width: width, height: size.height)))
                        let color = NunaWorkoutLogZones.colors[2]
                        for r in rangeHighlight {
                            let near = session.filter { $0.ts >= r.lowerBound - 20 && $0.ts <= r.upperBound + 20 }
                            guard near.count >= 2 else { continue }
                            let run = near.map(pt)
                            var fill = Path()
                            fill.move(to: CGPoint(x: run[0].x, y: size.height))
                            for q in run { fill.addLine(to: q) }
                            fill.addLine(to: CGPoint(x: run[run.count - 1].x, y: size.height))
                            fill.closeSubpath()
                            inner.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0.08)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                            var seg = Path(); seg.move(to: run[0])
                            for q in run.dropFirst() { seg.addLine(to: q) }
                            inner.stroke(seg, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        }
                    }
                    // The start and the end of the session: dashed marks with a dot at the foot.
                    for x in [left, left + width] {
                        var m = Path(); m.move(to: CGPoint(x: x, y: 0)); m.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(m, with: .color(NunaPalette.textPrimary.opacity(0.75)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: size.height - 3, width: 6, height: 6)), with: .color(NunaPalette.textPrimary))
                    }
                }
                ForEach(Array(stride(from: lo, through: hi, by: 25)), id: \.self) { v in
                    Text(verbatim: "\(Int(v))").font(.nuna(size: 10.5, weight: .bold)).foregroundStyle(NunaPalette.textMuted).monospacedDigit()
                        .position(x: 14, y: plotHeight * CGFloat(1 - (v - lo) / (hi - lo)) - 8)
                }
            }
            .frame(height: plotHeight)
            // The two times, each centred under its mark.
            GeometryReader { geo in
                let left = Self.inset, right = geo.size.width - Self.inset
                Text(verbatim: NunaWorkoutFormat.clock(start)).position(x: left, y: 8)
                Text(verbatim: NunaWorkoutFormat.clock(end)).position(x: right, y: 8)
            }
            .font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(height: 16)
        }
        .padding(.top, 10)
        // Edge to edge: the scale sits at the screen's own edge and the two marks are the same distance from either side.
        .padding(.horizontal, -NunaSpacing.screenH)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.2), value: highlightZone)
    }
}

// MARK: - Zones

/// A track with diagonal hatching, the empty part of a zone's bar.
private struct NunaHatchedTrack: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path(); var x: CGFloat = -size.height
            while x < size.width {
                p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0)); x += 5
            }
            ctx.stroke(p, with: .color(NunaPalette.ink.opacity(0.16)), lineWidth: 1.2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

/// One card per zone, the hardest first: its name and bpm range, its share of the session and the time spent there. A zone with no time is a
/// single quiet line. Each other card has a hatched bar holding the zone's share of the session; once a zone is picked, every bar instead shows
/// where in the session the heart rate was in its zone (the picked zone in its colour, the rest in grey), the way the curve above lights it.
struct NunaWorkoutLogZones: View {
    let minutes: [Double]?
    /// The zone (1...5) whose stretches are lit on the heart-rate curve above; tapping a card picks it, tapping it again clears it.
    @Binding var selection: Int?
    /// The curve, for the stretches (optional: without it the bars always show the share).
    var buckets: [HRBucket] = []
    var start = 0
    var end = 0
    /// The usual share of each zone (see `typical(for:in:)`), drawn as a dashed box on the bar while nothing is picked.
    var typical: [ClosedRange<Double>]? = nil
    /// The session's length, said at the right of the head of the list (when the figures at the top do not say it).
    var durationS: Double? = nil
    @EnvironmentObject private var profile: ProfileStore

    /// Time under the lowest zone, in minutes: the "Zone 0" row at the foot of the list. nil when it is not known (the zones came as stored
    /// percentages that already add up to the whole session), and the row is left out.
    var belowMinutes: Double? = nil

    /// The colour of a zone: white for zone 0, then the five below.
    static func color(_ zone: Int) -> Color { zone <= 0 ? Color(hex: "#EEF1F4") : colors[min(zone, 5) - 1] }

    /// The heart-rate curve: a steel blue, calmer than the bright Effort blue.
    static let hrBlue = Color(hex: "#2F78B4")

    /// Lowest zone to highest: pale steel, blue, green, amber, red.
    static let colors: [Color] = [Color(hex: "#A9BAC8"), Color(hex: "#4F97C2"), Color(hex: "#6BB894"), Color(hex: "#D4A55A"), Color(hex: "#CF6068")]

    /// The usual share of a session spent in each zone (index 0 = zone 1), as the middle half (25th to 75th percentile) of the wearer's other
    /// sessions of the same sport over the last 30 days. nil under three of them with zones: a range of one or two is not usual yet.
    static func typical(for row: WorkoutRow, in rows: [WorkoutRow]) -> [ClosedRange<Double>]? {
        let from = row.startTs - 30 * 86_400
        let shares = rows.filter { $0.sport == row.sport && $0.startTs != row.startTs && $0.startTs >= from && $0.startTs < row.startTs }
            .compactMap { WorkoutZones.percents($0.zonesJSON) }.filter { $0.count >= 5 }.map { $0.map { $0 / 100 } }
        guard shares.count >= 3 else { return nil }
        func pct(_ v: [Double], _ q: Double) -> Double {
            let s = v.sorted(); let pos = q * Double(s.count - 1); let i = Int(pos.rounded(.down)), j = min(i + 1, s.count - 1)
            return s[i] + (s[j] - s[i]) * (pos - Double(i))
        }
        return (0..<5).map { z in let col = shares.map { $0[z] }; return pct(col, 0.25)...pct(col, 0.75) }
    }

    /// Where the heart rate was in a zone, as fractions (0...1) of the session: each reading holds until the next (at most twice the usual
    /// spacing), and neighbouring readings in the zone join into one stretch.
    private func stretches(zone: Int) -> [ClosedRange<Double>] {
        let pts = buckets.sorted { $0.ts < $1.ts }
        guard pts.count >= 2, end > start else { return [] }
        let diffs = zip(pts.dropFirst(), pts).map { Double($0.ts - $1.ts) }.filter { $0 > 0 }.sorted()
        let step = diffs.isEmpty ? 60 : diffs[diffs.count / 2]
        let span = Double(end - start)
        var out: [ClosedRange<Double>] = []
        for i in pts.indices where profile.hrZoneSet.zoneNumber(forBPM: pts[i].bpm) == zone {
            let next = i + 1 < pts.count ? Double(pts[i + 1].ts - pts[i].ts) : step
            let a = min(max(Double(pts[i].ts - start) / span, 0), 1)
            let b = min(max((Double(pts[i].ts - start) + min(next, step * 2)) / span, 0), 1)
            if let last = out.last, a - last.upperBound < 0.002 { out[out.count - 1] = last.lowerBound...max(b, last.upperBound) }
            else { out.append(a...max(b, a)) }
        }
        return out
    }

    var body: some View {
        let bands = profile.hrZoneSet.zones
        VStack(alignment: .leading, spacing: 8) {
            if let mins = minutes, mins.count >= 5, mins.contains(where: { $0 > 0 }) || (belowMinutes ?? 0) > 0 {
                let total = max(mins.reduce(0, +) + (belowMinutes ?? 0), 0.0001)
                let list: [(zone: Int, mins: Double)] = (1...5).reversed().map { ($0, mins[$0 - 1]) } + (belowMinutes.map { [(0, $0)] } ?? [])
                if (typical != nil && selection == nil) || durationS != nil {
                    HStack(spacing: 8) {
                        if typical != nil, selection == nil {
                            ZStack {
                                Rectangle().fill(NunaPalette.textPrimary.opacity(0.12))
                                HStack { Rectangle().fill(NunaPalette.textSecondary).frame(width: 1); Spacer(); Rectangle().fill(NunaPalette.textSecondary).frame(width: 1) }
                            }
                            .frame(width: 14, height: 18)
                            Text("Typical range").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer()
                        if let durationS {
                            let t = Int(durationS.rounded())
                            Text("Duration").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                            Text(verbatim: String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)).font(.nuna(size: 14, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(NunaPalette.textPrimary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                ForEach(list, id: \.zone) { item in
                    let zone = item.zone, m = item.mins
                    let on = m * 60 >= 1
                    let share = m / total
                    let picked = selection == zone
                    let tint = Self.color(zone)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text(verbatim: String(localized: "Zone \(zone)")).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingHead(0.8)).textCase(.uppercase)
                                .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textMuted)
                            if zone >= 1, zone <= bands.count {
                                Text(verbatim: "\(Int(bands[zone - 1].lower.rounded()))–\(Int(bands[zone - 1].upper.rounded())) BPM").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingHead(0.4))
                                    .foregroundStyle(NunaPalette.textMuted).textCase(nil)
                            } else if zone == 0, let first = bands.first {
                                Text(verbatim: "<\(Int(first.lower.rounded())) BPM").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingHead(0.4))
                                    .foregroundStyle(NunaPalette.textMuted).textCase(nil)
                            }
                            Text(verbatim: "\(Int((share * 100).rounded()))%").font(.nuna(size: 13, weight: .heavy))
                                .foregroundStyle(on ? tint : tint.opacity(0.45))
                            Spacer(minLength: 8)
                            time(m * 60, on: on)
                        }
                        if on {
                            bar(zone: zone, share: share, color: tint, usual: zone >= 1 ? typical.flatMap { $0.indices.contains(zone - 1) ? $0[zone - 1] : nil } : nil)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, on ? 12 : 9)
                    .background(picked ? Color.clear : NunaPalette.tile, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(NunaPalette.textPrimary.opacity(picked ? 0.9 : 0), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture { if on { selection = picked ? nil : zone } }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(on ? .isButton : [])
                }
            } else {
                Text("No heart-rate readings were recorded for this session.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selection)
    }

    /// The hatched bar: the zone's share while nothing is picked, its stretches through the session once a zone is.
    private func bar(zone: Int, share: Double, color: Color, usual: ClosedRange<Double>?) -> some View {
        let h: CGFloat = 13
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                NunaHatchedTrack().frame(height: h)
                if let pick = selection, !buckets.isEmpty {
                    let tint = pick == zone ? color : NunaPalette.textSecondary.opacity(0.7)
                    ForEach(Array(stretches(zone: zone).enumerated()), id: \.offset) { _, r in
                        let x = geo.size.width * CGFloat(r.lowerBound)
                        RoundedRectangle(cornerRadius: 1, style: .continuous).fill(tint)
                            .frame(width: max(geo.size.width * CGFloat(r.upperBound - r.lowerBound), 3), height: h).offset(x: min(x, geo.size.width - 3))
                    }
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: max(geo.size.width * CGFloat(share), 10), height: h)
                }
            }
            .frame(width: geo.size.width, height: h)
            // The usual range stands a little proud of the bar, so it is laid over it and does not take part in the layout.
            .overlay(alignment: .leading) {
                if selection == nil, let usual {
                    let x = geo.size.width * CGFloat(usual.lowerBound), w = max(geo.size.width * CGFloat(usual.upperBound - usual.lowerBound), 8)
                    ZStack {
                        Rectangle().fill(NunaPalette.textPrimary.opacity(0.1))
                        HStack(spacing: 0) {
                            Rectangle().fill(NunaPalette.textPrimary.opacity(0.7)).frame(width: 1)
                            Spacer(minLength: 0)
                            Rectangle().fill(NunaPalette.textPrimary.opacity(0.7)).frame(width: 1)
                        }
                        .mask(VStack(spacing: 3) { ForEach(0..<4, id: \.self) { _ in Rectangle().frame(height: 3) } })
                    }
                    .frame(width: w, height: 21).offset(x: min(x, geo.size.width - w))
                }
            }
        }
        .frame(height: h)
    }

    /// "0:02:50", the seconds smaller and in a lighter tone.
    private func time(_ seconds: Double, on: Bool) -> some View {
        let t = Int(seconds.rounded())
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: String(format: "%d:%02d", t / 3600, (t % 3600) / 60)).font(.nuna(size: 17, weight: .heavy)).monospacedDigit()
                .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textMuted)
            Text(verbatim: String(format: ":%02d", t % 60)).font(.nuna(size: 13, weight: .heavy)).monospacedDigit().foregroundStyle(NunaPalette.textMuted)
        }
    }
}

// MARK: - Key statistics

/// The title of a block of figures on a workout log ("KEY STATISTICS", "SESSION METRICS"): white and heavy, with the comparison to its right
/// small and grey.
struct NunaLogSectionTitle: View {
    let title: LocalizedStringKey
    var trailing: LocalizedStringKey?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.nuna(size: 14.5, weight: .black)).tracking(nunaTrackingHead(1)).textCase(.uppercase).foregroundStyle(Color.white)
            Spacer()
            if let trailing { Text(trailing).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingHead(0.4)).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary) }
        }
    }
}


/// Everything the session measured, together: distance and steps for the sports that cover ground (GPS and treadmill alike), pace or speed,
/// calories and the heart rate. Each tile carries the 30-day average of the same sport when there is one.
struct NunaWorkoutLogStats: View {
    let row: WorkoutRow
    let steps: Int?
    let averages: NunaWorkoutAverages?
    /// The distance (and so the pace) was worked out from steps and height, not measured.
    var distanceEstimated = false
    /// The route card above already says distance, pace and climb: those tiles are left out here, and the rest scroll sideways.
    var routeShown = false
    /// The steps are already one of the two figures at the top.
    var stepsAtTop = false
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceRaw = ""

    private var system: UnitSystem { UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceRaw) }

    private struct Tile: Identifiable {
        let id: String; let icon: String; let label: LocalizedStringKey; let value: String; let unit: String
        /// Shown after the value, smaller (the seconds of a duration).
        var small = ""
        var pill: (value: Double, average: Double, text: String)?
    }

    static func coversGround(_ sport: String) -> Bool {
        StravaActivityType.isTreadmill(sport) || [.onFoot, .cycling, .swimming, .rowing, .otherDistance].contains(NunaWorkoutSportKind.of(sport))
    }

    private func distanceParts(_ m: Double?) -> (String, String)? {
        guard let m, m > 0 else { return nil }
        if NunaWorkoutSportKind.of(row.sport) == .swimming || NunaWorkoutSportKind.of(row.sport) == .rowing {
            return system == .imperial ? ("\(Int((m * 1.0936).rounded()))", "yd") : ("\(Int(m.rounded()))", "m")
        }
        return system == .imperial ? (String(format: "%.2f", locale: AppLanguage.activeLocale, m / 1609.344), "mi")
                                   : (String(format: "%.2f", locale: AppLanguage.activeLocale, m / 1000), "km")
    }

    private var tiles: [Tile] {
        let secs = row.durationS ?? Double(row.endTs - row.startTs)
        let kind = NunaWorkoutSportKind.of(row.sport)
        let treadmill = StravaActivityType.isTreadmill(row.sport)
        let ground = Self.coversGround(row.sport)
        let onFoot = kind == .onFoot || treadmill
        var out: [Tile] = []

        if ground {
            let d = distanceParts(row.distanceM)
            var t = Tile(id: "dist", icon: "point.topleft.down.to.point.bottomright.curvepath", label: distanceEstimated ? "Estimated distance" : "Distance", value: d?.0 ?? "–", unit: d?.1 ?? "")
            if let m = row.distanceM, let avg = averages?.distanceM, let a = distanceParts(avg) { t.pill = (m, avg, a.0 + " " + a.1) }
            out.append(t)
        }
        if onFoot {
            var t = Tile(id: "steps", icon: "shoeprints.fill", label: "Steps", value: steps.map { NunaTrendsFormat.num(Double($0)) } ?? "–", unit: "")
            if let s = steps, let avg = averages?.steps { t.pill = (Double(s), avg, NunaTrendsFormat.num(avg)) }
            out.append(t)
        }
        if ground {
            if kind == .cycling || kind == .otherDistance {
                if let d = row.distanceM, d > 200, secs > 0 {
                    let v = d / secs * 3.6 / (system == .imperial ? 1.609344 : 1)
                    out.append(Tile(id: "speed", icon: "speedometer", label: "Speed", value: String(format: "%.1f", locale: AppLanguage.activeLocale, v), unit: system == .imperial ? "mph" : "km/h"))
                }
            } else if let pace = NunaWorkoutFormat.pace(distanceM: row.distanceM, seconds: secs, system) {
                let parts = pace.split(separator: " ", maxSplits: 1).map(String.init)
                out.append(Tile(id: "pace", icon: "speedometer", label: distanceEstimated ? "Estimated pace" : "Pace", value: parts.first ?? pace, unit: parts.count > 1 ? parts[1] : ""))
            }
        }
        if let kcal = row.energyKcal {
            var t = Tile(id: "kcal", icon: "flame", label: "Calories", value: NunaTrendsFormat.num(kcal), unit: "cal")
            if let avg = averages?.kcal { t.pill = (kcal, avg, NunaTrendsFormat.num(avg)) }
            out.append(t)
        }
        if let hr = row.avgHr {
            var t = Tile(id: "avg", icon: "heart", label: "Avg HR", value: "\(hr)", unit: "bpm")
            if let avg = averages?.avgHr { t.pill = (Double(hr), avg, "\(Int(avg.rounded())) bpm") }
            out.append(t)
        }
        if let hr = row.maxHr {
            var t = Tile(id: "max", icon: "bolt.heart", label: "Max HR", value: "\(hr)", unit: "bpm")
            if let avg = averages?.maxHr { t.pill = (Double(hr), avg, "\(Int(avg.rounded())) bpm") }
            out.append(t)
        }
        // With the steps at the top, the duration is a tile here (it is not one of the two figures).
        if stepsAtTop, secs > 0 {
            let t = Int(secs.rounded())
            var d = Tile(id: "dur", icon: "timer", label: "Duration", value: String(format: "%d:%02d", t / 3600, (t % 3600) / 60), unit: "")
            d.small = String(format: ":%02d", t % 60)
            if let avg = averages?.durationS { let a = Int(avg.rounded()); d.pill = (secs, avg, String(format: "%d:%02d:%02d", a / 3600, (a % 3600) / 60, a % 60)) }
            out.append(d)
        }
        return out
    }

    var body: some View {
        let hidden = Set((routeShown ? ["dist", "pace", "speed"] : []) + (stepsAtTop ? ["steps"] : []))
        let list = tiles.filter { !hidden.contains($0.id) }
        VStack(alignment: .leading, spacing: 10) {
            NunaLogSectionTitle(title: "Key statistics", trailing: averages != nil ? "vs. 30 day average" : nil)
            if routeShown {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) { ForEach(list) { tile($0).frame(width: 168) } }
                        .padding(.horizontal, NunaSpacing.screenH)
                }
                .padding(.horizontal, -NunaSpacing.screenH)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(list) { tile($0) }
                }
            }
        }
    }

    private func tile(_ t: Tile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: t.icon).font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                Text(t.label).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingHead(0.4)).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.bottom, 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                (Text(verbatim: t.value).font(.nuna(size: 36, weight: .bold, design: NunaType.design))
                    + Text(verbatim: t.small).font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary))
                    .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                if !t.unit.isEmpty && t.value != "–" { Text(verbatim: t.unit).font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(1) }
            }
            .padding(.bottom, 6)
            if let p = t.pill { NunaAveragePill(value: p.value, average: p.average, text: p.text) }
            else { Color.clear.frame(height: 28) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Edit the time

/// Moves a session in time and nothing else: its start and its end. What was measured inside the new window is read again.
struct NunaWorkoutTimeSheet: View {
    let row: WorkoutRow
    let onSave: (_ start: Date, _ end: Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date

    init(row: WorkoutRow, onSave: @escaping (_ start: Date, _ end: Date) -> Void) {
        self.row = row; self.onSave = onSave
        _start = State(initialValue: Date(timeIntervalSince1970: TimeInterval(row.startTs)))
        _end = State(initialValue: Date(timeIntervalSince1970: TimeInterval(row.endTs)))
    }

    private var valid: Bool { end > start && end.timeIntervalSince(start) <= 24 * 3600 && end <= Date().addingTimeInterval(60) }
    private var changed: Bool { Int(start.timeIntervalSince1970) != row.startTs || Int(end.timeIntervalSince1970) != row.endTs }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button { dismiss() } label: { NunaBareIcon("xmark") }.buttonStyle(.plain).accessibilityLabel(Text("Close"))
                Spacer()
                Text("Edit time").font(.nuna(size: 18, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            VStack(spacing: 0) {
                picker("Start time", $start)
                NunaDivider()
                picker("End time", $end)
            }
            if !valid {
                Text(end <= start ? "The end must come after the start." : "A session runs up to 24 hours and cannot end in the future.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).textCase(nil)
            }
            Text("Calories, heart rate and zones are read again from the strap for the new time.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            Spacer(minLength: 0)
            Button { onSave(start, end); dismiss() } label: { Text("Save") }
                .buttonStyle(.nuna(.primary, fullWidth: true)).disabled(!valid || !changed)
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 24)
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    private func picker(_ title: LocalizedStringKey, _ date: Binding<Date>) -> some View {
        HStack {
            Text(title).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            DatePicker("", selection: date, in: ...Date().addingTimeInterval(60), displayedComponents: [.date, .hourAndMinute]).labelsHidden()
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Actions

/// One line of the actions popover.
struct NunaActionItem: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let symbol: String
    var destructive = false
    var enabled = true
    let action: () -> Void
}

/// The three outlined circles at the corner of a saved workout, and the small dark popover under them: a large symbol and a capital label for
/// each action. The action runs once the popover has gone, so a sheet or a dialog can open without meeting it.
struct NunaActionsButton: View {
    let items: [NunaActionItem]
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: {
            HStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in Circle().strokeBorder(NunaPalette.textPrimary, lineWidth: 2).frame(width: 8, height: 8) } }
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(Text("More"))
        .popover(isPresented: $shown, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    Button {
                        shown = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { item.action() }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: item.symbol).font(.system(size: 22, weight: .light)).frame(width: 30)
                            Text(item.title).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(0.8)).textCase(.uppercase).lineLimit(1)
                        }
                        .foregroundStyle(item.destructive ? NunaPalette.alertText : NunaPalette.textPrimary)
                        .padding(.horizontal, 20).frame(maxWidth: .infinity, alignment: .leading).frame(height: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(!item.enabled).opacity(item.enabled ? 1 : 0.4)
                }
            }
            .padding(.vertical, 6).frame(minWidth: 230)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(Color(white: 0.13))
            .preferredColorScheme(NunaTheme.colorScheme)
        }
    }
}
#endif
