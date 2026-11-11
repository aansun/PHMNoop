#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

extension Notification.Name {
    /// A workout was saved from outside Today's own sheets (a detected one): Today reloads its day.
    static let nunaWorkoutsChanged = Notification.Name("nunaWorkoutsChanged")
}

/// "Today's activities": one card with a row for the night's sleep and every workout of the day in the order they happened. Each row is a
/// coloured tile with the figure that matters (sleep time, Effort), the name, and when it began and ended. A row opens its own detail; the
/// Nothing is cut off: a day with six activities shows six rows.
struct NunaTodayActivities: View {
    let workouts: [WorkoutRow]
    let effortScale: EffortScale
    let dayStart: Date
    let sleepMinutes: Double?
    var isToday = true
    /// Effort only concerns movement. Its embedded activity card deliberately leaves sleep and naps out.
    var includesSleep = true
    /// The two buttons under the rows. Left out (nil) where the card is embedded and the screen has its own way to start.
    var onAdd: (() -> Void)?
    var onStart: (() -> Void)?
    /// The Effort page's version: no card, no buttons. A plain title over bare rows, and only the activities that gave Effort (a walk, a run,
    /// a lift), not sleep, naps, recovery work or a detected suggestion.
    var plain = false
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @State private var night: (onset: Date, wake: Date)?
    @State private var naps: [(dayKey: String, nap: NunaNap)] = []
    /// A workout the detector found that is not logged yet (Auto-detect on): shown as its own row until it is saved or deleted.
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetect = false
    @State private var detected: AutoWorkoutSuggestion?
    @State private var confirming = false
    /// Ideas committed to in the Daily Outlook, shown after today's rows until they are added, started or removed.
    @AppStorage(NunaOutlookGate.plannedKey) private var plannedRaw = ""
    @State private var openPlan: NunaPlannedActivity?
    /// The heart-rate day across the whole screen, opened by the arrow at the top right of the card.
    @State private var showHeartRate = false

    private struct Item: Identifiable {
        enum Kind { case sleep, workout(WorkoutRow), nap(String, NunaNap) }
        let id: String
        let kind: Kind
        let start: Date
        let end: Date
    }

    private var items: [Item] {
        var out: [Item] = workouts.map { w in
            Item(id: "w-\(w.startTs)-\(w.sport)", kind: .workout(w),
                 start: Date(timeIntervalSince1970: TimeInterval(w.startTs)), end: Date(timeIntervalSince1970: TimeInterval(w.endTs)))
        }
        if includesSleep, let night { out.append(Item(id: "sleep", kind: .sleep, start: night.onset, end: night.wake)) }
        if includesSleep {
            out += naps.map { Item(id: "nap-\(Int($0.nap.start.timeIntervalSince1970))", kind: .nap($0.dayKey, $0.nap), start: $0.nap.start, end: $0.nap.end) }
        }
        return out.sorted { $0.start < $1.start }
    }

    /// "Activities · Tue 20 Oct" for a day that is not today.
    private static func dayTitle(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return String(localized: "Activities") + " · " + f.string(from: d)
    }

    /// The workouts of the day that added Effort.
    private var effortRows: [Item] {
        items.filter { item in
            if case .workout(let w) = item.kind { return (w.strain ?? 0) > 0 && !NunaActivityKind.isCharge(w.sport) }
            return false
        }
    }

