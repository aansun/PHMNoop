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

    init?(for row: WorkoutRow, in rows: [WorkoutRow]) {
        let from = row.startTs - 30 * 86_400
        let others = rows.filter { $0.sport == row.sport && $0.startTs != row.startTs && $0.startTs >= from && $0.startTs < row.startTs }
        guard others.count >= 2 else { return nil }
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
private struct NunaAveragePill: View {
    let value: Double
    let average: Double
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: value >= average ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 8, weight: .bold))
            Text(verbatim: text).font(.nuna(size: 11.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        .padding(.horizontal, 8).frame(height: 22)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Header

/// The sport, when it ran and where it came from, under the screen title.
struct NunaWorkoutLogHeader: View {
    let row: WorkoutRow
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ActivitySport.symbol(for: row.sport)).font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: NunaWorkoutFormat.day(row.startTs) + " · " + NunaWorkoutFormat.clock(row.startTs) + " – " + NunaWorkoutFormat.clock(row.endTs))
                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            NunaChip(NunaWorkoutSourceLabel.label(row.source))
        }
    }
}

// MARK: - Effort and time

/// The two figures the log opens with: the Effort the session added and how long it ran, each with the 30-day average beside it.
struct NunaWorkoutLogFigures: View {
    let row: WorkoutRow
    let averages: NunaWorkoutAverages?
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
            figure(label: "Duration", value: Self.clock(secs), color: NunaPalette.textPrimary,
                   pill: averages?.durationS.map { avg in NunaAveragePill(value: secs, average: avg, text: Self.clock(avg)) })
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

/// The heart rate through the session as a filled curve, with the beats-per-minute scale on the left and the start and the end under it.
struct NunaWorkoutHRArea: View {
    let buckets: [HRBucket]
    let start: Int
    let end: Int

