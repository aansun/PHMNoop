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
    /// The change against yesterday (HRV, resting heart rate, respiratory rate, blood oxygen), shown as a small triangle with the value
    /// before it under the figure, as in Key Metrics. `upIsGood` colours it; nil leaves it neutral.
    var delta: Double? = nil
    var upIsGood: Bool? = nil
    var decimals = 0
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

    /// The figure with its change as a triangle, and the value before underneath. The triangle's slot is always there, so the figures of
    /// every row end on the same line.
    private func figure(_ value: String, _ row: NunaLinkRow) -> some View {
        let step = row.decimals == 0 ? 1.0 : 0.1
        let moved = row.delta.flatMap { abs($0) >= step - 0.0001 ? $0 : nil }
        let tint: Color = row.upIsGood == nil ? NunaPalette.textSecondary : (((moved ?? 0) > 0) == row.upIsGood! ? NunaPalette.charge : NunaPalette.warning)
        let now = Double(value.replacingOccurrences(of: ",", with: "."))
        return VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .center, spacing: 5) {
                Text(verbatim: value).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Group {
                    if let moved {
                        Image(systemName: moved > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(tint)
                    } else { Color.clear }
                }
                .frame(width: 10, height: 10)
            }
            if let moved, let now {
                Text(verbatim: String(format: "%.\(row.decimals)f", locale: AppLanguage.activeLocale, now - moved))
                    .font(.nuna(size: 12, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                    .monospacedDigit().padding(.trailing, 15)
            }
        }
    }

    @ViewBuilder private func link(_ row: NunaLinkRow) -> some View {
        let content = NunaListRow(LocalizedStringKey(row.title), subtitle: LocalizedStringKey(row.subtitle),
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
                made = (nil, NunaRowTarget(kind: .nuna(.hydration)), "drop.fill", NunaPalette.effortText)
            case .coupled:     made = (nil, NunaRowTarget(kind: .tab(.coupled)), "square.split.2x1.fill", nil)
            case .coach:
                guard coachEnabled else { return nil }
                made = (nil, NunaRowTarget(kind: .coach), NunaGlyph.anya, nil)
            }
            guard let target = made.1 else { return nil }
            var change: (Double?, Bool?, Int) = (nil, nil, 0)
            switch card {
            case .hrv: change = (model.hrvDelta, true, 0)
            case .restingHr: change = (model.restingHrDelta, false, 0)
            case .respiratory: change = (model.respiratoryDelta, nil, 1)
            case .bloodOxygen: change = (model.spo2Delta, true, 0)
            default: break
            }
            return NunaLinkRow(id: card.rawValue, title: card.title, subtitle: card.subtitle, value: made.0,
                               icon: made.2, tint: made.3, target: target, delta: change.0, upIsGood: change.1, decimals: change.2)
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
