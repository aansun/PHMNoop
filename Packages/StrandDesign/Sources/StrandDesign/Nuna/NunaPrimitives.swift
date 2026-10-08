import SwiftUI

// MARK: - Nuna primitives
//
// Building blocks shared by every Nuna screen. See docs/nuna/COMPONENTS.md for the mockup class each one
// mirrors. Platform-neutral SwiftUI only (StrandDesign also builds for macOS and watchOS).

// MARK: Buttons

/// Pill button. `primary` is white on black, `ghost` is a translucent pill, `destructive` is the alert tint.
public struct NunaButtonStyle: ButtonStyle {
    public enum Kind { case primary, ghost, destructive }
    private let kind: Kind
    private let height: CGFloat
    private let fullWidth: Bool

    public init(_ kind: Kind = .primary, height: CGFloat = 48, fullWidth: Bool = false) {
        self.kind = kind; self.height = height; self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nuna(size: 15, weight: .heavy))
            .foregroundStyle(foreground)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(background, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return NunaPalette.onAccent
        case .ghost: return NunaPalette.textPrimary
        case .destructive: return NunaPalette.alertText
        }
    }
    private var background: Color {
        switch kind {
        case .primary: return NunaPalette.accent
        case .ghost: return NunaPalette.glassStrong
        case .destructive: return NunaPalette.alert.opacity(0.14)
        }
    }
    private var border: Color {
        switch kind {
        case .primary: return .clear
        case .ghost: return NunaPalette.ink.opacity(0.12)
        case .destructive: return NunaPalette.alert.opacity(0.45)
        }
    }
}

public extension ButtonStyle where Self == NunaButtonStyle {
    static func nuna(_ kind: NunaButtonStyle.Kind = .primary, height: CGFloat = 48, fullWidth: Bool = false) -> NunaButtonStyle {
        NunaButtonStyle(kind, height: height, fullWidth: fullWidth)
    }
}

/// 44 pt circular icon button (header actions).
public struct NunaIconButton: View {
    private let systemImage: String
    private let label: LocalizedStringKey
    private let filled: Bool
    private let action: () -> Void