    var body: some View {
        let pts = buckets.sorted { $0.ts < $1.ts }
        let lo = floor((pts.map(\.bpm).min() ?? 0) / 25) * 25
        let hi = max(ceil((pts.map(\.bpm).max() ?? 25) / 25) * 25, lo + 25)
        let span = max(Double(end - start), 1)
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ForEach(Array(stride(from: lo, through: hi, by: 25)), id: \.self) { v in
                        GeometryReader { geo in
                            Text(verbatim: "\(Int(v))").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).monospacedDigit()
                                .position(x: geo.size.width - 8, y: geo.size.height * CGFloat(1 - (v - lo) / (hi - lo)))
                        }
                    }
                }
                .frame(width: 30, height: 150)
                Canvas { ctx, size in
                    func pt(_ b: HRBucket) -> CGPoint {
                        CGPoint(x: size.width * CGFloat(min(max(Double(b.ts - start) / span, 0), 1)), y: size.height * CGFloat(1 - (b.bpm - lo) / (hi - lo)))
                    }
                    for v in stride(from: lo, through: hi, by: 25) {
                        var g = Path(); let y = size.height * CGFloat(1 - (v - lo) / (hi - lo))
                        g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(g, with: .color(NunaPalette.ink.opacity(0.07)), lineWidth: 1)
                    }
                    guard pts.count >= 2 else { return }
                    var line = Path()
                    for (i, b) in pts.enumerated() { i == 0 ? line.move(to: pt(b)) : line.addLine(to: pt(b)) }
                    var area = line
                    area.addLine(to: CGPoint(x: pt(pts[pts.count - 1]).x, y: size.height))
                    area.addLine(to: CGPoint(x: pt(pts[0]).x, y: size.height))
                    area.closeSubpath()
                    ctx.fill(area, with: .linearGradient(Gradient(colors: [NunaPalette.effortModerate.opacity(0.5), NunaPalette.effortMinimal.opacity(0.04)]),
                                                         startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    ctx.stroke(line, with: .color(NunaPalette.effortModerate), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    // The start and the end of the session as dashed marks.
                    for x in [CGFloat(0), size.width] {
                        var m = Path(); m.move(to: CGPoint(x: x, y: 0)); m.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(m, with: .color(NunaPalette.textSecondary.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .frame(height: 150)
            }
            HStack {
                Text(verbatim: NunaWorkoutFormat.clock(start)); Spacer(); Text(verbatim: NunaWorkoutFormat.clock(end))
            }
            .font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.leading, 38)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Zones

/// A track with diagonal hatching, the empty part of a zone's bar.
private struct NunaHatchedTrack: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path(); var x: CGFloat = -size.height
            while x < size.width {
                p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0)); x += 6
            }
            ctx.stroke(p, with: .color(NunaPalette.ink.opacity(0.14)), lineWidth: 1)
        }
        .clipShape(Capsule())
    }
}

/// One row per zone, the hardest first: its name and bpm range, its share of the session and the time spent there.
struct NunaWorkoutLogZones: View {
    let minutes: [Double]?
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        let colors: [Color] = [NunaPalette.textSecondary, NunaPalette.rest, NunaPalette.charge, NunaPalette.warning, NunaPalette.alert]
        let bands = profile.hrZoneSet.zones
        VStack(alignment: .leading, spacing: 10) {
            if let mins = minutes, mins.count >= 5, mins.contains(where: { $0 > 0 }) {
                let total = max(mins.reduce(0, +), 0.0001)
                ForEach((0..<5).reversed(), id: \.self) { i in
                    let on = mins[i] * 60 >= 1
                    let share = mins[i] / total
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: String(localized: "Zone \(i + 1)")).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textMuted)
                            if i < bands.count {
                                Text(verbatim: "\(Int(bands[i].lower.rounded()))–\(Int(bands[i].upper.rounded())) BPM").font(.nuna(size: 11.5, weight: .semibold))
                                    .foregroundStyle(NunaPalette.textMuted).textCase(nil)
                            }
                            if on { Text(verbatim: "\(Int((share * 100).rounded()))%").font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(colors[i]) }
                            Spacer(minLength: 8)
                            time(mins[i] * 60, on: on)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                NunaHatchedTrack()
                                if on { Capsule().fill(colors[i]).frame(width: max(geo.size.width * CGFloat(share), 8)) }
                            }
                        }.frame(height: 8)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else {
                Text("No heart-rate readings were recorded for this session.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
    }

    /// "0:03:58", the seconds in a lighter weight.
    private func time(_ seconds: Double, on: Bool) -> some View {
        let t = Int(seconds.rounded())
        return (Text(verbatim: String(format: "%d:%02d", t / 3600, (t % 3600) / 60)).foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textMuted)
                + Text(verbatim: String(format: ":%02d", t % 60)).foregroundStyle(NunaPalette.textMuted))
            .font(.nuna(size: 17, weight: .bold, design: NunaType.design))
    }
}

// MARK: - Key statistics

/// Everything the session measured, together: distance and steps for the sports that cover ground (GPS and treadmill alike), pace or speed,
/// calories and the heart rate. Each tile carries the 30-day average of the same sport when there is one.
struct NunaWorkoutLogStats: View {
    let row: WorkoutRow
    let steps: Int?
    let averages: NunaWorkoutAverages?
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceRaw = ""

    private var system: UnitSystem { UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceRaw) }

    private struct Tile: Identifiable {
        let id: String; let icon: String; let label: LocalizedStringKey; let value: String; let unit: String
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
            var t = Tile(id: "dist", icon: "point.topleft.down.to.point.bottomright.curvepath", label: "Distance", value: d?.0 ?? "–", unit: d?.1 ?? "")
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
                out.append(Tile(id: "pace", icon: "speedometer", label: "Pace", value: parts.first ?? pace, unit: parts.count > 1 ? parts[1] : ""))
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
        return out
    }

    var body: some View {
        let list = tiles
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                nunaTrendsCap("Key statistics")
                Spacer()
                if averages != nil { Text("vs. 30 day average").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textMuted) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(list) { tile($0) }
            }
        }
    }

    private func tile(_ t: Tile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: t.icon).font(.nuna(size: 12, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                Text(t.label).font(.nuna(size: 10, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: t.value).font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                if !t.unit.isEmpty && t.value != "–" { Text(verbatim: t.unit).font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1) }
            }
            if let p = t.pill { NunaAveragePill(value: p.value, average: p.average, text: p.text) }
            else { Color.clear.frame(height: 22) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .background(NunaPalette.canvas.ignoresSafeArea())
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
#endif
