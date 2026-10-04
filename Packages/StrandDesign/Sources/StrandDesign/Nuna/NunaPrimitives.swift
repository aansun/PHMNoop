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
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(foreground)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
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
        case .primary: return NunaPalette.textPrimary
        case .ghost: return NunaPalette.glassStrong
        case .destructive: return NunaPalette.alert.opacity(0.14)
        }
    }
    private var border: Color {
        switch kind {
        case .primary: return .clear
        case .ghost: return Color.white.opacity(0.12)
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
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(filled ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .frame(width: 44, height: 44)
                .background(filled ? NunaPalette.textPrimary : NunaPalette.glassStrong, in: Circle())
                .overlay(Circle().strokeBorder(NunaPalette.hairline, lineWidth: filled ? 0 : 1))
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
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(NunaPalette.onAccent)
                .frame(width: 58, height: 58)
                .background(NunaPalette.textPrimary, in: Circle())
                .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
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
                .font(.system(size: onBack == nil ? NunaTypeSize.h1 : 24, weight: .heavy))
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
            .font(.system(size: NunaTypeSize.caption, weight: .heavy))
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
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .bold))
            // Icons are neutral by design: colour is kept for scores and status, never for symbols.
            .foregroundStyle(NunaPalette.textPrimary)
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
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
        HStack(spacing: 12) {
            if let systemImage { NunaIconTile(systemImage, tint: tint) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: NunaTypeSize.h3 - 1, weight: .bold))
                    .foregroundStyle(NunaPalette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NunaPalette.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

public extension NunaListRow where Trailing == EmptyView {
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
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(selected ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(selected ? NunaPalette.glassStrong : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(NunaPalette.glass, in: Capsule())
        .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
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
                Image(systemName: "plus").font(.system(size: 17, weight: .bold))
                Text(title).font(.system(size: 15, weight: .heavy))
            }
            .foregroundStyle(NunaPalette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Tab bar

public struct NunaTabItem: Identifiable, Hashable {
    public let id: Int
    public let title: LocalizedStringKey
    public let systemImage: String
    public init(id: Int, title: LocalizedStringKey, systemImage: String) {
        self.id = id; self.title = title; self.systemImage = systemImage
    }
    public static func == (l: NunaTabItem, r: NunaTabItem) -> Bool { l.id == r.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

/// Floating, pill-shaped tab bar. Hosts place it with `.safeAreaInset(edge: .bottom)`.
public struct NunaTabBar: View {
    private let items: [NunaTabItem]
    @Binding private var selection: Int
    private let onReselect: (Int) -> Void

    public init(items: [NunaTabItem], selection: Binding<Int>, onReselect: @escaping (Int) -> Void = { _ in }) {
        self.items = items; self._selection = selection; self.onReselect = onReselect
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let on = item.id == selection
                Button {
                    if on { onReselect(item.id) } else { selection = item.id }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.systemImage).font(.system(size: 18, weight: .semibold))
                        Text(item.title).font(.system(size: 11, weight: .bold)).lineLimit(1)
                    }
                    .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                    .frame(minWidth: 58, minHeight: 58)
                    .frame(maxWidth: .infinity)
                    .background(on ? NunaPalette.glassStrong : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 72)
        .background(Color(hex: "#14181D"), in: Capsule())
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
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
                .presentationBackground(Color(hex: "#14181D"))
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
