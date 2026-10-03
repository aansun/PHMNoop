#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Pushes owned by the Nuna Today stack. Kept apart from `TabRoute` so the shared registration in
/// `NunaRootView` is not doubled.
enum NunaTodayRoute: Hashable {
    case metric(MetricDescriptor)
    case allMetrics
    case earlyWarning
    case sleep(Int)
    case sleepStages(Int)
    case sleepVitals(Int)
    case sleepPerformance(Int)
    case sleepNaps(Int)
    case fitnessAge
}

extension View {
    func nunaTodayDestinations() -> some View {
        navigationDestination(for: NunaTodayRoute.self) { route in
            switch route {
            case .metric(let m): NunaMetricDetailView(metric: m)
            case .allMetrics: NunaAllMetricsView()
            case .earlyWarning: NunaEarlyWarningView()
            case .sleep(let i): NunaSleepView(startIndex: i)
            case .sleepStages(let i): NunaSleepStagesView(startIndex: i)
            case .sleepVitals(let i): NunaSleepVitalsView(startIndex: i)
            case .sleepPerformance(let i): NunaSleepPerformanceView(startIndex: i)
            case .sleepNaps(let i): NunaNapView(startIndex: i)
            case .fitnessAge: NunaFitnessAgeView()
            }
        }
    }
}

// MARK: - Metric detail

/// One metric over time: latest value, a 7/30/90 day bar chart, average / low / high, and Anya.
/// Display only; the data comes from `Repository.exploreSeries`, like the Default metric screen.
struct NunaMetricDetailView: View {
    let metric: MetricDescriptor

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var range = 30
    @State private var series: [(day: String, value: Double)] = []
    @State private var loaded = false
    @State private var showCoach = false

    private var color: Color {
        switch metric.category {
        case "Effort": return NunaPalette.effortText
        case "Rest": return NunaPalette.restText
        default: return NunaPalette.charge
        }
    }

    private var isEffort: Bool { metric.key == "strain" }

    private func format(_ v: Double) -> String {
        if isEffort { return UnitFormatter.effortDisplay(v, scale: UnitPrefs.resolveEffortScale(effortScaleRaw)) }
        return String(format: "%.\(metric.decimals)f", locale: AppLanguage.activeLocale, v)
    }

    private var unit: String { isEffort ? "" : metric.unit }

    /// One slot per calendar day in the window, nil where the metric has no value.
    private var window: [Double?] {
        let byDay = Dictionary(series.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        let cal = Calendar.current
        let today = Date()
        return (0..<range).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today) ?? today
            return byDay[Repository.localDayKey(d)]
        }
    }

    var body: some View {
        let values = window
        let present = values.compactMap { $0 }
        let latest = series.last
        let avg = present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                NunaHeader(LocalizedStringKey(metric.title), onBack: { dismiss() })
                NunaCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: latest.map { format($0.value) } ?? "–")
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundStyle(NunaPalette.textPrimary)
                                .minimumScaleFactor(0.6).lineLimit(1)
                            if !unit.isEmpty {
                                Text(verbatim: unit).font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 8) {
                            if let latest { NunaChip(verbatim: latest.day) }
                            if let latest, let avg { deltaChip(latest.value - avg) }
                        }
                        NunaSegmented([(value: 7, title: "7 days"), (value: 30, title: "30 days"), (value: 90, title: "90 days")],
                                      selection: $range)
                        if present.isEmpty {
                            Text(loaded ? "No data in this period" : " ")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: 140)
                        } else {
                            NunaBars(values: values, color: color, average: avg).frame(height: 150)
                        }
                    }
                }
                if !present.isEmpty, let avg {
                    HStack(spacing: 12) {
                        stat("Average", format(avg))
                        stat("Low", format(present.min() ?? avg))
                        stat("High", format(present.max() ?? avg))
                    }
                }
                if let blurb = metric.description {
                    NunaCard(small: true) {
                        Text(verbatim: blurb).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if coachEnabled { NunaAnyaCard(title: "Ask Anya about this") { showCoach = true } }
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(metric.id)-\(repo.refreshSeq)") {
            series = await repo.exploreSeries(key: metric.key, source: metric.source, days: 120)
            loaded = true
        }
        .sheet(isPresented: $showCoach) { CoachLauncherSheet(context: metric.title) }
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.system(size: 11, weight: .heavy)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                Text(verbatim: value).font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func deltaChip(_ delta: Double) -> some View {
        let up = delta >= 0
        let good: Bool? = metric.higherIsBetter.map { $0 == up }
        let tint: Color = good == nil ? NunaPalette.textSecondary : (good! ? NunaPalette.charge : NunaPalette.warning)
        let magnitude = String(format: "%.\(metric.decimals)f", locale: AppLanguage.activeLocale, abs(delta))
        return NunaChip(verbatim: (up ? "+" : "−") + magnitude + " vs avg", color: tint)
    }
}

