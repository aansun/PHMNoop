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
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(context.state.bpm.map { "\($0)" } ?? "–")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text("bpm")
                                .font(.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        Text("HEART RATE")
                            .font(.caption2)
                            .tracking(0.8)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        if let startedAt = context.state.activityStartedAt {
                            Text(timerInterval: startedAt...startedAt.addingTimeInterval(86_400),
                                 countsDown: false)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                        Text(context.state.activityName ?? context.attributes.title)
                            .font(.caption2)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.trailing)
                    }
                }
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
                    Label("\(context.state.bpm.map(String.init) ?? "–")", systemImage: "heart.fill")
                        .foregroundStyle(StrandPalette.statusCritical)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // Charge + Effort (#446) — one more stat alongside the leading live HR.
                    HStack(spacing: 10) {
                        if let r = context.state.recovery {
                            statColumn(label: "Charge", value: "\(r)%")
                        }
                        if let e = context.state.effort {
                            statColumn(label: "Effort", value: "\(e)")
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.activityName ?? context.attributes.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(StrandPalette.statusCritical)
            } compactTrailing: {
                Text("\(context.state.bpm.map(String.init) ?? "–")")
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(StrandPalette.statusCritical)
            }
        }
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
