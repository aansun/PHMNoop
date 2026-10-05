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
            // Lock Screen / banner presentation.
            HStack(spacing: 14) {
                NOOPLiveGlyph(symbol: glyphName(context.state.phase), tint: glyphTint(context.state.phase), size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: context.attributes.title).font(.nuna(size: 11.5, weight: .heavy)).tracking(0.5).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    Text(verbatim: context.state.status).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    if let detail = context.state.detail {
                        Text(verbatim: detail).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                Spacer()
                if isActive(context.state.phase) {
                    VStack(alignment: .trailing, spacing: 2) {
                        elapsed(since: context.state.startedAt).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).monospacedDigit()
                            .foregroundStyle(NunaPalette.textPrimary)
                        if context.state.chunks > 0 {
                            Text("Chunks \(context.state.chunks)").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(NunaPalette.card)
            .activitySystemActionForegroundColor(NunaPalette.textPrimary)
        } dynamicIsland: { context in
            // One line, deliberately: iOS shows the expanded layout for a few seconds whenever an activity starts and offers no way
            // to start compact, so the only lever on that flash is how tall it is. The backlog detail lives on the Lock Screen banner.
            let tint = glyphTint(context.state.phase)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        NOOPLiveGlyph(symbol: glyphName(context.state.phase), tint: tint, size: 28)
                        Text(verbatim: context.state.status).font(.nuna(size: 14, weight: .heavy)).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if isActive(context.state.phase) {
                        elapsed(since: context.state.startedAt).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: glyphName(context.state.phase)).foregroundStyle(tint)
            } compactTrailing: {
                // "…" while connecting and until the first chunk lands; then the chunk count, the only live number a sync has.
                // Never "0", so the island never claims progress the strap has not made.
                Text(verbatim: context.state.chunks > 0 ? "\(context.state.chunks)" : "…").font(.nuna(size: 13, weight: .bold)).monospacedDigit()
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
