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
    case bodyClock
    case bodyClockPlan
    case deepTimeline
    case liveHeart
    case mood
    case weight
    case waist
    case nutrition
    case labBook
    case cycle
    case smartAlarm
    case windDown
}

extension View {
    func nunaTodayDestinations() -> some View {
        navigationDestination(for: NunaTodayRoute.self) { route in
            switch route {
            case .metric(let m):
                switch (m.key, m.source) {
                case ("recovery", _): NunaChargeDetailView()
                case ("strain", _): NunaEffortDetailView()
                case ("stress", "my-whoop"): NunaStressDetailView()
                case ("sleep_performance", _): NunaSleepView()
                case ("spo2", _): NunaOxygenView()
                case ("resp_rate", _): NunaOxygenView(startOnBreathing: true)
                case ("skin_temp", _): NunaSkinTempView()
                case ("fitness_age", _): NunaFitnessAgeView()
                default: NunaMetricDetailView(metric: m)
                }
            case .allMetrics: NunaAllMetricsView()
            case .earlyWarning: NunaEarlyWarningView()
            case .sleep(let i): NunaSleepView(startIndex: i)
            case .sleepStages(let i): NunaSleepStagesView(startIndex: i)
            case .sleepVitals(let i): NunaSleepVitalsView(startIndex: i)
            case .sleepPerformance(let i): NunaSleepPerformanceView(startIndex: i)
            case .sleepNaps(let i): NunaNapView(startIndex: i)
            case .fitnessAge: NunaFitnessAgeView()
            case .bodyClock: NunaBodyClockView()
            case .bodyClockPlan: NunaBodyClockPlanView()
            case .deepTimeline: NunaDeepTimelineView()
            case .liveHeart: NunaLiveHeartView()
            case .mood: NunaMoodView()
            case .weight: NunaWeightView()
            case .waist: NunaWaistView()
            case .nutrition: NunaNutritionView()
            case .labBook: NunaLabBookView()
            case .cycle: NunaCycleView()
            case .smartAlarm: NunaSmartAlarmView()
            case .windDown: NunaWindDownView()
            }
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