    @ViewBuilder private var plainBody: some View {
        let rows = effortRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(isToday ? "Today's Activities" : LocalizedStringKey(Self.dayTitle(dayStart)))
                    .font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    .accessibilityAddTraits(.isHeader).padding(.top, 22).padding(.horizontal, 4)
                VStack(spacing: 12) { ForEach(rows) { item in row(item) } }
            }
        }
    }

    var body: some View {
        if plain { plainBody.task(id: "\(repo.refreshSeq)-\(dayStart.timeIntervalSince1970)") { night = nil; naps = [] } }
        else { cardBody }
    }

    private var cardBody: some View {
        let rows = items
        // Measured on the reference (3x): the card is 244 pt tall, its title is centred 23 pt under the top edge, the rows are 56 pt high with 12 pt
        // between them and 12 pt in from the card's sides, the buttons are 40 pt high and 20 pt under the last row.
        return NunaCard(padding: EdgeInsets(top: 5, leading: 12, bottom: 16, trailing: 12)) {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isToday ? "Today's activities" : LocalizedStringKey(Self.dayTitle(dayStart)))
                    .font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer(minLength: 8)
                // Opens the heart-rate day, turned on its side across the whole screen.
                Button { showHeartRate = true } label: {
                    NunaExpandGlyph().stroke(Color(red: 0.58, green: 0.59, blue: 0.60), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 13, height: 13)
                        .frame(width: 40, height: 36, alignment: .trailing).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Heart rate"))
            }
            .padding(.leading, 4).padding(.trailing, 1).frame(height: 36)
            VStack(spacing: 12) {
                if rows.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "figure.run").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                        Text("No activities logged today").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 56)
                    .background(NunaPalette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ForEach(rows) { item in row(item) }
                }
                if let detected { detectedRow(detected) }
                if isToday { ForEach(NunaOutlookGate.planned(plannedRaw)) { plan in
                    Button { openPlan = plan } label: { NunaPlannedRow(plan: plan, effortScale: effortScale) }.buttonStyle(.plain)
                } }
            }
            .padding(.top, 3)
            if onAdd != nil || onStart != nil {
                HStack(spacing: 12) {
                    if let onAdd { actionButton("Add activity", icon: "plus", action: onAdd) }
                    if let onStart { actionButton("Start activity", icon: "stopwatch", action: onStart) }
                }
                .padding(.top, 20)
            }
        }
        }
        // The card is the same surface as every other card; only the rows and buttons inside it are a shade darker.
        .task(id: "\(repo.refreshSeq)-\(dayStart.timeIntervalSince1970)-\(includesSleep)") {
            if includesSleep { await loadNight() }
            else { night = nil; naps = [] }
        }
        .task(id: "\(autoDetect)-\(repo.refreshSeq)-\(dayStart.timeIntervalSince1970)") { await loadDetected() }
        .fullScreenCover(isPresented: $showHeartRate) { NunaHRFullScreen { showHeartRate = false } }
        .sheet(item: $openPlan) { plan in
            NunaPlannedSheet(plan: plan, effortScale: effortScale, onAdd: onAdd, onStart: onStart, onRemove: { NunaOutlookGate.remove(plan) })
        }
        .sheet(isPresented: $confirming) {
            if let s = detected {
                NunaManualWorkoutSheet(detected: s, onDelete: {
                    if let id = s.stravaId { StravaHandled.add(id); repo.dismissStravaSuggestion(s.workout) } else { repo.dismissDetectedSuggestion(s.workout) }
                    detected = nil
                }) { row, _ in
                    Task {
                        // A workout from Strava keeps its title and, when the sheet had none, its distance.
                        var row = row
                        if s.stravaId != nil {
                            let title = (s.stravaName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            row = WorkoutRow(startTs: row.startTs, endTs: row.endTs, sport: row.sport, source: row.source, durationS: row.durationS, energyKcal: row.energyKcal,
                                             avgHr: row.avgHr, maxHr: row.maxHr, strain: row.strain, distanceM: row.distanceM ?? s.distanceM, zonesJSON: row.zonesJSON,
                                             notes: title.isEmpty ? "Strava" : "Strava · " + title, steps: row.steps)
                            if let id = s.stravaId { StravaHandled.add(id) }
                        }
                        await repo.saveManualWorkout(row)
                        await repo.refresh()
                        NotificationCenter.default.post(name: .nunaWorkoutsChanged, object: nil)
                    }
                    detected = nil
                }
                .nunaSheetChrome(detents: [.large])
            }
        }
    }

    /// The detector's suggestion, when it began on the day on show.
    private func loadDetected() async {
        #if DEBUG
        if CommandLine.arguments.contains("--demo-detected") {
            // A made-up detection an hour ago, to look at the row and the check without waiting for a real one.
            let end = Int(Date().timeIntervalSince1970) - 600
            let w = DetectedWorkout(startSec: end - 38 * 60, endSec: end, avgBpm: 128, peakBpm: 151, durationMin: 38)
            let s = AutoWorkoutSuggestion(workout: w, sport: "Walking", confidence: 0.5, alternatives: ["Running", "Hiking"])
            detected = Calendar.current.isDate(Date(timeIntervalSince1970: TimeInterval(w.startSec)), inSameDayAs: dayStart) ? s : nil
            return
        }
        if CommandLine.arguments.contains("--demo-strava-detected") {
            // The same for a workout found on Strava: its row and its check, without an account.
            let end = Int(Date().timeIntervalSince1970) - 600
            let w = DetectedWorkout(startSec: end - 41 * 60, endSec: end, avgBpm: 112, peakBpm: 148, durationMin: 41)
            let s = AutoWorkoutSuggestion(workout: w, sport: "Strength Training", confidence: 1, stravaId: 1, stravaName: "Evening Weight Training", distanceM: nil)
            detected = Calendar.current.isDate(Date(timeIntervalSince1970: TimeInterval(w.startSec)), inSameDayAs: dayStart) ? s : nil
            return
        }
        #endif
        // A workout found on Strava, when it began on the day on show, comes first: it knows the sport and the exact times, and the heart-rate detector is
        // not asked at all, so the same session is not offered twice.
        let sameDay: (AutoWorkoutSuggestion) -> Bool = { Calendar.current.isDate(Date(timeIntervalSince1970: TimeInterval($0.startSec)), inSameDayAs: dayStart) }
        if let fromStrava = await StravaDetector.suggestion(repo: repo), sameDay(fromStrava) { detected = fromStrava; return }
        guard autoDetect, let s = await repo.autoDetectSuggestion() else { detected = nil; return }
        detected = sameDay(s) ? s : nil
    }

    /// "Activity detected" with a Process button: a dark outlined tile, the words, and the way into the check.
    private func detectedRow(_ s: AutoWorkoutSuggestion) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.arms.open").font(.nuna(size: 24, weight: .regular)).foregroundStyle(Color.white)
                .frame(width: 95, height: 40)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            Text(s.stravaId != nil ? "Found on Strava" : "Activity detected").font(.nuna(size: 12.5, weight: .heavy)).tracking(1.1).foregroundStyle(NunaPalette.textPrimary)
                .lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: 6)
            Button { confirming = true } label: {
                Text("Process").font(.nuna(size: 12, weight: .heavy)).tracking(1.1).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 96, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(NunaPalette.textPrimary, lineWidth: 1.5))
            }.buttonStyle(.plain)
        }
        .padding(8)
        .background(NunaPalette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func actionButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // About 4.4 : 1 as drawn in the design, with a label that is small against the card.
            HStack(spacing: 7) {
                Image(systemName: icon).font(.nuna(size: 12, weight: .bold))
                Text(title).font(.nuna(size: 12, weight: .heavy)).tracking(0.6).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(NunaPalette.textPrimary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
            .background(NunaPalette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func row(_ item: Item) -> some View {
        switch item.kind {
        case .sleep:
            NavigationLink(value: NunaTodayRoute.sleep(0)) {
                rowBody(tint: NunaPalette.rest, tile: NunaRestChart.steel, icon: "moon.fill", figure: sleepFigure(item), name: Text("Sleep"), start: item.start, end: item.end)
            }.buttonStyle(.plain)
        case .nap(let dayKey, let nap):
            NavigationLink(value: NunaTodayRoute.nap(dayKey, Int(nap.start.timeIntervalSince1970))) {
                rowBody(tint: NunaPalette.rest, tile: NunaRestChart.steel, icon: "moon.zzz.fill", figure: Self.hoursAndMinutes(nap.asleepMin), name: Text("Nap"), start: item.start, end: item.end)
            }.buttonStyle(.plain)
        case .workout(let w):
            let strength = NunaWorkoutKind.isStrength(w)
            // Recovery work (breathwork, a cold shower, a sauna) is not Effort: a lighter blue tile that says how long it lasted.
            let recovery = NunaActivityKind.isCharge(w.sport)
            NavigationLink(value: NunaWorkoutRoute.summary(NunaWorkoutKey(startTs: w.startTs, sport: w.sport, source: w.source))) {
                rowBody(tint: recovery ? Self.recoveryBlue : effortTint(w.strain), tile: recovery ? Self.recoveryBlue : NunaPalette.effortModerate,
                        icon: strength ? "dumbbell.fill" : (recovery ? ActivitySport.symbol(for: w.sport) : sportSymbol(w.sport)),
                        drawn: w.sport,
                        figure: recovery ? Self.hoursAndMinutes((w.durationS ?? Double(w.endTs - w.startTs)) / 60) : workoutFigure(w),
                        name: Text(verbatim: WorkoutSource.displaySport(w.sport)), start: item.start, end: item.end)
            }.buttonStyle(.plain)
        }
    }

    /// The tile and line of a recovery activity: a light blue, apart from the Effort blue.
    private static var recoveryBlue: Color { NunaPalette.recoveryBlue }

    /// A tile in neutral grey (icon and figure), the name, when it began and ended, and a thin line with a dot at each end whose colour
    /// follows the Effort of the workout (sleep keeps the Rest colour).
    private func rowBody(tint: Color, tile: Color, icon: String, drawn: String? = nil, figure: String, name: Text, start: Date, end: Date) -> some View {
        // Row 56 pt: a 95 x 40 pt tile 8 pt in (icon and figure centred in it), the name 16 pt after it, the two times at the right in grey DIN Bold,
        // and a 28 pt line with a dot at each end, its right edge 12 pt from the row's.
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                if let drawn, NunaActivityIcons.has(drawn) { NunaActivityGlyph(name: drawn, size: 22).frame(width: 22) }
                else { Image(systemName: icon).font(.nuna(size: 19, weight: .regular)).frame(width: 22) }
                Text(verbatim: figure).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.white)
            .frame(width: 95, height: 40)
            .background(tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            name.font(.nuna(size: 13, weight: .heavy)).tracking(1.3).foregroundStyle(NunaPalette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading).padding(.leading, 16)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text(verbatim: Self.stamp(start, relativeTo: dayStart))
                Text(verbatim: Self.stamp(end, relativeTo: dayStart))
            }
            .font(.nunaBoldFigure(size: 12)).monospacedDigit().foregroundStyle(Color(red: 0.63, green: 0.64, blue: 0.64))
            VStack(spacing: 0) {
                Circle().fill(Color.white).frame(width: 3, height: 3)
                Rectangle().fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .top, endPoint: .bottom)).frame(width: 2.7, height: 22)
                Circle().fill(Color.white).frame(width: 3, height: 3)
            }
            .padding(.leading, 9).padding(.trailing, 4)
        }
        .padding(8)
        // A shade lighter than the card it sits on (a thin wash of the text colour): it follows the active look.
        .background(NunaPalette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    /// A time of day, with the weekday in brackets before it when it falls on another day than the one on show: "[Thu] 23:04".
    private static func stamp(_ d: Date, relativeTo dayStart: Date) -> String {
        let clock = NunaWorkoutFormat.clock(Int(d.timeIntervalSince1970))
        if Calendar.current.isDate(d, inSameDayAs: dayStart) { return clock }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return "[" + f.string(from: d) + "] " + clock
    }

    /// From light to heavy on the stored 0 to 100 Effort: Rest colour, Effort colour, amber, then red.
    private func effortTint(_ stored: Double?) -> Color {
        guard let stored else { return NunaPalette.textMuted }
        switch stored {
        case ..<10: return NunaPalette.rest
        case ..<25: return NunaPalette.effort
        case ..<40: return NunaPalette.warning
        default: return NunaPalette.alert
        }
    }

    /// Sleep as hours and minutes ("6:50"); the span of the night when the daily figure is not there.
    private func sleepFigure(_ item: Item) -> String {
        Self.hoursAndMinutes(sleepMinutes ?? item.end.timeIntervalSince(item.start) / 60)
    }

    /// "6:50", with no unit: sleep and naps read the same way in the tile, so the column of figures stays even.
    private static func hoursAndMinutes(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// Effort when the workout has one, else its length in minutes, as a bare number: no tile carries a unit.
    private func workoutFigure(_ w: WorkoutRow) -> String {
        if let s = w.strain { return UnitFormatter.effortDisplay(s, scale: effortScale) }
        let secs = w.durationS ?? Double(w.endTs - w.startTs)
        return String(Int((secs / 60).rounded()))
    }

    /// The night that ended on this day: the sessions of at least three hours that woke inside it, from the first onset to the last wake.
    private func loadNight() async {
        naps = await NunaSleepModel.naps(from: dayStart, to: dayStart.addingTimeInterval(86_400), repo: repo)
        let lo = Int(dayStart.timeIntervalSince1970)
        let hi = lo + 86_400
        let sessions = await repo.allSleepSessions(days: 4).filter { $0.endTs >= lo && $0.endTs < hi && ($0.endTs - $0.effectiveStartTs) >= 3 * 3600 }
        guard let first = sessions.min(by: { $0.effectiveStartTs < $1.effectiveStartTs }), let last = sessions.max(by: { $0.endTs < $1.endTs }) else {
            night = nil; return
        }
        night = (Date(timeIntervalSince1970: TimeInterval(first.effectiveStartTs)), Date(timeIntervalSince1970: TimeInterval(last.endTs)))
    }
}

/// The expand arrow of the reference: a diagonal with a head at each end (upper right and lower left) and a gap in the middle.
struct NunaExpandGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let a = CGPoint(x: r.minX, y: r.maxY), b = CGPoint(x: r.maxX, y: r.minY), head = r.width * 0.46
        func along(_ t: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        // The two halves of the line.
        p.move(to: a); p.addLine(to: along(0.36))
        p.move(to: along(0.64)); p.addLine(to: b)
        // The heads.
        p.move(to: CGPoint(x: b.x - head, y: b.y)); p.addLine(to: b); p.addLine(to: CGPoint(x: b.x, y: b.y + head))
        p.move(to: CGPoint(x: a.x + head, y: a.y)); p.addLine(to: a); p.addLine(to: CGPoint(x: a.x, y: a.y - head))
        return p
    }
}
#endif
