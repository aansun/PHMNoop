import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for a running Lift Log session, in the Nuna look (LiveActivitiesNoGps and LiveIsland, gym).
///
/// Lock Screen and expanded Island: the session clock, sets done of planned and the volume lifted so far, with the heart rate and the
/// zone bar. Through a rest the Island turns blue and counts the rest down.
///
/// THE CLOCKS TICK WITHOUT THE APP. Every timer is `Text(timerInterval:)`, driven by dates in the content state, so the Lock Screen
/// counts on its own between pushes. The app only sends a new state when something actually changes (stage, set, heart rate).
struct LiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiftActivityAttributes.self) { context in
            LiftLockScreen(state: context.state, program: context.attributes.programName)
                .activityBackgroundTint(NunaPalette.card)
                .activitySystemActionForegroundColor(NunaPalette.textPrimary)
        } dynamicIsland: { context in
            let s = context.state
            let tint = s.accent
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        NOOPLiveRing(symbol: "dumbbell.fill", tint: tint, progress: s.ringProgress)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Gym").font(.nuna(size: 14.5, weight: .heavy))
                            if s.isResting {
                                Text("Resting").font(.nuna(size: 11, weight: .heavy)).foregroundStyle(tint)
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
                        LiftMetrics(state: s, size: 22)
                        NOOPZoneBar(zone: s.heartRateZone, position: s.zonePosition)
                    }
                    .padding(.top, 6)
                }
            } compactLeading: {
                HStack(spacing: 6) {
                    NOOPLiveRing(symbol: s.isResting ? "bolt.fill" : "dumbbell.fill", tint: tint, progress: s.ringProgress)
                    if s.isResting {
                        Text("Resting").font(.nuna(size: 13, weight: .heavy)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        sessionClock(s).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).monospacedDigit().lineLimit(1)
                            .minimumScaleFactor(0.7).frame(maxWidth: 46, alignment: .leading)
                    }
                }
            } compactTrailing: {
                Group {
                    if s.isResting { restClock(s).foregroundStyle(tint) }
                    else if let d = s.setsDone, let p = s.setsPlanned { Text("Set \(d)/\(p)") }
                    else { Text(verbatim: s.status) }
                }
                .font(.nuna(size: 12.5, weight: .heavy, design: NunaType.design)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: 62)
            } minimal: {
                Image(systemName: s.isResting ? "bolt.fill" : "dumbbell.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
            }
            .keylineTint(s.isResting ? tint : nil)
        }
    }
}

private extension LiftActivityAttributes.ContentState {
    /// Blue through a rest, otherwise the colour of the current heart-rate zone.
    var accent: Color { isResting ? NunaPalette.rest : NOOPLive.tint(zone: heartRateZone) }
    func effortText(_ e: Int) -> Text { effortLabel.map { Text("Effort +\($0)") } ?? Text("Effort +\(e)") }
    var ringProgress: Double? {
        guard let d = setsDone, let p = setsPlanned, p > 0 else { return nil }
        return min(max(Double(d) / Double(p), 0), 1)
    }
}

/// The session clock, counting up from the start of the whole session.
@ViewBuilder private func sessionClock(_ s: LiftActivityAttributes.ContentState) -> some View {
    let from = s.sessionStartedAt ?? s.stageStartedAt
    Text(timerInterval: from...from.addingTimeInterval(86_400), countsDown: false)
}

/// Counts DOWN through a rest (the number you act on); an overrun rest counts UP from when it was due.
///
/// `Text(timerInterval:)` is the API widgets are given for a clock that advances without the app pushing. `Text(date, style: .timer)`
/// looks equivalent and is not: on the Lock Screen it rendered "25 minutes" where a gym timer has to read 25:02. A zero-length range
/// would render nothing, so the end is pushed a day out.
@ViewBuilder private func restClock(_ s: LiftActivityAttributes.ContentState) -> some View {
    if let ends = s.restEndsAt, ends > .now {
        Text(timerInterval: .now...ends, countsDown: true)
    } else {
        let from = s.restEndsAt ?? s.stageStartedAt
        Text(timerInterval: from...from.addingTimeInterval(86_400), countsDown: false)
    }
}

private struct LiftLockScreen: View {
    let state: LiftActivityAttributes.ContentState
    let program: String

    var body: some View {
        let tint = state.accent
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 10) {
                    Circle().fill(NunaPalette.alert).frame(width: 10, height: 10)
                    Text("Gym").font(.nuna(size: 15.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                }
                Spacer(minLength: 8)
                if state.isResting {
                    HStack(spacing: 6) {
                        Text("Resting")
                        restClock(state).monospacedDigit().frame(minWidth: 34, alignment: .leading)
                    }
                    .fixedSize()
                    .font(.nuna(size: 12, weight: .heavy)).foregroundStyle(tint)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if let e = state.effort {
                    NOOPLiveChip(text: state.effortText(e), color: NunaPalette.effortText, systemImage: "bolt.fill")
                }
            }
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(verbatim: state.bpm.map(String.init) ?? "–").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).monospacedDigit()
                            .foregroundStyle(NunaPalette.textPrimary)
                        Text("bpm").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    if let z = state.heartRateZone { NOOPLiveChip(text: Text("Zone \(z)"), color: NOOPLive.tint(zone: z)).scaleEffect(0.85, anchor: .leading) }
                }
                Spacer(minLength: 6)
                Text(verbatim: state.exercise + " · " + state.status).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.top, 8)
            NOOPZoneBar(zone: state.heartRateZone, position: state.zonePosition).padding(.top, 6)
            Rectangle().fill(NunaPalette.hairline).frame(height: 1).padding(.top, 2).padding(.bottom, 8)
            LiftMetrics(state: state, size: 26)
        }
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18))
    }
}

/// Time, sets done of planned, and volume lifted so far.
private struct LiftMetrics: View {
    let state: LiftActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        let v = NOOPLive.split(state.volume)
        HStack(spacing: 0) {
            NOOPLiveMetric(label: "TIME", text: sessionClock(state), size: size, alignment: .leading)
            NOOPLiveMetric(label: "SETS", text: Text(verbatim: state.setsDone.map(String.init) ?? "–"),
                           unit: state.setsPlanned.map { "/ \($0)" } ?? "", size: size, alignment: .center)
            NOOPLiveMetric(label: "VOLUME", text: Text(verbatim: v.0), unit: v.1, size: size, alignment: .trailing)
        }
    }
}
