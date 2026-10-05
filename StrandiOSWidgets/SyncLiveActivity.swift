import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for a strap history sync — the Lock Screen banner and the Dynamic Island.
///
/// Shows what the app's own Today sync control shows: that a sync is running, how many chunks it has
/// pulled, how long it has been going, and the strap's connect-time backlog when it reported one. No
/// progress bar, because there is no total to draw one against (see `SyncActivityAttributes`).
struct SyncLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SyncActivityAttributes.self) { context in
            // Lock Screen / banner presentation, in the grammar of the workout banner: a title row, the status, then the figures a sync has.
            let st = context.state
            let tint = glyphTint(st.phase)
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 10) {
                        Circle().fill(tint).frame(width: 10, height: 10)
                        Text(verbatim: context.attributes.title).font(.nuna(size: 15.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: glyphName(st.phase)).font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
                }
                Text(verbatim: st.status).font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                if let detail = st.detail {
                    Text(verbatim: detail).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
                }
                if isActive(st.phase) {
                    Rectangle().fill(NunaPalette.hairline).frame(height: 1).padding(.vertical, 14)
                    HStack(spacing: 0) {
                        NOOPLiveMetric(label: "CHUNKS", text: Text(verbatim: st.chunks > 0 ? "\(st.chunks)" : "···"), size: 30, alignment: .leading)
                        NOOPLiveMetric(label: "TIME", text: elapsed(since: st.startedAt), size: 30, alignment: .trailing)
                    }
                }
            }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 18, trailing: 18))
            .activityBackgroundTint(NunaPalette.card)
            .activitySystemActionForegroundColor(NunaPalette.textPrimary)
        } dynamicIsland: { context in
            // One line, deliberately: iOS shows the expanded layout for a few seconds whenever an activity starts and offers no way
            // to start compact, so the only lever on that flash is how tall it is. The backlog detail lives on the Lock Screen banner.
            let tint = glyphTint(context.state.phase)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        NOOPLiveRing(symbol: glyphName(context.state.phase), tint: tint, progress: nil)
                        Text(verbatim: context.state.status).font(.nuna(size: 14, weight: .heavy)).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if isActive(context.state.phase) {
                        elapsed(since: context.state.startedAt).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).monospacedDigit()
                    }
                }
            } compactLeading: {
                NOOPLiveRing(symbol: glyphName(context.state.phase), tint: tint, progress: nil)
            } compactTrailing: {
                // "…" while connecting and until the first chunk lands; then the chunk count, the only live number a sync has.
                // Never "0", so the island never claims progress the strap has not made.
                Text(verbatim: context.state.chunks > 0 ? "\(context.state.chunks)" : "…").font(.nuna(size: 12.5, weight: .heavy, design: NunaType.design)).monospacedDigit()
            } minimal: {
                Image(systemName: glyphName(context.state.phase)).foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

private func isActive(_ phase: SyncActivityAttributes.Phase) -> Bool {
    phase == .connecting || phase == .syncing
}

/// Counts up on its own from the run's start; no pushes needed to keep it moving.
private func elapsed(since start: Date) -> some View {
    Text(timerInterval: start...Date.distantFuture, countsDown: false)
}

private func glyphName(_ phase: SyncActivityAttributes.Phase) -> String {
    switch phase {
    case .connecting, .syncing: return "arrow.triangle.2.circlepath"
    case .done: return "checkmark.circle.fill"
    case .interrupted: return "exclamationmark.circle.fill"
    }
}

/// Green for both active phases (the connecting and syncing difference is the trailing "…" against the count, so the compact pill's
/// width stays steady), green again once done, and the alert colour when the strap went quiet.
private func glyphTint(_ phase: SyncActivityAttributes.Phase) -> Color {
    phase == .interrupted ? NunaPalette.alert : NunaPalette.charge
}
