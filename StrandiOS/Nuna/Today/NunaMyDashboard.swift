#if os(iOS)
import SwiftUI
import StrandDesign

/// One entry of "My Dashboard" on Today: either one of the cards Your cards always had, or a trend page (Effort, Charge, the sleep readings...)
/// that opens that page when tapped.
enum NunaDashItem: Identifiable, Hashable {
    case card(DashboardCard)
    case page(NunaTrendPage)

    var id: String {
        switch self {
        case .card(let c): return c.rawValue
        case .page(let p): return "page." + p.rawValue
        }
    }

    /// The trend pages that are not already a card (HRV, resting heart rate, respiratory rate, steps and calories are cards of their own).
    static let pages: [NunaTrendPage] = NunaTrendPage.allCases.filter { ![.hrv, .rhr, .respiratory, .steps, .calories, .vo2max, .skinTemp, .weight, .vitality, .spo2, .stressTotal, .stressNonActivity, .stressSleep].contains($0) }

    static var canonicalOrder: [NunaDashItem] { DashboardCard.canonicalOrder.map(NunaDashItem.card) + pages.map(NunaDashItem.page) }

    var title: String {
        switch self {
        case .card(let c): return c.title
        case .page(let p): return p.titleText
        }
    }

    var subtitle: String? {
        switch self {
        case .card(let c): return c.subtitle
        case .page(let p): return p.section.titleText
        }
    }

    /// The icon the dashboard card shows on Today, so the editor lists the same one.
    var icon: String {
        switch self {
        case .card(let c): return c.nunaIcon
        case .page(let p): return p.icon
        }
    }
}

extension DashboardCard {
    /// The icon of a card on Today: the traced metric icons where there is one, a symbol otherwise. `DashboardCard.icon` is the older set shared with
    /// the other platforms; My Dashboard and its editor read this one.
    var nunaIcon: String {
        switch self {
        case .hrv: return "met:heart-rate-variability"
        case .restingHr: return "met:resting-heart-rate"
        case .respiratory: return "met:respiratory-rate"
        case .steps, .stepsAverage30: return "met:steps"
        case .stress: return "met:total-day-stress"
        case .fitnessAge: return "figure.run"
        case .vo2max: return "met:vo2-max"
        case .vitality: return "sparkles"
        case .bloodOxygen: return "vital:spo2"
        case .hydration: return "drop.fill"
        case .skinTemp: return "vital:temp"
        case .sleep: return "met:sleep-performance"
        case .calories: return "met:calories"
        case .weight: return "met:weight"
        case .coupled: return "square.split.2x1.fill"
        case .coach: return NunaGlyph.anya
        }
    }
}

extension NunaTrendPage {
    /// The page name as plain text, for rows that are built from strings.
    var titleText: String {
        switch self {
        case .effort: return String(localized: "Strain")
        case .calories: return String(localized: "Calories")
        case .steps: return String(localized: "Steps")
        case .hrZonesLow: return String(localized: "Heart rate zones 1–3")
        case .hrZonesHigh: return String(localized: "Heart rate zones 4–5")
        case .hrZonesAll: return String(localized: "Heart rate zones all")
        case .strengthTime: return String(localized: "Strength activity time")
        case .avgHr: return String(localized: "Average heart rate")
        case .totalVolumeLoad: return String(localized: "Total volume load")
        case .charge: return String(localized: "Recovery")
        case .hrv: return String(localized: "Heart rate variability")
        case .rhr: return String(localized: "Resting heart rate")
        case .respiratory: return String(localized: "Respiratory rate")
        case .restPerformance: return String(localized: "Sleep performance")
        case .timeInBed: return String(localized: "Time in bed")
        case .hoursNeededHours: return String(localized: "Hours vs. needed (hours)")
        case .hoursNeededPct: return String(localized: "Hours vs. needed (%)")
        case .consistency: return String(localized: "Sleep consistency")
        case .restorative: return String(localized: "Restorative sleep (hours)")
        case .efficiency: return String(localized: "Sleep efficiency")
        case .debt: return String(localized: "Sleep debt")
        case .vo2max: return String(localized: "VO₂ max")
        case .skinTemp: return String(localized: "Skin temperature")
        case .weight: return String(localized: "Weight")
        case .leanBodyMass: return String(localized: "Lean body mass")
        case .vitality: return String(localized: "Vitality")
        case .spo2: return String(localized: "Blood oxygen")
        case .stressTotal: return String(localized: "Total day stress")
        case .stressNonActivity: return String(localized: "Non activity stress")
        case .stressSleep: return String(localized: "Sleep stress")
        }
    }
}

