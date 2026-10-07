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
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @State private var night: (onset: Date, wake: Date)?

    private struct Item: Identifiable {
        enum Kind { case sleep, workout(WorkoutRow) }
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
        if let night { out.append(Item(id: "sleep", kind: .sleep, start: night.onset, end: night.wake)) }
        return out.sorted { $0.start < $1.start }
    }

    var body: some View {
        let rows = items
        VStack(alignment: .leading, spacing: 10) {
            // The heading of Key Metrics, in the same place inside its card, with the same chevron.
            NunaTitleRow(title: "Today's activities") {
                Button { router.requestedDestination = .workouts } label: {
                    Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .heavy))
                        .frame(width: 40, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(Text("All workouts"))
                .padding(.trailing, -13)
            }
            .padding(.horizontal, 6)
            VStack(spacing: 7) {
                ForEach(rows) { item in row(item) }
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
        // The same surface as every other card, so it follows the active look (Default or WHP) with them.
        .background(NunaPalette.card, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(NunaPalette.hairlineSoft, lineWidth: 1))
        .task(id: "\(repo.refreshSeq)-\(dayStart.timeIntervalSince1970)") { await loadNight() }
    }

    @ViewBuilder private func row(_ item: Item) -> some View {
        switch item.kind {
        case .sleep:
            NavigationLink(value: NunaTodayRoute.sleep(0)) {
                rowBody(tint: NunaPalette.rest, icon: "moon.fill", figure: sleepFigure(item), name: Text("Sleep"), start: item.start, end: item.end)
            }.buttonStyle(.plain)
        case .workout(let w):
            let strength = NunaWorkoutKind.isStrength(w)
            NavigationLink(value: NunaWorkoutRoute.summary(NunaWorkoutKey(startTs: w.startTs, sport: w.sport, source: w.source))) {
                rowBody(tint: effortTint(w.strain), icon: strength ? "dumbbell.fill" : sportSymbol(w.sport),
                        figure: workoutFigure(w), name: Text(verbatim: WorkoutSource.displaySport(w.sport)), start: item.start, end: item.end)
            }.buttonStyle(.plain)
        }
    }

    /// A tile in neutral grey (icon and figure), the name, when it began and ended, and a thin line with a dot at each end whose colour
    /// follows the Effort of the workout (sleep keeps the Rest colour).
    private func rowBody(tint: Color, icon: String, figure: String, name: Text, start: Date, end: Date) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.nuna(size: 15, weight: .semibold)).frame(width: 20)
                Text(verbatim: figure).font(.nuna(size: 18, weight: .bold, design: NunaType.design)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(NunaPalette.textPrimary)
            .frame(width: 92, height: 40)
            .background(NunaPalette.ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            name.font(.nuna(size: 13, weight: .heavy)).tracking(0.8).foregroundStyle(NunaPalette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(verbatim: NunaWorkoutFormat.clock(Int(start.timeIntervalSince1970)))
                Text(verbatim: NunaWorkoutFormat.clock(Int(end.timeIntervalSince1970)))
            }
            .font(.nuna(size: 11.5, weight: .bold)).monospacedDigit().foregroundStyle(NunaPalette.textSecondary)
            VStack(spacing: 0) {
                Circle().fill(NunaPalette.textPrimary.opacity(0.85)).frame(width: 3.5, height: 3.5)
                Rectangle().fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .top, endPoint: .bottom)).frame(width: 2.5, height: 24)
                Circle().fill(NunaPalette.textPrimary.opacity(0.85)).frame(width: 3.5, height: 3.5)
            }
            .padding(.trailing, 2)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
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
        let minutes = sleepMinutes ?? item.end.timeIntervalSince(item.start) / 60
        let m = Int(minutes.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// Effort when the workout has one, else its length in minutes.
    private func workoutFigure(_ w: WorkoutRow) -> String {
        if let s = w.strain { return UnitFormatter.effortDisplay(s, scale: effortScale) }
        let secs = w.durationS ?? Double(w.endTs - w.startTs)
        return String(localized: "\(Int((secs / 60).rounded())) min")
    }

    /// The night that ended on this day: the sessions of at least three hours that woke inside it, from the first onset to the last wake.
    private func loadNight() async {
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
