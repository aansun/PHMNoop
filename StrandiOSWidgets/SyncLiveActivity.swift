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
            // Lock Screen presentation: glass. The background is left to the system's own material (no solid tint), so the wallpaper shows through and the
            // card follows light and dark by itself; every colour here is a system one for the same reason. An icon and the status lead, then the two figures of
            // a sync in tiles of their own.
            let st = context.state
            let tint = glyphTint(st.phase)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(tint.opacity(0.22))
                        Image(systemName: glyphName(st.phase)).font(.system(size: 17, weight: .bold)).foregroundStyle(tint)
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: context.attributes.title).font(.nuna(size: 11.5, weight: .heavy)).tracking(1).textCase(.uppercase)
                            .foregroundStyle(.secondary).lineLimit(1)
                        Text(verbatim: st.status).font(.nuna(size: 22, weight: .bold, design: NunaType.design))
                            .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }
                if let detail = st.detail {
                    Text(verbatim: detail).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(.secondary).lineLimit(2)
                }
                if isActive(st.phase) {
                    HStack(spacing: 10) {
                        glassTile("CHUNKS", Text(verbatim: st.chunks > 0 ? "\(st.chunks)" : "···"))
                        glassTile("TIME", elapsed(since: st.startedAt))
                    }
                }
            }
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
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

/// One figure on a soft glass tile: the label small above, the value large below.
private func glassTile<V: View>(_ label: LocalizedStringKey, _ value: V) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(0.9).foregroundStyle(.secondary)
        value.font(.nuna(size: 26, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(.primary)
            .lineLimit(1).minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14).padding(.vertical, 10)
    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
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