    public init(_ systemImage: String, label: LocalizedStringKey, filled: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage; self.label = label; self.filled = filled; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            NunaGlyph(systemImage, pointSize: 16)
                .foregroundStyle(filled ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .frame(width: 44, height: 44)
                .background(filled ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: filled ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The floating white "+" that opens Quick actions on Today.
public struct NunaFAB: View {
    private let label: LocalizedStringKey
    private let action: () -> Void
    public init(label: LocalizedStringKey = "Quick actions", action: @escaping () -> Void) {
        self.label = label; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.nuna(size: 19, weight: .bold))
                .foregroundStyle(NunaPalette.onAccent)
                .frame(width: 44, height: 44)
                .background(NunaPalette.accent.opacity(0.82), in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                .shadow(color: NunaPalette.field, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: Header and sections

/// Screen header: optional back control, title, optional trailing content.
public struct NunaHeader<Trailing: View>: View {
    private let title: LocalizedStringKey
    private let onBack: (() -> Void)?
    private let trailing: Trailing

    public init(_ title: LocalizedStringKey, onBack: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.onBack = onBack; self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let onBack {
                NunaIconButton("chevron.left", label: "Back", action: onBack)
            }
            Text(title)
                .font(.nuna(size: onBack == nil ? NunaTypeSize.h1 : 24, weight: .heavy))
                .foregroundStyle(NunaPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
    }
}

public extension NunaHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, onBack: (() -> Void)? = nil) {
        self.init(title, onBack: onBack) { EmptyView() }
    }
}

/// Small uppercase caption above a group of rows.
public struct NunaSectionHeader: View {
    private let title: LocalizedStringKey
    public init(_ title: LocalizedStringKey) { self.title = title }
    public var body: some View {
        Text(title)
            .font(.nuna(size: NunaTypeSize.caption, weight: .heavy))
            .tracking(1.15)
            .textCase(.uppercase)
            .foregroundStyle(NunaPalette.textSecondary)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: Rows

/// 40 pt rounded icon tile used at the leading edge of rows.
public struct NunaIconTile: View {
    private let systemImage: String
    private let tint: Color?
    public init(_ systemImage: String, tint: Color? = nil) {
        self.systemImage = systemImage; self.tint = tint
    }
    public var body: some View {
        // A bare, quiet icon: no tile behind it, so the title carries the row.
        NunaGlyph(systemImage, pointSize: 18)
            .foregroundStyle(NunaPalette.textSecondary)
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
    }
}

/// A list row: icon tile, title, optional subtitle, trailing content. Rows are meant to sit inside a
/// `NunaCard` and are separated by `NunaDivider`.
public struct NunaListRow<Trailing: View>: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let systemImage: String?
    private let tint: Color?
    private let showsChevron: Bool
    private let trailing: Trailing

    public init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, systemImage: String? = nil,
                tint: Color? = nil, showsChevron: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.systemImage = systemImage
        self.tint = tint; self.showsChevron = showsChevron; self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 14) {
            if let systemImage { NunaIconTile(systemImage, tint: tint) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.nuna(size: 14.5, weight: .heavy))
                    .tracking(nunaTrackingLabel)
                    .foregroundStyle(NunaPalette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.nuna(size: 12.5, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                        .textCase(nil)
                }
            }
            Spacer(minLength: 8)
            trailing
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.nuna(size: 13, weight: .bold))
                    .foregroundStyle(NunaPalette.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

public extension NunaListRow {
    /// A row with an explanation the screen does not need to show: the line is accepted so the wording stays with the row, and left
    /// out of the picture. Text under a title is kept for state (On, Off, a time, a count) and for the few warnings that matter; use
    /// `subtitle:` for those.
    init(_ title: LocalizedStringKey, description: LocalizedStringKey, systemImage: String? = nil,
         tint: Color? = nil, showsChevron: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, subtitle: nil, systemImage: systemImage, tint: tint, showsChevron: showsChevron, trailing: trailing)
    }
}

public extension NunaListRow where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, description: LocalizedStringKey, systemImage: String? = nil,
         tint: Color? = nil, showsChevron: Bool = false) {
        self.init(title, subtitle: nil, systemImage: systemImage, tint: tint, showsChevron: showsChevron) { EmptyView() }
    }

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, systemImage: String? = nil,
         tint: Color? = nil, showsChevron: Bool = false) {
        self.init(title, subtitle: subtitle, systemImage: systemImage, tint: tint, showsChevron: showsChevron) { EmptyView() }
    }
}

/// Hairline between rows inside a card.
public struct NunaDivider: View {
    public init() {}
    public var body: some View {
        Rectangle().fill(NunaPalette.hairline).frame(height: 1)
    }
}

/// Row with a trailing switch. Green when on.
public struct NunaToggleRow: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let systemImage: String?
    private let tint: Color?
    @Binding private var isOn: Bool

    public init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, systemImage: String? = nil,
                tint: Color? = nil, isOn: Binding<Bool>) {
        self.title = title; self.subtitle = subtitle; self.systemImage = systemImage
        self.tint = tint; self._isOn = isOn
    }

    public var body: some View {
        NunaListRow(title, subtitle: subtitle, systemImage: systemImage, tint: tint) {
            Toggle("", isOn: $isOn).labelsHidden().tint(NunaPalette.charge)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Segmented control

/// Capsule segmented control with a lighter selected segment.
public struct NunaSegmented<Value: Hashable>: View {
    private let options: [(value: Value, title: LocalizedStringKey)]
    @Binding private var selection: Value

    public init(_ options: [(value: Value, title: LocalizedStringKey)], selection: Binding<Value>) {
        self.options = options; self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.nuna(size: 13, weight: .bold))
                        .foregroundStyle(selected ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(selected ? NunaPalette.glassStrong : .clear, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(NunaPalette.glass, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
    }
}

// MARK: Bare icon

/// The glyph of a settings or edit control: just the symbol, no card behind it, with a target around it that is still easy to hit.
public struct NunaBareIcon: View {
    private let symbol: String
    private let tint: Color
    private let target: CGFloat
    public init(_ symbol: String, tint: Color = NunaPalette.textPrimary, target: CGFloat = 44) {
        self.symbol = symbol; self.tint = tint; self.target = target
    }
    public var body: some View {
        Image(systemName: symbol).font(.nuna(size: 17, weight: .bold)).foregroundStyle(tint)
            .frame(width: target, height: target).contentShape(Rectangle())
    }
}

// MARK: Page tabs

/// The tabs at the top of a page (Health: All, Vital, Body, Sleep): plain capital labels, the chosen one in the main text colour with a
/// short underline that slides to the next, the others dimmed. Use it to switch what the page shows; keep `NunaSegmented` for choosing
/// a value (a range, a unit).
public struct NunaPageTabs<Value: Hashable>: View {
    private let options: [(value: Value, title: LocalizedStringKey)]
    @Binding private var selection: Value
    @Namespace private var underline

    public init(_ options: [(value: Value, title: LocalizedStringKey)], selection: Binding<Value>) {
        self.options = options; self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let selected = option.value == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { selection = option.value }
                } label: {
                    VStack(spacing: 7) {
                        Text(option.title)
                            .font(.nuna(size: 12.5, weight: .heavy)).tracking(0.9).textCase(.uppercase)
                            .foregroundStyle(selected ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        ZStack {
                            Color.clear.frame(height: 2)
                            if selected {
                                Capsule().fill(NunaPalette.textPrimary).frame(height: 2).matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: Dashed add card

/// "Add a card / Add WHOOP" affordance.
public struct NunaAddCard: View {
    private let title: LocalizedStringKey
    private let action: () -> Void
    public init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.nuna(size: 17, weight: .bold))
                Text(title).font(.nuna(size: 15, weight: .heavy))
            }
            .foregroundStyle(NunaPalette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous)
                .strokeBorder(NunaPalette.ink.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Tab bar

public struct NunaTabItem: Identifiable, Hashable {
    public let id: Int
    /// The tab's name, always in English, so the tabs keep one width and the icons one size in every language.
    public let title: String
    public let systemImage: String
    public let usesAssetImage: Bool
    public init(id: Int, title: String, systemImage: String, usesAssetImage: Bool = false) {
        self.id = id; self.title = title; self.systemImage = systemImage; self.usesAssetImage = usesAssetImage
    }
    public static func == (l: NunaTabItem, r: NunaTabItem) -> Bool { l.id == r.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

/// The preferences behind the floating bar. Shared by the bar and by Appearance, which edits them.
public enum NunaTabBarPrefs {
    /// Hide the bar while the page is scrolled up, show it again on the way back. The same preference NOOP's own Settings use.
    public static let autoHideKey = "noop.bottomBarAutoHide"
    /// Frosted glass behind the bar (on) or a solid surface (off).
    public static let glassKey = "nuna.tabBar.glass"
    /// How see-through the bar is: 0 solid, 100 clear.
    public static let transparencyKey = "nuna.tabBar.transparency"
    public static let defaultTransparency = 45
}

/// Floating tab bar: a rounded glass bar for the main tabs and, apart from it on the right, one round button for the trailing tab (Anya).
/// Hosts place it with `.safeAreaInset(edge: .bottom)`.
public struct NunaTabBar: View {
    private let items: [NunaTabItem]
    private let trailing: NunaTabItem?
    @Binding private var selection: Int
    private let onReselect: (Int) -> Void
    @AppStorage(NunaTabBarPrefs.glassKey) private var glass = true
    @AppStorage(NunaTabBarPrefs.transparencyKey) private var transparency = NunaTabBarPrefs.defaultTransparency

    public init(items: [NunaTabItem], trailing: NunaTabItem? = nil, selection: Binding<Int>, onReselect: @escaping (Int) -> Void = { _ in }) {
        self.items = items; self.trailing = trailing; self._selection = selection; self.onReselect = onReselect
    }

    private let radius: CGFloat = 28

    public var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) { ForEach(items) { tab($0) } }
                .padding(.horizontal, 6)
                .frame(height: 64)
                .background { surface(cornerRadius: radius) }
            if let trailing {
                Button {
                    if selection == trailing.id { onReselect(trailing.id) } else { selection = trailing.id }
                } label: {
                    glyph(trailing, size: 30)
                        .foregroundStyle(selection == trailing.id ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                        .frame(width: 64, height: 64)
                        .background { surface(cornerRadius: radius) }
                        .overlay {
                            if selection == trailing.id {
                                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(NunaPalette.textPrimary.opacity(0.55), lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: trailing.title))
                .accessibilityAddTraits(selection == trailing.id ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    /// Frosted glass over whatever is behind, tinted with the card colour; how much of that tint shows is the transparency setting.
    @ViewBuilder private func surface(cornerRadius r: CGFloat) -> some View {
        let t = Double(min(max(transparency, 0), 100)) / 100
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        ZStack {
            if glass { shape.fill(.ultraThinMaterial) }
            shape.fill(NunaPalette.card.opacity(glass ? 0.9 * (1 - t) : 1 - 0.85 * t))
        }
        .overlay(shape.strokeBorder(NunaPalette.ink.opacity(glass ? 0.14 : 0.08), lineWidth: 1))
        .shadow(color: NunaPalette.shade.opacity(0.35), radius: 14, y: 5)
    }

    @ViewBuilder private func glyph(_ item: NunaTabItem, size: CGFloat) -> some View {
        if item.systemImage == NunaGlyph.anya {
            NunaGlyph(NunaGlyph.anya, pointSize: size * 0.72)
        } else if item.usesAssetImage {
            Image(item.systemImage).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: item.systemImage).font(.nuna(size: size * 0.74, weight: .semibold))
        }
    }

    private func tab(_ item: NunaTabItem) -> some View {
        let on = item.id == selection
        return Button {
            if on { onReselect(item.id) } else { selection = item.id }
        } label: {
            VStack(spacing: 4) {
                glyph(item, size: 28).frame(width: 32, height: 28)
                Text(verbatim: item.title).font(.nuna(size: NunaThemePrefs.skin == .whp ? 9.5 : 11, weight: .bold)).lineLimit(1)
                    .minimumScaleFactor(0.6).tracking(NunaThemePrefs.skin == .whp ? -0.2 : 0).allowsTightening(true)
            }
            .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
            .frame(minWidth: 52, minHeight: 52)
            .frame(maxWidth: .infinity)
            .background(on ? NunaPalette.ink.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: Sheet chrome

public extension View {
    /// Applies the Nuna bottom sheet look: dark surface, 34 pt top radius, visible grabber.
    func nunaSheetChrome(detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        modifier(NunaSheetChrome(detents: detents))
    }

    /// Standard Nuna screen background.
    func nunaScreenBackground() -> some View {
        self.background(NunaPalette.canvas.ignoresSafeArea())
    }
}

/// Presentation styling for Nuna sheets. The corner radius and background modifiers need iOS 16.4.
struct NunaSheetChrome: ViewModifier {
    let detents: Set<PresentationDetent>

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 16.4, *) {
            content
                .presentationDetents(detents)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(NunaRadius.sheet)
                .presentationBackground(NunaPalette.card)
        } else {
            content
                .presentationDetents(detents)
                .presentationDragIndicator(.visible)
        }
        #else
        content
        #endif
    }
}
