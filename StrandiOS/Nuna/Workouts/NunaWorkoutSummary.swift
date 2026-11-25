#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandImport
import WhoopStore

/// One saved session, laid out as a log: the Effort and the time, an Anya line that reads the whole log, the heart-rate curve, the key
/// statistics together (against the wearer's 30-day average of the sport), the zones, the map when a route was recorded, then photos and
/// how it felt. Share (a file, or Strava), edit the time and delete sit behind the three dots in the header.
/// Gym sessions open [NunaGymSessionView], which is built from the same pieces.
struct NunaWorkoutSummaryView: View {
    let key: NunaWorkoutKey
    var initialRow: WorkoutRow? = nil
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var m = NunaWorkoutsModel()
    @StateObject private var data = NunaWorkoutDetailData()
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @State private var confirmDelete = false
    @State private var showCoach = false
    @State private var showBreathAnya = false
    @State private var showEdit = false
    @State private var showEditActivity = false
    /// The zone picked in the zone list, lit on the heart-rate curve.
    @State private var zonePick: Int?
    /// The stress through the session, for a low-intensity one (see `NunaLowIntensity`), and which of its two charts is showing.
    @State private var stress: [NunaWorkoutStress.Point] = []
    @State private var lowTab = LowTab.stress
    private enum LowTab: Hashable { case stress, heartRate }
    @State private var stravaState: NunaStravaState = .off
    @State private var stravaMessage: String?
    @StateObject private var strava = StravaSettingsModel()
    /// Observed so the read changes once the weather and air arrive.
    @ObservedObject private var environment = EnvironmentStore.shared

    /// Opened from the end of a session: the row may not be in the store yet, so it is shown from memory for a short while instead of "no
    /// longer saved". The screen reloads when the save lands.
    private var justSaved: Bool {
        guard let r = initialRow else { return false }
        return Date().timeIntervalSince1970 - Double(r.endTs) < 30
    }