extension NunaTrendPage.Section {
    var titleText: String {
        switch self {
        case .effort: return String(localized: "Strain")
        case .charge: return String(localized: "Recovery")
        case .rest: return String(localized: "Sleep")
        case .other: return String(localized: "Other")
        }
    }
}

/// What is stored for My Dashboard: the ordered ids of its entries, in one key of its own. The cards among them are written to Your cards' key as well,
/// so the Default looks keep showing the same ones.
enum NunaDashPrefs {
    static let key = "nuna.myDashboard"

    static func encode(_ items: [NunaDashItem]) -> String {
        let ids = items.map(\.id)
        if let data = try? JSONEncoder().encode(ids), let json = String(data: data, encoding: .utf8) { return json }
        return ids.joined(separator: ",")
    }

    /// The entries to show: the stored list, or, until one is stored, the cards Your cards holds.
    static func items(_ raw: String, cardsRaw: String) -> [NunaDashItem] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return NunaTodayDefaults.yourCardsEnabled(cardsRaw).map(NunaDashItem.card) }
        var ids: [String] = []
        if let data = trimmed.data(using: .utf8), let decoded = try? JSONDecoder().decode([String].self, from: data) { ids = decoded }
        else { ids = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        let all = Dictionary(NunaDashItem.canonicalOrder.map { ($0.id, $0) }, uniquingKeysWith: { l, _ in l })
        var seen = Set<String>()
        return ids.compactMap { id in all[id].flatMap { seen.insert(id).inserted ? $0 : nil } }
    }
}

extension NunaTodayView {
    /// The earlier figure of a page's series: the latest day before `day` that has one.
    func earlier(_ series: [String: Double], before day: String) -> Double? {
        series.keys.filter { $0 < day }.max().flatMap { series[$0] }
    }

