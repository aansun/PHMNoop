#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Names and one-line descriptions, in the Nuna wording (TodayCustomize.dc)

extension TodaySection {
    var nunaName: String {
        switch self {
        case .hero: return String(localized: "Daily scores")
        case .synthesis: return "Anya"
        case .recoveryVitals: return String(localized: "Stress monitor")
        case .keyMetrics: return String(localized: "Key metrics")
        case .workouts: return String(localized: "Activity")
        case .journal: return String(localized: "Quick log")
        case .yourCards: return String(localized: "Your cards")
        case .menstrualCycle: return String(localized: "Menstrual cycle")
        case .heartRate: return String(localized: "Heart rate")
        case .liveSession: return String(localized: "Start session")
        case .addedCards: return String(localized: "Added cards")
        }
    }

    var nunaNote: String {
        switch self {
        case .hero: return String(localized: "Charge, Effort and Rest")
        case .synthesis: return String(localized: "One suggestion for today")
        case .recoveryVitals: return String(localized: "Average and timeline")
        case .keyMetrics: return String(localized: "The metrics you choose")
        case .workouts: return String(localized: "Latest activity")
        case .journal: return String(localized: "Water, journal and mood")
        case .yourCards: return String(localized: "Cards you chose")
        case .menstrualCycle: return String(localized: "Cycle awareness")
        case .heartRate: return String(localized: "Live heart rate")
        case .liveSession: return String(localized: "Start a live session")
        case .addedCards: return String(localized: "From Sleep and Trends")
        }
    }
}

