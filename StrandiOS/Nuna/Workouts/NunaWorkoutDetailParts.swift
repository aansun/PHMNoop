#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The pieces every session detail is built from, so a run, a swim, a yoga class and a gym session read the same way:
// header with the Effort it added, an Anya line, the map (only when a route was recorded), the summary that fits the
// sport, the heart-rate curve, the zones, photos, how it felt and Strava.

/// What a session detail loads once: the heart-rate curve, zone minutes, the GPS route and the Effort of that day.
@MainActor
final class NunaWorkoutDetailData: ObservableObject {
    @Published var hr: [HRBucket] = []
    @Published var zoneMin: [Double]?
    @Published var route: [RouteMath.LatLng] = []
    @Published var dayEffort: Double?

    func load(startTs: Int, endTs: Int, sport: String, source: String, repo: Repository, zoneSet: HRZoneSet) async {
        hr = await repo.workoutHrBuckets(from: startTs, to: endTs, source: source)
        zoneMin = await repo.workoutZoneMinutes(from: startTs, to: endTs, zoneSet: zoneSet, source: source)
        if let rt = RouteStore.load(startTs: startTs, sport: sport) {
            let pts = RouteMath.decode(rt.polyline); route = pts.count >= 2 ? pts : []
        }
        let k = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(startTs)))
        dayEffort = repo.days.first { $0.day == k }?.strain
    }
}

enum NunaWorkoutSourceLabel {
    static func label(_ source: String) -> LocalizedStringKey {
        switch WorkoutSource.classify(source) {
        case .whoop: return "Strap"
        case .manual: return "Manual"
        case .detected: return "Detected"
        case .apple: return "Apple Health"
        case .lifting: return "Lifting"
        case .activityFile: return "Imported file"
        }
    }
}

/// Minutes in each zone: the stored percentages when the row has them, otherwise what the heart-rate readings gave.
enum NunaWorkoutZoneMath {
    static func minutes(_ r: WorkoutRow, measured: [Double]?) -> [Double]? {
        if let pct = WorkoutZones.percents(r.zonesJSON) {
            let d = (r.durationS ?? Double(r.endTs - r.startTs)) / 60
            return pct.map { d * $0 / 100 }
        }
        return measured
    }

    static func minutes(zonesJSON: String?, durationMin: Double, measured: [Double]?) -> [Double]? {
        if let pct = WorkoutZones.percents(zonesJSON) { return pct.map { durationMin * $0 / 100 } }
        return measured
    }
}

// MARK: - Header

