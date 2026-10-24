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
            // Lock Screen presentation: glass and small. The background is the system's own material (no solid tint), so the wallpaper shows through and the card
            // follows light and dark by itself. One row carries all of it: the icon, the status, and the two figures of a sync at the right; the backlog, when the
            // strap reported one, is a single line under it.
            let st = context.state
            let tint = glyphTint(st.phase)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: glyphName(st.phase)).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                        .frame(width: 30, height: 30).background(tint.opacity(0.2), in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: context.attributes.title).font(.nuna(size: 10.5, weight: .heavy)).tracking(0.9).textCase(.uppercase)
                            .foregroundStyle(.secondary).lineLimit(1)
                        Text(verbatim: st.status).font(.nuna(size: 17, weight: .bold, design: NunaType.design))
                            .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 6)
                    if isActive(st.phase) {
                        HStack(spacing: 14) {
                            figure("CHUNKS", Text(verbatim: st.chunks > 0 ? "\(st.chunks)" : "···"), width: 58)
                            figure("TIME", elapsed(since: st.startedAt), width: 50)
                        }
                    }
                }
                if let detail = st.detail {
                    Text(verbatim: detail).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            .activityBackgroundTint(nil)
            .activitySystemActionForegroundColor(Color.primary)
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

/// One figure: the label small above, the value below, in a fixed width so a ticking clock does not push the row about.
private func figure<V: View>(_ label: LocalizedStringKey, _ value: V, width: CGFloat) -> some View {
    VStack(alignment: .trailing, spacing: 0) {
        Text(label).font(.nuna(size: 9.5, weight: .heavy)).tracking(0.6).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        value.font(.nuna(size: 19, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(.primary)
            .lineLimit(1).minimumScaleFactor(0.7)
    }
    .frame(width: width, alignment: .trailing)
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
