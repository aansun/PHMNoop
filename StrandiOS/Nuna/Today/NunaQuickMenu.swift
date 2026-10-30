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
            Image(systemName: open ? "xmark" : "plus").font(.nuna(size: 17, weight: .bold))
                .foregroundStyle(open ? NunaPalette.textPrimary : NunaPalette.onAccent)
                .frame(width: 40, height: 40)
                .background(open ? NunaPalette.cardHighlight : NunaPalette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
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

/// The shortcuts behind the plus: a short card of up to five rows, an icon and a name each.
struct NunaQuickMenu: View {
    let actions: [NunaQuickAction]
    let onPick: (NunaQuickAction) -> Void

    static let width: CGFloat = 276
    static let rowHeight: CGFloat = 60
    static func height(_ rows: Int) -> CGFloat { CGFloat(rows) * rowHeight + 20 }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(actions) { a in
                Button { onPick(a) } label: {
                    HStack(spacing: 18) {
                        NunaGlyph(a.icon, pointSize: 22, weight: .regular).frame(width: 30)
                        Text(LocalizedStringKey(a.title)).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(NunaPalette.textPrimary)
                    .padding(.horizontal, 22).frame(height: Self.rowHeight).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .frame(width: Self.width)
        .background(NunaPalette.cardHighlight, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(NunaPalette.cardBorderHighlight.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }
}

/// Carries out the shortcut that was picked. It stays in place, out of sight, so the screens a shortcut opens are not torn down with the
/// menu that offered it.
struct NunaQuickRunner: View {
    @Binding var action: NunaQuickAction?
    let onAddActivity: () -> Void

    @EnvironmentObject private var router: NavRouter
    @State private var todayPanel: NunaTodayRoute?
    @State private var mePanel: NunaMeRoute?
    @State private var workoutPanel: NunaWorkoutRoute?
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
            .sheet(item: $todayPanel) { NunaQuickPanel(route: $0) }
            .sheet(item: $mePanel) { NunaQuickPanel(route: $0) }
            .sheet(item: $workoutPanel) { NunaQuickPanel(route: $0) }
    }

    private func run(_ a: NunaQuickAction) {
        switch a.kind {
        case .addActivity: onAddActivity()
        case .route(let d): router.requestedDestination = d
        case .breathing: breathing = true
        case .today(let r): todayPanel = r
        case .me(let r): mePanel = r
        case .workout(let r): workoutPanel = r
        case .foodAdd: addingFood = true
        case .metric(let key):
            if let m = MetricCatalog.metric(key: key, source: "my-whoop") { todayPanel = .metric(m) }
        }
    }
}
#endif
