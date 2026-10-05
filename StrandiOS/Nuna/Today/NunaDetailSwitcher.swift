#if os(iOS)
import SwiftUI
import StrandDesign

/// The dropdown at the top of the vital and score detail screens: it lists the sibling screens and swaps the current one in
/// place, so the wearer moves from Heart Rate Variability to Resting Heart Rate to Breathing without going back to the menu.
struct NunaDetailSwitch {
    struct Item: Identifiable, Hashable {
        let key: String
        let title: String
        let icon: String
        var id: String { key }
    }
    let current: String
    let items: [Item]
    let select: (String) -> Void
}

private struct NunaDetailSwitchKey: EnvironmentKey { static let defaultValue: NunaDetailSwitch? = nil }

extension EnvironmentValues {
    var nunaDetailSwitch: NunaDetailSwitch? {
        get { self[NunaDetailSwitchKey.self] }
        set { self[NunaDetailSwitchKey.self] = newValue }
    }
}

struct NunaDetailSwitcher: View {
    @Environment(\.nunaDetailSwitch) private var sw
    /// In the screen header, between the back button and Anya: the same height as they are.
    var inHeader = false

    var body: some View {
        if let sw, let cur = sw.items.first(where: { $0.key == sw.current }) {
            Menu {
                ForEach(sw.items) { item in
                    Button { sw.select(item.key) } label: {
                        if item.key == sw.current { Label(item.title, systemImage: "checkmark") } else { Text(verbatim: item.title) }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: cur.icon).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 26)
                    Text(verbatim: cur.title).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                }
                .padding(.horizontal, inHeader ? 12 : 16).frame(height: inHeader ? 44 : 54)
                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(NunaPalette.hairlineSoft, lineWidth: 1))
            }
            .accessibilityLabel(Text("Switch metric"))
        }
    }
}

/// The metrics the dropdown moves between (Sleep keeps its own multi-night screen).
enum NunaDetailSet {
    static let metricKeys = ["recovery", "strain", "hrv", "rhr", "resp_rate", "spo2", "skin_temp", "stress"]

    static func items() -> [NunaDetailSwitch.Item] {
        metricKeys.compactMap { k in
            guard let m = MetricCatalog.metric(key: k, source: "my-whoop") else { return nil }
            let title = k == "stress" ? String(localized: "Stress monitor") : m.title
            return .init(key: k, title: title, icon: m.icon)
        }
    }
}

/// Holds the metric on show and renders the right screen for it. Switching from the dropdown swaps the screen in place, so
/// the navigation stack stays one level deep.
struct NunaMetricHost: View {
    @State private var current: MetricDescriptor

    init(initial: MetricDescriptor) { _current = State(initialValue: initial) }

    var body: some View {
        screen(for: current)
            .id(current.id)
            .environment(\.nunaDetailSwitch, NunaDetailSet.metricKeys.contains(current.key)
                ? NunaDetailSwitch(current: current.key, items: NunaDetailSet.items()) { key in
                    if let m = MetricCatalog.metric(key: key, source: "my-whoop") { current = m }
                } : nil)
    }

    @ViewBuilder private func screen(for m: MetricDescriptor) -> some View {
        switch (m.key, m.source) {
        case ("recovery", _): NunaChargeDetailView()
        case ("strain", _): NunaEffortDetailView()
        case ("stress", "my-whoop"): NunaStressDetailView()
        case ("sleep_performance", _): NunaSleepView()
        case ("skin_temp", _): NunaSkinTempView()
        case ("fitness_age", _): NunaFitnessAgeView()
        default: NunaMetricDetailView(metric: m)
        }
    }
}
#endif
