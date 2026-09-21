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
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(StrandPalette.statusCritical)
                    Text(context.attributes.title)
                        .font(.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer(minLength: 8)
                    Text(context.state.bpm.map { "\($0)" } ?? "–")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("bpm")
                        .font(.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Rectangle()
                    .fill(StrandPalette.hairline)
                    .frame(height: 1)
                NOOPHeartRateZoneRail(zone: context.state.heartRateZone)
                HStack(spacing: 0) {
                    NOOPLiveMetric(label: "DISTANCE", value: context.state.distance ?? "—")
                    Rectangle()
                        .fill(StrandPalette.hairline)
                        .frame(width: 1, height: 34)
                        .padding(.horizontal, 12)
                    NOOPLiveMetric(label: "SPEED", value: context.state.speed ?? "—")
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
                    Text(context.attributes.title).font(.caption).foregroundStyle(.secondary)
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
