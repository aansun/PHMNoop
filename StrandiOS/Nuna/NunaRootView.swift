#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// The Nuna navigation shell: four tabs (Home, Health, Breathing, More) in one floating tab bar, with Anya as a floating button beside it.
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

    init(homeScreenQuickActionsEnabled: Bool) {
        self.homeScreenQuickActionsEnabled = homeScreenQuickActionsEnabled
        // Nuna reads Effort on WHOOP's 0 to 21 scale unless the wearer picked another one; a choice already made is never touched.
        if UserDefaults.standard.object(forKey: UnitPrefs.effortScaleKey) == nil {
            UserDefaults.standard.set(EffortScale.whoop.rawValue, forKey: UnitPrefs.effortScaleKey)
        }
    }

    private enum Tab: Int, CaseIterable { case today = 0, health, breath, me }

    @State private var selection = Tab.today.rawValue
    @State private var paths: [NavigationPath] = Array(repeating: NavigationPath(), count: Tab.allCases.count)
    @State private var showDevices = false
    /// Anya's sheet, opened by the round button beside the tab bar.
    @State private var showAnya = false
    @State private var routed: NavRouter.Destination?
    /// The Journal fills the screen, as on the reference, instead of rising as a sheet.
    @State private var journalOpen = false
    /// While the keyboard is up the tab bar steps aside: it floats over the content, so above a keyboard it would sit on top of whatever is being typed.
    @State private var keyboardUp = false
    /// "Hide bar when scrolling": the bar steps down while the page is scrolled and returns on the way back (same preference as the Default design).
    @AppStorage(NunaTabBarPrefs.autoHideKey) private var autoHide = false
    @State private var barHidden = false

    /// One bar: Home, Health, Breathing and More. Anya is the round button beside it.
    private var items: [NunaTabItem] {
        [
            NunaTabItem(id: Tab.today.rawValue, title: "Home", systemImage: "tab:home"),
            NunaTabItem(id: Tab.health.rawValue, title: "Health", systemImage: "tab:health"),
            NunaTabItem(id: Tab.breath.rawValue, title: "Breathing", systemImage: NunaIcons.breathing),
            NunaTabItem(id: Tab.me.rawValue, title: "More", systemImage: "tab:more"),
        ]
    }

    /// Anya's button: her mark in a ring, on the same glass as the bar. It opens her sheet over the page; it is not a tab.
    private var anyaButton: AnyView { AnyView(NunaAnyaRing(size: 34)) }

    /// What Anya reads for the tab that is open.
    private var anyaContext: String {
        switch selection {
        case Tab.health.rawValue: return "Health"
        default: return "Today"
        }
    }

    /// The tab bar belongs to the main page of a tab. Once a page is pushed the bar steps away and the page's own back button is the way out.
    private var atTabRoot: Bool { selection < paths.count ? paths[selection].isEmpty : true }

    var body: some View {
        TabView(selection: $selection) {
            stack(.today) { NunaTodayView() }
            stack(.health) { NunaHealthTabView() }
            stack(.breath) { NunaBreathView(asTabRoot: true) }
            stack(.me) { NunaMeView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardUp {
                VStack(spacing: 0) {
                    NunaWorkoutBar()
                    NunaLiftBar()
                    if atTabRoot {
                        NunaTabBar(items: items,
                                   trailing: coachEnabled ? NunaTabItem(id: -1, title: "Anya", systemImage: NunaGlyph.anya) : nil,
                                   trailingView: coachEnabled ? anyaButton : nil, onTrailing: coachEnabled ? { showAnya = true } : nil,
                                   selection: $selection, minimized: autoHide && barHidden,
                                   onExpand: { barHidden = false }) { id in
                            // Re-tapping the active tab pops it to its root.
                            if id < paths.count { paths[id] = NavigationPath() }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: keyboardUp)
        .animation(.easeInOut(duration: 0.22), value: atTabRoot)
        .animation(.easeInOut(duration: 0.22), value: barHidden)
        // Scrolling a page moves a finger up (content goes up) or down; read it beside the page's own scroll, never instead of it.
        // Only while "Hide bar when scrolling" is on: a gesture on the whole shell is tracked on every touch, so it is not attached when it has no job.
        .simultaneousGesture(DragGesture(minimumDistance: 14).onChanged { v in
            guard abs(v.translation.height) > abs(v.translation.width) else { return }
            if v.translation.height < -14, !barHidden { barHidden = true }
            else if v.translation.height > 14, barHidden { barHidden = false }
        }, including: autoHide ? .all : .subviews)
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
            #if DEBUG
            NunaAnyaQA.runIfRequested(model: model)
            #endif
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
        .sheet(isPresented: $showAnya) { NunaAnyaSheet(context: anyaContext, floating: true) }
        .sheet(item: $routed) { dest in sheetStack { destinationView(dest) } }
        .fullScreenCover(isPresented: $journalOpen) {
            NavigationStack { NunaJournalView().nunaTodayDestinations().nunaMeDestinations() }.preferredColorScheme(NunaTheme.colorScheme)
        }
        .onChange(of: router.requestedDestination) { _, dest in handle(dest) }
        #if DEBUG
        // `--open-journal`: a debug build opens the Journal once at launch, to look at it without finding the card on Today.
        .task {
            guard CommandLine.arguments.contains("--open-journal") else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            journalOpen = true
        }
        #endif
        .onChange(of: router.pendingMetricKey) { _, key in openMetric(key) }
        .onChange(of: router.openNotificationSettings) { _, on in
            guard on else { return }
            selection = Tab.me.rawValue
            paths[Tab.me.rawValue] = NavigationPath([NunaMeRoute.notifications])
            router.openNotificationSettings = false
        }
        .onChange(of: router.openRecommendedSettings) { _, on in
            guard on else { return }
            selection = Tab.me.rawValue
            paths[Tab.me.rawValue] = NavigationPath([NunaMeRoute.settings, NunaMeRoute.appSettings, NunaMeRoute.recommended])
            router.openRecommendedSettings = false
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
                .background(NunaBackdrop())
                .toolbar(.hidden, for: .navigationBar)
                .tabRouteDestinations()
                .nunaAnyaDestinations()
                .nunaDeviceDestinations()
                .nunaMeDestinations()
        }
        .toolbar(.hidden, for: .tabBar)
        // Every page pushed in the Settings tab, whichever way it is opened (a route or a plain link), takes the Settings page title and type scale.
        .environment(\.nunaSettingsPage, tab == .me)
        .environment(\.nunaPushToday) { paths[Tab.today.rawValue].append($0) }
        .environment(\.nunaPushMe) { paths[Tab.today.rawValue].append($0) }
        .environment(\.nunaPushWorkout) { paths[tab.rawValue].append($0) }
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
                .background(NunaBackdrop())
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
        case .trends: NunaTrendsView()
        case .workouts: NunaWorkoutsView()
        // Start activity opens the start screen itself, not the Workouts page with the start screen pushed on it: closing it returns to where it was opened.
        case .activeWorkout: NunaWorkoutStartView(sport: nil, resume: true).nunaWorkoutDestinations()
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
            // The full conversation opens over the page (a moment after Anya's sheet has gone, when that is where it came from).
            if coachEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { routed = dest }
            }
        case .health:
            // There is no Health tab: what opened it (the vital sign widget) lands on the vital signs page of Today.
            selection = Tab.today.rawValue
            paths[Tab.today.rawValue] = NavigationPath([NunaTodayRoute.vitalSigns])
        case .liveSession:
            selection = Tab.today.rawValue
        case .journal:
            journalOpen = true
        default:
            routed = dest
        }
        router.requestedDestination = nil
    }
}

/// Pushes a Today page from a screen that would otherwise push it by a flag: a push made by a flag is not in the tab's navigation path, so the
/// shell could not tell a page had been opened and would keep the tab bar over it.
private struct NunaPushTodayKey: EnvironmentKey { static let defaultValue: (NunaTodayRoute) -> Void = { _ in } }
/// The same for a page of More or of Workouts opened from Today (the quick actions).
private struct NunaPushMeKey: EnvironmentKey { static let defaultValue: (NunaMeRoute) -> Void = { _ in } }
private struct NunaPushWorkoutKey: EnvironmentKey { static let defaultValue: (NunaWorkoutRoute) -> Void = { _ in } }
extension EnvironmentValues {
    var nunaPushMe: (NunaMeRoute) -> Void {
        get { self[NunaPushMeKey.self] }
        set { self[NunaPushMeKey.self] = newValue }
    }
    var nunaPushWorkout: (NunaWorkoutRoute) -> Void {
        get { self[NunaPushWorkoutKey.self] }
        set { self[NunaPushWorkoutKey.self] = newValue }
    }
    var nunaPushToday: (NunaTodayRoute) -> Void {
        get { self[NunaPushTodayKey.self] }
        set { self[NunaPushTodayKey.self] = newValue }
    }
}
#endif
