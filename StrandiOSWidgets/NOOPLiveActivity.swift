import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for an active live-HR session — shown on the Lock Screen and in the Dynamic Island.
struct NOOPLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NOOPActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            VStack(spacing: 10) {
                ZStack {
                    HStack(alignment: .center, spacing: 0) {
                        if let startedAt = context.state.activityStartedAt {
                            Text(timerInterval: startedAt...startedAt.addingTimeInterval(86_400),
                                 countsDown: false)
                                .font(.system(size: 35, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(StrandPalette.textPrimary)
                        } else {
                            Text("—")
                                .font(.system(size: 35, weight: .bold, design: .rounded))
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                        Spacer(minLength: 12)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(StrandPalette.statusCritical)
                            Text(context.state.bpm.map { "\($0)" } ?? "–")
                                .font(.system(size: 35, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text("bpm")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    NOOPBatteryRing(percent: context.state.batteryPct)
                }
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                Rectangle()
                    .fill(StrandPalette.hairline)
                    .frame(height: 1)
                NOOPHeartRateZoneRail(zone: context.state.heartRateZone)
                HStack(spacing: 0) {
                    NOOPLiveMetric(label: "AVG", value: context.state.averageBPM.map(String.init) ?? "—")
                    Rectangle()
                        .fill(StrandPalette.hairline)
                        .frame(width: 1, height: 34)
                        .padding(.horizontal, 12)
                    NOOPLiveMetric(label: "PEAK", value: context.state.peakBPM.map(String.init) ?? "—")
                    Rectangle()
                        .fill(StrandPalette.hairline)
                        .frame(width: 1, height: 34)
                        .padding(.horizontal, 12)
                    NOOPLiveMetric(label: "EFFORT", value: context.state.effort.map(String.init) ?? "—")
                }
                if context.state.distance != nil || context.state.pace != nil {
                    Rectangle()
                        .fill(StrandPalette.hairline)
                        .frame(height: 1)
                    HStack(spacing: 0) {
                        NOOPLiveMetric(label: "DISTANCE", value: context.state.distance ?? "—")
                        Rectangle()
                            .fill(StrandPalette.hairline)
                            .frame(width: 1, height: 34)
                            .padding(.horizontal, 12)
                        NOOPLiveMetric(label: "PACE", value: context.state.pace ?? "—")
                    }
                }
            }
            .padding()
            .activityBackgroundTint(StrandPalette.surfaceBase)
            .activitySystemActionForegroundColor(StrandPalette.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let startedAt = context.state.activityStartedAt {
                        Text(timerInterval: startedAt...startedAt.addingTimeInterval(86_400),
                             countsDown: false)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(StrandPalette.textPrimary)
                    } else {
                        Text("—")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    NOOPBatteryRing(percent: context.state.batteryPct, size: 36)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(StrandPalette.statusCritical)
                        Text(context.state.bpm.map(String.init) ?? "–")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("bpm")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        NOOPHeartRateZoneRail(zone: context.state.heartRateZone)
                        HStack(spacing: 0) {
                            NOOPLiveMetric(label: "AVG", value: context.state.averageBPM.map(String.init) ?? "—")
                            Rectangle()
                                .fill(StrandPalette.hairline)
                                .frame(width: 1, height: 24)
                                .padding(.horizontal, 8)
                            NOOPLiveMetric(label: "PEAK", value: context.state.peakBPM.map(String.init) ?? "—")
                            Rectangle()
                                .fill(StrandPalette.hairline)
                                .frame(width: 1, height: 24)
                                .padding(.horizontal, 8)
                            NOOPLiveMetric(label: "EFFORT", value: context.state.effort.map(String.init) ?? "—")
                        }
                    }
                }
            } compactLeading: {
                if let startedAt = context.state.activityStartedAt {
                    Text(timerInterval: startedAt...startedAt.addingTimeInterval(86_400), countsDown: false)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("—")
                }
            } compactTrailing: {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(StrandPalette.statusCritical)
                    Text("\(context.state.bpm.map(String.init) ?? "–")")
                        .monospacedDigit()
                }
            } minimal: {
                NOOPBatteryRing(percent: context.state.batteryPct, size: 24)
            }
        }
    }
}

/// Compact strap-battery ring used in the open centre of the Lock Screen banner.
private struct NOOPBatteryRing: View {
    let percent: Int?
    var size: CGFloat = 48

    private var progress: CGFloat {
        guard let percent else { return 0 }
        return CGFloat(min(max(percent, 0), 100)) / 100
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(StrandPalette.hairline, lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    StrandPalette.chargeColor,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(percent.map { "\($0)%" } ?? "—")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(percent.map { "Battery \($0) percent" } ?? "Battery unavailable")
    }
}

/// Lock-Screen banner stat column (label over value). File-scope because the `ActivityConfiguration`
/// content closure isn't a method of `NOOPLiveActivity`.
///
/// #759 - the label and value are CENTRE-aligned so each value sits directly under its own label. The
/// old `.trailing` alignment right-pinned both to the column's edge: when the value was narrower than
/// the label (e.g. "12" under "Effort") it drifted to the label's right edge instead of under it, which
/// read as "the number doesn't line up with its label". `fixedSize` stops either line truncating so the
/// pairing is never clipped at narrow widths.
@ViewBuilder
private func bannerStat(label: String, value: String) -> some View {
    VStack(alignment: .center, spacing: 2) {
        Text(label).font(.caption2).foregroundStyle(StrandPalette.textSecondary)
        Text(value).font(.headline).foregroundStyle(StrandPalette.textPrimary)
    }
    .multilineTextAlignment(.center)
    .fixedSize()
}


/// Dynamic Island expanded-region stat column (label over value). File-scope for the same reason as
/// `bannerStat`. #759 - centre-aligned + `fixedSize` for the same value-under-its-label fix as the banner.
@ViewBuilder
private func statColumn(label: String, value: String) -> some View {
    VStack(alignment: .center, spacing: 1) {
        Text(label).font(.caption2).foregroundStyle(.secondary)
        Text(value).font(.headline)
    }
    .multilineTextAlignment(.center)
    .fixedSize()
}
