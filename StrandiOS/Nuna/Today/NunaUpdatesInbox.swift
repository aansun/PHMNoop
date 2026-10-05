#if os(iOS)
import SwiftUI
import StrandDesign

/// The bell on Today (TodayNotifs.dc): what is new in the app and in the data, newest first, grouped by day. Same inbox as the
/// Default screen (`UpdateStore`): tapping a row marks it read and opens what it points at, a swiped-away Today card can be
/// restored, and nothing here is medical.
struct NunaUpdatesInbox: View {
    @EnvironmentObject private var updateStore: UpdateStore
    @EnvironmentObject private var router: NavRouter
    let onClose: () -> Void

    private var cal: Calendar { Calendar.current }

    private var groups: [(id: Int, title: LocalizedStringKey, items: [UpdateItem])] {
        let today = updateStore.sortedItems.filter { cal.isDateInToday($0.date) }
        let yesterday = updateStore.sortedItems.filter { cal.isDateInYesterday($0.date) }
        let earlier = updateStore.sortedItems.filter { !cal.isDateInToday($0.date) && !cal.isDateInYesterday($0.date) }
        return [(0, "Today", today), (1, "Yesterday", yesterday), (2, "Earlier", earlier)].filter { !$0.2.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                header
                if updateStore.items.isEmpty {
                    empty
                } else {
                    ForEach(groups, id: \.id) { g in
                        VStack(alignment: .leading, spacing: 10) {
                            nunaTrendsCap(g.title)
                            ForEach(g.items) { row($0) }
                        }
                    }
                    Button { onClose(); router.openNotificationSettings = true } label: {
                        Text("Notification settings").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 50).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                    Button { withAnimation { updateStore.clearAll() } } label: {
                        Text("Clear all").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity).frame(height: 40)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 18).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications").font(.nuna(size: NunaTypeSize.h1, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: subtitle).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 8)
            Button { withAnimation { updateStore.markAllRead() } } label: {
                Text("Mark all read").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 38)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(updateStore.unreadCount == 0).opacity(updateStore.unreadCount == 0 ? 0.4 : 1)
        }
    }

    private var subtitle: String {
        if updateStore.items.isEmpty { return String(localized: "What's new in the app and your data") }
        return updateStore.unreadCount == 0 ? String(localized: "All caught up") : String(localized: "\(updateStore.unreadCount) unread")
    }

    private var empty: some View {
        NunaCard {
            VStack(spacing: 10) {
                Image(systemName: "bell.slash").font(.nuna(size: 30, weight: .regular)).foregroundStyle(NunaPalette.textMuted)
                Text("You're all caught up.").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text("New release notes and fresh data will land here.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).multilineTextAlignment(.center)
                Button { onClose(); router.openNotificationSettings = true } label: {
                    Text("Notification settings").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 18).frame(height: 40).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).padding(.top, 6)
            }.frame(maxWidth: .infinity).padding(.vertical, 12)
        }
    }

    private func row(_ item: UpdateItem) -> some View {
        NunaCard(small: true, highlight: !item.read) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    NunaIconTile(symbol(item.kind))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: item.title).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        Text(verbatim: item.message).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(verbatim: time(item.date)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                        if !item.read { Circle().fill(NunaPalette.alert).frame(width: 8, height: 8) }
                    }
                }
                if item.kind == .dismissedCard {
                    Button { restore(item) } label: {
                        Label("Restore to Today", systemImage: "arrow.uturn.up").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 14).frame(height: 36).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { tap(item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func symbol(_ k: UpdateItem.Kind) -> String {
        switch k {
        case .dismissedCard: return "rectangle.on.rectangle"
        case .whatsNew: return "sparkles"
        case .reading: return "waveform.path.ecg"
        case .strapAlert: return "exclamationmark.triangle"
        case .newVersion: return "arrow.down.circle"
        }
    }

    private func time(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale
        if cal.isDateInToday(d) || cal.isDateInYesterday(d) { f.timeStyle = .short; f.dateStyle = .none } else { f.setLocalizedDateFormatFromTemplate("d MMM") }
        return f.string(from: d)
    }

    private func tap(_ item: UpdateItem) {
        withAnimation { updateStore.markRead(item.id) }
        guard let key = item.deepLink, let dest = NavRouter.Destination(deepLinkKey: key) else { return }
        onClose()
        router.requestedDestination = dest
    }

    private func restore(_ item: UpdateItem) {
        if let payload = item.restorePayload { UserDefaults.standard.set(false, forKey: TodayCardDismissal.flagKey(payload)) }
        updateStore.requestRestore(item)
        onClose()
    }
}
#endif
