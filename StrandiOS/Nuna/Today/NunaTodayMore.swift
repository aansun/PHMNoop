#if os(iOS)
import SwiftUI
import StrandDesign

/// Today sections that were Default-only until now: Your Cards, Added Cards and Menstrual Cycle.
/// They are compact link rows in one card; the full cards stay in their own screens.

struct NunaRowTarget {
    enum Kind { case tab(TabRoute), nuna(NunaTodayRoute), coach }
    let kind: Kind
}

struct NunaLinkRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let value: String?
    let icon: String
    let tint: Color?
    let target: NunaRowTarget
    /// The comparison with the figure before it, drawn beside and under the figure, as in Key Metrics: a triangle when it moved, a dot when it
    /// did not or there is nothing earlier.
    var trend: NunaTrend? = nil
}

struct NunaRowsCard: View {
    let rows: [NunaLinkRow]
    let onCoach: () -> Void
    /// A heading inside the card, with a pencil on the right that opens this card's own settings.
    var title: LocalizedStringKey?
    var onEdit: (() -> Void)?

    var body: some View {
        NunaCard(small: true, padding: title == nil ? nil : EdgeInsets(top: 10, leading: 18, bottom: 6, trailing: 18)) {
            VStack(spacing: 0) {
                if let title {
                    NunaTitleRow(title: title) {
                        if let onEdit {
                            Button(action: onEdit) {
                                Image(systemName: "pencil").font(.nuna(size: 14, weight: .heavy)).frame(width: 40, height: 40).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityLabel(Text("Edit"))
                            .padding(.trailing, -13)
                        }
                    }
                    .padding(.bottom, 8)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    if idx > 0 { NunaDivider() }
                    link(row)
                }
            }
        }
    }

    private func figure(_ value: String, _ row: NunaLinkRow) -> some View {
        NunaTrendFigure(value: value, trend: row.trend)
    }

    @ViewBuilder private func link(_ row: NunaLinkRow) -> some View {
        let content = NunaListRow(LocalizedStringKey(row.title), description: LocalizedStringKey(row.subtitle),
                                  systemImage: row.icon, tint: row.tint, showsChevron: true) {
            if let v = row.value { figure(v, row) }
        }
        switch row.target.kind {
        case .tab(let r): NavigationLink(value: r) { content }.buttonStyle(.plain)
        case .nuna(let r): NavigationLink(value: r) { content }.buttonStyle(.plain)
        case .coach: Button(action: onCoach) { content }.buttonStyle(.plain)
        }
    }
}

extension NunaTodayView {
    /// Rows for the user's "Your Cards" selection.
    func yourCardRows() -> [NunaLinkRow] {
        func desc(_ key: String, _ source: String = "my-whoop") -> NunaRowTarget? {
            MetricCatalog.metric(key: key, source: source).map { NunaRowTarget(kind: .nuna(.metric($0))) }
        }
        func num(_ v: Double?, _ d: Int = 0) -> String? {
            v.map { String(format: "%.\(d)f", locale: AppLanguage.activeLocale, $0) }
        }
        let steps = MetricCatalog.todayStepsMetric(hasMeasuredSteps: model.steps != nil)
            .map { NunaRowTarget(kind: .nuna(.metric($0))) }
        return NunaDashPrefs.items(myDashboardRaw, cardsRaw: dashboardCardsRaw).compactMap { item -> NunaLinkRow? in
            let card: DashboardCard
            switch item {
            case .page(let page): return pageRow(page)
            case .card(let c): card = c
            }
            let ex = model.extras
            let made: (String?, NunaRowTarget?, String, Color?)
            switch card {
            case .hrv:         made = (num(model.hrv), desc("hrv"), "waveform.path.ecg", nil)
            case .restingHr:   made = (num(model.restingHr), desc("rhr"), "heart.fill", nil)
            case .respiratory: made = (num(model.respiratory, 1), desc("resp_rate"), "lungs.fill", nil)
            case .steps:       made = (num(model.steps), steps, "figure.walk", nil)
            case .stepsAverage30: made = (nil, steps, "figure.walk", nil)
            case .stress:      made = (num(model.stress, 1), NunaRowTarget(kind: .tab(.stress)), "wind", NunaPalette.charge)
            case .fitnessAge:  made = (num(ex["fitness_age"]), desc("fitness_age"), "figure.run", nil)
            case .vo2max:      made = (num(ex["vo2max_est"], 1), desc("vo2max_est"), "lungs", nil)
            case .vitality:    made = (num(ex["vitality"]), desc("vitality"), "sparkles", nil)
            case .bloodOxygen: made = (num(model.spo2), desc("spo2"), "drop.fill", nil)
            case .skinTemp:    made = (num(ex["skin_temp"], 1), desc("skin_temp"), "thermometer", nil)
            case .sleep:
                made = (model.sleepMinutes.map { "\(Int($0) / 60)h \(Int($0) % 60)m" }, NunaRowTarget(kind: .nuna(.sleep(0))), "moon.zzz.fill", NunaPalette.restText)
            case .calories:    made = (num(model.calories), desc("energy_kcal"), "flame.fill", nil)
            case .hydration:
                guard hydrationEnabled else { return nil }
                made = (nil, NunaRowTarget(kind: .nuna(.hydration)), "drop.fill", NunaPalette.effortText)
            case .weight:
                // The latest reading (Apple Health or one added on the Weight page), else the weight in the profile.
                made = (num(ex["weight"] ?? (profile.weightKg > 0 ? profile.weightKg : nil), 1), NunaRowTarget(kind: .nuna(.weight)), "scalemass.fill", nil)
            case .coupled:     made = (nil, NunaRowTarget(kind: .tab(.coupled)), "square.split.2x1.fill", nil)
            case .coach:
                guard coachEnabled else { return nil }
                made = (nil, NunaRowTarget(kind: .coach), NunaGlyph.anya, nil)
            }
            guard let target = made.1 else { return nil }
            // Every figure with a value is compared with the one before it; a card with no value (hydration, Anya) has nothing to compare.
            func cmp(_ current: Double?, _ previous: Double?, _ decimals: Int = 0, good: Bool?, format: ((Double) -> String)? = nil) -> NunaTrend? {
                NunaTrend.make(current: current, previous: previous, decimals: decimals, upIsGood: good, format: format)
            }
            func before(_ value: Double?, _ delta: Double?) -> Double? { value.flatMap { v in delta.map { v - $0 } } }
            let trend: NunaTrend?
            switch card {
            case .hrv: trend = cmp(model.hrv, before(model.hrv, model.hrvDelta), good: true)
            case .restingHr: trend = cmp(model.restingHr, before(model.restingHr, model.restingHrDelta), good: false)
            case .respiratory: trend = cmp(model.respiratory, before(model.respiratory, model.respiratoryDelta), 1, good: nil)
            case .bloodOxygen: trend = cmp(model.spo2, before(model.spo2, model.spo2Delta), good: true)
            case .steps: trend = cmp(model.steps, model.previous["steps"], good: true)
            case .stress: trend = cmp(model.stress, model.previous["stress"], 1, good: false)
            case .fitnessAge: trend = cmp(ex["fitness_age"], model.previous["fitness_age"], good: false)
            case .vo2max: trend = cmp(ex["vo2max_est"], model.previous["vo2max_est"], 1, good: true)
            case .vitality: trend = cmp(ex["vitality"], model.previous["vitality"], good: true)
            case .skinTemp: trend = cmp(ex["skin_temp"], model.previous["skin_temp"], 1, good: nil)
            case .calories: trend = cmp(model.calories, model.previous["calories"], good: nil)
            case .sleep:
                trend = cmp(model.sleepMinutes, model.previous["sleep"], good: true, format: { "\(Int($0) / 60)h \(Int($0) % 60)m" })
            case .weight: trend = cmp(ex["weight"] ?? (profile.weightKg > 0 ? profile.weightKg : nil), ex["weight"] == nil ? nil : model.previous["weight"], 1, good: nil)
            case .stepsAverage30, .hydration, .coupled, .coach: trend = nil
            }
            return NunaLinkRow(id: card.rawValue, title: card.title, subtitle: card.subtitle, value: made.0,
                               icon: made.2, tint: made.3, target: target, trend: trend)
        }
    }

    func addedCardRows() -> [NunaLinkRow] {
        HostedCardPrefs.decodeEnabled(hostedCardsRaw).map { card in
            let sleep = card.rawValue.hasPrefix("sleep.")
            return NunaLinkRow(id: card.rawValue, title: card.title, subtitle: sleep ? "From Sleep" : "From Trends", value: nil,
                               icon: sleep ? "moon.zzz.fill" : "chart.line.uptrend.xyaxis",
                               tint: sleep ? NunaPalette.restText : nil,
                               target: NunaRowTarget(kind: sleep ? .nuna(.sleep(0)) : .tab(.metricExplorer)))
        }
    }
}
#endif
