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
    static let pages: [NunaTrendPage] = NunaTrendPage.allCases.filter { ![.hrv, .rhr, .respiratory, .steps, .calories].contains($0) }

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

    var icon: String {
        switch self {
        case .card(let c): return c.icon
        case .page(let p): return p.icon
        }
    }
}

extension NunaTrendPage {
    /// The page name as plain text, for rows that are built from strings.
    var titleText: String {
        switch self {
        case .effort: return String(localized: "Effort")
        case .calories: return String(localized: "Calories")
        case .steps: return String(localized: "Steps")
        case .hrZonesLow: return String(localized: "Heart rate zones 1–3")
        case .hrZonesHigh: return String(localized: "Heart rate zones 4–5")
        case .charge: return String(localized: "Charge")
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
        }
    }
}

extension NunaTrendPage.Section {
    var titleText: String {
        switch self {
        case .effort: return String(localized: "Effort")
        case .charge: return String(localized: "Charge")
        case .rest: return String(localized: "Rest")
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
    private func earlier(_ series: [String: Double], before day: String) -> Double? {
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
        case .hrZonesLow, .hrZonesHigh, .steps, .calories, .hrv, .rhr, .respiratory: break
        }
        return NunaLinkRow(id: "page." + page.rawValue, title: page.titleText, subtitle: page.section.titleText, value: figure.0,
                           icon: page.icon, tint: nil, target: NunaRowTarget(kind: .nuna(.trend(page))), trend: figure.1)
    }
}

/// The My Dashboard page of the Today editor: the cards on the dashboard in the order they show (drag to move, the minus takes one off), and under
/// them everything that can be added, each with a plus.
struct NunaDashboardEditor: View {
    @Binding var draft: EditableLayoutDraft<NunaDashItem>
    let onReset: () -> Void

    var body: some View {
        List {
            Text("My Dashboard").font(.nuna(size: 26, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 12, leading: NunaSpacing.screenH, bottom: 8, trailing: NunaSpacing.screenH))
            ForEach(draft.visible) { item in
                row(item) {
                    Button { remove(item) } label: {
                        Image(systemName: "minus.circle.fill").font(.nuna(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                            .frame(width: 36, height: 36).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Remove"))
                }
                .deleteDisabled(true)
            }
            .onMove { draft.moveVisible(from: $0, to: $1) }

            if !draft.hidden.isEmpty {
                HStack(spacing: 14) {
                    Text("Add to my dashboard").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Rectangle().fill(NunaPalette.hairline).frame(height: 1)
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 22, leading: NunaSpacing.screenH, bottom: 8, trailing: NunaSpacing.screenH))
                .moveDisabled(true).deleteDisabled(true)
                ForEach(draft.hidden) { item in
                    row(item, reserve: 40) {
                        Button { add(item) } label: {
                            Image(systemName: "plus").font(.nuna(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                                .frame(width: 36, height: 36).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel(Text("Add"))
                    }
                    .moveDisabled(true).deleteDisabled(true)
                    .onTapGesture { add(item) }
                }
            }

            Button(role: .destructive, action: onReset) {
                Text("Reset this layout").font(.nuna(size: 15.5, weight: .bold)).frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 12, leading: NunaSpacing.screenH, bottom: 12, trailing: NunaSpacing.screenH)).moveDisabled(true).deleteDisabled(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(NunaPalette.canvas)
        .environment(\.editMode, .constant(.active))
    }

    /// `reserve` keeps a row as wide as the rows that carry the system drag handle on their right.
    private func row<Trailing: View>(_ item: NunaDashItem, reserve: CGFloat = 0, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon).font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
            Text(verbatim: item.title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.leading, 14).padding(.trailing, 2).frame(height: 60)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: NunaSpacing.screenH, bottom: 4, trailing: NunaSpacing.screenH + reserve))
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
                Text("My Dashboard").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
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
                Image(systemName: row.icon).font(.nuna(size: 20, weight: .regular)).foregroundStyle(row.tint ?? NunaPalette.textSecondary).frame(width: 30)
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
