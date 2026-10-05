import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for an active workout or live-HR session: the Lock Screen banner and the Dynamic Island, in the Nuna look.
///
/// A GPS sport leads with distance, time and pace; a sport without GPS with time, average and peak heart rate; plain live heart rate
/// (no workout) shows the heart rate and Effort. The symbol and the colours follow the sport and the heart-rate zone, so the minimal
/// Island is one ring in the zone's colour.
struct NOOPLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NOOPActivityAttributes.self) { context in
            LockScreen(state: context.state, title: context.attributes.title)
                .activityBackgroundTint(NunaPalette.card)
                .activitySystemActionForegroundColor(NunaPalette.textPrimary)
        } dynamicIsland: { context in
            let s = context.state
            let tint = NOOPLive.tint(zone: s.heartRateZone)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        NOOPLiveGlyph(symbol: symbol(s), tint: tint, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: s.activityName ?? context.attributes.title).font(.nuna(size: 14, weight: .heavy)).lineLimit(1)
                            if let e = s.effort { Text("Effort \(e)").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Image(systemName: "heart.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                        Text(verbatim: s.bpm.map(String.init) ?? "–").font(.nuna(size: 26, weight: .bold, design: NunaType.design)).monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        Metrics(state: s)
                        NOOPHeartRateZoneRail(zone: s.heartRateZone, compact: true)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                clock(s).font(.nuna(size: 13, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(tint).frame(maxWidth: 52)
            } compactTrailing: {
                if let pace = s.pace {
                    Text(verbatim: pace).font(.nuna(size: 13, weight: .bold, design: NunaType.design)).monospacedDigit().lineLimit(1)
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                        Text(verbatim: s.bpm.map(String.init) ?? "–").font(.nuna(size: 13, weight: .bold, design: NunaType.design)).monospacedDigit()
                    }
                }
            } minimal: {
                ZStack {
                    Circle().stroke(tint, lineWidth: 2.5)
                    Image(systemName: symbol(s)).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                }
            }
            .keylineTint(tint)
        }
    }
}

private func symbol(_ s: NOOPActivityAttributes.ContentState) -> String {
    s.activityName.map(ActivitySport.symbol(for:)) ?? "heart.fill"
}

@ViewBuilder private func clock(_ s: NOOPActivityAttributes.ContentState) -> some View {
    if let start = s.activityStartedAt {
        Text(timerInterval: start...start.addingTimeInterval(86_400), countsDown: false)
    } else {
        Text(verbatim: "–")
    }
}

private struct LockScreen: View {
    let state: NOOPActivityAttributes.ContentState
    let title: String

    var body: some View {
        let tint = NOOPLive.tint(zone: state.heartRateZone)
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                NOOPLiveGlyph(symbol: symbol(state), tint: tint, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: state.activityName ?? title).font(.nuna(size: 18, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                    HStack(spacing: 6) {
                        if let e = state.effort { NOOPLiveChip(text: Text("Effort \(e)"), color: NunaPalette.effortText) }
                        if let z = state.heartRateZone { NOOPLiveChip(text: Text("Zone \(z)"), color: tint) }
                    }
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: state.bpm.map(String.init) ?? "–").font(.nuna(size: 38, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
                    Text("bpm").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            NOOPHeartRateZoneRail(zone: state.heartRateZone)
            Rectangle().fill(NunaPalette.hairline).frame(height: 1)
            Metrics(state: state)
        }
        .padding(16)
    }
}

/// Three figures. GPS: distance, time, pace. Without GPS: time, average and peak heart rate. Live heart rate alone: time, average, battery.
private struct Metrics: View {
    let state: NOOPActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 0) {
            if state.distance != nil || state.pace != nil {
                NOOPLiveMetric(label: "DISTANCE", value: state.distance ?? "–")
                NOOPLiveDivider()
                timeMetric
                NOOPLiveDivider()
                NOOPLiveMetric(label: "PACE", value: state.pace ?? "–")
            } else {
                timeMetric
                NOOPLiveDivider()
                NOOPLiveMetric(label: "AVG", value: state.averageBPM.map(String.init) ?? "–")
                NOOPLiveDivider()
                if state.activityName != nil {
                    NOOPLiveMetric(label: "PEAK", value: state.peakBPM.map(String.init) ?? "–")
                } else {
                    VStack(spacing: 2) {
                        Text("Battery").font(.nuna(size: 10.5, weight: .heavy)).tracking(0.5).foregroundStyle(NunaPalette.textSecondary)
                        NOOPBatteryRing(percent: state.batteryPct, size: 26)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var timeMetric: some View {
        VStack(alignment: .center, spacing: 2) {
            Text("TIME").font(.nuna(size: 10.5, weight: .heavy)).tracking(0.5).foregroundStyle(NunaPalette.textSecondary)
            clock(state).font(.nuna(size: 19, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
                .multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.7).frame(width: 78, alignment: .center)
        }
        .frame(maxWidth: .infinity)
    }
}
