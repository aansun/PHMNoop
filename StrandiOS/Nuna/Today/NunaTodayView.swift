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
    /// Nuna keeps its own arrangement: the Default look saves its order and hidden set under other keys, and the two looks start from
    /// different defaults, so one must not leak into the other.
    static let orderKey = "nuna.today.sectionOrder"
    static let hiddenKey = "nuna.today.hiddenSections"
    /// Rings and the synthesis chips, Anya, key metrics, the stress card, the journal with water and mood, then the add-or-arrange card.
    /// Everything else (activity, heart rate, start session, your cards, cycle, added cards) stays out until the person adds it.
    static let order: [TodaySection] = [
        .hero, .synthesis, .keyMetrics, .recoveryVitals, .journal,
        .workouts, .heartRate, .liveSession, .yourCards, .menstrualCycle, .addedCards,
    ]
    static let hidden: [TodaySection] = [.workouts, .heartRate, .liveSession, .yourCards, .menstrualCycle, .addedCards]
}

struct NunaTodayView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var liftSession: LiftSessionController
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var updateStore: UpdateStore
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var intelligence: IntelligenceEngine

    @AppStorage("noop.coachEnabled") var coachEnabled = true
    @AppStorage(HydrationStore.enabledKey) var hydrationEnabled = false
    @AppStorage(NunaTodayDefaults.orderKey) private var sectionOrderRaw = ""
    @AppStorage(NunaTodayDefaults.hiddenKey) private var hiddenSectionsRaw = ""
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
    /// 0 when Today is at the top, 1 once the pinned score rings have shrunk to their small size.
    @State private var collapse: CGFloat = 0
    /// Today's suggested session, the same one the plan screen shows. Nil until Charge exists.
    @State private var dayPlan: NunaDayPlanResult?
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
            if editing {
                editScreen
            } else {
                ZStack(alignment: .top) {
                    ScrollView {
                        VStack(spacing: NunaSpacing.section) {
                            // Space for the pinned header; it scrolls away exactly as fast as the header shrinks.
                            Color.clear.frame(height: pinnedHeight(collapse: 0))
                            if !model.isToday { pastDayBanner }
                            ForEach(sections) { section in sectionView(section) }
                            customizeButton
                        }
                        .padding(.horizontal, NunaSpacing.screenH)
                        .padding(.bottom, 160)
                        .background(NunaScrollOffsetReader { offset in
                        let t = min(max(offset / max(pinnedHeight(collapse: 0) - pinnedHeight(collapse: 1), 1), 0), 1)
                        if abs(t - collapse) > 0.004 { collapse = t }
                    })
                    }
                    .scrollIndicators(.hidden)
                    pinnedHeader
                }
            }

            if model.isToday && !editing {
                NunaFAB { showQuick = true }
                    .padding(.trailing, NunaSpacing.screenH)
                    .padding(.bottom, liftSession.isActive && !liftSession.isPresented ? 172 : 104)
            }
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .nunaTodayDestinations()
        .task(id: "\(repo.refreshSeq)-\(model.dayOffset)") {
            await model.load(repo: repo, profile: profile)
            dayPlan = model.isToday ? await NunaDayPlanResult.load(repo: repo, profile: profile) : nil
        }
        .sheet(isPresented: $showCustomize) {
            NunaTodayCustomizeSheet(
                initialDestination: customizeDestination,
                order: effectiveOrder, hidden: effectiveHidden,
                defaultHidden: Self.nunaDefaultHidden, defaultOrder: Self.nunaDefaultOrder,
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
        .sheet(isPresented: $showMood) {
            NavigationStack { NunaMoodView().toolbar(.hidden, for: .navigationBar) }
                .environmentObject(repo)
                .preferredColorScheme(NunaTheme.colorScheme)
        }
        .sheet(isPresented: $showInbox) { NunaUpdatesInbox(onClose: { showInbox = false }).nunaSheetChrome(detents: [.large]) }
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "today") }
    }

    // MARK: Header

    private var showsRings: Bool { sections.contains(.hero) }

    private func pinnedHeight(collapse t: CGFloat) -> CGFloat {
        let bar: CGFloat = 52
        guard showsRings else { return bar + 8 }
        return bar + 6 + NunaScoreRings.fullHeight + (NunaScoreRings.compactHeight - NunaScoreRings.fullHeight) * t + 8
    }

    /// Bell, the day (with arrows to step it) and the strap on one slim row, then the three score rings. Stays at the top while
    /// the page scrolls under it; the rings shrink as the page moves.
    private var pinnedHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button { showInbox = true } label: {
                    Image(systemName: "bell").font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 44, height: 44)
                        .overlay(alignment: .topTrailing) {
                            if updateStore.unreadCount > 0 {
                                Circle().fill(NunaPalette.alert).frame(width: 9, height: 9).offset(x: -8, y: 9)
                            }
                        }
                }
                .accessibilityLabel(Text("Updates"))
                Spacer(minLength: 0)
                dayNav
                Spacer(minLength: 0)
                Button { router.openDevices() } label: {
                    NunaStrapChip(connected: live.connected, battery: live.batteryPct)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("WHOOP strap"))
            }
            .frame(height: 46)
            if showsRings {
                NunaScoreRings(charge: model.charge, effort: model.effort, rest: model.rest, effortScale: effortScale, collapse: collapse)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, NunaSpacing.screenH - 4)
        .padding(.top, 2).padding(.bottom, 8)
        .background(
            NunaPalette.canvas.ignoresSafeArea(edges: .top)
                .overlay(alignment: .bottom) { Rectangle().fill(NunaPalette.hairline).frame(height: 1).opacity(Double(collapse)) }
        )
    }

    /// "<  Today  >": the arrows step one day, the middle opens the calendar.
    private var dayNav: some View {
        HStack(spacing: 0) {
            Button { model.dayOffset += 1 } label: {
                Image(systemName: "chevron.left").font(.nuna(size: 14, weight: .bold)).frame(width: 40, height: 40)
            }
            Button { showDate = true } label: {
                Text(verbatim: dateTitle).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .frame(minWidth: 110).frame(height: 36)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
            }
            Button { if model.dayOffset > 0 { model.dayOffset -= 1 } } label: {
                Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).frame(width: 40, height: 40)
                    .opacity(model.dayOffset > 0 ? 1 : 0.3)
            }
            .disabled(model.dayOffset == 0)
        }
        .buttonStyle(.plain)
        .foregroundStyle(NunaPalette.textPrimary)
    }

    private var dateTitle: String {
        if model.dayOffset == 0 { return String(localized: "Today") }
        if model.dayOffset == 1 { return String(localized: "Yesterday") }
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
                Button { customizeDestination = .today; showCustomize = true } label: { Label("Card settings", systemImage: "slider.horizontal.3").lineLimit(1).minimumScaleFactor(0.8) }
                    .buttonStyle(.nuna(.ghost, height: 52, fullWidth: true))
                Button { sectionOrderRaw = ""; hiddenSectionsRaw = ""; keyMetricsRaw = ""; dashboardCardsRaw = ""; hostedCardsRaw = "" } label: { Text("Restore defaults").lineLimit(1).minimumScaleFactor(0.8) }
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
                        .frame(width: 34, height: 34).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
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

    private var hiddenDashboardCards: [DashboardCard] {
        let on = DashboardCardPrefs.decodeEnabled(dashboardCardsRaw)
        return DashboardCard.canonicalOrder.filter { !on.contains($0) }
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
                if hiddenSections.isEmpty && hiddenDashboardCards.isEmpty && hiddenHostedCards.isEmpty {
                    Text("Every card is already on Today.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                if !hiddenSections.isEmpty {
                    NunaSettingsGroup("Hidden cards") {
                        ForEach(Array(hiddenSections.enumerated()), id: \.element.id) { idx, sec in
                            if idx > 0 { NunaDivider() }
                            Button { add(sec, after: addAfter); showAddCard = false } label: {
                                NunaListRow(LocalizedStringKey(sec.nunaName), subtitle: LocalizedStringKey(sec.nunaNote), systemImage: sec.customizationIcon) { addLabel }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !hiddenDashboardCards.isEmpty {
                    NunaSettingsGroup("For Your cards") {
                        ForEach(Array(hiddenDashboardCards.enumerated()), id: \.element.id) { idx, card in
                            if idx > 0 { NunaDivider() }
                            Button {
                                dashboardCardsRaw = DashboardCardPrefs.encode(DashboardCardPrefs.decodeEnabled(dashboardCardsRaw) + [card])
                                add(.yourCards, after: addAfter); showAddCard = false
                            } label: { NunaListRow(LocalizedStringKey(card.title), subtitle: LocalizedStringKey(card.subtitle), systemImage: card.icon) { addLabel } }.buttonStyle(.plain)
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
                Button { showAddCard = false; customizeDestination = .today; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showCustomize = true } } label: {
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
            // The rings themselves are pinned at the top; what belongs with them stays here.
            VStack(spacing: NunaSpacing.section) {
                if readyLine != nil || model.charge.pct != nil || (model.isToday && live.heartRate != nil) {
                    // Readiness, Charge state and heart rate: three chips of one shape on one line.
                    HStack(spacing: 8) { synthesisChips; heartRatePill; Spacer(minLength: 0) }
                }
                if model.isToday, let warn = appModel.illnessSignal, warn.level != .quiet {
                    NunaEarlyWarningCard(result: warn)
                }
            }
        case .synthesis:
            if coachEnabled && model.isToday {
                NunaAnyaCard(verbatim: dayPlan?.title ?? synthLine, buttonTitle: "Start",
                             onButton: {
                                 if let r = dayPlan { router.plannedSession = .init(title: r.title, minutes: r.plan.totalMinutes, zone: r.plan.mainZone) }
                                 router.requestedDestination = .activeWorkout
                             }) { showCoach = true }
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
                                .font(.nuna(size: 14, weight: .bold))
                        }
                        .accessibilityLabel(Text(metricsLayout == .cards ? "Show as list" : "Show as cards"))
                        Button { customizeDestination = .keyMetrics; showCustomize = true } label: {
                            Image(systemName: "slider.horizontal.3").font(.nuna(size: 14, weight: .bold))
                        }
                        .accessibilityLabel(Text("Edit"))
                        NavigationLink(value: NunaTodayRoute.allMetrics) { NunaLinkLabel(text: "All", chevron: true) }
                    }
                    NunaMetricsGrid(tiles: tiles, layout: metricsLayout)
                }
            }
        case .workouts:
            if let w = model.workouts.last {
                VStack(spacing: 12) {
                    NunaTitleRow(title: "Activity") {
                        Button { router.requestedDestination = .workouts } label: { NunaLinkLabel(text: "All workouts", chevron: true) }
                    }
                    NunaActivityRow(workout: w, effortScale: effortScale)
                }
            }
        case .heartRate:
            if model.isToday, let hr = live.heartRate {
                NavigationLink(value: TabRoute.fullDayChart) {
                    NunaCard(small: true) {
                        NunaListRow("Heart Rate", systemImage: "heart.fill", tint: NunaPalette.alertText, showsChevron: true) {
                            Text(verbatim: "\(hr) bpm").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        case .journal:
            VStack(spacing: 12) {
                NunaJournalWeekCard { router.requestedDestination = .journal }
                if model.isToday {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            if hydrationEnabled {
                                NunaQuickChip(title: "Water +250", systemImage: "drop", tint: NunaPalette.effortText) {
                                    Task { _ = await repo.logHydration(amountMl: 250); repo.noteHydrationChanged() }
                                }
                            }
                            NunaQuickChip(title: "Mood", systemImage: "heart") { showMood = true }
                        }
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
                NavigationLink(value: NunaTodayRoute.cycle) {
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

    /// What the Default Today synthesis shows beside its greeting, minus the greeting: the readiness chip with its word (Push, Maintain,
    /// Rest) and the Charge state (Solid, Last night, Calibrating, No data), from the same engine and display state.
    @ViewBuilder private var synthesisChips: some View {
        if model.isToday, let level = model.readiness?.level, let word = Self.readinessWord(level) {
            let tone = level == .primed ? NunaPalette.charge : (level == .balanced ? NunaPalette.effortText : NunaPalette.warning)
            todayChip(icon: .symbol("bolt.fill"), text: Text(verbatim: word), tint: tone)
        }
        if model.charge != .noData {
            todayChip(icon: .dot(NunaPalette.charge), text: Text(verbatim: model.charge.stateLabel), tint: nil)
        }
    }

    private enum ChipIcon { case symbol(String), dot(Color) }

    /// One chip shape for the whole row: the same height, radius, type and padding. A tint colours the readiness chip; the others are neutral.
    private func todayChip(icon: ChipIcon, text: Text, tint: Color?) -> some View {
        HStack(spacing: 6) {
            switch icon {
            case .symbol(let name): Image(systemName: name).font(.nuna(size: 11.5, weight: .bold))
            case .dot(let c): Circle().fill(c).frame(width: 7, height: 7)
            }
            text.font(.nuna(size: 12.5, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint ?? NunaPalette.textPrimary)
        .padding(.horizontal, 12).frame(height: 30)
        .background(tint.map { NunaPalette.tint($0) } ?? NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous).strokeBorder(tint?.opacity(0.35) ?? NunaPalette.hairline, lineWidth: 1))
        .fixedSize()
    }

    private static func readinessWord(_ level: ReadinessEngine.Level) -> String? {
        switch level {
        case .primed: return String(localized: "Push")
        case .balanced: return String(localized: "Maintain")
        case .strained, .rundown: return String(localized: "Rest")
        case .insufficient: return nil
        }
    }

    @ViewBuilder private var heartRatePill: some View {
        if model.isToday, let hr = live.heartRate {
            NavigationLink(value: TabRoute.fullDayChart) {
                todayChip(icon: .symbol("heart.fill"), text: Text(verbatim: "\(hr) bpm"), tint: nil)
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
