#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - The menu, as WHOOP draws it

/// What a "…" or a drop-down does here, in the way of the End and save / Discard choice: a short sheet from the bottom with one plain row for each thing it can
/// do, instead of the small system popover. It takes the place of SwiftUI's `Menu`, with the same shape of call:
///
///     NunaMenu {
///         NunaMenuItem("Share routine", icon: "square.and.arrow.up") { share() }
///         NunaMenuItem("Delete", icon: "trash", role: .destructive) { askToDelete() }
///     } label: { Image(systemName: "ellipsis") }
///
/// A row does its work once the sheet has gone, as the End flow does, so a row can push a page, raise another sheet or ask a question without the two screens
/// fighting over the window. A row can open a deeper list (`NunaMenuSub`), and a choice among several (what `Picker` was in a menu) is a column of rows with
/// the current one marked (`selected:`).
struct NunaMenu<Label: View, Content: View>: View {
    private let content: Content
    private let label: Label
    @StateObject private var host = NunaMenuHost()
    @State private var open = false

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content(); self.label = label()
    }

    var body: some View {
        Button { host.reset(); open = true } label: { label }
            .buttonStyle(.plain)
            .sheet(isPresented: $open, onDismiss: { host.finish() }) {
                NunaMenuSheet(root: AnyView(content), host: host, close: { open = false })
            }
    }
}

/// What the rows of the open sheet need to know: the lists opened inside it, and the work chosen, which runs when the sheet is gone.
final class NunaMenuHost: ObservableObject {
    struct Level { let title: String; let content: AnyView }
    @Published var levels: [Level] = []
    var pending: (() -> Void)?
    var close: () -> Void = {}

    func reset() { levels = []; pending = nil }
    func run(_ action: @escaping () -> Void) { pending = action; close() }
    func finish() { let a = pending; pending = nil; levels = []; a?() }
}

private struct NunaMenuSheet: View {
    let root: AnyView
    @ObservedObject var host: NunaMenuHost
    let close: () -> Void
    @State private var height: CGFloat = 320

    private var maxHeight: CGFloat { UIScreen.main.bounds.height * 0.78 }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let level = host.levels.last {
                    NunaMenuRow(title: Text(verbatim: level.title), icon: "chevron.left", trailing: nil, tint: NunaPalette.textSecondary) { _ in
                        withAnimation(.easeOut(duration: 0.18)) { _ = host.levels.popLast() }
                    }
                    level.content
                } else {
                    root
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 34).padding(.bottom, 28)
            .background(GeometryReader { Color.clear.preference(key: NunaMenuHeightKey.self, value: $0.size.height) })
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .onPreferenceChange(NunaMenuHeightKey.self) { height = min($0, maxHeight) }
        .environmentObject(host)
        .onAppear { host.close = close }
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
        .nunaSheetChrome(detents: [.height(height)])
    }
}

private struct NunaMenuHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The look of one row: the picture, the words in capitals, and a tick or an arrow at the end.
private struct NunaMenuRow: View {
    let title: Text
    let icon: String?
    /// "checkmark" for the choice in force, "chevron.right" for a deeper list.
    let trailing: String?
    let tint: Color
    let action: (NunaMenuHost) -> Void
    @EnvironmentObject private var host: NunaMenuHost
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button { action(host) } label: {
            HStack(spacing: 18) {
                if let icon { Image(systemName: icon).font(.nuna(size: 20, weight: .regular)).foregroundStyle(tint).frame(width: 34) }
                title.font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(tint)
                    .multilineTextAlignment(.leading).lineLimit(2)
                Spacer(minLength: 8)
                if let trailing { Image(systemName: trailing).font(.nuna(size: 14, weight: .bold)).foregroundStyle(tint) }
            }
            .padding(.horizontal, 22).frame(minHeight: 60)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(enabled ? 1 : 0.4)
    }
}

/// One thing the menu does. `selected` marks the choice in force in a column of choices.
struct NunaMenuItem: View {
    private let title: Text
    private let icon: String?
    private let role: ButtonRole?
    private let selected: Bool
    private let action: () -> Void

    init(_ title: LocalizedStringKey, icon: String? = nil, role: ButtonRole? = nil, selected: Bool = false, action: @escaping () -> Void) {
        self.title = Text(title); self.icon = icon; self.role = role; self.selected = selected; self.action = action
    }

    /// For a name or a figure that is not a translated phrase.
    init(verbatim title: String, icon: String? = nil, role: ButtonRole? = nil, selected: Bool = false, action: @escaping () -> Void) {
        self.title = Text(verbatim: title); self.icon = icon; self.role = role; self.selected = selected; self.action = action
    }

    var body: some View {
        NunaMenuRow(title: title, icon: icon, trailing: selected ? "checkmark" : nil, tint: role == .destructive ? NunaPalette.alertText : NunaPalette.textPrimary) { host in
            host.run(action)
        }
    }
}

/// A row that opens a deeper list inside the same sheet, with a row at the top to go back.
struct NunaMenuSub<Content: View>: View {
    private let title: String
    private let icon: String?
    private let content: Content
    @EnvironmentObject private var host: NunaMenuHost

    init(_ title: LocalizedStringResource, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = String(localized: title); self.icon = icon; self.content = content()
    }

    init(verbatim title: String, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.content = content()
    }

    var body: some View {
        NunaMenuRow(title: Text(verbatim: title), icon: icon, trailing: "chevron.right", tint: NunaPalette.textPrimary) { host in
            withAnimation(.easeOut(duration: 0.18)) { host.levels.append(.init(title: title, content: AnyView(content))) }
        }
    }
}

/// A little air between two groups of rows, where a menu had a divider.
struct NunaMenuGap: View {
    var body: some View { Color.clear.frame(height: 4) }
}
// MARK: - The same menu from a long press

extension View {
    /// What a long press on this view offers (what `.contextMenu` did), as the same sheet from the bottom.
    func nunaLongPressMenu<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        modifier(NunaLongPressMenu(items: content))
    }
}

private struct NunaLongPressMenu<Items: View>: ViewModifier {
    let items: () -> Items
    @StateObject private var host = NunaMenuHost()
    @State private var open = false

    func body(content: Content) -> some View {
        content
            // High priority, so a press that lasts wins over the tap of a button underneath it, and a short one still reaches the button.
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                host.reset(); open = true
            })
            .sheet(isPresented: $open, onDismiss: { host.finish() }) {
                NunaMenuSheet(root: AnyView(items()), host: host, close: { open = false })
            }
    }
}
#endif
