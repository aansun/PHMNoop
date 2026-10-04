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
}

struct NunaRowsCard: View {
    let rows: [NunaLinkRow]
    let onCoach: () -> Void

    var body: some View {
        NunaCard(small: true) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    if idx > 0 { NunaDivider() }
                    link(row)
                }
            }
        }
    }

    @ViewBuilder private func link(_ row: NunaLinkRow) -> some View {
        let content = NunaListRow(LocalizedStringKey(row.title), subtitle: LocalizedStringKey(row.subtitle),
                                  systemImage: row.icon, tint: row.tint, showsChevron: true) {
            if let v = row.value {
                Text(verbatim: v).font(.system(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            }
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
        return DashboardCardPrefs.decodeEnabled(dashboardCardsRaw).compactMap { card -> NunaLinkRow? in
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
                made = (nil, NunaRowTarget(kind: .tab(.hydration)), "drop.fill", NunaPalette.effortText)
            case .coupled:     made = (nil, NunaRowTarget(kind: .tab(.coupled)), "square.split.2x1.fill", nil)
            case .coach:
                guard coachEnabled else { return nil }
                made = (nil, NunaRowTarget(kind: .coach), "sparkles", nil)
            }
            guard let target = made.1 else { return nil }
            return NunaLinkRow(id: card.rawValue, title: card.title, subtitle: card.subtitle, value: made.0,
                               icon: made.2, tint: made.3, target: target)
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
