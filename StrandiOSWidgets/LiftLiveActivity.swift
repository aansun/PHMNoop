import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for a running Lift Log session — the minimised session bar, on the Lock Screen and
/// in the Dynamic Island.
///
/// It carries the same four things the in-app bar does, in the same order, because it is answering
/// the same question from further away: what am I doing, on what, with what numbers, and how long.
/// The colour language matches too — green while a set is being worked, amber through the rest.
///
/// THE CLOCK TICKS WITHOUT THE APP. Both timers are `Text(timerInterval:)`, driven by dates in the
/// content state, so the Lock Screen counts on its own between pushes. The app only sends a new
/// state when something actually changes (stage, set, heart rate), never once a second to animate a
/// number.
struct LiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiftActivityAttributes.self) { context in
            lockScreen(context.state, program: context.attributes.programName)
                .activityBackgroundTint(NunaPalette.card)
                .activitySystemActionForegroundColor(NunaPalette.textPrimary)
        } dynamicIsland: { context in
            let s = context.state
            let tint = tint(s)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        NOOPLiveGlyph(symbol: "dumbbell.fill", tint: tint, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: s.exercise).font(.nuna(size: 14, weight: .heavy)).lineLimit(1)
                            Text(verbatim: s.status).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    clock(s, tint: tint).font(.nuna(size: 26, weight: .bold, design: NunaType.design))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        HStack(spacing: 0) {
                            NOOPLiveMetric(label: "SETS", value: s.progress)
                            if let d = s.detail { NOOPLiveDivider(); NOOPLiveMetric(label: "LOAD", value: d) }
                            NOOPLiveDivider()
                            NOOPLiveMetric(label: "HEART", value: s.bpm.map(String.init) ?? "–")
                        }
                        NOOPHeartRateZoneRail(zone: s.heartRateZone, compact: true)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                clock(s, tint: tint).font(.nuna(size: 13, weight: .bold, design: NunaType.design)).frame(maxWidth: 52)
            } compactTrailing: {
                Text(verbatim: s.isResting ? s.status : s.detail ?? s.status).font(.nuna(size: 12, weight: .bold)).lineLimit(1).frame(maxWidth: 70)
            } minimal: {
                ZStack {
                    Circle().stroke(tint, lineWidth: 2.5)
                    Image(systemName: "dumbbell.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                }
            }
            .keylineTint(tint)
        }
    }

    /// Green while working, amber through the rest: the sheet's and the bar's colour language.
    private func tint(_ state: LiftActivityAttributes.ContentState) -> Color {
        state.isResting ? NunaPalette.warning : NunaPalette.charge
    }

    private func lockScreen(_ state: LiftActivityAttributes.ContentState, program: String) -> some View {
        let tint = tint(state)
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                NOOPLiveGlyph(symbol: "dumbbell.fill", tint: tint, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: state.exercise).font(.nuna(size: 17, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                    Text(verbatim: state.detail.map { "\(state.status) · \($0)" } ?? state.status)
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                clock(state, tint: tint).font(.nuna(size: 34, weight: .bold, design: NunaType.design))
            }
            NOOPHeartRateZoneRail(zone: state.heartRateZone)
            Rectangle().fill(NunaPalette.hairline).frame(height: 1)
            HStack(spacing: 0) {
                NOOPLiveMetric(label: "SETS", value: state.progress)
                NOOPLiveDivider()
                NOOPLiveMetric(label: "HEART", value: state.bpm.map { "\($0) bpm" } ?? "–")
                if let d = state.distance {
                    NOOPLiveDivider()
                    NOOPLiveMetric(label: "DISTANCE", value: d)
                }
            }
            Text(verbatim: program).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    /// Counts DOWN through a rest (the number you act on) and UP through a set, both self-ticking.
    ///
    /// Both branches use `Text(timerInterval:)`, which is the API widgets are given for a clock that
    /// advances without the app pushing. `Text(date, style: .timer)` looks equivalent and is not: on
    /// the Lock Screen it rendered "25 minutes" — a rounded, prose duration — where a gym timer has
    /// to read 25:02. Verified in the simulator, which is the only reason it was caught.
    ///
    /// An overrun rest (`restEndsAt` already past) counts UP from when it was due, which is the
    /// honest reading: you are over, and by how much. A zero-length range would render nothing, so
    /// the end is pushed a day out — well beyond any session.
    private func clock(_ state: LiftActivityAttributes.ContentState, tint: Color) -> some View {
        let counter: some View = {
            if let ends = state.restEndsAt, ends > .now {
                return Text(timerInterval: .now...ends, countsDown: true)
            }
            let from = state.restEndsAt ?? state.stageStartedAt
            return Text(timerInterval: from...from.addingTimeInterval(86_400), countsDown: false)
        }()
        return counter
            .monospacedDigit()
            .foregroundStyle(tint)
    }
}