    var body: some View {
        Group {
            if let ls = m.liftSessions.first(where: { $0.startTs == key.startTs }), m.row(key).map(NunaWorkoutKind.isStrength) ?? false {
                NunaGymSessionView(sessionId: ls.id)
            } else if let r = m.row(key) ?? (m.loaded && !justSaved ? nil : initialRow) {
                NunaDetailScreen(nunaSportKey(WorkoutSource.displaySport(r.sport)), titleSymbol: ActivitySport.symbol(for: r.sport), subtitle: NunaWorkoutFormat.span(r.startTs, r.endTs), titleActivity: r.sport, trailing: AnyView(actionsMenu(r))) { content(r) }
            } else {
                NunaDetailScreen("Workout") {
                    NunaCard { Text(m.loaded ? "This session is no longer saved." : " ").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
        }
        .task(id: repo.refreshSeq) {
            await m.load(repo: repo)
            if let r = m.row(key) {
                await data.load(startTs: r.startTs, endTs: r.endTs, sport: r.sport, source: r.source, knownSteps: r.steps, repo: repo, zoneSet: profile.hrZoneSet, ticksPerStep: profile.stepTicksPerStep)
                stravaState = NunaStravaCheck.state(r)
                let z = NunaWorkoutZoneMath.minutes(r, measured: data.zoneMin)
                stress = NunaLowIntensity.applies(row: r, zoneMinutes: z, hasHeartRate: data.hr.count >= 2, hasRoute: data.route.count >= 2) || r.sport == NunaBreathRecovery.sport
                    ? await NunaWorkoutStress.series(repo: repo, from: r.startTs, to: r.endTs) : []
                // A session that has just finished is read against the conditions now, when none was taken near it.
                if Int(Date().timeIntervalSince1970) - r.endTs < 90 * 60, environment.snapshot(near: (r.startTs + r.endTs) / 2) == nil {
                    await environment.refreshIfNeeded(maxAge: 15 * 60)
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let r = m.row(key) { NunaWorkoutTimeSheet(row: r) { start, end in Task { await moveInTime(r, start: start, end: end) } }.nunaSheetChrome(detents: [.height(430)]) }
        }
        .sheet(isPresented: $showEditActivity) {
            if let r = m.row(key) {
                NunaManualWorkoutSheet(editing: r, suggestedDistanceM: NunaTreadmillEstimate.meters(row: r, steps: data.steps)) { new, old in
                    Task { await applyEdit(old ?? r, to: new) }
                }
                .nunaSheetChrome(detents: [.large])
            }
        }
        .alert(stravaMessage ?? "", isPresented: Binding(get: { stravaMessage != nil }, set: { if !$0 { stravaMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "workouts") }
        .sheet(isPresented: $showBreathAnya) { NunaAnyaSheet(context: "Breathing") }
        .environment(\.nunaAnyaCardContext, "workouts")
        // Anya as one slim row, as on Today; what she says beyond the headline is in the sheet it opens.
        .environment(\.nunaAnyaRow, true)
        .nunaDialog("Delete this workout?", isPresented: $confirmDelete) {
            NunaDialogButton("Delete", role: .destructive) {
                if let r = m.row(key) { Task { NunaWorkoutReviewStore.remove(startTs: r.startTs, sport: r.sport); await repo.deleteWorkout(r); await repo.refresh(); dismiss() } }
            }
            NunaDialogButton("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private func content(_ r: WorkoutRow) -> some View {
        let mins = NunaWorkoutZoneMath.minutes(r, measured: data.zoneMin)
        let averages = NunaWorkoutAverages(for: r, in: m.rows)
        let shown = NunaTreadmillEstimate.filled(r, steps: data.steps)
        let mapped = data.route.count >= 2
        if NunaLowIntensity.applies(row: r, zoneMinutes: mins, hasHeartRate: data.hr.count >= 2, hasRoute: mapped) {
            lowContent(r, shown: shown.row, mins: mins, averages: averages)
        } else {
            NunaWorkoutLogFigures(row: r, averages: averages, steps: data.steps)
            sourceLine(r)
            if mapped {
                // With a map: the heart rate and its zones first, then the route, then the key statistics.
                heartRateAndZones(r, mins: mins)
                zoneFootnote
                NunaWorkoutRouteCard(points: data.route, row: shown.row, elevationGainM: data.elevationGainM, onShare: { Task { await exportFile(r, gpx: true) } })
                NunaWorkoutLogStats(row: shown.row, steps: data.steps, averages: averages, distanceEstimated: shown.estimated, routeShown: true, stepsAtTop: data.steps != nil)
            } else {
                NunaWorkoutLogStats(row: shown.row, steps: data.steps, averages: averages, distanceEstimated: shown.estimated, routeShown: false, stepsAtTop: data.steps != nil)
                heartRateAndZones(r, mins: mins)
            }
            anyaCard(shown.row, mins: mins, averages: averages)
        }
    }

    /// The heart-rate chart and, under it, the zones (the duration is said at their head when the figures at the top show the steps).
    @ViewBuilder private func heartRateAndZones(_ r: WorkoutRow, mins: [Double]?) -> some View {
        if data.hr.count >= 2 { NunaWorkoutHRArea(buckets: data.hr, start: r.startTs, end: r.endTs, around: data.hrAround, highlightZone: zonePick, zoneSet: profile.hrZoneSet) }
        if mins?.contains(where: { $0 > 0 }) ?? false {
            NunaWorkoutLogZones(minutes: mins, selection: $zonePick, buckets: data.hr, start: r.startTs, end: r.endTs,
                                typical: NunaWorkoutLogZones.typical(for: r, in: m.rows),
                                durationS: data.steps != nil ? (r.durationS ?? Double(r.endTs - r.startTs)) : nil,
                                belowMinutes: NunaWorkoutZoneMath.below(r, measured: data.zoneMin))
        }
    }

    /// Under the zones: where the ranges come from, and the way to change them.
    private var zoneFootnote: some View {
        NavigationLink { NunaZonesView() } label: {
            (Text("Zone ranges are set from your maximum heart rate.") + Text(verbatim: " ") + Text("View HR settings").underline().foregroundStyle(NunaPalette.textPrimary))
                .font(.nuna(size: 12, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: Low intensity

    /// A session in which the heart rate stayed in zone 0 and zone 1: the minutes and the stress change, Anya's line, the stress and the heart
    /// rate on two tabs, the milestone, the heart-rate figures and the impact on recovery.
    @ViewBuilder private func lowContent(_ r: WorkoutRow, shown: WorkoutRow, mins: [Double]?, averages: NunaWorkoutAverages?) -> some View {
        NunaLowFigures(row: r, averages: averages, stress: stress, steps: data.steps)
        sourceLine(r)
        anyaCard(shown, mins: mins, averages: averages)
        NunaCapsuleTabs(options: [(value: LowTab.stress, title: "Stress"), (value: LowTab.heartRate, title: "Heart rate")], selection: $lowTab)
        switch lowTab {
        case .stress:
            if stress.count >= 2 { NunaWorkoutStressArea(points: stress, start: r.startTs, end: r.endTs) }
            else { Text("There is not enough heart rate in this session to read the stress.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
        case .heartRate:
            // A session that is not truly low (a minute or more in zone 2 or above, as a brisk walk is) also shows its zones under the chart,
            // as the log of a mapped session does. A session that stayed in zone 0 and 1 keeps the plain chart.
            let reachedHigherZones = (mins?.dropFirst().reduce(0, +) ?? 0) >= 1
            if data.hr.count >= 2 {
                NunaWorkoutHRArea(buckets: data.hr, start: r.startTs, end: r.endTs, around: data.hrAround,
                                  highlightZone: reachedHigherZones ? zonePick : nil, zoneSet: profile.hrZoneSet, plotHeight: 200)
            } else { Text("There is no heart rate for this session.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            if reachedHigherZones {
                NunaWorkoutLogZones(minutes: mins, selection: $zonePick, buckets: data.hr, start: r.startTs, end: r.endTs,
                                    typical: NunaWorkoutLogZones.typical(for: r, in: m.rows), durationS: nil,
                                    belowMinutes: NunaWorkoutZoneMath.below(r, measured: data.zoneMin))
                zoneFootnote
            }
        }
        NunaActivityMilestoneCard(count: m.rows.filter { $0.sport == r.sport && $0.startTs <= r.startTs }.count)
        NunaSessionMetrics(items: sessionMetrics(r, averages: averages))
        NunaActivityImpactCard(impact: NunaActivityImpact.compute(row: r, rows: m.rows, days: repo.days))
    }

    private func sessionMetrics(_ r: WorkoutRow, averages: NunaWorkoutAverages?) -> [NunaSessionMetrics.Item] {
        var items: [NunaSessionMetrics.Item] = []
        if let lo = data.hr.map(\.minBpm).min() { items.append(.init(id: "min", icon: "arrow.down.heart", label: "Min HR", value: "\(Int(lo.rounded()))")) }
        if let hr = r.avgHr {
            var t = NunaSessionMetrics.Item(id: "avg", icon: NunaIcons.avgHr, label: "Avg HR", value: "\(hr)")
            if let avg = averages?.avgHr { t.pill = (Double(hr), avg, "\(Int(avg.rounded()))bpm") }
            items.append(t)
        }
        if let hr = r.maxHr {
            var t = NunaSessionMetrics.Item(id: "max", icon: NunaIcons.maxHr, label: "Max HR", value: "\(hr)")
            if let avg = averages?.maxHr { t.pill = (Double(hr), avg, "\(Int(avg.rounded()))bpm") }
            items.append(t)
        }
        return items
    }

    /// Under the figures and above Anya: where an activity came from when it was not recorded here (Apple Health, Strava). Nothing for the strap or
    /// for what was logged in the app.
    @ViewBuilder private func sourceLine(_ r: WorkoutRow) -> some View {
        if let from = WorkoutSource.externalName(r) {
            Text(verbatim: String(localized: "Imported from \(from)")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Anya

    /// Anya's card under the figures. A breathing session gets her own reading of it (what the heart rate, HRV and stress did) in a warm voice, and
    /// when the same exercise keeps coming back, the offer to keep it as a favourite; every other session gets the workout read.
    @ViewBuilder private func anyaCard(_ r: WorkoutRow, mins: [Double]?, averages: NunaWorkoutAverages?) -> some View {
        if let rec = NunaBreathCoach.record(for: r) {
            NunaBreathInsightCard(insight: NunaBreathCoach.insight(for: rec, stress: stress, heartRate: data.hr.map(\.bpm)), offer: NunaBreathCoach.offer(for: rec)) { showBreathAnya = true }
        } else if let line = anyaLine(r, mins: mins, averages: averages) {
            NunaAnyaCard(verbatim: line.headline, detail: line.detail) { showCoach = true }
        }
    }

    /// Everything the log says, for Anya to read: the zone line first, then distance and pace, steps, calories, heart rate and Effort, each
    /// against the wearer's own 30-day average of the sport when there is one.
    private func anyaLine(_ r: WorkoutRow, mins: [Double]?, averages: NunaWorkoutAverages?) -> (headline: String, detail: String?)? {
        let scale = UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? EffortScale.hundred.rawValue)
        let system = UnitPrefs.resolveDistance(system: UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric,
                                               override: UserDefaults.standard.string(forKey: UnitPrefs.distanceSystemKey) ?? "")
        let secs = r.durationS ?? Double(r.endTs - r.startTs)
        let facts = WorkoutFacts(durationS: secs, distanceM: r.distanceM, avgHr: r.avgHr.map(Double.init), effort: r.strain, zoneMin: mins)
        // The wearer's own other sessions of the sport over the last 30 days; the zone minutes are the mean of the ones that have them.
        var baseline: WorkoutBaseline?
        if let a = averages {
            let others = otherSessions(r)
            let zoneMean: [Double]? = others.count >= 2 && others.allSatisfy({ $0.count >= 5 })
                ? (0..<5).map { z in others.map { $0[z] }.reduce(0, +) / Double(others.count) } : nil
            baseline = WorkoutBaseline(count: a.count, durationS: a.durationS ?? secs, distanceM: a.distanceM, avgHr: a.avgHr, effort: a.effort, zoneMin: zoneMean)
        }
        // The day the session belongs to, against the Effort range its Charge supports.
        var day: WorkoutDayContext?
        if let effort = data.dayEffort, let charge = data.dayCharge, let band = CoupledView.optimalStrainRange(recovery: charge) {
            day = WorkoutDayContext(dayEffort: effort, rangeLow: Double(band.lowerBound) / UnitFormatter.effortScaleFactor,
                                    rangeHigh: Double(band.upperBound) / UnitFormatter.effortScaleFactor, charge: charge)
        }
        // The weather and air at the time, when the app read them near the session.
        let conditions = EnvironmentStore.shared.snapshot(near: (r.startTs + r.endTs) / 2)
        guard let read = WorkoutRead.analyze(facts, baseline: baseline, day: day, conditions: conditions) else { return nil }
        return NunaInsightText.workout(read, system: system, scale: scale)
    }

    // MARK: Header actions

    private func actionsMenu(_ r: WorkoutRow) -> some View {
        var items: [NunaActionItem] = [
            NunaActionItem(title: "Export file", symbol: "square.and.arrow.up") { Task { await exportFile(r, gpx: false) } },
        ]
        if data.route.count >= 2 { items.append(NunaActionItem(title: "Export route (GPX)", symbol: "map") { Task { await exportFile(r, gpx: true) } }) }
        if stravaState == .ready {
            items.append(NunaActionItem(title: "Upload to Strava", symbol: "arrow.up.circle") { Task { await sendToStrava(r) } })
        } else if stravaState == .uploaded || stravaState == .processing {
            items.append(NunaActionItem(title: "On Strava", symbol: "checkmark.circle", enabled: false) {})
        }
        if WorkoutSource.classify(r.source) == .manual {
            items.append(NunaActionItem(title: "Edit activity", symbol: "pencil") { showEditActivity = true })
        } else if Self.canEditTime(r) {
            items.append(NunaActionItem(title: "Edit time", symbol: "clock") { showEdit = true })
        }
        items.append(NunaActionItem(title: "Delete", symbol: "trash", destructive: true) { confirmDelete = true })
        return NunaActionsButton(items: items)
    }

    /// Only a session this app owns can be moved in time: a strap or manual one, never an Apple Health, imported file or Hevy session.
    private static func canEditTime(_ r: WorkoutRow) -> Bool {
        switch WorkoutSource.classify(r.source) {
        case .whoop, .manual, .detected: return true
        case .apple, .lifting, .activityFile: return false
        }
    }

    private func exportFile(_ r: WorkoutRow, gpx: Bool) async {
        let points = data.route.map { RoutePoint(lat: $0.lat, lon: $0.lon) }
        let steps = data.steps
        let r = NunaTreadmillEstimate.filled(r, steps: steps).row
        let format: RouteExporter.Format = gpx ? .gpx : .fit
        let name = "noop-workout-\(r.startTs).\(format.ext)"
        let file = await Task.detached(priority: .userInitiated) {
            RouteExporter.render(format, route: points, startTs: r.startTs, endTs: r.endTs, sport: r.sport, distanceM: r.distanceM,
                                 energyKcal: r.energyKcal, avgHr: r.avgHr, maxHr: r.maxHr, movingTimeS: r.durationS, steps: steps)
        }.value
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? file.write(to: url)) != nil else { return }
        FileExport.exportFile(at: url, suggestedName: name)
    }

    private func sendToStrava(_ r: WorkoutRow) async {
        await strava.upload(r)
        stravaState = NunaStravaCheck.state(r)
        stravaMessage = strava.statusText
    }

    /// Moves the session to the new start and end. Its photos, how it felt and its Strava record follow it; the figures measured inside the
    /// window are cleared for a strap session so they are read again for the new time.
    private func moveInTime(_ r: WorkoutRow, start: Date, end: Date) async {
        let s = Int(start.timeIntervalSince1970), e = Int(end.timeIntervalSince1970)
        let fromStrap = WorkoutSource.classify(r.source) != .manual
        let moved = WorkoutRow(startTs: s, endTs: e, sport: r.sport, source: r.source, durationS: Double(e - s),
                               energyKcal: fromStrap ? nil : r.energyKcal, avgHr: fromStrap ? nil : r.avgHr, maxHr: fromStrap ? nil : r.maxHr,
                               strain: fromStrap ? nil : r.strain, distanceM: r.distanceM, zonesJSON: fromStrap ? nil : r.zonesJSON,
                               notes: r.notes, steps: fromStrap ? nil : r.steps)
        await repo.saveManualWorkout(moved, replacing: r)
        carryRecords(from: r, to: moved)
        await intelligence.analyzeRecent()
        await repo.refresh()
        dismiss()
    }

    /// Its photos, how it felt and its Strava record follow a session whose start or sport changed.
    private func carryRecords(from r: WorkoutRow, to moved: WorkoutRow) {
        NunaWorkoutReviewStore.move(fromStartTs: r.startTs, fromSport: r.sport, toStartTs: moved.startTs, toSport: moved.sport)
        let oldKey = StravaSettingsModel.workoutKey(for: r), newKey = StravaSettingsModel.workoutKey(for: moved)
        guard oldKey != newKey, let rec = StravaActivityStore.record(for: oldKey) else { return }
        let copy = StravaUploadRecord(workoutKey: newKey, startTs: moved.startTs, sport: rec.sport, uploadId: rec.uploadId,
                                      activityId: rec.activityId, status: rec.status, message: rec.message, updatedAt: rec.updatedAt)
        StravaActivityStore.save(copy)
        StravaActivityStore.remove(workoutKeys: [oldKey])
    }

    /// Saves what the edit sheet changed (sport, time, distance, average heart rate, calories). The session keeps what was measured: its
    /// heart-rate curve, zones, Effort and steps.
    private func applyEdit(_ r: WorkoutRow, to new: WorkoutRow) async {
        await repo.saveManualWorkout(new, replacing: r)
        carryRecords(from: r, to: new)
        await intelligence.analyzeRecent()
        await repo.refresh()
        if new.startTs != r.startTs || new.sport != r.sport { dismiss() }
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
