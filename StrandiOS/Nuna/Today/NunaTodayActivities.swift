#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// "Today's activities": one card with a row for the night's sleep and every workout of the day in the order they happened. Each row is a
/// coloured tile with the figure that matters (sleep time, Effort), the name, and when it began and ended. A row opens its own detail; the
/// icon at the top right opens all workouts. Nothing is cut off: a day with six activities shows six rows.
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                nunaTrendsCap("Today's activities")
                Spacer()
                Button { router.requestedDestination = .workouts } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(Text("All workouts"))
            }
            VStack(spacing: 8) {
                ForEach(rows) { item in row(item) }
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 16)
        .background(NunaPalette.glass, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
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
                rowBody(tint: strength ? NunaPalette.rest : NunaPalette.effort, icon: strength ? "dumbbell.fill" : sportSymbol(w.sport),
                        figure: workoutFigure(w), name: Text(verbatim: WorkoutSource.displaySport(w.sport)), start: item.start, end: item.end)
            }.buttonStyle(.plain)
        }
    }

    private func rowBody(tint: Color, icon: String, figure: String, name: Text, start: Date, end: Date) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.nuna(size: 16, weight: .bold))
                Text(verbatim: figure).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).monospacedDigit()
            }
            .foregroundStyle(Color.black.opacity(0.82))
            .frame(width: 108, height: 46, alignment: .center)
            .background(tint.opacity(0.88), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            name.font(.nuna(size: 15, weight: .heavy)).tracking(0.6).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: NunaWorkoutFormat.clock(Int(start.timeIntervalSince1970))).font(.nuna(size: 13, weight: .bold)).monospacedDigit()
                Text(verbatim: NunaWorkoutFormat.clock(Int(end.timeIntervalSince1970))).font(.nuna(size: 13, weight: .bold)).monospacedDigit()
            }
            .foregroundStyle(NunaPalette.textSecondary)
            Capsule().fill(tint).frame(width: 3, height: 34)
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
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