    /// The row of a trend page: the figure of the day on show, the one before it under it, and the page it opens.
    func pageRow(_ page: NunaTrendPage) -> NunaLinkRow {
        let day = dayKeyNow
        let h = history
        func hm(_ minutes: Double) -> String { let m = Int(minutes.rounded()); return String(format: "%d:%02d", m / 60, m % 60) }
        func pct(_ v: Double) -> String { String(format: "%.0f%%", locale: AppLanguage.activeLocale, v) }
        func make(_ series: [String: Double], decimals: Int = 0, good: Bool?, format: @escaping (Double) -> String)
            -> (String?, NunaTrend?) {
            // The figure of the day on show, else the latest one before it (today's night may not be in yet).
            guard let nowKey = series[day] != nil ? day : series.keys.filter({ $0 <= day }).max(), let now = series[nowKey] else { return (nil, nil) }
            return (format(now), NunaTrend.make(current: now, previous: earlier(series, before: nowKey), decimals: decimals, upIsGood: good, format: format))
        }
        func fig(_ v: Double?, _ previous: Double?, _ decimals: Int = 0, good: Bool?) -> (String?, NunaTrend?) {
            guard let v else { return (nil, nil) }
            return (String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, v), NunaTrend.make(current: v, previous: previous, decimals: decimals, upIsGood: good, format: nil))
        }
        let scale = UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? EffortScale.whoop.rawValue)
        var figure: (String?, NunaTrend?) = (nil, nil)
        switch page {
        case .effort:
            let shown = h.effort.mapValues { UnitFormatter.effortValue($0, scale: scale) }
            figure = make(shown, decimals: 1, good: nil) { String(format: "%.1f", locale: AppLanguage.activeLocale, $0) }
        case .charge: figure = make(h.charge, good: true, format: pct)
        case .restPerformance: figure = make(h.performance, good: true, format: pct)
        case .timeInBed:
            figure = make(Dictionary(uniqueKeysWithValues: h.bedHour.compactMap { k, b in h.wakeHour[k].map { (k, ($0 - b) * 60) } }), good: true, format: hm)
        case .hoursNeededHours: figure = make(h.asleepMin, good: true, format: hm)
        case .hoursNeededPct:
            figure = make(Dictionary(uniqueKeysWithValues: h.asleepMin.keys.compactMap { k in h.hoursVsNeeded(k).map { (k, $0) } }), good: true, format: pct)
        case .consistency: figure = make(h.consistency, good: true, format: pct)
        case .efficiency: figure = make(h.efficiency, good: true, format: pct)
        case .restorative:
            figure = make(Dictionary(uniqueKeysWithValues: h.deepMin.keys.compactMap { k in h.remMin[k].map { (k, h.deepMin[k]! + $0) } }), good: true, format: hm)
        case .debt: figure = make(h.debtMin, good: false, format: hm)
        // The figures Today already holds for the day on show, each against the one before it, so these rows show their number straight away.
        case .steps: figure = fig(model.steps, model.previous["steps"], good: true)
        case .calories: figure = fig(model.calories, model.previous["calories"], good: nil)
        case .hrv: figure = fig(model.hrv, model.hrvDelta.flatMap { d in model.hrv.map { $0 - d } }, good: true)
        case .rhr: figure = fig(model.restingHr, model.restingHrDelta.flatMap { d in model.restingHr.map { $0 - d } }, good: false)
        case .respiratory: figure = fig(model.respiratory, model.respiratoryDelta.flatMap { d in model.respiratory.map { $0 - d } }, 1, good: nil)
        case .spo2: figure = fig(model.spo2, model.spo2Delta.flatMap { d in model.spo2.map { $0 - d } }, good: true)
        case .skinTemp: figure = fig(model.extras["skin_temp"], model.previous["skin_temp"], 1, good: nil)
        case .weight: figure = fig(model.extras["weight"], model.previous["weight"], 1, good: nil)
        case .vitality: figure = fig(model.extras["vitality"], model.previous["vitality"], good: true)
        // Not measured every day, or kept in a history this screen does not load: these open their page without a figure.
        case .hrZonesLow, .hrZonesHigh, .hrZonesAll, .strengthTime, .avgHr, .totalVolumeLoad, .vo2max, .leanBodyMass,
             .stressTotal, .stressNonActivity, .stressSleep: break
        }
        return NunaLinkRow(id: "page." + page.rawValue, title: page.titleText, subtitle: page.section.titleText, value: figure.0,
                           icon: page.icon, tint: nil, target: NunaRowTarget(kind: .nuna(.trend(page))), trend: figure.1)
    }
}

/// The My Dashboard page of the Today editor: the cards on the dashboard in the order they show (the handle at the right moves one, sliding
/// it to the left uncovers the red delete button), and under them everything that can be added, each with a plus.
struct NunaDashboardEditor: View {
    @Binding var draft: EditableLayoutDraft<NunaDashItem>
    let onReset: () -> Void

