import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for an active workout or live-HR session: the Lock Screen banner and the Dynamic Island, in the Nuna look
/// (LiveActivities, LiveActivitiesNoGps and LiveIsland).
///
/// A route sport leads with distance, time and pace (speed for a bike); a sport without a route with time, calories and the time in the
/// current zone. The Island's compact view is a progress ring and the clock on the left and the sport's main figure on the right; a
/// pause turns it yellow and runs the pause clock, and leaving the target zone turns it red.
struct NOOPLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NOOPActivityAttributes.self) { context in
            LockScreen(state: context.state, title: context.attributes.title)
                .widgetURL(URL(string: "noop://workout"))
                // Glass: a translucent tint over the system material, so the wallpaper shows through softly.
                .activityBackgroundTint(NunaPalette.card.opacity(0.55))
                .activitySystemActionForegroundColor(NunaPalette.textPrimary)
        } dynamicIsland: { context in
            let s = context.state
            let tint = s.accent
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HeartRate(state: s, tint: tint, size: 28)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedPill(state: s, tint: tint, size: 17)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        ZoneStrip(state: s, tint: tint)
                        WorkoutFigures(state: s, size: 20)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                HStack(spacing: 6) {
                    NOOPLiveRing(symbol: s.compactSymbol, tint: tint, progress: s.progress)
                    if s.isPaused {
                        Text("Paused").font(.nuna(size: 13, weight: .heavy)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
                    } else if s.outOfZone, let z = s.heartRateZone {
                        Text("Zone \(z)").font(.nuna(size: 13, weight: .heavy)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        clock(s).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: 46, alignment: .leading)
                    }
                }
            } compactTrailing: {
                Group {
                    if let paused = s.pausedAt {
                        Text(timerInterval: paused...paused.addingTimeInterval(86_400), countsDown: false).foregroundStyle(tint)
                    } else if s.outOfZone {
                        Text(verbatim: s.bpm.map(String.init) ?? "–").foregroundStyle(tint)
                    } else if s.isRoute {
                        Text(verbatim: s.mainFigure)
                    } else {
                        Text(verbatim: s.bpm.map { "\($0) bpm" } ?? "–")
                    }
                }
                .font(.nuna(size: 12.5, weight: .heavy, design: NunaType.design)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: 62)
            } minimal: {
                Image(systemName: s.compactSymbol).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
            }
            // Tapping the banner or the Island opens the app on the session that is running.
            .widgetURL(URL(string: "noop://workout"))
            .keylineTint(s.isPaused ? NunaPalette.warning : (s.outOfZone ? NunaPalette.alert : nil))
        }
    }
}

// MARK: - state helpers

private extension NOOPActivityAttributes.ContentState {
    var isPaused: Bool { pausedAt != nil }
    /// A session with a target zone, heart rate above it.
    var outOfZone: Bool {
        guard let t = targetZone, let z = heartRateZone else { return false }
        return z > t
    }
    /// Colour of everything that reads "this session": yellow paused, red out of zone, otherwise the current zone.
    var accent: Color {
        if isPaused { return NunaPalette.warning }
        if outOfZone { return NunaPalette.alert }
        return NOOPLive.tint(zone: heartRateZone)
    }
    var symbol: String { activityName.map(ActivitySport.symbol(for:)) ?? "heart.fill" }
    var compactSymbol: String { isPaused ? "pause.fill" : (outOfZone ? "heart.fill" : symbol) }
    var isCycling: Bool { activityName == "Cycling" }
    /// A sport that records a route leads with distance, time and pace.
    var isRoute: Bool { activityName.map { ActivitySport.isRoute($0) } == true || distance != nil || pace != nil }
    /// What the compact Island shows on the right for a route sport: speed on a bike, pace otherwise.
    var mainFigure: String { ((isCycling ? speed : pace) ?? "–").replacingOccurrences(of: " ", with: "") }
    func effortText(_ e: Int) -> Text {
        if activityName == nil { return Text("Effort \(e)") }
        return effortLabel.map { Text("Effort +\($0)") } ?? Text("Effort +\(e)")
    }
}

@ViewBuilder private func clock(_ s: NOOPActivityAttributes.ContentState) -> some View {
    if let start = s.activityStartedAt {
        Text(timerInterval: start...start.addingTimeInterval(86_400), pauseTime: s.pausedAt, countsDown: false)
    } else {
        Text(verbatim: "–")
    }
}

// MARK: - Lock Screen

private struct LockScreen: View {
    let state: NOOPActivityAttributes.ContentState
    let title: String

    var body: some View {
        if state.activityName == nil { liveHeartRate } else { workout }
    }

    /// No workout, only the live heart rate: a heart and the number, nothing else.
    private var liveHeartRate: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(NunaPalette.alertText)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(verbatim: state.bpm.map(String.init) ?? "–").font(.nuna(size: 40, weight: .bold, design: NunaType.design)).monospacedDigit()
                    .foregroundStyle(state.bonded ? NunaPalette.textPrimary : NunaPalette.textMuted)
                Text("bpm").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
            Spacer(minLength: 8)
            // The link to the strap dropped: the banner stays and says so, instead of vanishing and needing the app to come back.
            if !state.bonded {
                Text("Reconnecting…").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
    }

