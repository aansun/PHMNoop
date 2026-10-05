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
                .activityBackgroundTint(NunaPalette.card)
                .activitySystemActionForegroundColor(NunaPalette.textPrimary)
        } dynamicIsland: { context in
            let s = context.state
            let tint = s.accent
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        NOOPLiveRing(symbol: s.symbol, tint: tint, progress: s.progress)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: s.activityName ?? context.attributes.title).font(.nuna(size: 14.5, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                            if s.isPaused {
                                Text("Paused").font(.nuna(size: 11, weight: .heavy)).foregroundStyle(tint)
                            } else if let z = s.heartRateZone {
                                Text("Zone \(z)").font(.nuna(size: 11, weight: .heavy)).foregroundStyle(tint)
                            }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "heart.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                        Text(verbatim: s.bpm.map(String.init) ?? "–").font(.nuna(size: 18, weight: .bold, design: NunaType.design)).monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let e = s.effort { NOOPLiveChip(text: s.effortText(e), color: NunaPalette.effortText, systemImage: "bolt.fill") }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        Metrics(state: s, size: 22)
                        NOOPZoneBar(zone: s.heartRateZone, position: s.zonePosition)
                    }
                    .padding(.top, 6)
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
        let tint = state.accent
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 10) {
                    Circle().fill(NunaPalette.alert).frame(width: 10, height: 10)
                    Text(verbatim: state.activityName ?? title).font(.nuna(size: 15.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let paused = state.pausedAt {
                    HStack(spacing: 6) {
                        Text("Paused")
                        Text(timerInterval: paused...paused.addingTimeInterval(86_400), countsDown: false).monospacedDigit().frame(minWidth: 34, alignment: .leading)
                    }
                    .fixedSize()
                    .font(.nuna(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.warning)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(NunaPalette.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if let e = state.effort {
                    NOOPLiveChip(text: state.effortText(e), color: NunaPalette.effortText, systemImage: "bolt.fill")
                }
            }
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(verbatim: state.bpm.map(String.init) ?? "–").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).monospacedDigit()
                            .foregroundStyle(state.outOfZone ? tint : NunaPalette.textPrimary)
                        Text("bpm").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    if let z = state.heartRateZone { NOOPLiveChip(text: Text("Zone \(z)"), color: NOOPLive.tint(zone: z)).scaleEffect(0.85, anchor: .leading) }
                }
                Spacer(minLength: 6)
                if let sub = state.subtitle {
                    Text(verbatim: sub).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .padding(.top, 8)
            NOOPZoneBar(zone: state.heartRateZone, position: state.zonePosition).padding(.top, 6)
            Rectangle().fill(NunaPalette.hairline).frame(height: 1).padding(.top, 2).padding(.bottom, 8)
            Metrics(state: state, size: 26)
        }
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18))
    }
}

// MARK: - the three figures

/// Three figures, left, centre and right. A route sport: distance, time and pace (speed on a bike). A sport without a route: time,
/// calories and the time in the current zone. Live heart rate alone: Effort and the strap battery.
private struct Metrics: View {
    let state: NOOPActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        if state.activityName == nil {
            HStack(spacing: 0) {
                NOOPLiveMetric(label: "EFFORT", text: Text(verbatim: state.effort.map(String.init) ?? "–"), size: size, alignment: .leading)
                VStack(spacing: 4) {
                    Text("Battery").font(.nuna(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(NunaPalette.textSecondary)
                    NOOPBatteryRing(percent: state.batteryPct, size: size)
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else if state.isRoute {
            let d = NOOPLive.split(state.distance)
            let p = NOOPLive.split(state.isCycling ? state.speed : state.pace)
            HStack(spacing: 0) {
                NOOPLiveMetric(label: "DISTANCE", text: Text(verbatim: d.0), unit: d.1, size: size, alignment: .leading)
                NOOPLiveMetric(label: "TIME", text: clock(state), size: size, alignment: .center)
                NOOPLiveMetric(label: state.isCycling ? "SPEED" : "PACE", text: Text(verbatim: p.0), unit: p.1, size: size, alignment: .trailing)
            }
        } else {
            HStack(spacing: 0) {
                NOOPLiveMetric(label: "TIME", text: clock(state), size: size, alignment: .leading)
                NOOPLiveMetric(label: "CALORIES", text: Text(verbatim: state.calories.map(String.init) ?? "–"), unit: state.calories == nil ? "" : String(localized: "kcal"), size: size, alignment: .center)
                if let z = state.heartRateZone {
                    NOOPLiveMetric(label: "ZONE \(z)", text: Text(verbatim: mmss(state.zoneSeconds)), size: size, alignment: .trailing)
                } else {
                    NOOPLiveMetric(label: "ZONE", text: Text(verbatim: "–"), size: size, alignment: .trailing)
                }
            }
        }
    }

    private func mmss(_ s: Int?) -> String {
        guard let s else { return "–" }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
