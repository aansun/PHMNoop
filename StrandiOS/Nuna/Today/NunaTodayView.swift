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
struct NunaTodayView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var updateStore: UpdateStore
    @EnvironmentObject private var live: LiveState

    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(HydrationStore.enabledKey) private var hydrationEnabled = false
    @AppStorage(TodayLayoutPrefs.orderKey) private var sectionOrderRaw = ""
    @AppStorage(TodayLayoutPrefs.hiddenKey) private var hiddenSectionsRaw = ""
    @AppStorage(KeyMetricPrefs.layoutKey) private var keyMetricsRaw = ""
    @AppStorage("today.keyMetricsDetailed") private var keyMetricsDetailed = false
    @AppStorage("today.keyMetricsWindowDays") private var keyMetricsWindowDays = 14
    @AppStorage(DashboardCardPrefs.selectionKey) private var dashboardCardsRaw = ""
    @AppStorage(HostedCardPrefs.selectionKey) private var hostedCardsRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    @StateObject private var model = NunaTodayModel()
    @State private var showCustomize = false
    @State private var showQuick = false
    @State private var showDate = false
    @State private var showInbox = false
    @State private var showCoach = false

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var sections: [TodaySection] {
        TodayLayoutPrefs.visibleOrder(orderRaw: sectionOrderRaw, hiddenRaw: hiddenSectionsRaw)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: NunaSpacing.section) {
                    header
                    datePill
                    if !model.isToday { pastDayBanner }
                    ForEach(sections) { section in sectionView(section) }
                    customizeButton
                }
                .padding(.horizontal, NunaSpacing.screenH)
                .padding(.top, 8)
                .padding(.bottom, 160)
            }
            .scrollIndicators(.hidden)

            if model.isToday {
                NunaFAB { showQuick = true }
                    .padding(.trailing, NunaSpacing.screenH)
                    .padding(.bottom, 104)
            }
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .task(id: "\(repo.refreshSeq)-\(model.dayOffset)") { await model.load(repo: repo, profile: profile) }
        .sheet(isPresented: $showCustomize) {
            TodayCustomizationSheet(
                initialDestination: .today,
                sectionOrderRaw: $sectionOrderRaw, hiddenSectionsRaw: $hiddenSectionsRaw,
                keyMetricsRaw: $keyMetricsRaw, keyMetricsDetailed: $keyMetricsDetailed,
                keyMetricsWindowDays: $keyMetricsWindowDays,
                dashboardCardsRaw: $dashboardCardsRaw, hostedCardsRaw: $hostedCardsRaw)
        }
        .sheet(isPresented: $showQuick) {
            NunaQuickSheet(hydrationEnabled: hydrationEnabled, coachEnabled: coachEnabled)
                .nunaSheetChrome(detents: [.medium, .large])
        }
        .sheet(isPresented: $showDate) {
            NunaDateSheet(dayOffset: $model.dayOffset).nunaSheetChrome(detents: [.large])
        }
        .sheet(isPresented: $showInbox) { UpdatesInboxView(onClose: { showInbox = false }) }
        .sheet(isPresented: $showCoach) { CoachLauncherSheet(context: "today") }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Today")
                .font(.system(size: NunaTypeSize.h1, weight: .bold, design: .rounded))
                .foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 8)
            Button { router.openDevices() } label: {
                NunaChip(live.connected ? "Connected" : "Not connected",
                         systemImage: "dot.radiowaves.left.and.right",
                         color: live.connected ? NunaPalette.charge : NunaPalette.warning)
                    .lineLimit(1).fixedSize()
            }
            .buttonStyle(.plain)
            Button { showInbox = true } label: {
                Image(systemName: updateStore.unreadCount > 0 ? "bell.badge.fill" : "bell.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel(Text("Updates"))
        }
    }

    private var datePill: some View {
        HStack {
            Button { showDate = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar").font(.system(size: 14, weight: .bold))
                    Text(verbatim: dateTitle).font(.system(size: 14, weight: .bold))
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(NunaPalette.textPrimary)
                .padding(.horizontal, 14).frame(height: 40)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var dateTitle: String {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        return f.string(from: model.displayDate)
    }

    private var pastDayBanner: some View {
        NunaCard(small: true) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill").foregroundStyle(NunaPalette.textSecondary)
                Text("Viewing a past day. Read only.")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                Spacer()
                Button("Today") { model.dayOffset = 0 }.buttonStyle(.nuna(.ghost, height: 36))
            }
        }
    }

    private var customizeButton: some View {
        Button { showCustomize = true } label: {
            Label("Customise cards", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.nuna(.ghost, height: 48, fullWidth: true))
        .padding(.top, 4)
    }

    // MARK: Sections

    @ViewBuilder private func sectionView(_ section: TodaySection) -> some View {
        switch section {
        case .hero:
            NunaScoreCard(charge: model.charge, effort: model.effort, rest: model.rest,
                          effortScale: effortScale, readyLine: nil, heartRate: model.isToday ? live.heartRate : nil)
        case .synthesis:
            if coachEnabled && model.isToday { NunaAnyaCard(title: "What should I focus on today?") { showCoach = true } }
        case .keyMetrics:
            let tiles = metricTiles
            if !tiles.isEmpty { NunaMetricsGrid(tiles: tiles) }
        case .workouts:
            if let w = model.workouts.last { NunaActivityRow(workout: w, effortScale: effortScale) }
        case .recoveryVitals:
            if model.stress != nil { NunaStressCard(stress: model.stress) }
        case .heartRate:
            if model.isToday, let hr = live.heartRate {
                NavigationLink(value: TabRoute.fullDayChart) {
                    NunaCard(small: true) {
                        NunaListRow("Heart Rate", systemImage: "heart.fill", tint: NunaPalette.alertText, showsChevron: true) {
                            Text(verbatim: "\(hr) bpm").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        case .journal:
            NavigationLink(value: TabRoute.health) {
                NunaCard(small: true) {
                    NunaListRow("Journal", subtitle: "How did yesterday go?", systemImage: "book.closed.fill", showsChevron: true)
                }
            }
            .buttonStyle(.plain)
        case .liveSession where model.isToday:
            Button { router.requestedDestination = .liveSession } label: {
                Label("Start session", systemImage: "play.fill")
            }
            .buttonStyle(.nuna(.primary, height: 52, fullWidth: true))
        case .liveSession, .yourCards, .menstrualCycle, .addedCards:
            EmptyView()
        }
    }

    private var metricTiles: [NunaMetricTile] {
        let enabled = KeyMetricPrefs.decodeEnabled(keyMetricsRaw)
            .filter { ![.charge, .effort, .rest].contains($0) }
        func fmt(_ v: Double?, _ digits: Int = 0) -> String {
            v.map { String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, $0) } ?? "–"
        }
        return enabled.compactMap { m in
            switch m {
            case .hrv:         return NunaMetricTile(id: m.rawValue, label: "HRV", value: fmt(model.hrv), unit: "ms", route: .metric("hrv"))
            case .restingHr:   return NunaMetricTile(id: m.rawValue, label: "Resting HR", value: fmt(model.restingHr), unit: "bpm", route: .metric("resting_hr"))
            case .bloodOxygen: return NunaMetricTile(id: m.rawValue, label: "Blood Oxygen", value: fmt(model.spo2), unit: "%", route: .metric("spo2"))
            case .respiratory: return NunaMetricTile(id: m.rawValue, label: "Respiratory", value: fmt(model.respiratory, 1), unit: "/min", route: .metric("resp_rate"))
            case .steps:       return NunaMetricTile(id: m.rawValue, label: "Steps", value: fmt(model.steps), unit: "", route: .metric("steps"))
            case .calories:    return NunaMetricTile(id: m.rawValue, label: "Calories", value: fmt(model.calories), unit: "kcal", route: .metric("active_kcal"))
            case .weight, .skinTemp, .charge, .effort, .rest: return nil
            }
        }
    }
}
#endif