/// The Today layout editor in the Nuna design. It edits the same stored values as the Default one (section order and
/// visibility, key metrics, Your cards, Added cards), so both Experiences show the same Today. Changes are drafts until Save.
struct NunaTodayCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss

    private enum Route: Hashable { case keyMetrics, yourCards, addedCards }

    private let initialSections: EditableLayoutDraft<TodaySection>
    private let initialMetrics: EditableLayoutDraft<KeyMetric>
    private let initialCards: EditableLayoutDraft<DashboardCard>
    private let initialHosted: EditableLayoutDraft<HostedCard>
    private let initialDetailed: Bool
    private let initialWindow: Int
    private let defaultSections: EditableLayoutDraft<TodaySection>

    @Binding private var sectionOrderRaw: String
    @Binding private var hiddenSectionsRaw: String
    @Binding private var keyMetricsRaw: String
    @Binding private var keyMetricsDetailed: Bool
    @Binding private var keyMetricsWindowDays: Int
    @Binding private var dashboardCardsRaw: String
    @Binding private var hostedCardsRaw: String

    @State private var path: [Route]
    @State private var sections: EditableLayoutDraft<TodaySection>
    @State private var metrics: EditableLayoutDraft<KeyMetric>
    @State private var cards: EditableLayoutDraft<DashboardCard>
    @State private var hosted: EditableLayoutDraft<HostedCard>
    @State private var detailed: Bool
    @State private var windowDays: Int
    @State private var confirmDiscard = false

    /// `order` and `hidden` are what Today is showing right now (including the Nuna defaults before anything is stored), so
    /// the editor opens on exactly what the person sees.
    init(initialDestination: TodayCustomizationDestination = .today,
         order: [TodaySection], hidden: [TodaySection], defaultHidden: [TodaySection], defaultOrder: [TodaySection],
         sectionOrderRaw: Binding<String>, hiddenSectionsRaw: Binding<String>,
         keyMetricsRaw: Binding<String>, keyMetricsDetailed: Binding<Bool>, keyMetricsWindowDays: Binding<Int>,
         dashboardCardsRaw: Binding<String>, hostedCardsRaw: Binding<String>) {
        _sectionOrderRaw = sectionOrderRaw; _hiddenSectionsRaw = hiddenSectionsRaw
        _keyMetricsRaw = keyMetricsRaw; _keyMetricsDetailed = keyMetricsDetailed; _keyMetricsWindowDays = keyMetricsWindowDays
        _dashboardCardsRaw = dashboardCardsRaw; _hostedCardsRaw = hostedCardsRaw

        let hiddenSet = Set(hidden)
        let s = EditableLayoutDraft(visible: order.filter { !hiddenSet.contains($0) }, hidden: order.filter { hiddenSet.contains($0) })
        let dh = Set(defaultHidden)
        defaultSections = EditableLayoutDraft(visible: defaultOrder.filter { !dh.contains($0) }, hidden: defaultOrder.filter { dh.contains($0) })
        let m = EditableLayoutDraft(visible: KeyMetricPrefs.decodeEnabled(keyMetricsRaw.wrappedValue), allItems: KeyMetric.defaultOrder)
        let c = EditableLayoutDraft(visible: DashboardCardPrefs.decodeEnabled(dashboardCardsRaw.wrappedValue), allItems: DashboardCard.canonicalOrder)
        let h = EditableLayoutDraft(visible: HostedCardPrefs.decodeEnabled(hostedCardsRaw.wrappedValue), allItems: HostedCard.canonicalOrder)
        initialSections = s; initialMetrics = m; initialCards = c; initialHosted = h
        initialDetailed = keyMetricsDetailed.wrappedValue; initialWindow = keyMetricsWindowDays.wrappedValue
        _sections = State(initialValue: s); _metrics = State(initialValue: m); _cards = State(initialValue: c); _hosted = State(initialValue: h)
        _detailed = State(initialValue: keyMetricsDetailed.wrappedValue); _windowDays = State(initialValue: keyMetricsWindowDays.wrappedValue)
        switch initialDestination {
        case .today: _path = State(initialValue: [])
        case .keyMetrics: _path = State(initialValue: [.keyMetrics])
        case .yourCards: _path = State(initialValue: [.yourCards])
        case .addedCards: _path = State(initialValue: [.addedCards])
        }
    }

    private var isDirty: Bool {
        sections != initialSections || metrics != initialMetrics || cards != initialCards || hosted != initialHosted
            || detailed != initialDetailed || windowDays != initialWindow
    }

    var body: some View {
        NavigationStack(path: $path) {
            page(title: "Customize Today", back: nil) { sectionsPage }
                .navigationBarHidden(true)
                .navigationDestination(for: Route.self) { route in
                    Group {
                        switch route {
                        case .keyMetrics: page(title: "Key metrics", back: { path.removeAll() }) { metricsPage }
                        case .yourCards: page(title: "Your cards", back: { path.removeAll() }) { cardsPage }
                        case .addedCards: page(title: "Added cards", back: { path.removeAll() }) { hostedPage }
                        }
                    }
                    .navigationBarHidden(true)
                }
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    // MARK: Chrome

    private func page<Content: View>(title: LocalizedStringKey, back: (() -> Void)?, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let back {
                    Button(action: back) {
                        Image(systemName: "chevron.left").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: Circle())
                    }.accessibilityLabel(Text("Back"))
                } else {
                    Button { if isDirty { confirmDiscard = true } else { dismiss() } } label: {
                        Text("Cancel").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 16).frame(height: 40).background(NunaPalette.glassStrong, in: Capsule())
                    }
                }
                Spacer(minLength: 4)
                Text(title).font(.nuna(size: 17, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                Button(action: save) {
                    Text("Save").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                        .padding(.horizontal, 18).frame(height: 40).background(NunaPalette.accent, in: Capsule())
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 14).padding(.bottom, 10)
            content()
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
    }

    private func save() {
        sectionOrderRaw = TodayLayoutPrefs.encode(sections.visible + sections.hidden)
        // Always an explicit value, so the Nuna defaults stop applying once the person has chosen.
        hiddenSectionsRaw = sections.hidden.isEmpty ? "none" : TodayLayoutPrefs.encodeHidden(sections.hidden)
        keyMetricsRaw = KeyMetricPrefs.encode(metrics.visible)
        keyMetricsDetailed = detailed
        keyMetricsWindowDays = windowDays
        dashboardCardsRaw = DashboardCardPrefs.encode(cards.visible)
        hostedCardsRaw = HostedCardPrefs.encode(hosted.visible)
        dismiss()
    }

    // MARK: Pages

    private var sectionsPage: some View {
        NunaLayoutList(
            draft: $sections, intro: "Hold the grip to drag a card. Turn the switch off to hide it; hidden cards stay here.",
            shownTitle: "Active cards", hiddenTitle: "Hidden",
            title: { $0.nunaName }, subtitle: sectionNote, icon: { $0.customizationIcon },
            configure: { s in s == .keyMetrics || s == .yourCards || s == .addedCards },
            onConfigure: { s in
                switch s { case .keyMetrics: path.append(.keyMetrics); case .yourCards: path.append(.yourCards); case .addedCards: path.append(.addedCards); default: break }
            },
            onReset: { sections = defaultSections }
        ) { EmptyView() }
    }

    private func sectionNote(_ s: TodaySection) -> String {
        switch s {
        case .keyMetrics: return String(localized: "\(metrics.visible.count) metrics shown")
        case .yourCards:
            return cards.visible.contains(.stress)
                ? String(localized: "\(cards.visible.count) cards shown · Stress included")
                : String(localized: "\(cards.visible.count) cards shown · Stress available in Edit")
        case .addedCards: return hosted.visible.isEmpty ? String(localized: "None added yet") : String(localized: "\(hosted.visible.count) added")
        default: return s.nunaNote
        }
    }

    private var metricsPage: some View {
        NunaLayoutList(
            draft: $metrics, intro: "Choose the metrics on Today and put them in order.",
            shownTitle: "Shown", hiddenTitle: "Available",
            title: { $0.title }, subtitle: { _ in nil }, icon: { $0.customizationIcon },
            configure: { _ in false }, onConfigure: { _ in },
            onReset: { metrics = EditableLayoutDraft(visible: KeyMetric.defaultOrder, allItems: KeyMetric.defaultOrder); detailed = false; windowDays = 14 }
        ) {
            Section {
                NunaToggleRow("Detailed tiles", subtitle: "Show a trend graph beneath each metric.", systemImage: "chart.xyaxis.line", isOn: $detailed).padding(.vertical, 6)
                if detailed {
                    NunaSegmented([(value: 7, title: "1 week"), (value: 14, title: "2 weeks"), (value: 30, title: "1 month")], selection: $windowDays)
                        .padding(.vertical, 6)
                }
            } header: { cap("Display") }
            .listRowBackground(NunaPalette.card)
        }
    }

    private var cardsPage: some View {
        NunaLayoutList(
            draft: $cards, intro: "Pick the cards in Your cards and set their order.",
            shownTitle: "Shown", hiddenTitle: "Available",
            title: { $0.title }, subtitle: { $0.subtitle }, icon: { $0.icon },
            configure: { _ in false }, onConfigure: { _ in },
            onReset: { cards = EditableLayoutDraft(visible: DashboardCard.defaultSelection, allItems: DashboardCard.canonicalOrder) }
        ) { EmptyView() }
    }

    private var hostedPage: some View {
        NunaLayoutList(
            draft: $hosted, intro: "Add cards from Sleep and Trends to Today.",
            shownTitle: "Added to Today", hiddenTitle: "Available",
            title: { $0.title }, subtitle: { String(localized: "from \($0.origin)") }, icon: { $0.customizationIcon },
            configure: { _ in false }, onConfigure: { _ in },
            onReset: { hosted = EditableLayoutDraft(visible: HostedCard.defaultSelection, allItems: HostedCard.canonicalOrder) },
            allowEmpty: true, group: { $0.origin }
        ) { EmptyView() }
    }

    private func cap(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
    }
}

/// Shown and Hidden lists with a drag grip, a switch per row and an optional "Edit" link, in Nuna styling. A native List with
/// move enabled, so reordering is the system drag (reliable inside a sheet, with VoiceOver move actions).
struct NunaLayoutList<Item: Identifiable & Equatable, Extra: View>: View {
    @Binding var draft: EditableLayoutDraft<Item>
    let intro: LocalizedStringKey
    let shownTitle: LocalizedStringKey
    let hiddenTitle: LocalizedStringKey
    let title: (Item) -> String
    let subtitle: (Item) -> String?
    let icon: (Item) -> String
    let configure: (Item) -> Bool
    let onConfigure: (Item) -> Void
    let onReset: () -> Void
    var allowEmpty = false
    var group: ((Item) -> String)?
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        List {
            Section {
                Text(intro).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }
            extra()
            Section {
                ForEach(draft.visible) { item in row(item, shown: true) }
                    .onMove { draft.moveVisible(from: $0, to: $1) }
            } header: { cap(shownTitle) }
            .listRowBackground(NunaPalette.card)

            if draft.hidden.isEmpty {
                Section {
                    Text("Nothing hidden").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                } header: { cap(hiddenTitle) }
                .listRowBackground(NunaPalette.card)
            } else if let group {
                ForEach(groups(group), id: \.name) { g in
                    Section { ForEach(g.items) { row($0, shown: false) } } header: { cap(LocalizedStringKey(g.name)) }
                        .listRowBackground(NunaPalette.card)
                }
            } else {
                Section { ForEach(draft.hidden) { row($0, shown: false) } } header: { cap(hiddenTitle) }
                    .listRowBackground(NunaPalette.card)
            }

            Section {
                Button(role: .destructive, action: onReset) {
                    Text("Reset this layout").font(.nuna(size: 15.5, weight: .bold)).frame(maxWidth: .infinity)
                }
            }
            .listRowBackground(NunaPalette.card)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(NunaPalette.canvas)
        .environment(\.editMode, .constant(.active))
        .listRowSeparatorTint(NunaPalette.hairline)
    }

    private func row(_ item: Item, shown: Bool) -> some View {
        let canHide = draft.visible.count > (allowEmpty ? 0 : 1)
        return HStack(spacing: 12) {
            NunaIconTile(icon(item))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title(item)).font(.nuna(size: 16, weight: .bold)).foregroundStyle(shown ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                if let s = subtitle(item) { Text(verbatim: s).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(2) }
            }
            Spacer(minLength: 6)
            if shown, configure(item) {
                Button { onConfigure(item) } label: {
                    Text("Edit").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .padding(.horizontal, 12).frame(height: 32).background(NunaPalette.glassStrong, in: Capsule())
                }.buttonStyle(.plain)
            }
            Toggle("", isOn: Binding(
                get: { shown },
                set: { on in withAnimation(.easeInOut(duration: 0.2)) { if on { draft.show(item) } else if canHide { draft.hide(item) } } }))
                .labelsHidden().tint(NunaPalette.charge)
                .disabled(shown && !canHide)
        }
        .padding(.vertical, 4)
        .moveDisabled(!shown)
    }

    private func groups(_ key: (Item) -> String) -> [(name: String, items: [Item])] {
        var order: [String] = []; var buckets: [String: [Item]] = [:]
        for i in draft.hidden { let k = key(i); if buckets[k] == nil { order.append(k) }; buckets[k, default: []].append(i) }
        return order.map { (name: $0, items: buckets[$0] ?? []) }
    }

    private func cap(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
    }
}

extension View {
    /// A list row that looks like a free-standing block on the canvas rather than a table cell.
    func plainRow() -> some View {
        listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 7, leading: NunaSpacing.screenH, bottom: 7, trailing: NunaSpacing.screenH))
    }
}
#endif