    /// Heart rate and the clock always; the zone bar under them; then the figures the session has: distance and pace (speed on a bike)
    /// with a route, steps (walk, run) or calories in the middle.
    private var workout: some View {
        let tint = state.accent
        return VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                HeartRate(state: state, tint: tint, size: 36)
                Spacer(minLength: 8)
                ElapsedPill(state: state, tint: tint, size: 20)
            }
            ZoneStrip(state: state, tint: tint)
            WorkoutFigures(state: state, size: 24)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
    }
}

// MARK: - the pieces

/// The heart and the number, kept whole: the unit and the figure never give way.
private struct HeartRate: View {
    let state: NOOPActivityAttributes.ContentState
    let tint: Color
    let size: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill").font(.system(size: size * 0.62, weight: .bold)).foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: state.bpm.map(String.init) ?? "–").font(.nuna(size: size, weight: .bold, design: NunaType.design)).monospacedDigit()
                    .foregroundStyle(state.outOfZone ? tint : NunaPalette.textPrimary)
                Text("bpm").font(.nuna(size: max(size * 0.4, 11), weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
            .fixedSize()
        }
        .fixedSize()
    }
}

/// The elapsed time of the session in a rounded tile; it stands still, with a pause mark, while the session is paused.
private struct ElapsedPill: View {
    let state: NOOPActivityAttributes.ContentState
    let tint: Color
    let size: CGFloat

    var body: some View {
        let tone = state.isPaused ? NunaPalette.warning : NunaPalette.effortModerate
        // A timer text takes all the width it is offered, so it is given its own: five characters (m:ss) until the first hour, seven
        // after it. Left open it makes the whole row infinitely wide.
        let hours = (state.activityStartedAt.map { Date().timeIntervalSince($0) } ?? 0) >= 3600
        HStack(spacing: 8) {
            Image(systemName: state.isPaused ? "pause.fill" : "stopwatch").font(.system(size: size * 0.8, weight: .bold))
            clock(state).font(.nuna(size: size, weight: .bold, design: NunaType.design)).monospacedDigit()
                .foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                .frame(width: size * (hours ? 3.9 : 2.9), alignment: .leading)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 14).frame(height: size * 2.1)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: size * 1.05, style: .continuous))
        .fixedSize()
    }
}

/// The five-zone bar with the zone's name centred under it.
private struct ZoneStrip: View {
    let state: NOOPActivityAttributes.ContentState
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            NOOPZoneBar(zone: state.heartRateZone, position: state.zonePosition)
            if state.isPaused {
                Text("Paused").font(.nuna(size: 11.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(NunaPalette.warning)
            } else if let z = state.heartRateZone {
                Text("Zone \(z)").font(.nuna(size: 11.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(tint)
            }
        }
    }
}

// MARK: - the figures

/// One figure: the number with its unit beside it, and its name under it, centred in its column.
private struct FigureColumn: View {
    let label: LocalizedStringKey
    let value: String
    let unit: String
    let size: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value).font(.nuna(size: size, weight: .bold, design: NunaType.design)).monospacedDigit()
                    .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(verbatim: unit).font(.nuna(size: size * 0.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1)
                }
            }
            Text(label).font(.nuna(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(NunaPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// What the session can tell: distance and pace (speed on a bike) when it records a route, with steps (walk, run, hike) or calories in
/// the middle. Without a route: steps and calories on foot, calories otherwise. Live heart rate alone: Effort and the strap battery.
private struct WorkoutFigures: View {
    let state: NOOPActivityAttributes.ContentState
    let size: CGFloat

    private struct Figure: Identifiable {
        let id: String
        let label: LocalizedStringKey
        let value: String
        var unit = ""
    }

    private var onFoot: Bool { state.activityName.map(ActivitySport.countsSteps) ?? false }

    private var calories: Figure {
        Figure(id: "calories", label: "CALORIES", value: state.calories.map(String.init) ?? "–",
               unit: state.calories == nil ? "" : String(localized: "kcal"))
    }

    private var steps: Figure? {
        state.steps.map { Figure(id: "steps", label: "STEPS", value: String($0)) }
    }

    private var figures: [Figure] {
        if state.isRoute {
            let d = NOOPLive.split(state.distance)
            let p = NOOPLive.split(state.isCycling ? state.speed : state.pace)
            return [Figure(id: "distance", label: "DISTANCE", value: d.0, unit: d.1),
                    (onFoot ? steps : nil) ?? calories,
                    Figure(id: "pace", label: state.isCycling ? "SPEED" : "PACE", value: p.0, unit: p.1)]
        }
        return onFoot ? [steps, calories].compactMap { $0 } : [calories]
    }

    var body: some View {
        if state.activityName == nil {
            HStack(spacing: 0) {
                NOOPLiveMetric(label: "EFFORT", text: Text(verbatim: state.effort.map(String.init) ?? "–"), size: size, alignment: .leading)
                VStack(spacing: 4) {
                    Text("Battery").font(.nuna(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(NunaPalette.textSecondary)
                    NOOPBatteryRing(percent: state.batteryPct, size: size)
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            let items = figures
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: size * 1.9) }
                    FigureColumn(label: item.label, value: item.value, unit: item.unit, size: size)
                }
            }
        }
    }
}