/// When the session ran and the Effort it added. The sport is already the screen title.
struct NunaWorkoutHeaderCard: View {
    let symbol: String
    let startTs: Int
    let endTs: Int
    let source: LocalizedStringKey
    let strain: Double?
    let dayEffort: Double?
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        let top: Double = scale == .whoop ? 21 : 100
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    Text(verbatim: NunaWorkoutFormat.day(startTs) + " · " + NunaWorkoutFormat.clock(startTs) + " – " + NunaWorkoutFormat.clock(endTs))
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    NunaChip(source, systemImage: "checkmark")
                }
                if let s = strain {
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text(verbatim: "+" + UnitFormatter.effortDisplay(s, scale: scale)).font(.nuna(size: 46, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.effortText)
                        Text("Effort added").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer(minLength: 0)
                    }
                    if let d = dayEffort {
                        let v = UnitFormatter.effortValue(d, scale: scale)
                        VStack(alignment: .leading, spacing: 6) {
                            NunaProportionBar(parts: [(v, NunaPalette.effortText), (max(top - v, 0), NunaPalette.glassStrong)])
                            Text(verbatim: String(localized: "That day reached \(UnitFormatter.effortDisplay(d, scale: scale)) of \(UnitFormatter.effortScaleMax(scale))"))
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Map

struct NunaWorkoutRouteCard: View {
    let points: [RouteMath.LatLng]
    var body: some View {
        NunaCard {
            // A map of the captured route with start and end markers (tiles are cached by MapKit; the route itself
            // never leaves the phone).
            WorkoutRouteMap(points: points, stroke: UIColor(NunaPalette.effort)).environment(\.colorScheme, .dark)
                .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - Summary that fits the sport

/// How a sport is summarised: foot sports by distance and pace, wheels and sliding sports by distance and speed, swimming
/// and rowing by distance and pace per 100 m or 500 m, and everything else (classes, court and field sports, intervals) by time,
/// calories and heart rate.
enum NunaWorkoutSportKind {
    case onFoot, cycling, swimming, rowing, otherDistance, session

    static func of(_ sport: String) -> NunaWorkoutSportKind {
        let s = sport.lowercased()
        if s.contains("swim") { return .swimming }
        if s.contains("row") && !s.contains("arrow") { return .rowing }
        if s.contains("cycl") || s.contains("bik") || s.contains("spinning") { return .cycling }
        if WorkoutCatalog.isOnFoot(sport) || s.contains("ruck") || s.contains("nordic") || s.contains("snowshoe") || s.contains("walk") || s.contains("run") || s.contains("hik") { return .onFoot }
        if let c = WorkoutCatalog.sport(named: sport), c.isDistanceSport { return .otherDistance }
        return .session
    }
}

struct NunaWorkoutStat: Identifiable {
    let id = UUID()
    let label: LocalizedStringKey
    let value: String
}

struct NunaWorkoutSummaryCard: View {
    let row: WorkoutRow
    let zoneMin: [Double]?
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceRaw = ""

    private var system: UnitSystem { UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceRaw) }

    var body: some View {
        let (big, small) = stats()
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack { ForEach(big) { stat in tile(stat, size: 24, label: 10.5) } }
                if !small.isEmpty { HStack { ForEach(small) { stat in tile(stat, size: 15, label: 10.5) } } }
            }
        }
    }

    private func tile(_ s: NunaWorkoutStat, size: CGFloat, label: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: size > 20 ? 4 : 3) {
            Text(s.label).font(.nuna(size: label, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(verbatim: s.value).font(.nuna(size: size, weight: .bold, design: size > 20 ? NunaType.design : .default)).foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.7).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clock(_ s: Double) -> String {
        let t = Int(s.rounded()); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    /// Seconds per 100 m (or 100 yd), or per 500 m, as m:ss.
    private func splitPace(per meters: Double, unit: String) -> String? {
        guard let d = row.distanceM, d > 50, let s = row.durationS ?? Optional(Double(row.endTs - row.startTs)), s > 0 else { return nil }
        let sec = Int((s / (d / meters)).rounded())
        return String(format: "%d:%02d /%@", sec / 60, sec % 60, unit)
    }

    private func speed(_ secs: Double) -> String? {
        guard let d = row.distanceM, d > 200, secs > 0 else { return nil }
        let v = d / secs * 3.6 / (system == .imperial ? 1.609344 : 1)
        return String(format: "%.1f %@", locale: AppLanguage.activeLocale, v, system == .imperial ? "mph" : "km/h")
    }

    private func swimDistance() -> String? {
        guard let d = row.distanceM, d > 10 else { return nil }
        return system == .imperial ? "\(Int((d * 1.0936).rounded())) yd" : "\(Int(d.rounded())) m"
    }

    private func stats() -> ([NunaWorkoutStat], [NunaWorkoutStat]) {
        let secs = row.durationS ?? Double(row.endTs - row.startTs)
        let time = NunaWorkoutStat(label: "Time", value: clock(secs))
        let kcal = row.energyKcal.map { NunaWorkoutStat(label: "Calories", value: NunaTrendsFormat.num($0)) }
        let avg = row.avgHr.map { NunaWorkoutStat(label: "Avg HR", value: "\($0) bpm") }
        let mx = row.maxHr.map { NunaWorkoutStat(label: "Max HR", value: "\($0) bpm") }
        let steps = row.steps.map { NunaWorkoutStat(label: "Steps", value: NunaTrendsFormat.num(Double($0))) }
        let dist = NunaWorkoutFormat.distance(row.distanceM, system).map { NunaWorkoutStat(label: "Distance", value: $0) }
        let heart = [kcal, avg, mx].compactMap { $0 }

        switch NunaWorkoutSportKind.of(row.sport) {
        case .onFoot:
            if let dist {
                let pace = NunaWorkoutFormat.pace(distanceM: row.distanceM, seconds: secs, system).map { NunaWorkoutStat(label: "Pace", value: $0) }
                return ([dist, time] + [pace].compactMap { $0 }, heart + [steps].compactMap { $0 })
            }
        case .cycling, .otherDistance:
            if let dist {
                return ([dist, time] + [speed(secs).map { NunaWorkoutStat(label: "Speed", value: $0) }].compactMap { $0 }, heart)
            }
        case .swimming:
            if let d = swimDistance() {
                let pace = splitPace(per: system == .imperial ? 91.44 : 100, unit: system == .imperial ? "100 yd" : "100 m")
                return ([NunaWorkoutStat(label: "Distance", value: d), time] + [pace.map { NunaWorkoutStat(label: "Pace", value: $0) }].compactMap { $0 }, heart)
            }
        case .rowing:
            if let d = swimDistance() {
                let pace = splitPace(per: 500, unit: "500 m")
                return ([NunaWorkoutStat(label: "Distance", value: d), time] + [pace.map { NunaWorkoutStat(label: "Pace", value: $0) }].compactMap { $0 }, heart)
            }
        case .session:
            break
        }
        // No distance: time, calories and heart rate lead, with the top zone and steps behind.
        let mins = NunaWorkoutZoneMath.minutes(row, measured: zoneMin)
        var top: NunaWorkoutStat?
        if let mins, let best = mins.enumerated().max(by: { $0.element < $1.element }), best.element >= 1 {
            top = NunaWorkoutStat(label: "Top zone", value: String(localized: "Zone \(best.offset + 1)"))
        }
        return ([time] + [kcal, avg].compactMap { $0 }, [mx, top, steps].compactMap { $0 } + (dist.map { [$0] } ?? []))
    }
}

// MARK: - Anya

enum NunaWorkoutInsight {
    /// Where the time went, set against the person's own other sessions of the same sport when there are enough of them.
    static func zoneLine(mins: [Double]?, others: [[Double]]) -> String? {
        guard let mins, mins.reduce(0, +) > 0 else { return nil }
        let total = mins.reduce(0, +)
        let top = mins.enumerated().max { $0.element < $1.element }!
        let zone = top.offset + 1, minutes = Int(top.element.rounded()), share = Int((top.element / total * 100).rounded())
        guard minutes >= 1 else { return nil }
        if others.count >= 2 {
            let typical = others.map { $0[top.offset] }.reduce(0, +) / Double(others.count)
            let usual = Int(typical.rounded())
            if Double(minutes) >= typical * 1.25 + 1 {
                return String(localized: "You spent \(minutes) min in zone \(zone), \(share)% of the session. Your usual is \(usual) min, so this one ran harder.")
            } else if Double(minutes) <= typical * 0.75 - 1 {
                return String(localized: "You spent \(minutes) min in zone \(zone), \(share)% of the session. Your usual is \(usual) min, so this one was lighter.")
            }
            return String(localized: "You spent \(minutes) min in zone \(zone), \(share)% of the session. That is about your usual \(usual) min.")
        }
        return String(localized: "You spent \(minutes) min in zone \(zone), \(share)% of the session.")
    }
}

// MARK: - Heart rate and zones

struct NunaWorkoutHRCard: View {
    let start: Int
    let end: Int
    let buckets: [HRBucket]
    var body: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Heart rate")
                if buckets.count >= 2 {
                    NunaWorkoutHRCurve(buckets: buckets, start: start, end: end)
                } else {
                    Text("No heart-rate readings were recorded for this session.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
        }
    }
}

/// One row per zone: its number in the zone colour, the bpm range, minutes and share, and a bar sized against the longest zone.
struct NunaWorkoutZonesCard: View {
    let minutes: [Double]?
    let avgHr: Int?
    let maxHr: Int?
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        let colors: [Color] = [NunaPalette.textMuted, NunaPalette.rest, NunaPalette.charge, NunaPalette.warning, NunaPalette.alert]
        let bands = profile.hrZoneSet.zones
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    nunaTrendsCap("Heart rate zones")
                    Spacer()
                    if let a = avgHr, let mx = maxHr { Text(verbatim: String(localized: "Average \(a) · max \(mx)")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                }
                if let mins = minutes, mins.contains(where: { $0 > 0 }) {
                    let total = max(mins.reduce(0, +), 0.0001)
                    let peak = max(mins.max() ?? 1, 0.0001)
                    ForEach(0..<5, id: \.self) { i in
                        let on = mins[i] >= 0.5
                        VStack(spacing: 7) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(verbatim: "\(i + 1)").font(.nuna(size: 12, weight: .heavy, design: NunaType.design)).foregroundStyle(.black.opacity(0.8))
                                    .frame(width: 22, height: 22).background(colors[i].opacity(on ? 1 : 0.35), in: Circle())
                                if i < bands.count {
                                    Text(verbatim: "\(Int(bands[i].lower.rounded()))–\(Int(bands[i].upper.rounded())) bpm").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                }
                                Spacer(minLength: 8)
                                Text(verbatim: String(localized: "\(Int(mins[i].rounded())) min")).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textMuted)
                                Text(verbatim: "\(Int((mins[i] / total * 100).rounded()))%").font(.nuna(size: 13, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary).frame(width: 40, alignment: .trailing)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(NunaPalette.ink.opacity(0.08))
                                    Capsule().fill(colors[i]).frame(width: on ? max(geo.size.width * CGFloat(mins[i] / peak), 8) : 0)
                                }
                            }.frame(height: 8)
                        }
                    }
                } else {
                    Text("No heart-rate readings were recorded for this session.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
        }
    }
}
#endif
