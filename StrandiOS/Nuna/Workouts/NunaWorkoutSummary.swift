#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// One saved session (WorkoutSummary): distance, time and pace, the Effort it added, time in each heart-rate zone, the
/// heart-rate curve, splits when a GPS route was recorded, an Anya line and the housekeeping actions.
struct NunaWorkoutSummaryView: View {
    let key: NunaWorkoutKey
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceRaw = ""
    @StateObject private var m = NunaWorkoutsModel()
    @State private var hr: [HRBucket] = []
    @State private var zoneMin: [Double]?
    @State private var route: [RouteMath.LatLng] = []
    @State private var dayEffort: Double?
    @State private var confirmDelete = false
    @State private var showCoach = false

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var system: UnitSystem { UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceRaw) }

    var body: some View {
        Group {
            if let ls = m.liftSessions.first(where: { $0.startTs == key.startTs }), m.row(key).map(NunaWorkoutKind.isStrength) ?? false {
                NunaGymSessionView(sessionId: ls.id)
            } else if let r = m.row(key) {
                NunaDetailScreen(LocalizedStringKey(WorkoutSource.displaySport(r.sport))) { content(r) }
            } else {
                NunaDetailScreen("Workout") {
                    NunaCard { Text(m.loaded ? "This session is no longer saved." : " ").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
        }
        .task(id: repo.refreshSeq) { await m.load(repo: repo); if let r = m.row(key) { await loadDetail(r) } }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "workouts") }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let r = m.row(key) { Task { await repo.deleteWorkout(r); await repo.refresh(); dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private func content(_ r: WorkoutRow) -> some View {
        let secs = r.durationS ?? Double(r.endTs - r.startTs)
        HStack {
            Text(verbatim: NunaWorkoutFormat.day(r.startTs) + " · " + NunaWorkoutFormat.clock(r.startTs)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            Spacer()
            NunaChip(sourceName(r), systemImage: "checkmark")
        }
        mainCard(r, secs)
        if let s = r.strain { effortCard(s) }
        zonesCard(r)
        hrCard(r)
        if let line = anyaLine(r) { NunaAnyaCard(verbatim: line) { showCoach = true } }
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            NunaListRow("Apple Health", subtitle: "Workouts, energy and distance are written by the sync. Manage it in Me", systemImage: "heart.text.square")
        }
        Button(role: .destructive) { confirmDelete = true } label: {
            Text("Delete").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                .frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func sourceName(_ r: WorkoutRow) -> LocalizedStringKey {
        switch WorkoutSource.classify(r.source) {
        case .whoop: return "Strap"
        case .manual: return "Manual"
        case .detected: return "Detected"
        case .apple: return "Apple Health"
        case .lifting: return "Lifting"
        case .activityFile: return "Imported file"
        }
    }

    private func mainCard(_ r: WorkoutRow, _ secs: Double) -> some View {
        let dist = NunaWorkoutFormat.distance(r.distanceM, system)
        let pace = WorkoutCatalog.isOnFoot(r.sport) ? NunaWorkoutFormat.pace(distanceM: r.distanceM, seconds: secs, system) : nil
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                if route.count >= 2 {
                    // A map of the captured route with start and end markers (tiles are cached by MapKit; the route itself
                    // never leaves the phone). The plain line below stays as the fallback when MapKit has nothing to show.
                    WorkoutRouteMap(points: route, stroke: UIColor(NunaPalette.effort)).environment(\.colorScheme, .dark).frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                HStack {
                    if let dist { big("Distance", dist) }
                    big("Time", clockDuration(secs))
                    if let pace { big("Pace", pace) }
                    else if dist == nil { big("Avg HR", r.avgHr.map { "\($0)" } ?? "–") }
                }
                HStack {
                    if let kcal = r.energyKcal { small("Calories", NunaTrendsFormat.num(kcal)) }
                    if let avg = r.avgHr { small("Avg HR", "\(avg) bpm") }
                    if let mx = r.maxHr { small("Max HR", "\(mx) bpm") }
                }
            }
        }
    }

    private func clockDuration(_ s: Double) -> String {
        let t = Int(s.rounded()); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    private func big(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.7).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(_ l: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func effortCard(_ s: Double) -> some View {
        let max: Double = scale == .whoop ? 21 : 100
        return NunaCard {
            HStack(spacing: 16) {
                NunaRingGauge(fraction: UnitFormatter.effortValue(dayEffort ?? s, scale: scale) / max, color: NunaPalette.effortText, size: 84, lineWidth: 8) {
                    Text(verbatim: "+" + UnitFormatter.effortDisplay(s, scale: scale)).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Effort added").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    if let d = dayEffort {
                        Text(verbatim: String(localized: "That day reached \(UnitFormatter.effortDisplay(d, scale: scale)) of \(UnitFormatter.effortScaleMax(scale))")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func zonesCard(_ r: WorkoutRow) -> some View {
        var mins = zoneMin
        if let pct = WorkoutZones.percents(r.zonesJSON) {
            let d = (r.durationS ?? Double(r.endTs - r.startTs)) / 60
            mins = pct.map { d * $0 / 100 }
        }
        let total = max(mins?.reduce(0, +) ?? 0, 0.0001)
        let colors: [Color] = [NunaPalette.zoneBase, NunaPalette.rest, NunaPalette.charge, NunaPalette.warning, NunaPalette.alert]
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    nunaTrendsCap("Heart rate zones")
                    Spacer()
                    if let a = r.avgHr, let mx = r.maxHr { Text(verbatim: String(localized: "Average \(a) · max \(mx)")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                }
                if let mins, mins.contains(where: { $0 > 0 }) {
                    NunaProportionBar(parts: mins.enumerated().map { ($1, colors[$0]) })
                    ForEach(0..<5, id: \.self) { i in
                        if mins[i] >= 0.5 {
                            HStack(spacing: 10) {
                                Circle().fill(colors[i]).frame(width: 9, height: 9)
                                Text(verbatim: String(localized: "Zone \(i + 1)")).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Spacer()
                                Text(verbatim: String(localized: "\(Int(mins[i].rounded())) min · \(Int((mins[i] / total * 100).rounded()))%")).font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            }
                        }
                    }
                } else {
                    Text("No heart-rate readings were recorded for this session.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
    }

    private func hrCard(_ r: WorkoutRow) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Heart rate")
                if hr.count >= 2 {
                    NunaWorkoutHRCurve(buckets: hr, start: r.startTs, end: r.endTs)
                } else {
                    Text("No heart-rate readings were recorded for this session.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
    }

    private func anyaLine(_ r: WorkoutRow) -> String? {
        guard let mins = zoneMin ?? WorkoutZones.percents(r.zonesJSON).map({ p in p.map { (r.durationS ?? 0) / 60 * $0 / 100 } }), mins.reduce(0, +) > 0 else { return nil }
        let total = mins.reduce(0, +)
        let top = mins.enumerated().max { $0.element < $1.element }!
        return String(localized: "Most of this session, \(Int((top.element / total * 100).rounded()))%, was in zone \(top.offset + 1).")
    }

    private func loadDetail(_ r: WorkoutRow) async {
        hr = await repo.workoutHrBuckets(from: r.startTs, to: r.endTs, source: r.source)
        zoneMin = await repo.workoutZoneMinutes(from: r.startTs, to: r.endTs, zoneSet: profile.hrZoneSet, source: r.source)
        if let rt = RouteStore.load(startTs: r.startTs, sport: r.sport) {
            let pts = RouteMath.decode(rt.polyline); route = pts.count >= 2 ? pts : []
        }
        let k = m.dayKey(r.startTs)
        dayEffort = repo.days.first { $0.day == k }?.strain
    }
}

/// A heart-rate line with minute labels along the bottom and the lowest and highest values on the left.
struct NunaWorkoutHRCurve: View {
    let buckets: [HRBucket]
    let start: Int
    let end: Int
    var body: some View {
        let lo = floor((buckets.map(\.bpm).min() ?? 0) / 10) * 10, hi = ceil((buckets.map(\.bpm).max() ?? 1) / 10) * 10
        let span = max(Double(end - start), 1)
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                VStack { Text(verbatim: "\(Int(hi))"); Spacer(); Text(verbatim: "\(Int(lo))") }
                    .font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 26, height: 150)
                Canvas { ctx, size in
                    var grid = Path()
                    for i in 0...2 { let y = size.height * CGFloat(i) / 2; grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
                    ctx.stroke(grid, with: .color(NunaPalette.ink.opacity(0.07)), lineWidth: 1)
                    var p = Path(); var first = true
                    for b in buckets.sorted(by: { $0.ts < $1.ts }) {
                        let pt = CGPoint(x: size.width * CGFloat(Double(b.ts - start) / span), y: size.height * (1 - CGFloat((b.bpm - lo) / max(hi - lo, 1))))
                        if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                    }
                    ctx.stroke(p, with: .color(NunaPalette.alertText), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 150)
            }
            HStack {
                Spacer().frame(width: 32)
                Text("0"); Spacer(); Text(verbatim: "\(Int(span / 120))"); Spacer(); Text(verbatim: String(localized: "\(Int(span / 60)) min"))
            }
            .font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
        }
        .accessibilityHidden(true)
    }
}

/// The recorded GPS route drawn as a line scaled to its own bounds.
struct NunaRouteTrace: View {
    let points: [RouteMath.LatLng]
    var body: some View {
        Canvas { ctx, size in
            let lats = points.map(\.lat), lons = points.map(\.lon)
            guard let la0 = lats.min(), let la1 = lats.max(), let lo0 = lons.min(), let lo1 = lons.max() else { return }
            let k = cos(((la0 + la1) / 2) * .pi / 180)
            let w = max((lo1 - lo0) * k, 1e-6), h = max(la1 - la0, 1e-6)
            let scale = min((size.width - 20) / w, (size.height - 20) / h)
            let ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2
            var p = Path()
            for (i, pt) in points.enumerated() {
                let q = CGPoint(x: ox + (pt.lon - lo0) * k * scale, y: size.height - oy - (pt.lat - la0) * scale)
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            ctx.stroke(p, with: .color(NunaPalette.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .background(NunaPalette.shade.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}
#endif
