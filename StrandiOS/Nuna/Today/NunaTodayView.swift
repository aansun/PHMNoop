#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Nuna "Hari ini". Phase 1 of docs/nuna/IMPLEMENTATION_PLAN.md.
///
/// Display only: it reads the same repository and layout preferences as the Default Today screens
/// (`today.sectionOrder`, `today.hiddenSections`, `today.keyMetrics`), so switching Experience keeps the
/// user's arrangement. Sections without a Nuna card yet (Your Cards, Menstrual Cycle, Added Cards) are
/// skipped here and stay available in the Default Experience.
/// The order and visibility the Nuna Today screen uses until the person arranges their own.
#if DEBUG
/// Whether this launch has already opened the planner for `--open-planner`.
enum NunaTodayDebug { @MainActor static var openedPlanner = false }
#endif

enum NunaTodayDefaults {
    /// Nuna keeps its own arrangement: the Default look saves its order and hidden set under other keys, and the two looks start from
    /// different defaults, so one must not leak into the other.
    static let orderKey = "nuna.today.sectionOrder"
    static let hiddenKey = "nuna.today.hiddenSections"
    /// Rings, Highlights, the Vital signs and Stress monitor pair, what was done today, the journal with mood, Your cards, Charge and Effort for the
    /// week, then the add-or-arrange card. The state chips, key metrics, heart rate, start session, cycle and added cards stay out until the
    /// person adds them.
    static let order: [TodaySection] = [
        .hero, .synthesis, .weatherAir, .vitalMonitor, .workouts, .journal, .yourCards, .weekCompare, .recoveryVitals,
        .stateChips, .keyMetrics, .heartRate, .liveSession, .menstrualCycle, .addedCards,
    ]
    static let hidden: [TodaySection] = [.stateChips, .keyMetrics, .heartRate, .liveSession, .menstrualCycle, .addedCards]
    /// What Your cards holds until the person chooses their own. The Default looks keep `DashboardCard.defaultSelection` for the same key.
    static let yourCards: [DashboardCard] = [.steps, .fitnessAge, .calories, .weight]
    static func yourCardsEnabled(_ raw: String) -> [DashboardCard] {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? yourCards : DashboardCardPrefs.decodeEnabled(raw).filter { $0 != .vitality }
    }
    /// Set once the monitor pair has been hidden on a layout saved before it existed (it would otherwise appear on its own).
    static let monitorHiddenKey = "nuna.today.monitorHidden.v1"
    /// Set once the Activity card has been brought back on a layout saved while it was hidden by default.
    static let activityShownKey = "nuna.today.activityShown.v1"
    /// Set once Highlights has been moved up to just under the rings on a layout saved before it took that place.
    static let highlightsMovedKey = "nuna.today.highlightsMoved.v1"
}

// The small views below each observe one fast-changing object, so a heart-rate tick or a strap update redraws a chip, not the whole screen.

/// Shows `content` with the live heart rate while it is today and a reading exists.
private struct NunaLiveHR<Content: View>: View {
    @EnvironmentObject private var live: LiveState
    let isToday: Bool
    @ViewBuilder let content: (Int) -> Content
    var body: some View {
        if isToday, let hr = live.heartRate { content(hr) }
    }
}

/// Hands the shared app model to `content`, so only this small view is redrawn when it changes.
struct NunaWithApp<Content: View>: View {
    @EnvironmentObject private var appModel: AppModel
    @ViewBuilder let content: (AppModel) -> Content
    var body: some View { content(appModel) }
}

/// The same for the live strap state.
struct NunaWithLive<Content: View>: View {
    @EnvironmentObject private var live: LiveState
    @ViewBuilder let content: (LiveState) -> Content
    var body: some View { content(live) }
}

private struct NunaLiveStrapChip: View {
    @EnvironmentObject private var live: LiveState
    var body: some View { NunaStrapChip(connected: live.connected, battery: live.batteryPct) }
}

/// The early warning no longer takes a card on Today: it goes into the bell once a day per level (and Anya's card carries a short
/// line). It draws nothing itself.
private struct NunaIllnessNotifier: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var updateStore: UpdateStore
    private static let stampKey = "nuna.illness.posted"

    var body: some View {
        Color.clear
            .onChange(of: appModel.illnessSignal?.level, initial: true) { _, _ in post() }
    }

    private func post() {
        guard let r = appModel.illnessSignal, r.level != .quiet else { return }
        let stamp = "\(Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970))|\(r.level)"
        guard UserDefaults.standard.string(forKey: Self.stampKey) != stamp else { return }
        UserDefaults.standard.set(stamp, forKey: Self.stampKey)
        updateStore.post(UpdateItem(kind: .reading, title: String(localized: "Early warning"), message: localizedIllnessCopy(r), deepLink: "coach"))
    }
}

private struct NunaCycleGate<Content: View>: View {
    @EnvironmentObject private var appModel: AppModel
    @ViewBuilder let content: () -> Content
    var body: some View {
        if appModel.cyclePhase != nil { content() }
    }
}

final class NunaCollapse: ObservableObject {
    @Published var t: CGFloat = 0
}

/// The score rings, redrawn on their own while the page scrolls.
private struct NunaPinnedRings: View {
    @ObservedObject var state: NunaCollapse
    let charge: LiquidTodayView.ChargeDisplay
    let effort: Double?
    let rest: Double?
    let effortScale: EffortScale
    var body: some View { NunaScoreRings(charge: charge, effort: effort, rest: rest, effortScale: effortScale, collapse: state.t) }
}

/// "PHMNOOP" in thin wide letters over the rings; it folds away as the rings shrink.
private struct NunaPinnedBrand: View {
    @ObservedObject var state: NunaCollapse
    let height: CGFloat
    var body: some View {
        // The wordmark of the reference: about 17 pt, a regular stroke, wide letters, near white. The tracking is added after the last letter too, so
        // the same amount is taken off the leading side to keep the word on the centre line.
        PHMNWordmark(height: 11, color: NunaPalette.textPrimary.opacity(0.92))
            .frame(maxWidth: .infinity).frame(height: height * (1 - state.t), alignment: .center).clipped().offset(y: -3 * (1 - state.t))
            .opacity(Double(max(0, 1 - state.t * 1.8)))
            .accessibilityHidden(true)
    }
}

private struct NunaPinnedHairline: View {
    @ObservedObject var state: NunaCollapse
    var body: some View { Rectangle().fill(NunaPalette.hairline).frame(height: 1).opacity(Double(state.t)) }
}

/// Mirrors the number of saved gym sessions into the screen, writing only when it changes.
private struct NunaSavedSessionsWatcher: View {
    @Binding var count: Int
    @EnvironmentObject private var liftSession: LiftSessionController
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { if count != liftSession.savedSessions { count = liftSession.savedSessions } }
            .onChange(of: liftSession.savedSessions) { _, n in if count != n { count = n } }
    }
}

