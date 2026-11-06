#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// The square button at the end of the "My Day" row: a plus that opens the shortcuts, and the cross that closes them.
struct NunaQuickPlus: View {
    let open: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: open ? "xmark" : "plus").font(.nuna(size: 13, weight: .bold))
                .foregroundStyle(open ? NunaPalette.textPrimary : NunaPalette.onAccent)
                .frame(width: 30, height: 30)
                .background(open ? NunaPalette.cardHighlight : NunaPalette.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                // The square stays small; the touch area reaches a little past it.
                .padding(8).contentShape(Rectangle()).padding(-8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(open ? "Close" : "Quick actions"))
    }
}

/// Where the plus button sits, so the menu can open from it.
struct NunaQuickAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

/// The shortcuts behind the plus: a short card of up to five rows, an icon and a name each. Customizing is reached by holding the plus.
struct NunaQuickMenu: View {
    let actions: [NunaQuickAction]
    let onPick: (NunaQuickAction) -> Void
    /// How tall each row is: the full height when there is room, less when the menu has to fit under the top of the PHMN wordmark.
    var rowHeight: CGFloat = NunaQuickMenu.fullRowHeight

    static let width: CGFloat = 260
    static let fullRowHeight: CGFloat = 54
    static let minRowHeight: CGFloat = 40
    static let verticalPadding: CGFloat = 8
    static func height(_ rows: Int, rowHeight: CGFloat = fullRowHeight) -> CGFloat { CGFloat(rows) * rowHeight + 2 * verticalPadding }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(actions) { a in
                Button { onPick(a) } label: {
                    HStack(spacing: 18) {
                        NunaGlyph(a.icon, pointSize: 21, weight: .regular).frame(width: 30)
                        Text(LocalizedStringKey(a.title)).font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(NunaPalette.textPrimary)
                    .padding(.horizontal, 22).frame(height: rowHeight).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Self.verticalPadding)
        .frame(width: Self.width)
        .background(NunaPalette.cardHighlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(NunaPalette.cardBorderHighlight.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }
}

/// Carries out the shortcut that was picked. A page is pushed onto the Today stack, like any page opened from the menu; only Breathing (a
/// full-screen exercise) and Add food (a form) come up over it. It stays in place, out of sight, so what a shortcut opens is not torn down
/// with the menu that offered it.
struct NunaQuickRunner: View {
    @Binding var action: NunaQuickAction?
    let onAddActivity: () -> Void

    @EnvironmentObject private var router: NavRouter
    @Environment(\.nunaPushToday) private var pushToday
    @Environment(\.nunaPushMe) private var pushMe
    @Environment(\.nunaPushWorkout) private var pushWorkout
    @State private var breathing = false
    @State private var addingFood = false

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: action) { _, a in
                guard let a else { return }
                action = nil
                run(a)
            }
            .sheet(isPresented: $addingFood) {
                NunaFoodAddSheet(day: Repository.localDayKey(Date()), meal: NunaMeal.suggested()).nunaSheetChrome(detents: [.large])
            }
            .sheet(isPresented: $breathing) {
                NavigationStack { NunaBreathView().toolbar(.hidden, for: .navigationBar) }
                    .preferredColorScheme(NunaTheme.colorScheme)
            }
            #if DEBUG
            // `--open-breathing`: a debug build opens Breathing once at launch, to look at it without going through the menu.
            .task {
                guard CommandLine.arguments.contains("--open-breathing"), !NunaTodayDebug.openedPlanner else { return }
                NunaTodayDebug.openedPlanner = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                breathing = true
            }
            #endif
    }

    private func run(_ a: NunaQuickAction) {
        switch a.kind {
        case .addActivity: onAddActivity()
        case .route(let d):
            switch d {
            case .journal: pushToday(.journal)
            case .labBook: pushToday(.labBook)
            case .rhythm: pushToday(.rhythm)
            case .devices: pushToday(.devices)
            case .workouts: pushWorkout(.hub(0))
            default: router.requestedDestination = d
            }
        case .breathing: breathing = true
        case .today(let r): pushToday(r)
        case .me(let r): pushMe(r)
        case .workout(let r): pushWorkout(r)
        case .foodAdd: addingFood = true
        case .metric(let key):
            if let m = MetricCatalog.metric(key: key, source: "my-whoop") { pushToday(.metric(m)) }
        }
    }
}
#endif
