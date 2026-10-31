#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// "Today's activities": one card with a row for the night's sleep and every workout of the day in the order they happened. Each row is a
/// coloured tile with the figure that matters (sleep time, Effort), the name, and when it began and ended. A row opens its own detail; the
/// chevron at the top right opens all workouts. Nothing is cut off: a day with six activities shows six rows.
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
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @State private var night: (onset: Date, wake: Date)?
    @State private var naps: [(dayKey: String, nap: NunaNap)] = []

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

    var body: some View {
        let rows = items
        return NunaCard(padding: EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12)) {
        VStack(alignment: .leading, spacing: 10) {
            // A small heading, and at the right the way into every workout.
            HStack {
                Text(isToday ? "Today's activities" : LocalizedStringKey(Self.dayTitle(dayStart)))
                    .font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer(minLength: 8)
                Button { router.requestedDestination = .workouts } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(Text("All workouts"))
            }
            .padding(.horizontal, 6).padding(.top, 4)
            VStack(spacing: 7) {
                if rows.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "figure.run").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                        Text("No activities logged today").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 52)
                    .background(NunaPalette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ForEach(rows) { item in row(item) }
                }
            }
            if onAdd != nil || onStart != nil {
                HStack(spacing: 8) {
                    if let onAdd { actionButton("Add activity", icon: "plus", action: onAdd) }
                    if let onStart { actionButton("Start activity", icon: "stopwatch", action: onStart) }
                }
                .padding(.top, 3)
            }
        }
        }
        // The card is the same surface as every other card; only the rows and buttons inside it are a shade darker.
        .task(id: "\(repo.refreshSeq)-\(dayStart.timeIntervalSince1970)-\(includesSleep)") {
            if includesSleep { await loadNight() }
            else { night = nil; naps = [] }
        }
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
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
            .background(NunaPalette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: NunaRadius.chip + 2, style: .continuous))
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
                        figure: recovery ? Self.hoursAndMinutes((w.durationS ?? Double(w.endTs - w.startTs)) / 60) : workoutFigure(w),
                        name: Text(verbatim: WorkoutSource.displaySport(w.sport)), start: item.start, end: item.end)
            }.buttonStyle(.plain)
        }
    }

    /// The tile and line of a recovery activity: a light blue, apart from the Effort blue.
    private static let recoveryBlue = Color(hex: "#5EA9E8")

    /// A tile in neutral grey (icon and figure), the name, when it began and ended, and a thin line with a dot at each end whose colour
    /// follows the Effort of the workout (sleep keeps the Rest colour).
    private func rowBody(tint: Color, tile: Color, icon: String, figure: String, name: Text, start: Date, end: Date) -> some View {
        HStack(spacing: 12) {
            // Icon and figure start at the same place in every row, whatever the figure's width, so the column of figures reads as one line.
            HStack(spacing: 7) {
                Image(systemName: icon).font(.nuna(size: 15, weight: .semibold)).frame(width: 20)
                Text(verbatim: figure).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 11)
            .foregroundStyle(Color.white)
            .frame(width: 100, height: 40, alignment: .leading)
            .background(tile, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            name.font(.nuna(size: 12.5, weight: .heavy)).tracking(1.1).foregroundStyle(NunaPalette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(verbatim: Self.stamp(start, relativeTo: dayStart))
                Text(verbatim: Self.stamp(end, relativeTo: dayStart))
            }
            .font(.nuna(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(NunaPalette.textSecondary)
            VStack(spacing: 0) {
                Circle().fill(NunaPalette.textPrimary.opacity(0.85)).frame(width: 3.5, height: 3.5)
                Rectangle().fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .top, endPoint: .bottom)).frame(width: 2.5, height: 24)
                Circle().fill(NunaPalette.textPrimary.opacity(0.85)).frame(width: 3.5, height: 3.5)
            }
            .padding(.trailing, 2)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        // A shade darker than the card it sits on (a thin wash of the text colour): it follows the active look.
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
#endif