struct NunaTodayView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    /// How many gym sessions have been saved. The live session itself is NOT observed here: it ticks every second while it runs, and a screen that
    /// observed it would be re-evaluated whole, cards and all, each second, which is what made scrolling Today stutter during a session.
    @State private var savedSessions = 0
    /// The strap's charge while it is low (20% or less, not charging), else nil; and the level whose banner was put away.
    @State private var lowBatteryPct: Int?
    @AppStorage("noop.lowBatteryBannerDismissed") private var lowBatteryDismissed = 0
    /// A paired strap has been off for a few seconds: the "Strap not in use" notice sits under the day until it is back.
    @State private var strapIdle = false
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject private var updateStore: UpdateStore
    @EnvironmentObject private var intelligence: IntelligenceEngine

    @AppStorage("noop.coachEnabled") var coachEnabled = true
    @AppStorage(HydrationStore.enabledKey) var hydrationEnabled = false
    @AppStorage(NunaTodayDefaults.orderKey) private var sectionOrderRaw = ""
    @AppStorage(NunaTodayDefaults.hiddenKey) private var hiddenSectionsRaw = ""
    @AppStorage(KeyMetricPrefs.layoutKey) private var keyMetricsRaw = ""
    @AppStorage("today.keyMetricsDetailed") private var keyMetricsDetailed = false
    @AppStorage("today.keyMetricsWindowDays") private var keyMetricsWindowDays = 14
    @AppStorage(DashboardCardPrefs.selectionKey) var dashboardCardsRaw = ""
    @AppStorage(NunaDashPrefs.key) var myDashboardRaw = ""
    @AppStorage(HostedCardPrefs.selectionKey) var hostedCardsRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue

    @StateObject var model = NunaTodayModel()
    /// The year of sleep, charge and effort figures the My Dashboard cards that open a trend page show.
    @StateObject var history = NunaSleepHistory()
    @StateObject private var sparks = NunaKeySparkModel()
    @StateObject private var highlightsFeed = NunaHighlightsFeed()
    /// What the customize sheet opens on; set together with presenting it, so the sheet always gets the right page.
    @State private var customize: TodayCustomizationDestination?
    @State private var showQuick = false
    /// The one-time tour of the plus (hold it to change the shortcuts): shown the first time Home opens.
    @AppStorage(NunaQuickTip.seenKey) private var quickTipSeen = false
    @State private var showQuickTip = false
    /// Pulling Today down syncs the strap and says when it last did.
    @StateObject private var sync = NunaPullSync()
    /// The shortcut just picked, handed to `NunaQuickRunner`.
    @State private var pendingQuick: NunaQuickAction?
    @State private var editingQuick = false
    @AppStorage(NunaQuickActions.storageKey) private var quickRaw = ""
    @State private var showDate = false
    @State private var showCoach = false
    @State private var showOutlook = false
    @State private var editing = false
    @State private var showManual = false
    /// The saved session the Anya card opens straight to.
    @State private var showBreath = false
    @Environment(\.nunaPushToday) private var pushToday
    @Environment(\.nunaPushMe) private var pushMe
    @AppStorage("nuna.keyMetricsLayout") private var metricsLayoutRaw = NunaMetricsLayout.cards.rawValue
    @State private var showAddCard = false
    /// 0 when Today is at the top, 1 once the pinned score rings have shrunk to their small size.
    /// How far the page has scrolled, 0 to 1. Held in a small object that only the rings and the hairline observe, so a scroll
    /// frame redraws those two instead of re-evaluating the whole Today screen.
    @State private var collapse = NunaCollapse()
    /// Today's suggested session, the same one the plan screen shows. Nil until Charge exists.
    @State private var dayPlan: NunaDayPlanResult?
    @State private var addAfter: TodaySection?

    /// The day on show, as the key the stored series use.
    var dayKeyNow: String { model.dayKey(repo: repo) }

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// The baselines still being built, for the Highlights card: Recovery needs its first nights, the stress reading needs 14.
    private var calibrationStages: [NunaCalibrationStage] {
        guard model.loaded else { return [] }
        var out: [NunaCalibrationStage] = []
        if case .calibrating(let n) = model.charge { out.append(.init(id: "recovery", nights: n, total: Baselines.minNightsSeed)) }
        if !model.stressStatus.isReady { out.append(.init(id: "stress", nights: model.stressStatus.nights, total: StressEngine.requiredNights)) }
        return out
    }

    /// The order and visibility the Nuna mockup shows until the person arranges the cards themselves.
    /// Stored values (shared with Default) win as soon as they exist.
    private static let nunaDefaultOrder = NunaTodayDefaults.order
    private static let nunaDefaultHidden = NunaTodayDefaults.hidden
    private static let nunaDefaultMetrics: [KeyMetric] = [.hrv, .restingHr, .steps, .rest]

    private var effectiveOrder: [TodaySection] {
        sectionOrderRaw.trimmingCharacters(in: .whitespaces).isEmpty
            ? Self.nunaDefaultOrder : TodayLayoutPrefs.decodeOrder(sectionOrderRaw)
    }
    private var effectiveHidden: [TodaySection] {
        hiddenSectionsRaw.trimmingCharacters(in: .whitespaces).isEmpty
            ? Self.nunaDefaultHidden : TodayLayoutPrefs.decodeHidden(hiddenSectionsRaw)
    }
    private var sections: [TodaySection] { effectiveOrder.filter { !effectiveHidden.contains($0) } }

    // MARK: My Day and its shortcuts

    private var quickActions: [NunaQuickAction] {
        NunaQuickActions.decode(quickRaw.isEmpty ? NunaQuickActions.encode(NunaQuickActions.defaultIDs) : quickRaw).compactMap(NunaQuickActions.action)
    }

    /// The section the "My Day" row follows: the monitor pair, or the rings when that is hidden.
    private var myDayAnchor: TodaySection? {
        sections.contains(.vitalMonitor) ? .vitalMonitor : (sections.contains(.hero) ? .hero : sections.first)
    }

    private func setQuick(_ open: Bool) { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showQuick = open } }

    /// "My Day" with the plus at its end. Holding the plus opens the choice of shortcuts.
    private var myDayRow: some View {
        HStack(alignment: .center) {
            Text("My Day").font(.nuna(size: 19, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Spacer(minLength: 8)
            NunaQuickPlus(open: false) { setQuick(true) }
                .opacity(showQuick ? 0 : 1)
                .anchorPreference(key: NunaQuickAnchorKey.self, value: .bounds) { $0 }
                .nunaLongPressMenu {
                    NunaMenuItem("Customize quick actions", icon: "gearshape") { editingQuick = true }
                }
        }
        .padding(.horizontal, 4).padding(.top, 14)
    }

    /// The tour of the plus, over a dimmed screen with the plus lit. Not shown when the plus is out of sight.
    @ViewBuilder private func quickTip(_ anchor: Anchor<CGRect>?) -> some View {
        if showQuickTip, !quickTipSeen, !showQuick, let anchor {
            GeometryReader { geo in
                let r = geo[anchor]
                if geo.frame(in: .local).insetBy(dx: 0, dy: 60).contains(CGPoint(x: r.midX, y: r.midY)) {
                    NunaQuickTip(target: r) { withAnimation(.easeOut(duration: 0.2)) { quickTipSeen = true; showQuickTip = false } }
                }
            }
            // The reader takes the whole screen, so the plus and the dimmed layer are measured from the same corner.
            .ignoresSafeArea()
        }
    }

    /// The shortcuts over a dimmed screen, opening upward from the plus (downward when there is no room above), with the plus turned into a cross.
    @ViewBuilder private func quickOverlay(_ anchor: Anchor<CGRect>?) -> some View {
        if showQuick, let anchor {
            GeometryReader { geo in
                let r = geo[anchor]
                let rows = max(quickActions.count, 1)
                // Between the top of the wordmark and the plus, the rows are as tall as they can be (not past their full height, not under 40 pt).
                let fitting = (r.minY - 12 - Self.quickTopLimit - 2 * NunaQuickMenu.verticalPadding) / CGFloat(rows)
                let rowH = min(NunaQuickMenu.fullRowHeight, max(fitting, NunaQuickMenu.minRowHeight))
                let h = NunaQuickMenu.height(rows, rowHeight: rowH)
                // The menu never rises past the top of the PHMN wordmark: with no room for it between there and the plus, it opens downward.
                let above = r.minY - 12 - h >= Self.quickTopLimit
                let cx = min(r.maxX, geo.size.width - 12) - NunaQuickMenu.width / 2
                let cy = above ? r.minY - 12 - h / 2 : r.maxY + 12 + h / 2
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { setQuick(false) }
                    NunaQuickMenu(actions: quickActions, onPick: { a in
                        setQuick(false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { pendingQuick = a }
                    }, rowHeight: rowH)
                    .position(x: cx, y: cy)
                    .transition(.scale(scale: 0.92, anchor: above ? .bottomTrailing : .topTrailing).combined(with: .opacity))
                    NunaQuickPlus(open: true) { setQuick(false) }.position(x: r.midX, y: r.midY)
                }
            }
            .transition(.opacity)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if editing {
                editScreen
            } else {
                ZStack(alignment: .top) {
                    ScrollView {
                        VStack(spacing: NunaSpacing.section) {
                            // Space for the pinned header; it scrolls away exactly as fast as the header shrinks.
                            Color.clear.frame(height: pinnedHeight(collapse: 0) - 34)
                            if !model.isToday { pastDayBanner }
                            ForEach(sections) { section in
                                sectionView(section)
                                if model.isToday && section == myDayAnchor {
                                    myDayRow
                                    // Under "My Day", close to it: once there are enough days of data to know the person's habits.
                                    if NunaOutlookGate.ready(repo.days) { NunaDailyOutlookCard(review: NunaReviewGate.isEvening()) { showOutlook = true }.padding(.top, -NunaSpacing.section + 12) }
                                }
                            }
                            customizeButton
                        }
                        .padding(.horizontal, NunaSpacing.screenH)
                        .padding(.bottom, 160)
                        .background(NunaScrollOffsetReader { offset in
                        let t = min(max(offset / max(pinnedHeight(collapse: 0) - pinnedHeight(collapse: 1), 1), 0), 1)
                        if abs(t - collapse.t) > 0.004 { collapse.t = t }
                    })
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { await sync.run() }
                    pinnedHeader
                }
            }
        }
        .overlayPreferenceValue(NunaQuickAnchorKey.self) { anchor in
            ZStack { quickOverlay(anchor); quickTip(anchor) }
        }
        .task {
            // Once, the first time Home is on screen: a moment to settle, then the tour of the plus.
            guard !quickTipSeen, model.isToday else { return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !quickTipSeen { withAnimation(.easeOut(duration: 0.25)) { showQuickTip = true } }
        }
        .background(NunaBackdrop())
        .background(NunaQuickRunner(action: $pendingQuick, onAddActivity: { showManual = true }))
        .nunaTodayDestinations()
        .nunaWorkoutDestinations()
        .sheet(isPresented: $showBreath) {
            NavigationStack { NunaBreathView().toolbar(.hidden, for: .navigationBar) }.preferredColorScheme(NunaTheme.colorScheme)
        }
        // The Activity card used to be hidden by default; a layout saved back then keeps it hidden, so it is opened once.
        .task {
            // A layout saved before the monitor pair existed lists what is hidden; a section absent from that list shows, so add it once.
            if !UserDefaults.standard.bool(forKey: NunaTodayDefaults.monitorHiddenKey) {
                UserDefaults.standard.set(true, forKey: NunaTodayDefaults.monitorHiddenKey)
                let raw = hiddenSectionsRaw.trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty {
                    var hidden = TodayLayoutPrefs.decodeHidden(raw)
                    if !hidden.contains(.vitalMonitor) {
                        hidden.append(.vitalMonitor)
                        hiddenSectionsRaw = TodayLayoutPrefs.encodeHidden(hidden)
                    }
                }
            }
            // Highlights took Anya's place and sit right under the rings, so a saved layout that has it further down is moved up once.
            if !UserDefaults.standard.bool(forKey: NunaTodayDefaults.highlightsMovedKey) {
                UserDefaults.standard.set(true, forKey: NunaTodayDefaults.highlightsMovedKey)
                if !sectionOrderRaw.trimmingCharacters(in: .whitespaces).isEmpty {
                    var order = TodayLayoutPrefs.decodeOrder(sectionOrderRaw)
                    if let from = order.firstIndex(of: .synthesis), let hero = order.firstIndex(of: .hero), from != hero + 1 {
                        order.remove(at: from)
                        order.insert(.synthesis, at: (order.firstIndex(of: .hero) ?? -1) + 1)
                        sectionOrderRaw = TodayLayoutPrefs.encode(order)
                    }
                }
            }
            guard !UserDefaults.standard.bool(forKey: NunaTodayDefaults.activityShownKey) else { return }
            UserDefaults.standard.set(true, forKey: NunaTodayDefaults.activityShownKey)
            let raw = hiddenSectionsRaw.trimmingCharacters(in: .whitespaces)
            if !raw.isEmpty {
                var hidden = TodayLayoutPrefs.decodeHidden(raw)
                if hidden.contains(.workouts) {
                    hidden.removeAll { $0 == .workouts }
                    hiddenSectionsRaw = hidden.isEmpty ? "none" : TodayLayoutPrefs.encodeHidden(hidden)
                }
            }
            // And to just under Anya, where it was never placed on a layout saved back then (it sat at the very bottom).
            if !sectionOrderRaw.trimmingCharacters(in: .whitespaces).isEmpty {
                var order = TodayLayoutPrefs.decodeOrder(sectionOrderRaw)
                if let from = order.firstIndex(of: .workouts), let anya = order.firstIndex(of: .synthesis), from > anya + 1 {
                    order.remove(at: from)
                    order.insert(.workouts, at: anya + 1)
                    sectionOrderRaw = TodayLayoutPrefs.encode(order)
                }
            }
        }
        // A saved gym session adds a workout without changing the caches `refreshSeq` follows, so it is a reason to reload on its own.
        // "Detailed tiles": the trend lines under the Key Metrics, over the number of days chosen in their settings.
        .task(id: "\(repo.refreshSeq)-\(keyMetricsDetailed)-\(keyMetricsWindowDays)-\(keyMetricsRaw)") {
            guard keyMetricsDetailed else { return }
            let chosen: [KeyMetric] = keyMetricsRaw.trimmingCharacters(in: .whitespaces).isEmpty
                ? Self.nunaDefaultMetrics : KeyMetricPrefs.decodeEnabled(keyMetricsRaw)
            await sparks.load(repo: repo, metrics: chosen, days: max(keyMetricsWindowDays, 2))
        }
        // Only the cards that open a trend page, and the Sleep performance card (it compares with the night before), need the long history.
        .task(id: "\(repo.refreshSeq)-\(myDashboardRaw)") {
            guard NunaDashPrefs.items(myDashboardRaw, cardsRaw: dashboardCardsRaw).contains(where: {
                if case .page = $0 { return true }
                if case .card(let c) = $0 { return c == .sleep }
                return false
            }) else { return }
            await history.load(repo: repo)
        }
        .background(NunaSavedSessionsWatcher(count: $savedSessions))
        .background(NunaLowBatteryWatcher(pct: $lowBatteryPct, onRecovered: { if lowBatteryDismissed != 0 { lowBatteryDismissed = 0 } }))
        .background(NunaPullSyncBinder(sync: sync))
        .background(NunaStrapIdleWatcher(idle: $strapIdle))
        #if DEBUG
        // `--open-planner`: a debug build opens the Sleep planner once, at launch, to look at it without scrolling Today. Once only: a `.task` runs
        // again every time Today comes back on screen, which would push the planner again each time the person went back.
        // `--open-trend <page>` opens one trend page (a `NunaTrendPage` raw value), once, the same way.
        .task {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "--open-trend"), i + 1 < args.count, let page = NunaTrendPage(rawValue: args[i + 1]),
                  !NunaTodayDebug.openedPlanner else { return }
            NunaTodayDebug.openedPlanner = true
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            pushToday(.trend(page))
        }
        // `--open-metric <key>` opens one metric's page (`avg_hr`, `hrv`), once.
        .task {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "--open-metric"), i + 1 < args.count, !NunaTodayDebug.openedPlanner else { return }
            NunaTodayDebug.openedPlanner = true
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            router.openMetric(args[i + 1])
        }
        // `--open-nap` opens the nap page on today's first nap, once.
        .task {
            guard CommandLine.arguments.contains("--open-nap"), !NunaTodayDebug.openedPlanner else { return }
            NunaTodayDebug.openedPlanner = true
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            pushToday(.sleepNaps(0))
        }
        // `--open-sleep` opens the Sleep detail on last night, once.
        .task {
            guard CommandLine.arguments.contains("--open-sleep"), !NunaTodayDebug.openedPlanner else { return }
            NunaTodayDebug.openedPlanner = true
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            pushToday(.sleep(0))
        }
        // `--open-weather` opens the weather and air page, once.
        .task {
            guard CommandLine.arguments.contains("--open-weather"), !NunaTodayDebug.openedPlanner else { return }
            NunaTodayDebug.openedPlanner = true
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            pushToday(.weatherAir)
        }
        // `--open-plan` opens the plan overview, once.
        .task {
            guard CommandLine.arguments.contains("--open-plan"), !NunaTodayDebug.openedPlanner else { return }
            NunaTodayDebug.openedPlanner = true
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            pushToday(.plan)
        }
        .task {
            guard CommandLine.arguments.contains("--open-planner"), !NunaTodayDebug.openedPlanner else { return }
            NunaTodayDebug.openedPlanner = true
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            pushToday(.smartAlarm)
        }
        #endif
        .onChange(of: model.dayOffset) { _, v in router.todayDayOffset = v }
        .onAppear { router.todayDayOffset = model.dayOffset }
        .task(id: "\(repo.refreshSeq)-\(model.dayOffset)-\(savedSessions)") {
            await model.load(repo: repo, profile: profile)
            dayPlan = model.isToday ? await NunaDayPlanResult.load(repo: repo, profile: profile) : nil
        }
        // The stress card follows the day: every minute it re-reads the curve while the screen is up.
        .task(id: model.dayOffset) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await model.refreshStress(repo: repo)
            }
        }
        .sheet(item: $customize) { destination in
            NunaTodayCustomizeSheet(
                initialDestination: destination,
                order: effectiveOrder, hidden: effectiveHidden,
                defaultHidden: Self.nunaDefaultHidden, defaultOrder: Self.nunaDefaultOrder,
                sectionOrderRaw: $sectionOrderRaw, hiddenSectionsRaw: $hiddenSectionsRaw,
                keyMetricsRaw: $keyMetricsRaw, keyMetricsDetailed: $keyMetricsDetailed,
                keyMetricsWindowDays: $keyMetricsWindowDays,
                dashboardCardsRaw: $dashboardCardsRaw, myDashboardRaw: $myDashboardRaw, hostedCardsRaw: $hostedCardsRaw)
        }
        .sheet(isPresented: $editingQuick) { NunaQuickActionsEditor(raw: $quickRaw).nunaSheetChrome(detents: [.large]) }
        .sheet(isPresented: $showDate) {
            NunaDateSheet(dayOffset: $model.dayOffset).nunaSheetChrome(detents: [.height(470)])
        }
        .onReceive(NotificationCenter.default.publisher(for: .nunaWorkoutsChanged)) { _ in
            Task { await intelligence.analyzeRecent(); await model.load(repo: repo, profile: profile) }
        }
        .sheet(isPresented: $showManual) {
            NunaManualWorkoutSheet(editing: nil) { row, replacing in
                Task {
                    await repo.saveManualWorkout(row, replacing: replacing)
                    await intelligence.analyzeRecent()
                    await model.load(repo: repo, profile: profile)
                }
            }
            .nunaSheetChrome(detents: [.large])
        }
        .sheet(isPresented: $showAddCard) { addCardSheet }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "today") }
        .sheet(isPresented: $showOutlook) { NunaAnyaSheet(context: "today", floating: true, outlook: true, review: NunaReviewGate.isEvening()) }
        .environment(\.nunaAnyaCardContext, "today")
        .environment(\.nunaAnyaRow, true)
    }

    // MARK: Header

    private var showsRings: Bool { sections.contains(.hero) }

    /// The wordmark over the rings, and the room between it and the day: both go as the page scrolls.
    private static let brandHeight: CGFloat = 58

    /// Where the top of the PHMN wordmark is, measured from the top of the safe area: the pinned header's top padding, the row of the bell, the
    /// day and the strap, and the space the wordmark's own line leaves above its letters.
    private static let quickTopLimit: CGFloat = 2 + 46 + (brandHeight - 14) / 2

    /// The level (20 or 10) of a low-battery banner that is due: the strap is low, and no banner at this level or a lower one was put away. Putting
    /// away the 10% banner therefore also silences the 20% one, so a reading that wobbles between 10 and 11 does not bring it back.
    private var lowBatteryLevel: Int? {
        guard showsRings, !strapIdle, let p = lowBatteryPct else { return nil }
        let level = p <= 10 ? 10 : 20
        return (lowBatteryDismissed != 0 && level >= lowBatteryDismissed) ? nil : level
    }

    /// The idle notice shows while the sync banner (which says the same, with the last sync) is not up.
    private var showsIdleBanner: Bool { showsRings && strapIdle && sync.phase == nil }

    private func pinnedHeight(collapse t: CGFloat) -> CGFloat {
        let bar: CGFloat = 52
        guard showsRings else { return bar + 8 }
        let banner: CGFloat = sync.phase == nil ? 0 : (NunaSyncBanner.height + 33) * (1 - t)
        let low: CGFloat = lowBatteryLevel == nil ? 0 : (NunaLowBatteryBanner.height + 16) * (1 - t)
        let idle: CGFloat = showsIdleBanner ? (NunaStrapIdleBanner.height + 16) * (1 - t) : 0
        return bar + 6 + banner + low + idle + Self.brandHeight * (1 - t) + NunaScoreRings.fullHeight + (NunaScoreRings.compactHeight - NunaScoreRings.fullHeight) * t + 8
    }

    /// Bell, the day (with arrows to step it) and the strap on one slim row, then the three score rings. Stays at the top while
    /// the page scrolls under it; the rings shrink as the page moves.
    private var pinnedHeader: some View {
        VStack(spacing: 0) {
            // The bell and the strap at the edges, the day pill on the centre line of the screen (and so of the label and the middle ring), whatever the
            // widths of the two at its sides.
            ZStack {
                dayNav
                HStack(spacing: 8) {
                NunaTodayProfileBadge()
                Spacer(minLength: 0)
                // Pushed into the page's own stack like every other page, so the way back and the tab bar behave as they do elsewhere.
                Button { pushMe(.devices) } label: {
                    NunaLiveStrapChip()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("WHOOP strap"))
                }
            }
            .frame(height: 46)
            if let phase = sync.phase, collapse.t < 0.05 {
                NunaSyncBanner(phase: phase).padding(.horizontal, 4).padding(.top, 28).padding(.bottom, 5).transition(.opacity.combined(with: .move(edge: .top)))
            }
            if showsIdleBanner, collapse.t < 0.05 {
                NunaStrapIdleBanner().padding(.horizontal, 4).padding(.top, 10).padding(.bottom, 6).transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let level = lowBatteryLevel, let p = lowBatteryPct, collapse.t < 0.05 {
                NunaLowBatteryBanner(pct: p) { withAnimation(.easeOut(duration: 0.2)) { lowBatteryDismissed = level } }
                    .padding(.horizontal, 4).padding(.top, 10).padding(.bottom, 6).transition(.opacity.combined(with: .move(edge: .top)))
            }
            if showsRings {
                NunaPinnedBrand(state: collapse, height: Self.brandHeight)
                NunaPinnedRings(state: collapse, charge: model.charge, effort: model.effort, rest: model.rest, effortScale: effortScale)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, NunaSpacing.screenH - 4)
        .padding(.top, 2).padding(.bottom, 8)
        .background(
            NunaBackdrop(top: true)
                .overlay(alignment: .bottom) { NunaPinnedHairline(state: collapse) }
        )
    }

    /// "<  Today  >": a capsule with the arrows at its two ends and the day, in a lighter capsule, between them. The arrows step one day, the middle
    /// opens the calendar.
    private var dayNav: some View {
        HStack(spacing: 0) {
            Button { model.dayOffset += 1 } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .heavy)).frame(width: 30, height: 28).contentShape(Rectangle())
            }
            .foregroundStyle(NunaPalette.textPrimary)
            Button { showDate = true } label: {
                Text(verbatim: dateTitle).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingHead(0.8)).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary).frame(minWidth: 84).padding(.horizontal, 6).frame(height: 28)
                    .background(NunaPalette.textPrimary.opacity(0.14), in: Capsule())
            }
            Button { if model.dayOffset > 0 { model.dayOffset -= 1 } } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).frame(width: 30, height: 28).contentShape(Rectangle())
                    .foregroundStyle(NunaPalette.textPrimary.opacity(model.dayOffset > 0 ? 1 : 0.38))
            }
            .disabled(model.dayOffset == 0)
        }
        .buttonStyle(.plain)
        .background(NunaPalette.textPrimary.opacity(0.07), in: Capsule())
    }

    private var dateTitle: String {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: model.displayDate)
    }

    private var pastDayBanner: some View {
        NunaCard(small: true) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill").foregroundStyle(NunaPalette.textSecondary)
                Text("Viewing a past day. Read only.")
                    .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                Spacer()
                Button("Today") { model.dayOffset = 0 }.buttonStyle(.nuna(.ghost, height: 36))
            }
        }
    }

    private var customizeButton: some View {
        NunaAddCard("Add or arrange cards") { withAnimation(.easeInOut(duration: 0.2)) { editing = true } }
    }

    // MARK: Edit mode

    private func nunaTitle(_ s: TodaySection) -> LocalizedStringKey {
        switch s {
        case .hero: return "Daily scores"
        case .stateChips: return "State chips"
        case .synthesis: return "Highlights"
        case .recoveryVitals: return "Stress monitor"
        case .vitalMonitor: return "Vital and stress monitors"
        case .weekCompare: return "Strain & Recovery"
        case .keyMetrics: return "Key metrics"
        case .workouts: return "Activity"
        case .journal: return "Quick log"
        case .yourCards: return "My Dashboard"
        case .menstrualCycle: return "Menstrual cycle"
        case .heartRate: return "Heart rate"
        case .liveSession: return "Start activity"
        case .addedCards: return "Added cards"
        case .weatherAir: return "Weather and air"
        }
    }

    /// Arrange mode. A native list with the system reorder grip, so dragging works the same way everywhere (hold the grip, then drag)
    /// and VoiceOver gets move actions.
    private var editScreen: some View {
        let visible = effectiveOrder.filter { !effectiveHidden.contains($0) }
        return List {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edit mode").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                        Text("Arrange cards").font(.nuna(size: NunaTypeSize.h1, weight: .heavy, design: NunaType.design))
                            .foregroundStyle(NunaPalette.textPrimary)
                    }
                    Spacer()
                    Button { withAnimation(.easeInOut(duration: 0.2)) { editing = false } } label: { Text("Done") }
                        .buttonStyle(.nuna(.primary, height: 44)).fixedSize()
                }
                Text("Hold the grip on the right, then drag to reorder. Tap X to hide a card.")
                    .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            .moveDisabled(true).plainRow()

            ForEach(Array(visible.enumerated()), id: \.element) { idx, section in
                VStack(spacing: 10) {
                    editFrame(section)
                    if !hiddenSections.isEmpty && (idx % 3 == 0 || idx == visible.count - 1) {
                        NunaAddCard("Add a card here") { addAfter = section; showAddCard = true }
                    }
                }
                .plainRow()
            }
            .onMove { from, to in moveVisible(visible, from: from, to: to) }

            if visible.isEmpty && !hiddenSections.isEmpty {
                NunaAddCard("Add a card here") { addAfter = nil; showAddCard = true }.moveDisabled(true).plainRow()
            }
            VStack(spacing: 10) {
                Button { customize = .today } label: { Label("Card settings", systemImage: "gearshape").lineLimit(1).minimumScaleFactor(0.8) }
                    .buttonStyle(.nuna(.ghost, height: 52, fullWidth: true))
                Button { sectionOrderRaw = ""; hiddenSectionsRaw = ""; keyMetricsRaw = ""; dashboardCardsRaw = ""; myDashboardRaw = ""; hostedCardsRaw = "" } label: { Text("Restore defaults").lineLimit(1).minimumScaleFactor(0.8) }
                    .buttonStyle(.nuna(.ghost, height: 52, fullWidth: true))
            }
            .moveDisabled(true).plainRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 140, for: .scrollContent)
        .environment(\.editMode, .constant(.active))
    }

    /// Puts the dragged card where it was dropped, among the visible ones; hidden cards keep their places.
    private func moveVisible(_ visible: [TodaySection], from: IndexSet, to: Int) {
        var moved = visible
        moved.move(fromOffsets: from, toOffset: to)
        var queue = moved[...]
        let hiddenSet = Set(effectiveHidden)
        let order = effectiveOrder.map { hiddenSet.contains($0) ? $0 : queue.popFirst() ?? $0 }
        persist(order: order)
    }

    private var hiddenSections: [TodaySection] { effectiveOrder.filter { effectiveHidden.contains($0) } }

    private func editFrame(_ section: TodaySection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(nunaTitle(section)).font(.nuna(size: 15.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Button { withAnimation { toggleHidden(section) } } label: {
                    Image(systemName: "xmark").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel(Text("Hide"))
            }
            editPreview(section)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(NunaPalette.ink.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .accessibilityAction(named: Text("Move up")) { move(section, by: -1) }
        .accessibilityAction(named: Text("Move down")) { move(section, by: 1) }
    }

    /// A compact stand-in for the card, inside the dashed frame.
    @ViewBuilder private func editPreview(_ section: TodaySection) -> some View {
        let inner = RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NunaPalette.cardHighlight)
        switch section {
        case .hero:
            HStack {
                miniRing(model.charge.pct, "Recovery", NunaPalette.charge, "%")
                miniRing(model.effort.map { Double(UnitFormatter.effortDisplay($0, scale: effortScale).replacingOccurrences(of: ",", with: ".")) ?? 0 }, "Strain", NunaPalette.effort, "", fraction: (model.effort ?? 0) / 100)
                miniRing(model.rest, "Sleep", NunaPalette.rest, "%")
            }
            .padding(.vertical, 12).frame(maxWidth: .infinity).background(inner)
        case .stateChips:
            // Only a picture of the chips while arranging: tapping one must not open its page.
            HStack(spacing: 8) { Spacer(minLength: 0); synthesisChips; heartRatePill }.allowsHitTesting(false)
        case .synthesis:
            previewRow("sparkles", nil, String(localized: "Highlights"), "What stands out today").background(inner)
        case .recoveryVitals:
            previewRow(NunaIcons.stress, NunaPalette.charge, model.stress.map { String(localized: "Stress \(String(format: "%.1f", locale: AppLanguage.activeLocale, $0)) / 3") } ?? String(localized: "Stress"), "Intraday curve").background(inner)
        case .weekCompare:
            previewRow("chart.bar.xaxis", NunaPalette.charge, String(localized: "Strain & Recovery"), "Last 7 days").background(inner)
        case .vitalMonitor:
            HStack(spacing: 8) {
                previewRow("heart.text.square", NunaPalette.charge, String(localized: "Vital signs"), "Within range").background(inner)
                previewRow(NunaIcons.stress, NunaPalette.warning, String(localized: "Stress monitor"), "Latest reading").background(inner)
            }
        case .keyMetrics:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(metricTiles.prefix(4)) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: t.value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(inner)
                }
            }
        case .workouts:
            previewRow("flame", NunaPalette.effortText,
                       model.workouts.last.map { WorkoutSource.displaySport($0.sport) } ?? String(localized: "No activity yet"),
                       "Latest activity").background(inner)
        case .journal:
            HStack(spacing: 8) {
                miniChip("Journal"); Spacer(minLength: 0)
            }
        case .yourCards: previewRow("rectangle.stack", nil, String(localized: "My Dashboard"), "Cards you chose").background(inner)
        case .menstrualCycle: previewRow(NunaIcons.cycle, NunaPalette.alertText, String(localized: "Menstrual cycle"), "Cycle awareness").background(inner)
        case .heartRate: previewRow(NunaIcons.heartRate, NunaPalette.alertText, String(localized: "Heart rate"), "Live").background(inner)
        case .liveSession: previewRow("play", NunaPalette.charge, String(localized: "Start activity"), "Live session").background(inner)
        case .addedCards: previewRow("square.stack", nil, String(localized: "Added cards"), "From Sleep and Trends").background(inner)
        case .weatherAir: previewRow("cloud.sun", nil, String(localized: "Weather and air"), "The day ahead and the best hours to train").background(inner)
        }
    }

    private func previewRow(_ icon: String, _ tint: Color?, _ title: String, _ sub: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            NunaIconTile(icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2)
                Text(sub).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniChip(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.nuna(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            .padding(.horizontal, 12).frame(height: 32).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
    }

    private func miniRing(_ value: Double?, _ label: LocalizedStringKey, _ color: Color, _ unit: String, fraction: Double? = nil) -> some View {
        VStack(spacing: 6) {
            NunaRingGauge(fraction: fraction ?? ((value ?? 0) / 100), color: color, size: 56, lineWidth: 6) {
                Text(verbatim: value.map { String(format: "%.0f", $0) + unit } ?? "–").font(.nuna(size: 13, weight: .bold, design: NunaType.design))
                    .foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6)
            }
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func move(_ section: TodaySection, by delta: Int) {
        var order = effectiveOrder
        guard let i = order.firstIndex(of: section), order.indices.contains(i + delta) else { return }
        order.swapAt(i, i + delta)
        persist(order: order)
    }

    private func persist(order: [TodaySection]) {
        sectionOrderRaw = TodayLayoutPrefs.encode(order)
        if hiddenSectionsRaw.trimmingCharacters(in: .whitespaces).isEmpty {
            hiddenSectionsRaw = TodayLayoutPrefs.encodeHidden(Self.nunaDefaultHidden)
        }
    }

    private func toggleHidden(_ section: TodaySection) {
        var hidden = effectiveHidden
        if let i = hidden.firstIndex(of: section) {
            hidden.remove(at: i)
        } else {
            // Keep at least one card on Today.
            guard effectiveOrder.filter({ !hidden.contains($0) }).count > 1 else { return }
            hidden.append(section)
        }
        if sectionOrderRaw.trimmingCharacters(in: .whitespaces).isEmpty { sectionOrderRaw = TodayLayoutPrefs.encode(effectiveOrder) }
        // Always write an explicit value, so the Nuna defaults stop applying once the person has chosen.
        hiddenSectionsRaw = hidden.isEmpty ? "none" : TodayLayoutPrefs.encodeHidden(hidden)
    }

    // MARK: Add a card

    private var hiddenDashboardItems: [NunaDashItem] {
        let on = NunaDashPrefs.items(myDashboardRaw, cardsRaw: dashboardCardsRaw)
        return NunaDashItem.canonicalOrder.filter { !on.contains($0) }
    }
    private var hiddenHostedCards: [HostedCard] {
        let on = HostedCardPrefs.decodeEnabled(hostedCardsRaw)
        return HostedCard.canonicalOrder.filter { !on.contains($0) }
    }

    /// Everything that can be put on Today: a hidden card, one more entry for Your cards, or a card from Sleep or Trends.
    private var addCardSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a card").font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).padding(.top, 22)
                if hiddenSections.isEmpty && hiddenDashboardItems.isEmpty && hiddenHostedCards.isEmpty {
                    Text("Every card is already on Today.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                if !hiddenSections.isEmpty {
                    NunaSettingsGroup("Hidden cards") {
                        ForEach(Array(hiddenSections.enumerated()), id: \.element.id) { idx, sec in
                            if idx > 0 { NunaDivider() }
                            Button { add(sec, after: addAfter); showAddCard = false } label: {
                                NunaListRow(LocalizedStringKey(sec.nunaName), description: LocalizedStringKey(sec.nunaNote), systemImage: sec.customizationIcon) { addLabel }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !hiddenDashboardItems.isEmpty {
                    NunaSettingsGroup("For My Dashboard") {
                        ForEach(Array(hiddenDashboardItems.enumerated()), id: \.element.id) { idx, item in
                            if idx > 0 { NunaDivider() }
                            Button {
                                let all = NunaDashPrefs.items(myDashboardRaw, cardsRaw: dashboardCardsRaw) + [item]
                                myDashboardRaw = NunaDashPrefs.encode(all)
                                dashboardCardsRaw = DashboardCardPrefs.encode(all.compactMap { if case .card(let c) = $0 { return c } else { return nil } })
                                add(.yourCards, after: addAfter); showAddCard = false
                            } label: { NunaListRow(LocalizedStringKey(item.title), subtitle: LocalizedStringKey(item.subtitle ?? ""), systemImage: item.icon) { addLabel } }.buttonStyle(.plain)
                        }
                    }
                }
                ForEach(hostedGroups, id: \.name) { g in
                    NunaSettingsGroup(LocalizedStringKey(String(localized: "From \(g.name)"))) {
                        ForEach(Array(g.cards.enumerated()), id: \.element.id) { idx, card in
                            if idx > 0 { NunaDivider() }
                            Button {
                                hostedCardsRaw = HostedCardPrefs.encode(HostedCardPrefs.decodeEnabled(hostedCardsRaw) + [card])
                                add(.addedCards, after: addAfter); showAddCard = false
                            } label: { NunaListRow(LocalizedStringKey(card.title), systemImage: card.customizationIcon) { addLabel } }.buttonStyle(.plain)
                        }
                    }
                }
                Button { showAddCard = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { customize = .today } } label: {
                    Text("Card settings").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 50).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 24)
        }
        .background(NunaPalette.card.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .nunaSheetChrome(detents: [.medium, .large])
    }

    private var addLabel: some View { Text("Add").font(.nuna(size: 14, weight: .heavy)).foregroundStyle(NunaPalette.charge) }

    private var hostedGroups: [(name: String, cards: [HostedCard])] {
        var order: [String] = []; var buckets: [String: [HostedCard]] = [:]
        for c in hiddenHostedCards { if buckets[c.origin] == nil { order.append(c.origin) }; buckets[c.origin, default: []].append(c) }
        return order.map { (name: $0, cards: buckets[$0] ?? []) }
    }

    /// Unhide `section` and place it right after `anchor` (or at the end).
    private func add(_ section: TodaySection, after anchor: TodaySection?) {
        var order = effectiveOrder
        order.removeAll { $0 == section }
        let at = anchor.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? order.endIndex
        order.insert(section, at: at)
        var hidden = effectiveHidden
        hidden.removeAll { $0 == section }
        sectionOrderRaw = TodayLayoutPrefs.encode(order)
        hiddenSectionsRaw = hidden.isEmpty ? "none" : TodayLayoutPrefs.encodeHidden(hidden)
    }

    // MARK: Sections

    @ViewBuilder private func sectionView(_ section: TodaySection) -> some View {
        switch section {
        case .hero:
            // The rings themselves are pinned at the top; the state chips are a section of their own.
            Color.clear.frame(height: 0)
                .background {
                    if model.isToday {
                        NunaIllnessNotifier()
                        NunaHighlightsTracker(feed: highlightsFeed, loaded: model.loaded, workouts: model.workouts, calibrating: calibrationStages)
                    }
                }
        case .stateChips:
            if readyLine != nil || model.charge.pct != nil {
                // Readiness, Charge state and heart rate: three chips of one shape on one line.
                HStack(spacing: 8) { Spacer(minLength: 0); synthesisChips; heartRatePill }
            }
        case .synthesis:
            if model.isToday {
                NunaHighlightsCard(charge: model.charge.pct, chargeScored: { if case .scored = model.charge { return true } else { return false } }(), hrv: model.hrv, restingHr: model.restingHr, sleepMinutes: model.sleepMinutes,
                                   effort: model.effort, stressNow: model.stressCurve.flatMap(StressDayCurve.latestLevel),
                                   stressHighMin: model.stressCurve.map(StressDayCurve.highMinutes),
                                   rest: model.rest, workouts: model.workouts, calibrating: calibrationStages, feed: highlightsFeed,
                                   onBreathe: { showBreath = true }, onWindDown: { pushToday(.windDown) }, onOutlook: { showOutlook = true },
                                   onJournal: { router.openJournal(day: 1) }, onTrend: { pushToday(.trend(.charge)) }, onPlan: { pushToday(.plan) },
                                   onRecommended: { router.openRecommendedSettings = true })
            }
        case .recoveryVitals:
            if !model.stressStatus.isReady {
                // Still learning the person: no stress figure, only how far along it is.
                if model.loaded { NunaStressCalibrationCard(nights: model.stressStatus.nights) }
            } else if model.stress != nil || model.stressCurve != nil {
                NunaStressCard(score: model.stress, curve: model.stressCurve, baseline: model.stressBaseline, isToday: model.isToday, workouts: model.workouts)
            }
#if DEBUG
            // `--demo-stress`: the demo year has no intraday stress, so the card is drawn from a made-up day to look at it.
            if CommandLine.arguments.contains("--demo-stress"), model.isToday {
                NunaStressCard(score: 1.0, curve: NunaStressDemo.curve(), baseline: 1.2, isToday: true, workouts: NunaStressDemo.workouts())
            }
#endif
        case .weekCompare:
            NunaWeekCompare(endDay: model.displayDate, effortScale: effortScale)
        case .vitalMonitor:
            NunaMonitorPackCard(hrv: model.hrv, restingHr: model.restingHr, spo2: model.spo2, respiratory: model.respiratory,
                                skinTemp: model.extras["skin_temp"], stress: model.stress, stressCurve: model.stressCurve,
                                stressNights: model.stressStatus.isReady || !model.loaded ? nil : model.stressStatus.nights)
        case .keyMetrics:
            let tiles = metricTiles
            if !tiles.isEmpty {
                NunaMetricsGrid(tiles: tiles, layout: metricsLayout, header: AnyView(
                    NunaTitleRow(title: "Key metrics") {
                        // Three separate targets, each 40 pt wide, so a thumb lands on the one it means.
                        HStack(spacing: 0) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    metricsLayoutRaw = (metricsLayout == .cards ? NunaMetricsLayout.list : .cards).rawValue
                                }
                            } label: {
                                Image(systemName: metricsLayout == .cards ? "list.bullet" : "square.grid.2x2")
                                    .font(.nuna(size: 14, weight: .bold)).frame(width: 40, height: 40).contentShape(Rectangle())
                            }
                            .accessibilityLabel(Text(metricsLayout == .cards ? "Show as list" : "Show as cards"))
                            Button { customize = .keyMetrics } label: {
                                Image(systemName: "gearshape").font(.nuna(size: 14, weight: .bold)).frame(width: 40, height: 40).contentShape(Rectangle())
                            }
                            .accessibilityLabel(Text("Edit"))
                            NavigationLink(value: NunaTodayRoute.allMetrics) {
                                Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .heavy)).frame(width: 40, height: 40).contentShape(Rectangle())
                            }
                            .accessibilityLabel(Text("All"))
                        }
                        // The last glyph still lines up with the card edge below.
                        .padding(.trailing, -13)
                    }
                ))
            }
        case .workouts:
            // Sleep and every workout of the day, in the order they happened. Always there, empty or not, with the two ways to log one.
            NunaTodayActivities(workouts: model.workouts.sorted { $0.startTs < $1.startTs }, effortScale: effortScale,
                                dayStart: Calendar.current.startOfDay(for: model.displayDate), sleepMinutes: model.sleepMinutes, isToday: model.isToday,
                                onAdd: { showManual = true },
                                onStart: { router.requestedDestination = .activeWorkout })
            if model.isToday { NunaTonightSleep() }
        case .heartRate:
            NunaLiveHR(isToday: model.isToday) { hr in
                NavigationLink(value: NunaTodayRoute.deepTimeline) {
                    NunaCard(small: true) {
                        NunaListRow("Heart Rate", systemImage: NunaIcons.heartRate, tint: NunaPalette.alertText, showsChevron: true) {
                            Text(verbatim: "\(hr)").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        case .journal:
            NunaJournalWeekCard { router.requestedDestination = .journal }
        case .liveSession where model.isToday:
            Button { router.requestedDestination = .liveSession } label: {
                Label("Start activity", systemImage: "play.fill")
            }
            .buttonStyle(.nuna(.primary, height: 52, fullWidth: true))
        case .yourCards:
            let rows = yourCardRows()
            VStack(spacing: NunaSpacing.section) {
                // The plan sits above My Dashboard and draws nothing until a goal is set.
                NunaPlanCard()
                if !rows.isEmpty {
                    NunaDashboardCards(rows: rows, onCoach: { showCoach = true }, onEdit: { customize = .yourCards })
                }
            }
        case .addedCards:
            let rows = addedCardRows()
            if !rows.isEmpty { NunaRowsCard(rows: rows) { showCoach = true } }
        case .menstrualCycle:
            NunaCycleGate {
                NavigationLink(value: NunaTodayRoute.cycle) {
                    NunaCard(small: true) {
                        NunaListRow("Menstrual Cycle", description: "Cycle awareness", systemImage: NunaIcons.cycle,
                                    tint: NunaPalette.alertText, showsChevron: true)
                    }
                }
                .buttonStyle(.plain)
            }
        case .weatherAir:
            NunaWeatherAirCard()
        case .liveSession:
            EmptyView()
        }
    }

    private var metricsLayout: NunaMetricsLayout { NunaMetricsLayout(rawValue: metricsLayoutRaw) ?? .cards }

    /// What the Default Today synthesis shows beside its greeting, minus the greeting: the readiness chip with its word (Push, Maintain,
    /// Rest) and the Charge state (Solid, Last night, Calibrating, No data), from the same engine and display state.
    @ViewBuilder private var synthesisChips: some View {
        if model.isToday, let level = model.readiness?.level, let word = Self.readinessWord(level) {
            let tone = level == .primed ? NunaPalette.charge : (level == .balanced ? NunaPalette.effortText : NunaPalette.warning)
            NavigationLink(value: NunaTodayRoute.readiness) {
                todayChip(icon: .symbol("bolt.fill"), text: Text(verbatim: word), tint: tone)
            }.buttonStyle(.plain)
        }
        if model.charge != .noData {
            NavigationLink(value: NunaTodayRoute.chargeState) {
                todayChip(icon: .dot(model.charge.pct.map(nunaChargeColor) ?? NunaPalette.textMuted), text: Text(verbatim: Self.chargeStateEnglish(model.charge)), tint: nil)
            }.buttonStyle(.plain)
        }
    }

    private enum ChipIcon { case symbol(String), dot(Color) }

    /// One chip shape for the whole row: the same height, radius, type and padding. A tint colours the readiness chip; the others are neutral.
    private func todayChip(icon: ChipIcon, text: Text, tint: Color?) -> some View {
        HStack(spacing: 5) {
            switch icon {
            case .symbol(let name): Image(systemName: name).font(.nuna(size: 10, weight: .bold))
            case .dot(let c): Circle().fill(c).frame(width: 6, height: 6)
            }
            text.font(.nuna(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint ?? NunaPalette.textPrimary)
        .padding(.horizontal, 9).frame(height: 24)
        .background(tint.map { NunaPalette.tint($0) } ?? NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous).strokeBorder(tint?.opacity(0.35) ?? NunaPalette.hairline, lineWidth: 1))
        .fixedSize()
    }

    /// The Charge state word, always in English: the chips under the rings keep one language whatever the app language is.
    private static func chargeStateEnglish(_ c: LiquidTodayView.ChargeDisplay) -> String {
        switch c {
        case .scored: return "Solid"
        case .carried: return "Last night"
        case .calibrating: return "Calibrating"
        case .noData: return "No data"
        }
    }

    private static func readinessWord(_ level: ReadinessEngine.Level) -> String? {
        switch level {
        case .primed: return "Push"
        case .balanced: return "Maintain"
        case .strained, .rundown: return "Rest"
        case .insufficient: return nil
        }
    }

    @ViewBuilder private var heartRatePill: some View {
        NunaLiveHR(isToday: model.isToday) { hr in
            NavigationLink(value: NunaTodayRoute.deepTimeline) {
                todayChip(icon: .symbol("heart.fill"), text: Text(verbatim: "\(hr)"), tint: nil)
            }
            .buttonStyle(.plain)
        }
    }

    private var readyLine: LocalizedStringKey? {
        guard model.isToday, let level = model.readiness?.level else { return nil }
        switch level {
        case .primed: return "Ready for a hard session"
        case .balanced: return "Ready for a moderate load"
        case .strained, .rundown: return "Take it easy today"
        case .insufficient: return nil
        }
    }

    /// The same one-line read the Default Today synthesis shows.
    private var synthLine: String {
        guard let level = model.readiness?.level else { return String(localized: "Still learning your baseline.") }
        switch level {
        case .primed: return String(localized: "You're primed. A hard session should land well today.")
        case .balanced: return String(localized: "You're in a good spot for training.")
        case .strained: return String(localized: "Signals are down a touch. Keep it easy today.")
        case .rundown: return String(localized: "Your body is asking for rest. Prioritise recovery today.")
        case .insufficient: return String(localized: "Still learning your baseline.")
        }
    }

    private var metricTiles: [NunaMetricTile] {
        let chosen: [KeyMetric] = keyMetricsRaw.trimmingCharacters(in: .whitespaces).isEmpty
            ? Self.nunaDefaultMetrics : KeyMetricPrefs.decodeEnabled(keyMetricsRaw)
        let enabled = chosen.filter { ![.charge, .effort].contains($0) }
        func fmt(_ v: Double?, _ digits: Int = 0) -> String {
            v.map { String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, $0) } ?? "–"
        }
        func route(_ key: String, _ source: String = "my-whoop") -> NunaTodayRoute? {
            MetricCatalog.metric(key: key, source: source).map { .metric($0) }
        }
        /// Every figure is compared with the one before it: a triangle when it moved, a dot when it did not or there is nothing earlier.
        func cmp(_ current: Double?, _ previous: Double?, _ decimals: Int = 0, good: Bool?, format: ((Double) -> String)? = nil) -> NunaTrend? {
            NunaTrend.make(current: current, previous: previous, decimals: decimals, upIsGood: good, format: format)
        }
        func before(_ value: Double?, _ delta: Double?) -> Double? { value.flatMap { v in delta.map { v - $0 } } }
        let stepsRoute = MetricCatalog.todayStepsMetric(hasMeasuredSteps: model.steps != nil && !model.stepsFromPhone, hasImportedSteps: model.stepsFromPhone).map { NunaTodayRoute.metric($0) }
        func tile(_ m: KeyMetric, _ label: LocalizedStringKey, _ value: String, _ unit: String, _ route: NunaTodayRoute?,
                  _ icon: String, _ tint: Color?, trend: NunaTrend?) -> NunaMetricTile {
            NunaMetricTile(id: m.rawValue, label: label, value: value, unit: unit, route: route,
                           trend: trend, icon: icon, tint: tint,
                           spark: keyMetricsDetailed ? sparks.values[m.rawValue] : nil)
        }
        return enabled.map { m in
            switch m {
            case .hrv:
                return tile(m, "HRV", fmt(model.hrv), "ms", route("hrv"), "met:heart-rate-variability", NunaPalette.charge, trend: cmp(model.hrv, before(model.hrv, model.hrvDelta), good: true))
            case .restingHr:
                return tile(m, "Resting HR", fmt(model.restingHr), "bpm", route("rhr"), "met:resting-heart-rate", NunaPalette.alertText, trend: cmp(model.restingHr, before(model.restingHr, model.restingHrDelta), good: false))
            case .bloodOxygen:
                return tile(m, "Blood Oxygen", fmt(model.spo2), "%", route("spo2"), "vital:spo2", NunaPalette.effortText, trend: cmp(model.spo2, before(model.spo2, model.spo2Delta), good: true))
            case .respiratory:
                return tile(m, "Respiratory", fmt(model.respiratory, 1), "/min", route("resp_rate"), NunaIcons.respiratory, NunaPalette.effortText, trend: cmp(model.respiratory, before(model.respiratory, model.respiratoryDelta), 1, good: nil))
            case .steps:
                return tile(m, "Steps", fmt(model.steps), "", stepsRoute, NunaIcons.steps, NunaPalette.charge, trend: cmp(model.steps, model.previous["steps"], good: true))
            case .calories:
                return tile(m, "Calories", fmt(model.calories), "kcal", route("energy_kcal"), NunaIcons.calories, NunaPalette.effortText, trend: cmp(model.calories, model.previous["calories"], good: nil))
            case .weight:
                return tile(m, "Weight", fmt(model.extras["weight"], 1), "kg", route("weight", "apple-health"), NunaIcons.weight, NunaPalette.effortText,
                            trend: cmp(model.extras["weight"], model.previous["weight"], 1, good: nil))
            case .skinTemp:
                return tile(m, "Skin Temp", fmt(model.extras["skin_temp"], 1), "°C", route("skin_temp"), "vital:temp", NunaPalette.alertText,
                            trend: cmp(model.extras["skin_temp"], model.previous["skin_temp"], 1, good: nil))
            case .rest:
                return tile(m, "Sleep", model.sleepMinutes.map { NunaSleepFormat.duration($0) } ?? "–", "", .sleep(0), NunaIcons.sleep, NunaPalette.restText,
                            trend: cmp(model.sleepMinutes, model.previous["sleep"], good: true, format: { NunaSleepFormat.duration($0) }))
            case .charge, .effort: return NunaMetricTile(id: m.rawValue, label: "", value: "", unit: "", route: nil)
            }
        }
    }
}

/// Reports how far the scroll view it sits behind has scrolled (0 at the top, negative bounce clamped), by observing the
/// enclosing UIScrollView's content offset. SwiftUI offers no scroll offset on iOS 17.
struct NunaScrollOffsetReader: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView { Probe() }

    func updateUIView(_ view: UIView, context: Context) {
        (view as? Probe)?.onChange = onChange
    }

    private final class Probe: UIView {
        var onChange: ((CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observation = nil
            guard window != nil else { return }
            // The probe is the scroll view's background, so the scroll view is somewhere up the chain.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var v: UIView? = self.superview
                while let cur = v, !(cur is UIScrollView) { v = cur.superview }
                guard let scroll = v as? UIScrollView else { return }
                self.observation = scroll.observe(\.contentOffset, options: [.initial, .new]) { [weak self] sv, _ in
                    self?.onChange?(max(0, sv.contentOffset.y + sv.adjustedContentInset.top))
                }
            }
        }
    }
}

/// Lays its children out left to right and wraps to a new line when the next one does not fit. Each child keeps its natural width.
struct NunaFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > w { y += lineH + lineSpacing; x = 0; lineH = 0 }
            x += s.width + spacing; lineH = max(lineH, s.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + lineH)
    }

    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > b.minX, x + s.width > b.maxX { y += lineH + lineSpacing; x = b.minX; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; lineH = max(lineH, s.height)
        }
    }
}
#endif
