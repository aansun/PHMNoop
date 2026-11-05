#if os(iOS)
import SwiftUI
import StrandDesign

/// Every trend page of the app, in the order the dropdown at the top of a trend page lists them: Effort, Charge and Rest, each with the readings it is made of.
enum NunaTrendPage: String, CaseIterable, Identifiable {
    case effort, steps, hrZonesLow, hrZonesHigh, hrZonesAll, strengthTime, totalVolumeLoad, calories, vo2max
    case charge, hrv, rhr, respiratory, skinTemp
    case restPerformance, timeInBed, hoursNeededHours, hoursNeededPct, consistency, restorative, efficiency, debt
    case weight, leanBodyMass, vitality, spo2, stressTotal, stressNonActivity, stressSleep

    var id: String { rawValue }

    enum Section: CaseIterable {
        case effort, charge, rest, other

        var title: LocalizedStringKey {
            switch self { case .effort: return "Strain"; case .charge: return "Recovery"; case .rest: return "Sleep"; case .other: return "Other" }
        }
        var pages: [NunaTrendPage] { NunaTrendPage.allCases.filter { $0.section == self } }
    }

    var section: Section {
        switch self {
        case .effort, .steps, .calories, .hrZonesLow, .hrZonesHigh, .hrZonesAll, .strengthTime, .totalVolumeLoad, .vo2max: return .effort
        case .charge, .hrv, .rhr, .respiratory, .skinTemp: return .charge
        case .weight, .leanBodyMass, .vitality, .spo2, .stressTotal, .stressNonActivity, .stressSleep: return .other
        default: return .rest
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .effort: return "Day Strain"
        case .calories: return "Calories"
        case .steps: return "Steps"
        case .hrZonesLow: return "Heart rate zones 1–3"
        case .hrZonesHigh: return "Heart rate zones 4–5"
        case .hrZonesAll: return "Heart rate zones all"
        case .strengthTime: return "Strength activity time"
        case .totalVolumeLoad: return "Total volume load"
        case .charge: return "Recovery"
        case .hrv: return "Heart rate variability"
        case .rhr: return "Resting heart rate"
        case .respiratory: return "Respiratory rate"
        case .restPerformance: return "Sleep performance"
        case .timeInBed: return "Time in bed"
        case .hoursNeededHours: return "Hours vs. needed (hours)"
        case .hoursNeededPct: return "Hours vs. needed (%)"
        case .consistency: return "Sleep consistency"
        case .restorative: return "Restorative sleep (hours)"
        case .efficiency: return "Sleep efficiency"
        case .debt: return "Sleep debt"
        case .vo2max: return "VO₂ max"
        case .skinTemp: return "Skin temperature"
        case .weight: return "Weight"
        case .leanBodyMass: return "Lean body mass"
        case .vitality: return "Vitality"
        case .spo2: return "Blood oxygen"
        case .stressTotal: return "Total day stress"
        case .stressNonActivity: return "Non activity stress"
        case .stressSleep: return "Sleep stress"
        }
    }

    var icon: String {
        switch self {
        case .effort: return "met:day-strain"
        case .calories: return "met:calories"
        case .steps: return "met:steps"
        case .hrZonesLow: return "met:heart-rate-zones-1-3"
        case .hrZonesHigh: return "met:heart-rate-zones-4-5"
        case .hrZonesAll: return "met:heart-rate-zones-all"
        case .strengthTime: return "met:strength-activity-time"
        case .totalVolumeLoad: return "met:total-volume-load"
        case .charge: return "met:recovery"
        case .hrv: return "met:heart-rate-variability"
        case .rhr: return "met:resting-heart-rate"
        case .respiratory: return "met:respiratory-rate"
        case .restPerformance: return "met:sleep-performance"
        case .timeInBed: return "met:time-in-bed"
        case .hoursNeededHours: return "met:hours-vs-needed-hours"
        case .hoursNeededPct: return "met:hours-vs-needed"
        case .consistency: return "met:sleep-consistency"
        case .restorative: return "met:restorative-sleep-hours"
        case .debt: return "met:sleep-debt"
        case .efficiency: return "met:sleep-efficiency"
        case .vo2max: return "met:vo2-max"
        case .skinTemp: return "vital:temp"
        case .weight: return "met:weight"
        case .leanBodyMass: return "met:lean-body-mass"
        case .vitality: return "sparkles"
        case .spo2: return "vital:spo2"
        case .stressTotal: return NunaStressCategory.total.icon
        case .stressNonActivity: return NunaStressCategory.nonActivity.icon
        case .stressSleep: return NunaStressCategory.sleep.icon
        }
    }

