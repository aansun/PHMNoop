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
enum NunaTodayDefaults {
    static let order: [TodaySection] = [
        .hero, .synthesis, .recoveryVitals, .keyMetrics, .workouts, .journal,
        .yourCards, .menstrualCycle, .addedCards, .heartRate, .liveSession,
    ]
    static let hidden: [TodaySection] = [.heartRate, .liveSession, .yourCards]
}

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
    @State private var showMood = false
    @AppStorage("nuna.keyMetricsLayout") private var metricsLayoutRaw = NunaMetricsLayout.cards.rawValue
    @State private var showAddCard = false
    @State private var addAfter: TodaySection?
    @State private var customizeDestination: TodayCustomizationDestination = .today

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: NunaSpacing.section) {
                    if editing {
                        editList
                    } else {
                        header
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
                initialDestination: customizeDestination,
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
        .sheet(isPresented: $showAddCard) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add a card").font(.system(size: NunaTypeSize.h2, weight: .heavy, design: .rounded)).foregroundStyle(NunaPalette.textPrimary).padding(.top, 22)
                NunaCard(small: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(hiddenSections.enumerated()), id: \.element.id) { idx, sec in
                            if idx > 0 { NunaDivider() }
                            Button { add(sec, after: addAfter); showAddCard = false } label: {
                                NunaListRow(nunaTitle(sec), systemImage: "plus") { Text("Add").font(.system(size: 14, weight: .heavy)).foregroundStyle(NunaPalette.charge) }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .background(NunaPalette.card.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .nunaSheetChrome(detents: [.medium, .large])
        }
        .sheet(isPresented: $showMood) {
            NavigationStack {
                ScrollView { MindSection().padding() }
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showMood = false } } }
            }
            .environmentObject(repo)
        }
        .sheet(isPresented: $showInbox) { UpdatesInboxView(onClose: { showInbox = false }) }
        .sheet(isPresented: $showCoach) { CoachLauncherSheet(context: "today") }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Today")
                .font(.system(size: NunaTypeSize.h1, weight: .heavy, design: .rounded))
                .foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 8)
            Button { router.openDevices() } label: {
                NunaStrapChip(connected: live.connected, battery: live.batteryPct)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("WHOOP strap"))
            Button { showInbox = true } label: {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(NunaPalette.glassStrong, in: Circle())
                    .overlay(Circle().strokeBorder(NunaPalette.hairline, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if updateStore.unreadCount > 0 {
                            Circle().fill(NunaPalette.alert).frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(NunaPalette.card, lineWidth: 2))
                                .offset(x: -10, y: 10)
                        }
                    }
            }
            .accessibilityLabel(Text("Updates"))
        }
        .padding(.top, 2)
    }

    private var datePill: some View {
        HStack {
            Button { showDate = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar").font(.system(size: 14, weight: .bold))
                    Text(verbatim: dateTitle).font(.system(size: 14, weight: .heavy))
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
                .foregroundStyle(NunaPalette.textPrimary)
                .padding(.horizontal, 14).frame(height: 38)
                .background(NunaPalette.glassStrong, in: Capsule())
                .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
        }
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
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
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
        case .synthesis: return "Anya"
        case .recoveryVitals: return "Stress monitor"
        case .keyMetrics: return "Key metrics"
        case .workouts: return "Activity"
        case .journal: return "Quick log"
        case .yourCards: return "Your cards"
        case .menstrualCycle: return "Menstrual cycle"
        case .heartRate: return "Heart rate"
        case .liveSession: return "Start session"
        case .addedCards: return "Added cards"
        }
    }

    private var editList: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edit mode").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                        Text("Arrange cards").font(.system(size: NunaTypeSize.h1, weight: .heavy, design: .rounded))
                            .foregroundStyle(NunaPalette.textPrimary)
                    }
                    Spacer()
                    Button { withAnimation(.easeInOut(duration: 0.2)) { editing = false } } label: { Text("Done") }
                        .buttonStyle(.nuna(.primary, height: 44)).fixedSize()
                }
                Text("Hold the grip, then drag to reorder. Tap X to hide a card.")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
            let visible = effectiveOrder.filter { !effectiveHidden.contains($0) }
            ForEach(Array(visible.enumerated()), id: \.element.id) { idx, section in
                editFrame(section)
                if !hiddenSections.isEmpty && (idx % 3 == 0 || idx == visible.count - 1) {
                    NunaAddCard("Add a card here") { addAfter = section; showAddCard = true }
                }
            }
            if visible.isEmpty && !hiddenSections.isEmpty {
                NunaAddCard("Add a card here") { addAfter = nil; showAddCard = true }
            }
            HStack(spacing: 12) {
                Button { showCustomize = true } label: { Label("Card settings", systemImage: "slider.horizontal.3").lineLimit(1).minimumScaleFactor(0.8) }
                    .buttonStyle(.nuna(.ghost, height: 52, fullWidth: true))
                Button { sectionOrderRaw = ""; hiddenSectionsRaw = ""; keyMetricsRaw = "" } label: { Text("Restore defaults").lineLimit(1).minimumScaleFactor(0.8) }
                    .buttonStyle(.nuna(.ghost, height: 52, fullWidth: true))
            }
            .padding(.top, 4)
        }
    }

    private var hiddenSections: [TodaySection] { effectiveOrder.filter { effectiveHidden.contains($0) } }

    private func editFrame(_ section: TodaySection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal").font(.system(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    .frame(width: 22)
                Text(nunaTitle(section)).font(.system(size: 15.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Button { withAnimation { toggleHidden(section) } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 34, height: 34).background(NunaPalette.glassStrong, in: Circle())
                }
                .accessibilityLabel(Text("Hide"))
            }
            .contentShape(Rectangle())
            .draggable(section.rawValue)
            editPreview(section)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let dragged = TodaySection(rawValue: raw) else { return false }
            reorder(dragged, before: section); return true
        }
        .accessibilityAction(named: Text("Move up")) { move(section, by: -1) }
        .accessibilityAction(named: Text("Move down")) { move(section, by: 1) }
    }

    /// A compact stand-in for the card, inside the dashed frame.
    @ViewBuilder private func editPreview(_ section: TodaySection) -> some View {
        let inner = RoundedRectangle(cornerRadius: 18, style: .continuous).fill(NunaPalette.cardHighlight)
        switch section {
        case .hero:
            HStack {
                miniRing(model.charge.pct, "Charge", NunaPalette.charge, "%")
                miniRing(model.effort.map { Double(UnitFormatter.effortDisplay($0, scale: effortScale).replacingOccurrences(of: ",", with: ".")) ?? 0 }, "Effort", NunaPalette.effort, "", fraction: (model.effort ?? 0) / 100)
                miniRing(model.rest, "Rest", NunaPalette.rest, "%")
            }
            .padding(.vertical, 12).frame(maxWidth: .infinity).background(inner)
        case .synthesis:
            previewRow("sparkles", nil, synthLine, "Anya suggestion").background(inner)
        case .recoveryVitals:
            previewRow("wind", NunaPalette.charge, model.stress.map { String(localized: "Stress \(String(format: "%.1f", locale: AppLanguage.activeLocale, $0)) / 3") } ?? String(localized: "Stress"), "Intraday curve").background(inner)
        case .keyMetrics:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(metricTiles.prefix(4)) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.label).font(.system(size: 10.5, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: t.value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
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
                if hydrationEnabled { miniChip("Water +250") }
                miniChip("Journal"); miniChip("Mood"); Spacer(minLength: 0)
            }
        case .yourCards: previewRow("rectangle.stack", nil, String(localized: "Your cards"), "Cards you chose").background(inner)
        case .menstrualCycle: previewRow("drop", NunaPalette.alertText, String(localized: "Menstrual cycle"), "Cycle awareness").background(inner)
        case .heartRate: previewRow("heart", NunaPalette.alertText, String(localized: "Heart rate"), "Live").background(inner)
        case .liveSession: previewRow("play", NunaPalette.charge, String(localized: "Start session"), "Live session").background(inner)
        case .addedCards: previewRow("square.stack", nil, String(localized: "Added cards"), "From Sleep and Trends").background(inner)
        }
    }

    private func previewRow(_ icon: String, _ tint: Color?, _ title: String, _ sub: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            NunaIconTile(icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2)
                Text(sub).font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniChip(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.system(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            .padding(.horizontal, 12).frame(height: 32).background(NunaPalette.glassStrong, in: Capsule())
    }

    private func miniRing(_ value: Double?, _ label: LocalizedStringKey, _ color: Color, _ unit: String, fraction: Double? = nil) -> some View {
        VStack(spacing: 6) {
            NunaRingGauge(fraction: fraction ?? ((value ?? 0) / 100), color: color, size: 56, lineWidth: 6) {
                Text(verbatim: value.map { String(format: "%.0f", $0) + unit } ?? "–").font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6)
            }
            Text(label).font(.system(size: 10.5, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func reorder(_ dragged: TodaySection, before target: TodaySection) {
        guard dragged != target else { return }
        var order = effectiveOrder
        order.removeAll { $0 == dragged }
        let idx = order.firstIndex(of: target) ?? order.endIndex
        order.insert(dragged, at: idx)
        persist(order: order)
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
            VStack(spacing: NunaSpacing.section) {
                NunaScoreCard(charge: model.charge, effort: model.effort, rest: model.rest,
                              effortScale: effortScale, readyLine: readyLine, heartRate: model.isToday ? live.heartRate : nil)
                if model.isToday, let warn = appModel.illnessSignal, warn.level != .quiet {
                    NunaEarlyWarningCard(result: warn)
                }
            }
        case .synthesis:
            if coachEnabled && model.isToday {
                NunaAnyaCard(verbatim: synthLine, buttonTitle: "Start",
                             onButton: { router.requestedDestination = .activeWorkout }) { showCoach = true }
            }
        case .recoveryVitals:
            if model.stress != nil || model.stressCurve != nil {
                NunaStressCard(score: model.stress, curve: model.stressCurve, isToday: model.isToday)
            }
        case .keyMetrics:
            let tiles = metricTiles
            if !tiles.isEmpty {
                VStack(spacing: 12) {
                    NunaTitleRow(title: "Key metrics") {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                metricsLayoutRaw = (metricsLayout == .cards ? NunaMetricsLayout.list : .cards).rawValue
                            }
                        } label: {
                            Image(systemName: metricsLayout == .cards ? "list.bullet" : "square.grid.2x2")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .accessibilityLabel(Text(metricsLayout == .cards ? "Show as list" : "Show as cards"))
                        Button { customizeDestination = .keyMetrics; showCustomize = true } label: {
                            NunaLinkLabel(text: "Edit", systemImage: "slider.horizontal.3")
                        }
                        NavigationLink(value: NunaTodayRoute.allMetrics) { NunaLinkLabel(text: "All", chevron: true) }
                    }
                    NunaMetricsGrid(tiles: tiles, layout: metricsLayout)
                }
            }
        case .workouts:
            if let w = model.workouts.last {
                VStack(spacing: 12) {
                    NunaTitleRow(title: "Activity") {
                        NavigationLink(value: TabRoute.workouts) { NunaLinkLabel(text: "All workouts", chevron: true) }
                    }
                    NunaActivityRow(workout: w, effortScale: effortScale)
                }
            }
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
            if model.isToday {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if hydrationEnabled {
                            NunaQuickChip(title: "Water +250", systemImage: "drop", tint: NunaPalette.effortText) {
                                Task { _ = await repo.logHydration(amountMl: 250); repo.noteHydrationChanged() }
                            }
                        }
                        NunaQuickChip(title: "Journal", systemImage: "bookmark") { router.requestedDestination = .journal }
                        NunaQuickChip(title: "Mood", systemImage: "heart") { showMood = true }
                    }
                }
            }
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

    private var metricsLayout: NunaMetricsLayout { NunaMetricsLayout(rawValue: metricsLayoutRaw) ?? .cards }

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
        /// "▲ 4" against the previous day; `downIsGood` for resting heart rate.
        func delta(_ d: Double?, downIsGood: Bool = false, decimals: Int = 0) -> (String, Bool)? {
            guard let d else { return nil }
            let step = decimals == 0 ? 1.0 : 0.1
            guard abs(d) >= step - 0.0001 else { return nil }
            let shown = String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, abs(d))
            return ((d > 0 ? "▲ " : "▼ ") + shown, downIsGood ? d < 0 : d > 0)
        }
        let stepsRoute = MetricCatalog.todayStepsMetric(hasMeasuredSteps: model.steps != nil).map { NunaTodayRoute.metric($0) }
        func tile(_ m: KeyMetric, _ label: LocalizedStringKey, _ value: String, _ unit: String, _ route: NunaTodayRoute?,
                  _ icon: String, _ tint: Color?, delta d: (String, Bool)? = nil) -> NunaMetricTile {
            NunaMetricTile(id: m.rawValue, label: label, value: value, unit: unit, route: route,
                           delta: d?.0, deltaGood: d?.1, icon: icon, tint: tint)
        }
        return enabled.map { m in
            switch m {
            case .hrv:
                return tile(m, "HRV", fmt(model.hrv), "ms", route("hrv"), "waveform.path.ecg", NunaPalette.charge, delta: delta(model.hrvDelta))
            case .restingHr:
                return tile(m, "Resting HR", fmt(model.restingHr), "bpm", route("rhr"), "heart", NunaPalette.alertText, delta: delta(model.restingHrDelta, downIsGood: true))
            case .bloodOxygen:
                return tile(m, "Blood Oxygen", fmt(model.spo2), "%", route("spo2"), "drop", NunaPalette.effortText, delta: delta(model.spo2Delta))
            case .respiratory:
                return tile(m, "Respiratory", fmt(model.respiratory, 1), "/min", route("resp_rate"), "wind", NunaPalette.effortText, delta: delta(model.respiratoryDelta, decimals: 1))
            case .steps:       return tile(m, "Steps", fmt(model.steps), "", stepsRoute, "figure.walk", NunaPalette.charge)
            case .calories:    return tile(m, "Calories", fmt(model.calories), "kcal", route("energy_kcal"), "flame", NunaPalette.effortText)
            case .weight:      return tile(m, "Weight", fmt(model.extras["weight"], 1), "kg", route("weight", "apple-health"), "scalemass", NunaPalette.effortText)
            case .skinTemp:    return tile(m, "Skin Temp", fmt(model.extras["skin_temp"], 1), "°C", route("skin_temp"), "thermometer", NunaPalette.alertText)
            case .rest:
                return tile(m, "Sleep", model.sleepMinutes.map { NunaSleepFormat.duration($0) } ?? "–", "", .sleep(0), "moon", NunaPalette.restText)
            case .charge, .effort: return NunaMetricTile(id: m.rawValue, label: "", value: "", unit: "", route: nil)
            }
        }
    }
}
#endif
