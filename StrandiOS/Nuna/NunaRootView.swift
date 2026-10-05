#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// The Nuna navigation shell: five tabs with a floating tab bar.
///
/// Phase 0 of docs/nuna/IMPLEMENTATION_PLAN.md. The tab roots still host the existing screens; later
/// phases replace them one by one. The shell is only used when `ExperienceMode` is `.nuna`; the default
/// experience keeps `RootTabView` untouched.
struct NunaRootView: View {
    /// Same gate `RootTabView` takes so `iOSRootView` can swap shells without changing its call shape.
    /// Home Screen quick actions are not handled by this shell yet.
    let homeScreenQuickActionsEnabled: Bool

    @EnvironmentObject private var router: NavRouter
    /// The live gym session, owned at the app root. Both shells present it; this one with its own face.
    @EnvironmentObject private var liftSession: LiftSessionController
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    /// The theme choices. The palette reads them from UserDefaults, so a change rebuilds the tabs (the navigation paths are kept).
    @AppStorage(NunaTheme.storageKey) private var themeRaw = NunaTheme.Mode.dark.rawValue
    @AppStorage(NunaThemePrefs.densityKey) private var densityRaw = NunaThemePrefs.Density.standard.rawValue
    @AppStorage(NunaThemePrefs.skinKey) private var skinRaw = NunaThemePrefs.Skin.standard.rawValue

    private enum Tab: Int, CaseIterable { case today = 0, health, trends, anya, me }

    @State private var selection = Tab.today.rawValue
    @State private var paths: [NavigationPath] = Array(repeating: NavigationPath(), count: Tab.allCases.count)
    @State private var showDevices = false
    @State private var routed: NavRouter.Destination?

    private var items: [NunaTabItem] {
        var out = [
            NunaTabItem(id: Tab.today.rawValue, title: "Today", systemImage: "square.grid.2x2.fill"),
            NunaTabItem(id: Tab.health.rawValue, title: "Health", systemImage: "heart.text.square.fill"),
            NunaTabItem(id: Tab.trends.rawValue, title: "Trends", systemImage: "chart.line.uptrend.xyaxis"),
        ]
        if coachEnabled { out.append(NunaTabItem(id: Tab.anya.rawValue, title: "Anya", systemImage: NunaGlyph.anya)) }
        out.append(NunaTabItem(id: Tab.me.rawValue, title: "Me", systemImage: "person.fill"))
        return out
    }

    var body: some View {
        TabView(selection: $selection) {
            stack(.today) { NunaTodayView() }
            stack(.health) { NunaHealthView() }
            stack(.trends) { NunaTrendsView() }
            if coachEnabled { stack(.anya) { NunaAnyaView() } }
            stack(.me) { NunaMeView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                NunaLiftBar()
                NunaTabBar(items: items, selection: $selection) { id in
                    // Re-tapping the active tab pops it to its root.
                    if id < paths.count { paths[id] = NavigationPath() }
                }
            }
        }
        .nunaScreenBackground()
        .id("\(themeRaw)-\(densityRaw)-\(skinRaw)")
        // Nuna is dark-first. The Appearance setting is honoured again once Phase 7 lands the Nuna theme screen.
        .preferredColorScheme(NunaTheme.colorScheme)
        .onAppear { Self.applyWindowStyle() }
        .onChange(of: themeRaw) { _, _ in Self.applyWindowStyle() }
        .onChange(of: skinRaw) { _, _ in Self.applyWindowStyle() }
        .onDisappear { Self.applyWindowStyle(reset: true) }
        .sheet(isPresented: $liftSession.isPresented) { NunaLiftSessionView() }
        // A session left running by a previous launch comes back as the bar, not as a sheet thrown in the user's face.
        .task {
            guard !liftSession.isActive, let snapshot = LiftSessionPersistence.load() else { return }
            liftSession.resume(from: snapshot)
        }
        .sheet(isPresented: $showDevices) { sheetStack { NunaDevicesView() } }
        .sheet(item: $routed) { dest in sheetStack { destinationView(dest) } }
        .onChange(of: router.requestedDestination) { _, dest in handle(dest) }
        .onChange(of: router.openNotificationSettings) { _, on in
            guard on else { return }
            selection = Tab.me.rawValue
            paths[Tab.me.rawValue] = NavigationPath([NunaMeRoute.notifications])
            router.openNotificationSettings = false
        }
    }

    /// Light or dark is also set on the windows themselves, because pages pushed inside the tabs are hosted by UIKit and
    /// do not always pick up `preferredColorScheme`. Cleared when this shell goes away so the Default look is untouched.
    static func applyWindowStyle(reset: Bool = false) {
        let style: UIUserInterfaceStyle = reset ? .unspecified : (NunaTheme.colorScheme.map { $0 == .dark ? .dark : .light } ?? .unspecified)
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] { window.overrideUserInterfaceStyle = style }
        }
    }

    // MARK: Tab roots

    private func stack<Root: View>(_ tab: Tab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: $paths[tab.rawValue]) {
            root()
                .background(NunaPalette.canvas.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .tabRouteDestinations()
                .nunaAnyaDestinations()
                .nunaDeviceDestinations()
                .nunaMeDestinations()
        }
        .toolbar(.hidden, for: .tabBar)
        // Pushed screens live in UIKit hosting; they need the choice stated again to resolve the adaptive palette.
        .preferredColorScheme(NunaTheme.colorScheme)
        .tag(tab.rawValue)
    }

    private func sheetStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .tabRouteDestinations()
                .nunaDeviceDestinations()
                .nunaAnyaDestinations()
                .nunaMeDestinations()
                .background(NunaPalette.canvas.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDevices = false; routed = nil }
                    }
                }
        }
    }

    @ViewBuilder private func destinationView(_ dest: NavRouter.Destination) -> some View {
        switch dest {
        case .insightsHub: InsightsHubView()
        case .labBook: LabBookView()
        case .fusedRecord: FusedRecordHost()
        case .rhythm: RhythmHost(onClose: { routed = nil })
        case .devices: NunaDevicesView()
        case .trends: TrendsView()
        case .workouts: NunaWorkoutsView()
        case .activeWorkout: NunaWorkoutsView(autoOpenStart: true)
        case .liveSession: LiquidTodayView()
        case .journal: NunaJournalView()
        case .coach: NunaAnyaView()
        }
    }

    // MARK: Router

    private func handle(_ dest: NavRouter.Destination?) {
        guard let dest else { return }
        switch dest {
        case .devices:
            showDevices = true
        case .coach:
            if coachEnabled {
                selection = Tab.anya.rawValue
                paths[Tab.anya.rawValue] = NavigationPath()
            }
        case .trends:
            selection = Tab.trends.rawValue
        case .liveSession:
            selection = Tab.today.rawValue
        default:
            routed = dest
        }
        router.requestedDestination = nil
    }
}
#endif