    /// A row is 60 pt tall with 8 pt between rows.
    private static let pitch: CGFloat = 68
    @State private var dragging: NunaDashItem?
    @State private var dragY: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("My Dashboard").font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12).padding(.bottom, 4)
                ForEach(draft.visible) { item in
                    NunaSwipeDeleteRow(enabled: dragging == nil, onDelete: { remove(item) }) {
                        row(item) { handle(item) }
                    }
                    .offset(y: shift(item)).zIndex(dragging == item ? 1 : 0)
                    .shadow(color: .black.opacity(dragging == item ? 0.35 : 0), radius: 10, y: 4)
                    .animation(dragging == item ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: shift(item))
                }

                if !draft.hidden.isEmpty {
                    HStack(spacing: 14) {
                        Text("Add to my dashboard").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Rectangle().fill(NunaPalette.hairline).frame(height: 1)
                    }
                    .padding(.top, 22).padding(.bottom, 4)
                    ForEach(draft.hidden) { item in
                        row(item) {
                            Button { add(item) } label: {
                                Image(systemName: "plus").font(.nuna(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityLabel(Text("Add"))
                        }
                        .onTapGesture { add(item) }
                    }
                }

                Button(role: .destructive, action: onReset) {
                    Text("Reset this layout").font(.nuna(size: 15.5, weight: .bold)).frame(maxWidth: .infinity).frame(height: 44)
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(dragging != nil)
        .background(NunaPalette.canvas)
    }

    private func row<Trailing: View>(_ item: NunaDashItem, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            NunaIcon(name: item.icon, size: 18).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
            Text(verbatim: item.title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.leading, 14).padding(.trailing, 6).frame(height: 60)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
    }

    // MARK: Moving

    /// The two bars at the right of a row: dragging them moves the row, and the rows it passes make way.
    private func handle(_ item: NunaDashItem) -> some View {
        Image(systemName: "equal").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { v in dragging = item; dragY = v.translation.height }
                    .onEnded { _ in
                        if let from = draft.visible.firstIndex(of: item) {
                            let to = target(from)
                            if to != from { withAnimation(.easeInOut(duration: 0.2)) { draft.moveVisible(from: IndexSet(integer: from), to: to > from ? to + 1 : to) } }
                        }
                        dragging = nil; dragY = 0
                    }
            )
            .accessibilityLabel(Text("Reorder"))
    }

    /// Where the row being dragged would land.
    private func target(_ from: Int) -> Int {
        min(max(from + Int((dragY / Self.pitch).rounded()), 0), draft.visible.count - 1)
    }

    /// How far a row is moved on screen: the dragged one follows the finger, the ones it has passed move one place the other way.
    private func shift(_ item: NunaDashItem) -> CGFloat {
        guard let dragging, let from = draft.visible.firstIndex(of: dragging), let i = draft.visible.firstIndex(of: item) else { return 0 }
        if item == dragging { return dragY }
        let to = target(from)
        if from < i && i <= to { return -Self.pitch }
        if to <= i && i < from { return Self.pitch }
        return 0
    }

    private func add(_ item: NunaDashItem) {
        withAnimation(.easeInOut(duration: 0.2)) { draft.show(item) }
    }

    private func remove(_ item: NunaDashItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            guard let i = draft.visible.firstIndex(of: item) else { return }
            draft.hidden.append(draft.visible.remove(at: i))
            draft.hidden = NunaDashItem.canonicalOrder.filter { draft.hidden.contains($0) }
        }
    }
}

/// My Dashboard on Today: the heading and "Customize" on the canvas, then one card per entry (icon, name, the figure with its comparison).
struct NunaDashboardCards: View {
    let rows: [NunaLinkRow]
    let onCoach: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("My Dashboard").font(.nuna(size: 19.5, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Spacer(minLength: 8)
                Button(action: onEdit) {
                    HStack(spacing: 8) {
                        Text("Customize").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        Image(systemName: "pencil").font(.nuna(size: 15, weight: .regular))
                    }
                    .foregroundStyle(NunaPalette.textPrimary).frame(height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4).padding(.bottom, 2)
            ForEach(rows) { row in link(row) }
        }
    }

    private func card(_ row: NunaLinkRow) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 18)) {
            HStack(spacing: 14) {
                NunaIcon(name: row.icon, size: 20).foregroundStyle(row.tint ?? NunaPalette.textSecondary).frame(width: 30)
                Text(verbatim: row.title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if let v = row.value {
                    NunaTrendFigure(value: v, trend: row.trend, size: 20)
                } else {
                    Image(systemName: "chevron.right").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                }
            }
            .frame(height: 56)
        }
    }

    @ViewBuilder private func link(_ row: NunaLinkRow) -> some View {
        switch row.target.kind {
        case .tab(let r): NavigationLink(value: r) { card(row) }.buttonStyle(.plain)
        case .nuna(let r): NavigationLink(value: r) { card(row) }.buttonStyle(.plain)
        case .coach: Button(action: onCoach) { card(row) }.buttonStyle(.plain)
        }
    }
}
#endif