    /// The page a stored metric opens, when it has one of these (nil leaves the metric to its own screen).
    static func forMetric(_ key: String) -> NunaTrendPage? {
        switch key {
        case "hrv": return .hrv
        case "rhr": return .rhr
        case "resp_rate": return .respiratory
        case "energy_kcal": return .calories
        case "steps", "steps_est": return .steps
        case "sleep_consistency": return .consistency
        case "sleep_efficiency": return .efficiency
        case "sleep_debt", "sleep_debt_min": return .debt
        case "hours_vs_needed": return .hoursNeededPct
        case "spo2": return .spo2
        case "skin_temp": return .skinTemp
        case "vo2max_est": return .vo2max
        case "vitality": return .vitality
        case "weight": return .weight
        default: return nil
        }
    }

    @ViewBuilder func view(endingDaysAgo: Int) -> some View {
        switch self {
        case .effort: NunaEffortScoreTrendView(endingDaysAgo: endingDaysAgo)
        case .calories: NunaCaloriesTrendView(endingDaysAgo: endingDaysAgo)
        case .steps: NunaStepsTrendView(endingDaysAgo: endingDaysAgo)
        case .hrZonesLow: NunaEffortActivityDetailView(kind: .lowZones)
        case .hrZonesHigh: NunaEffortActivityDetailView(kind: .highZones)
        case .hrZonesAll: NunaEffortActivityDetailView(kind: .allZones)
        case .strengthTime: NunaEffortActivityDetailView(kind: .strength)
        case .totalVolumeLoad: NunaVolumeLoadTrendView()
        case .charge: NunaChargeScoreTrendView(endingDaysAgo: endingDaysAgo)
        case .hrv: NunaLineTrendView.forMetric("hrv", endingDaysAgo: endingDaysAgo)
        case .rhr: NunaLineTrendView.forMetric("rhr", endingDaysAgo: endingDaysAgo)
        case .respiratory: NunaLineTrendView.forMetric("resp_rate", endingDaysAgo: endingDaysAgo)
        case .restPerformance: NunaRestTrendView(endingDaysAgo: endingDaysAgo)
        case .timeInBed: NunaTimeInBedTrendView(endingDaysAgo: endingDaysAgo)
        case .hoursNeededHours: NunaHoursNeededTrendView(endingDaysAgo: endingDaysAgo)
        case .hoursNeededPct: NunaHoursNeededPctTrendView(endingDaysAgo: endingDaysAgo)
        case .consistency: NunaConsistencyTrendView(endingDaysAgo: endingDaysAgo)
        case .restorative: NunaRestorativeTrendView(endingDaysAgo: endingDaysAgo)
        case .efficiency: NunaEfficiencyTrendView(endingDaysAgo: endingDaysAgo)
        case .debt: NunaSleepDebtTrendView(endingDaysAgo: endingDaysAgo)
        case .vo2max: NunaLineTrendView.forMetric("vo2max_est", endingDaysAgo: endingDaysAgo)
        case .skinTemp: NunaLineTrendView.forMetric("skin_temp", endingDaysAgo: endingDaysAgo)
        case .weight: NunaLineTrendView.forMetric("weight", endingDaysAgo: endingDaysAgo)
        case .leanBodyMass: NunaLeanMassTrendView()
        case .vitality: NunaLineTrendView.forMetric("vitality", endingDaysAgo: endingDaysAgo)
        case .spo2: NunaLineTrendView.forMetric("spo2", endingDaysAgo: endingDaysAgo)
        case .stressTotal: NunaStressTrendView(category: .total)
        case .stressNonActivity: NunaStressTrendView(category: .nonActivity)
        case .stressSleep: NunaStressTrendView(category: .sleep)
        }
    }
}

