#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// One saved session (WorkoutSummary): when it ran and the Effort it added, an Anya line, the map when a route was recorded,
/// a summary that fits the sport, the heart-rate curve and zones, photos, how it felt, Strava and the housekeeping actions.
/// Gym sessions open [NunaGymSessionView], which is built from the same pieces.
struct NunaWorkoutSummaryView: View {
    let key: NunaWorkoutKey
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var m = NunaWorkoutsModel()
    @StateObject private var data = NunaWorkoutDetailData()
    @State private var confirmDelete = false
    @State private var showCoach = false

    var body: some View {
        Group {
            if let ls = m.liftSessions.first(where: { $0.startTs == key.startTs }), m.row(key).map(NunaWorkoutKind.isStrength) ?? false {
                NunaGymSessionView(sessionId: ls.id)
            } else if let r = m.row(key) {
                NunaDetailScreen(LocalizedStringKey(WorkoutSource.displaySport(r.sport))) { content(r) }
            } else {
                NunaDetailScreen("Workout") {
                    NunaCard { Text(m.loaded ? "This session is no longer saved." : " ").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
        }
        .task(id: repo.refreshSeq) {
            await m.load(repo: repo)
            if let r = m.row(key) { await data.load(startTs: r.startTs, endTs: r.endTs, sport: r.sport, source: r.source, repo: repo, zoneSet: profile.hrZoneSet) }
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "workouts") }
        .environment(\.nunaAnyaCardContext, "workouts")
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let r = m.row(key) { Task { NunaWorkoutReviewStore.remove(startTs: r.startTs, sport: r.sport); await repo.deleteWorkout(r); await repo.refresh(); dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private func content(_ r: WorkoutRow) -> some View {
        let mins = NunaWorkoutZoneMath.minutes(r, measured: data.zoneMin)
        NunaWorkoutHeaderCard(symbol: ActivitySport.symbol(for: r.sport), startTs: r.startTs, endTs: r.endTs, source: NunaWorkoutSourceLabel.label(r.source), strain: r.strain, dayEffort: data.dayEffort)
        if let line = NunaWorkoutInsight.zoneLine(mins: mins, others: otherSessions(r)) { NunaAnyaCard(verbatim: line) { showCoach = true } }
        if data.route.count >= 2 { NunaWorkoutRouteCard(points: data.route) }
        NunaWorkoutSummaryCard(row: r, zoneMin: data.zoneMin)
        NunaWorkoutHRCard(start: r.startTs, end: r.endTs, buckets: data.hr)
        if mins?.contains(where: { $0 > 0 }) ?? false { NunaWorkoutZonesCard(minutes: mins, avgHr: r.avgHr, maxHr: r.maxHr) }
        NunaWorkoutReviewSection(row: r)
        NunaWorkoutStravaCard(row: r, afterWorkout: false, checked: .constant(false))
        Button(role: .destructive) { confirmDelete = true } label: {
            Text("Delete").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                .frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    /// Zone minutes of the other saved sessions of the same sport.
    private func otherSessions(_ r: WorkoutRow) -> [[Double]] {
        m.rows.filter { $0.sport == r.sport && $0.startTs != r.startTs }.compactMap { o in
            guard let pct = WorkoutZones.percents(o.zonesJSON) else { return nil }
            let d = (o.durationS ?? Double(o.endTs - o.startTs)) / 60
            return pct.map { d * $0 / 100 }
        }
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
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}
#endif