/// Plain bar chart: one bar per day, a dashed average line, gaps for days without data.
struct NunaBars: View {
    let values: [Double?]
    let color: Color
    let average: Double?

    var body: some View {
        let present = values.compactMap { $0 }
        let hi = present.max() ?? 1
        let lo0 = present.min() ?? 0
        let lo = max(0, lo0 - (hi - lo0) * 0.5)
        let span = max(hi - lo, 0.0001)
        GeometryReader { geo in
            let gap: CGFloat = values.count > 40 ? 1 : 3
            let w = min(26, max(1, (geo.size.width - gap * CGFloat(values.count - 1)) / CGFloat(max(values.count, 1))))
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(values.indices, id: \.self) { i in
                        if let v = values[i] {
                            Capsule().fill(color)
                                .frame(width: w, height: max(4, geo.size.height * CGFloat((v - lo) / span)))
                        } else {
                            Capsule().fill(Color.white.opacity(0.06)).frame(width: w, height: 4)
                        }
                    }
                }
                if let average {
                    let y = geo.size.height * CGFloat(1 - (average - lo) / span)
                    Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                        .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - All metrics

struct NunaAllMetricsView: View {
    @Environment(\.dismiss) private var dismiss

    private static let groups = ["Charge", "Rest", "Effort", "Heart", "Health"]

    private var items: [(group: String, metrics: [MetricDescriptor])] {
        var seen = Set<String>()
        let usable = MetricCatalog.all.filter { ["my-whoop", "apple-health"].contains($0.source) }
        return Self.groups.map { g in
            (g, usable.filter { $0.category == g && seen.insert($0.key).inserted })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                NunaHeader("All metrics", onBack: { dismiss() })
                ForEach(items, id: \.group) { group in
                    NunaSectionHeader(LocalizedStringKey(group.group))
                    NunaCard(small: true) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.metrics.enumerated()), id: \.element.id) { idx, m in
                                if idx > 0 { NunaDivider() }
                                row(m)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private func row(_ m: MetricDescriptor) -> some View {
        let label = NunaListRow(LocalizedStringKey(m.title), systemImage: m.icon, showsChevron: true)
        if m.key == HeroRingMetric.rest {
            NavigationLink(value: NunaTodayRoute.sleep(0)) { label }.buttonStyle(.plain)
        } else {
            NavigationLink(value: NunaTodayRoute.metric(m)) { label }.buttonStyle(.plain)
        }
    }
}

// MARK: - Early warning

struct NunaEarlyWarningCard: View {
    let result: IllnessSignalEngine.Result
    var body: some View {
        NavigationLink(value: NunaTodayRoute.earlyWarning) {
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    NunaIconTile("exclamationmark.triangle.fill", tint: warnColor(result.level))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Early warning").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: localizedIllnessCopy(result))
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private func warnColor(_ level: IllnessSignalEngine.Level) -> Color {
    switch level {
    case .raised: return NunaPalette.alertText
    case .mild, .suppressed, .alreadyUnwell: return NunaPalette.warning
    case .quiet: return NunaPalette.charge
    }
}

struct NunaEarlyWarningView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @State private var showCoach = false

    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                NunaHeader("Early warning", onBack: { dismiss() })
                if let r = model.illnessSignal {
                    NunaCard {
                        VStack(alignment: .leading, spacing: 12) {
                            NunaChip(label(r.level), color: warnColor(r.level))
                            Text(verbatim: localizedIllnessCopy(r))
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !r.firedSignals.isEmpty {
                        NunaSectionHeader("Signals that are up")
                        NunaCard(small: true) {
                            VStack(spacing: 0) {
                                ForEach(Array(r.firedSignals.enumerated()), id: \.offset) { idx, s in
                                    if idx > 0 { NunaDivider() }
                                    NunaListRow(LocalizedStringKey(s), systemImage: "waveform.path.ecg", tint: warnColor(r.level))
                                }
                            }
                        }
                    }
                } else {
                    NunaCard {
                        Text("Still learning your baseline and keeping an eye on your signals.")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("On-device estimate. Not a diagnosis.")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                if coachEnabled { NunaAnyaCard(title: "Ask Anya about this") { showCoach = true } }
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCoach) { CoachLauncherSheet(context: "early warning") }
    }

    private func label(_ level: IllnessSignalEngine.Level) -> LocalizedStringKey {
        switch level {
        case .raised: return "Raised"
        case .mild: return "Mild"
        case .suppressed: return "Explained"
        case .alreadyUnwell: return "Unwell"
        case .quiet: return "Normal"
        }
    }
}
#endif
