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
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var intelligence: IntelligenceEngine

    @AppStorage("noop.coachEnabled") var coachEnabled = true
    @AppStorage(HydrationStore.enabledKey) var hydrationEnabled = false
    @AppStorage(TodayLayoutPrefs.orderKey) private var sectionOrderRaw = ""
    @AppStorage(TodayLayoutPrefs.hiddenKey) private var hiddenSectionsRaw = ""
    @AppStorage(KeyMetricPrefs.layoutKey) private var keyMetricsRaw = ""
    @AppStorage("today.keyMetricsDetailed") private var keyMetricsDetailed = false
    @AppStorage("today.keyMetricsWindowDays") private var keyMetricsWindowDays = 14
    @AppStorage(DashboardCardPrefs.selectionKey) var dashboardCardsRaw = ""
    @AppStorage(HostedCardPrefs.selectionKey) var hostedCardsRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    @StateObject var model = NunaTodayModel()
    @State private var showCustomize = false
    @State private var showQuick = false
    @State private var showDate = false
    @State private var showInbox = false
    @State private var showCoach = false
    @State private var editing = false
    @State private var showManual = false

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var sections: [TodaySection] {
        TodayLayoutPrefs.visibleOrder(orderRaw: sectionOrderRaw, hiddenRaw: hiddenSectionsRaw)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: NunaSpacing.section) {
                    header
                    if editing {
                        editList
                    } else {
                        datePill
                        if !model.isToday { pastDayBanner }
                        ForEach(sections) { section in sectionView(section) }
                        customizeButton
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH)
                .padding(.top, 8)
                .padding(.bottom, 160)
            }
            .scrollIndicators(.hidden)

            if model.isToday && !editing {
                NunaFAB { showQuick = true }
                    .padding(.trailing, NunaSpacing.screenH)
                    .padding(.bottom, 104)
            }
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .nunaTodayDestinations()
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
            NunaQuickSheet(hydrationEnabled: hydrationEnabled, coachEnabled: coachEnabled,
                           onAddActivity: { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showManual = true } })
                .nunaSheetChrome(detents: [.medium, .large])
        }
        .sheet(isPresented: $showDate) {
            NunaDateSheet(dayOffset: $model.dayOffset).nunaSheetChrome(detents: [.large])
        }
        .sheet(isPresented: $showManual) {
            ManualWorkoutSheet(editing: nil) { row, replacing in
                Task {
                    await repo.saveManualWorkout(row, replacing: replacing)
                    await intelligence.analyzeRecent()
                    await model.load(repo: repo, profile: profile)
                }
            }
            .preferredColorScheme(.dark)
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
        Button { withAnimation(.easeInOut(duration: 0.2)) { editing = true } } label: {
            Label("Customise cards", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.nuna(.ghost, height: 48, fullWidth: true))
        .padding(.top, 4)
    }

    // MARK: Edit mode

    private var editList: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit cards").font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text("Hide a card, or move it up or down. Hidden cards can come back any time.")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            let order = TodayLayoutPrefs.decodeOrder(sectionOrderRaw)
            let hidden = Set(TodayLayoutPrefs.decodeHidden(hiddenSectionsRaw))
            NunaCard(small: true) {
                VStack(spacing: 0) {
                    ForEach(Array(order.enumerated()), id: \.element.id) { idx, section in
                        if idx > 0 { NunaDivider() }
                        editRow(section, index: idx, count: order.count, isHidden: hidden.contains(section))
                    }
                }
            }
            Button { showCustomize = true } label: { Label("More options", systemImage: "slider.horizontal.3") }
                .buttonStyle(.nuna(.ghost, height: 48, fullWidth: true))
            Button { sectionOrderRaw = ""; hiddenSectionsRaw = "" } label: { Text("Reset to default") }
                .buttonStyle(.nuna(.ghost, height: 48, fullWidth: true))
            Button { withAnimation(.easeInOut(duration: 0.2)) { editing = false } } label: { Text("Done") }
                .buttonStyle(.nuna(.primary, height: 52, fullWidth: true))
        }
    }

    private func editRow(_ section: TodaySection, index: Int, count: Int, isHidden: Bool) -> some View {
        HStack(spacing: 10) {
            Button { toggleHidden(section) } label: {
                Image(systemName: isHidden ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isHidden ? NunaPalette.textMuted : NunaPalette.charge)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel(Text(isHidden ? "Show" : "Hide"))
            Text(verbatim: section.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isHidden ? NunaPalette.textMuted : NunaPalette.textPrimary)
            Spacer(minLength: 8)
            moveButton("chevron.up", enabled: index > 0) { move(section, by: -1) }
            moveButton("chevron.down", enabled: index < count - 1) { move(section, by: 1) }
        }
        .frame(minHeight: 58)
    }

    private func moveButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? NunaPalette.textPrimary : NunaPalette.textMuted.opacity(0.4))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .disabled(!enabled)
    }

    private func move(_ section: TodaySection, by delta: Int) {
        var order = TodayLayoutPrefs.decodeOrder(sectionOrderRaw)
        guard let i = order.firstIndex(of: section), order.indices.contains(i + delta) else { return }
        order.swapAt(i, i + delta)
        sectionOrderRaw = TodayLayoutPrefs.encode(order)
    }

    private func toggleHidden(_ section: TodaySection) {
        var hidden = TodayLayoutPrefs.decodeHidden(hiddenSectionsRaw)
        if let i = hidden.firstIndex(of: section) {
            hidden.remove(at: i)
        } else {
            // Keep at least one card on Today.
            guard TodayLayoutPrefs.decodeOrder(sectionOrderRaw).filter({ !hidden.contains($0) }).count > 1 else { return }
            hidden.append(section)
        }
        hiddenSectionsRaw = TodayLayoutPrefs.encodeHidden(hidden)
    }

    // MARK: Sections

    @ViewBuilder private func sectionView(_ section: TodaySection) -> some View {
        switch section {
        case .hero:
            VStack(spacing: NunaSpacing.section) {
                NunaScoreCard(charge: model.charge, effort: model.effort, rest: model.rest,
                              effortScale: effortScale, readyLine: nil, heartRate: model.isToday ? live.heartRate : nil)
                if model.isToday, let warn = appModel.illnessSignal, warn.level != .quiet {
                    NunaEarlyWarningCard(result: warn)
                }
            }
        case .synthesis:
            if coachEnabled && model.isToday { NunaAnyaCard(title: "What should I focus on today?") { showCoach = true } }
        case .keyMetrics:
            let tiles = metricTiles
            if !tiles.isEmpty {
                VStack(spacing: 12) {
                    NunaMetricsGrid(tiles: tiles)
                    NavigationLink(value: NunaTodayRoute.allMetrics) {
                        NunaCard(small: true) { NunaListRow("All metrics", systemImage: "list.bullet", showsChevron: true) }
                    }
                    .buttonStyle(.plain)
                }
            }
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
        case .yourCards:
            let rows = yourCardRows()
            if !rows.isEmpty { NunaRowsCard(rows: rows) { showCoach = true } }
        case .addedCards:
            let rows = addedCardRows()
            if !rows.isEmpty { NunaRowsCard(rows: rows) { showCoach = true } }
        case .menstrualCycle:
            if appModel.cyclePhase != nil {
                NavigationLink(value: TabRoute.health) {
                    NunaCard(small: true) {
                        NunaListRow("Menstrual Cycle", subtitle: "Cycle awareness", systemImage: "drop.fill",
                                    tint: NunaPalette.alertText, showsChevron: true)
                    }
                }
                .buttonStyle(.plain)
            }
        case .liveSession:
            EmptyView()
        }
    }

    private var metricTiles: [NunaMetricTile] {
        let enabled = KeyMetricPrefs.decodeEnabled(keyMetricsRaw)
            .filter { ![.charge, .effort, .rest].contains($0) }
        func fmt(_ v: Double?, _ digits: Int = 0) -> String {
            v.map { String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, $0) } ?? "–"
        }
        func route(_ key: String, _ source: String = "my-whoop") -> NunaTodayRoute? {
            MetricCatalog.metric(key: key, source: source).map { .metric($0) }
        }
        let stepsRoute = MetricCatalog.todayStepsMetric(hasMeasuredSteps: model.steps != nil).map { NunaTodayRoute.metric($0) }
        return enabled.map { m in
            switch m {
            case .hrv:         return NunaMetricTile(id: m.rawValue, label: "HRV", value: fmt(model.hrv), unit: "ms", route: route("hrv"))
            case .restingHr:   return NunaMetricTile(id: m.rawValue, label: "Resting HR", value: fmt(model.restingHr), unit: "bpm", route: route("rhr"))
            case .bloodOxygen: return NunaMetricTile(id: m.rawValue, label: "Blood Oxygen", value: fmt(model.spo2), unit: "%", route: route("spo2"))
            case .respiratory: return NunaMetricTile(id: m.rawValue, label: "Respiratory", value: fmt(model.respiratory, 1), unit: "/min", route: route("resp_rate"))
            case .steps:       return NunaMetricTile(id: m.rawValue, label: "Steps", value: fmt(model.steps), unit: "", route: stepsRoute)
            case .calories:    return NunaMetricTile(id: m.rawValue, label: "Calories", value: fmt(model.calories), unit: "kcal", route: route("energy_kcal"))
            case .weight:      return NunaMetricTile(id: m.rawValue, label: "Weight", value: fmt(model.extras["weight"], 1), unit: "kg", route: route("weight", "apple-health"))
            case .skinTemp:    return NunaMetricTile(id: m.rawValue, label: "Skin Temp", value: fmt(model.extras["skin_temp"], 1), unit: "°C", route: route("skin_temp"))
            case .charge, .effort, .rest: return NunaMetricTile(id: m.rawValue, label: "", value: "", unit: "", route: nil)
            }
        }
    }
}
#endif
