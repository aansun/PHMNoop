#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// The Nuna navigation shell: four tabs (Today, Trends, Anya, Me) in one floating tab bar.
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
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var sessionPresenter = NunaLiftSessionPresenter()
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    /// The theme choices. The palette reads them from UserDefaults, so a change rebuilds the tabs (the navigation paths are kept).
    @AppStorage(NunaTheme.storageKey) private var themeRaw = NunaTheme.Mode.dark.rawValue
    @AppStorage(NunaThemePrefs.densityKey) private var densityRaw = NunaThemePrefs.Density.standard.rawValue
    @AppStorage(NunaThemePrefs.skinKey) private var skinRaw = NunaThemePrefs.Skin.standard.rawValue

    private enum Tab: Int, CaseIterable { case today = 0, trends, anya, me }

    @State private var selection = Tab.today.rawValue
    @State private var paths: [NavigationPath] = Array(repeating: NavigationPath(), count: Tab.allCases.count)
    @State private var showDevices = false
    @State private var routed: NavRouter.Destination?
    /// While the keyboard is up the tab bar steps aside: it floats over the content, so above a keyboard it would sit on top of whatever is being typed.
    @State private var keyboardUp = false
    /// "Hide bar when scrolling": the bar steps down while the page is scrolled and returns on the way back (same preference as the Default design).
    @AppStorage(NunaTabBarPrefs.autoHideKey) private var autoHide = false
    @State private var barHidden = false

    /// One bar: Today, Trends, Anya (while it is on) and More.
    private var items: [NunaTabItem] {
        var out = [
            NunaTabItem(id: Tab.today.rawValue, title: "Today", systemImage: "square.grid.2x2.fill"),
            NunaTabItem(id: Tab.trends.rawValue, title: "Trends", systemImage: "chart.line.uptrend.xyaxis"),
        ]
        if coachEnabled { out.append(NunaTabItem(id: Tab.anya.rawValue, title: "Anya", systemImage: NunaGlyph.anya)) }
        out.append(NunaTabItem(id: Tab.me.rawValue, title: "More", systemImage: "line.3.horizontal"))
        return out
    }

    var body: some View {
        TabView(selection: $selection) {
            stack(.today) { NunaTodayView() }
            stack(.trends) { NunaTrendsView() }
            if coachEnabled { stack(.anya) { NunaAnyaView() } }
            stack(.me) { NunaMeView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardUp {
                VStack(spacing: 0) {
                    NunaWorkoutBar()
                    NunaLiftBar()
                    NunaTabBar(items: items, selection: $selection, minimized: autoHide && barHidden,
                               onExpand: { barHidden = false }) { id in
                        // Re-tapping the active tab pops it to its root.
                        if id < paths.count { paths[id] = NavigationPath() }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: keyboardUp)
        .animation(.easeInOut(duration: 0.22), value: barHidden)
        // Scrolling a page moves a finger up (content goes up) or down; read it beside the page's own scroll, never instead of it.
        .simultaneousGesture(DragGesture(minimumDistance: 14).onChanged { v in
            guard autoHide, abs(v.translation.height) > abs(v.translation.width) else { return }
            if v.translation.height < -14, !barHidden { barHidden = true }
            else if v.translation.height > 14, barHidden { barHidden = false }
        })
        .onChange(of: selection) { _, _ in barHidden = false }
        .onChange(of: autoHide) { _, on in if !on { barHidden = false } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .nunaScreenBackground()
        // WHP sets every label in capitals; sentences and Anya opt out with `.textCase(nil)` where they are drawn.
        .textCase(skinRaw == NunaThemePrefs.Skin.whp.rawValue ? .uppercase : nil)
        .tracking(skinRaw == NunaThemePrefs.Skin.whp.rawValue ? 0.6 : 0)
        .id("\(themeRaw)-\(densityRaw)-\(skinRaw)")
        // Nuna is dark-first. The Appearance setting is honoured again once Phase 7 lands the Nuna theme screen.
        .preferredColorScheme(NunaTheme.colorScheme)
        // Changing the theme or style swaps this view's identity (see `.id` above): the new shell appears and the old one disappears, in
        // either order. Only the last shell to go away may hand the windows back, or a switch to Light would be undone a moment after it was
        // applied and every pushed page would stay dark.
        .onAppear { Self.liveShells += 1; Self.applyWindowStyle() }
        .onChange(of: themeRaw) { _, _ in Self.applyWindowStyle() }
        .onChange(of: skinRaw) { _, _ in Self.applyWindowStyle() }
        .onDisappear {
            Self.liveShells = max(Self.liveShells - 1, 0)
            if Self.liveShells == 0 { Self.applyWindowStyle(reset: true) }
        }
        // The gym session is full screen, like the live workout of every other sport, and never a sheet that a swipe could close by accident:
        // it is put away with the chevron in its header. It is presented by UIKit over whatever is on top, so starting it from a sheet
        // (Gym in Quick actions) does not close the sheet first.
        .onChange(of: liftSession.summaryRequest) { _, id in
            guard let id else { return }
            sessionPresenter.showSummary(sessionId: id, repo: model.repo, model: model, session: liftSession, router: router)
            liftSession.summaryRequest = nil
        }
        .onChange(of: liftSession.isPresented) { _, on in
            if on { sessionPresenter.present(repo: model.repo, model: model, session: liftSession, router: router) } else { sessionPresenter.dismiss() }
        }
        // Anya reads the clock, the Plan card's session, banked Effort and tonight's sleep need with every request.
        .task {
            NunaAnyaDayContext.install(on: model.coach, repo: model.repo, profile: model.profile)
            // The daily brief is armed (and made, if its time has passed) as soon as the app is up, not only when the Anya tab is opened.
            CoachBriefScheduler.activateIfEnabled { await model.coach.generateBrief() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { CoachBriefScheduler.activateIfEnabled { await model.coach.generateBrief() } }
        }
        .onDisappear { model.coach.dayContextProvider = nil; model.coach.beforeBrief = nil }
        // A session left running by a previous launch comes back as the bar; if its screen was open when the app was killed, the screen comes back too.
        .task {
            guard !liftSession.isActive, let snapshot = LiftSessionPersistence.load() else { return }
            liftSession.resume(from: snapshot)
            // The screen it was on comes back with it (a session left open before the app was killed), not only the small bar.
            if snapshot.presented == true {
                try? await Task.sleep(nanoseconds: 700_000_000)
                liftSession.present()
            }
        }
        .sheet(isPresented: $showDevices) { sheetStack { NunaDevicesView() } }
        .sheet(item: $routed) { dest in sheetStack { destinationView(dest) } }
        .onChange(of: router.requestedDestination) { _, dest in handle(dest) }
        .onChange(of: router.pendingMetricKey) { _, key in openMetric(key) }
        .onChange(of: router.openNotificationSettings) { _, on in
            guard on else { return }
            selection = Tab.me.rawValue
            paths[Tab.me.rawValue] = NavigationPath([NunaMeRoute.notifications])
            router.openNotificationSettings = false
        }
    }

    /// Light or dark is also set on the windows themselves, because pages pushed inside the tabs are hosted by UIKit and
    /// do not always pick up `preferredColorScheme`. Cleared when this shell goes away so the Default look is untouched.
    private static var liveShells = 0

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
                .nunaTodayDestinations()
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
        case .labBook: NunaLabBookView()
        case .fusedRecord: FusedRecordHost()
        case .rhythm: RhythmHost(onClose: { routed = nil })
        case .devices: NunaDevicesView()
        case .trends: TrendsView()
        case .workouts: NunaWorkoutsView()
        case .activeWorkout: NunaWorkoutsView(autoOpenStart: true)
        case .liveSession: LiquidTodayView()
        case .journal: NunaJournalView()
        case .coach: NunaAnyaView()
        case .health: NunaHealthView(vitalsOnly: true)
        }
    }

    // MARK: Router

    /// A widget asked for one metric: switch to Today and push its detail. Charge, Effort and Rest open their own screens (the metric host
    /// swaps in the right one); heart rate opens the live screen.
    private func openMetric(_ key: String?) {
        guard let key else { return }
        defer { router.pendingMetricKey = nil }
        let route: NunaTodayRoute?
        switch key {
        case "heartrate": route = .deepTimeline
        case "steps":
            route = MetricCatalog.todayStepsMetric(hasMeasuredSteps: true).map { .metric($0) }
        default:
            route = MetricCatalog.metric(key: key, source: "my-whoop").map { .metric($0) }
        }
        guard let route else { return }
        selection = Tab.today.rawValue
        paths[Tab.today.rawValue] = NavigationPath([route])
    }

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
        case .health:
            // There is no Health tab: what opened it (the vital sign widget) lands on the vital signs page of Today.
            selection = Tab.today.rawValue
            paths[Tab.today.rawValue] = NavigationPath([NunaTodayRoute.vitalSigns])
        case .liveSession:
            selection = Tab.today.rawValue
        default:
            routed = dest
        }
        router.requestedDestination = nil
    }
}
#endif