/// What a trend page needs to draw the dropdown: the page on show, whether the list is open, and what choosing a row does.
struct NunaTrendMenu {
    let current: NunaTrendPage
    @Binding var isOpen: Bool
    let select: (NunaTrendPage) -> Void
}

private struct NunaTrendMenuKey: EnvironmentKey { static let defaultValue: NunaTrendMenu? = nil }

extension EnvironmentValues {
    var nunaTrendMenu: NunaTrendMenu? {
        get { self[NunaTrendMenuKey.self] }
        set { self[NunaTrendMenuKey.self] = newValue }
    }
}

/// Holds the trend page on show. Choosing another one in the dropdown swaps it in place, so the navigation stack stays one level deep.
struct NunaTrendHost: View {
    @State private var page: NunaTrendPage
    @State private var isOpen = false
    var endingDaysAgo = 0

    init(initial: NunaTrendPage, endingDaysAgo: Int = 0) {
        _page = State(initialValue: initial)
        self.endingDaysAgo = endingDaysAgo
    }

    var body: some View {
        page.view(endingDaysAgo: endingDaysAgo)
            .id(page)
            .environment(\.nunaTrendMenu, NunaTrendMenu(current: page, isOpen: $isOpen) { next in
                isOpen = false
                page = next
            })
    }
}

/// The box that names the reading at the top of a trend page. Inside a `NunaTrendHost` it is a button with a chevron that opens the list of every
/// trend page, grouped as Effort, Charge, Rest and Other, the page on show lit; on its own it is only the name.
struct NunaTrendNameBox: View {
    let icon: String
    let title: LocalizedStringKey
    @Environment(\.nunaTrendMenu) private var menu
    /// Inside the host the page on show names its own picture, so the box and the list can never show two different ones.
    private var shownIcon: String { menu?.current.icon ?? icon }

    var body: some View {
        VStack(spacing: 10) {
            if let menu {
                Button { withAnimation(.easeOut(duration: 0.2)) { menu.isOpen.toggle() } } label: { box(open: menu.isOpen, chevron: true) }
                    .buttonStyle(.plain)
                if menu.isOpen { list(menu) }
            } else {
                box(open: false, chevron: false)
            }
        }
    }

    private func box(open: Bool, chevron: Bool) -> some View {
        HStack(spacing: 16) {
            NunaIcon(name: shownIcon, size: 21).foregroundStyle(NunaPalette.textSecondary).frame(width: 32)
            Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 0)
            if chevron { Image(systemName: open ? "chevron.up" : "chevron.down").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary) }
        }
        .padding(.horizontal, 18).frame(height: 60)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
        .contentShape(Rectangle())
    }

    private func list(_ menu: NunaTrendMenu) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(NunaTrendPage.Section.allCases, id: \.self) { section in
                    HStack(spacing: 14) {
                        Text(section.title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Rectangle().fill(NunaPalette.hairline).frame(height: 1)
                    }
                    .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4)
                    ForEach(section.pages) { page in
                        Button { menu.select(page) } label: {
                            HStack(spacing: 14) {
                                NunaIcon(name: page.icon, size: 18).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
                                Text(page.title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).frame(height: 52)
                            .background(page == menu.current ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).id(page)
                    }
                }
            }
            .padding(10)
        }
        .scrollIndicators(.hidden)
        // The list opens on the page on show, so the highlighted row is always in view however far down it is.
        .onAppear { DispatchQueue.main.async { proxy.scrollTo(menu.current, anchor: .center) } }
        .frame(height: 480)
        .background(Color.black, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
        }
    }
}
#endif
