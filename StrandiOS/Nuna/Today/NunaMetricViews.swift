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
    /// What the Charge-state chip or the readiness chip under the rings means right now.
    case chargeState
    case readiness
    case sleep(Int)
    case sleepStages(Int)
    case sleepVitals(Int)
    case sleepPerformance(Int)
    case sleepNaps(Int)
    /// One nap: the day it belongs to (the day the night before it ended) and when it started.
    case nap(String, Int)
    case fitnessAge
    case bodyClock
    case bodyClockPlan
    /// The heart rate page: the day's timeline, the live reading, time in zones and the broadcast and Dynamic Island switches.
    case deepTimeline
    case mood
    case weight
    case nutrition
    case labBook
    case cycle
    case rhythm
    case smartAlarm
    case windDown
    case hydration
    /// The vital signs page: the live heart rate, the five vitals against their range, fitness age and the early warning.
    case vitalSigns
    /// What the Rest screen's top-right button opens: smart alarm, bedtime reminder, nap detection.
    case sleepSettings
    /// The seven-night sleep overview (what the Health tab used to show for sleep).
    case sleepOverview
}

extension View {
    func nunaTodayDestinations() -> some View {
        navigationDestination(for: NunaTodayRoute.self) { route in
            switch route {
            case .metric(let m): NunaMetricHost(initial: m)
            case .allMetrics: NunaAllMetricsView()
            case .earlyWarning: NunaEarlyWarningView()
            case .chargeState: NunaDayStateView(kind: .charge)
            case .readiness: NunaDayStateView(kind: .readiness)
            case .sleep(let i): NunaRestDetailView(startIndex: i, title: "Sleep")
            case .sleepStages(let i): NunaSleepStagesView(startIndex: i)
            case .sleepVitals(let i): NunaSleepVitalsView(startIndex: i)
            case .sleepPerformance(let i): NunaSleepPerformanceView(startIndex: i)
            case .sleepNaps(let i): NunaNapView(startIndex: i)
            case .nap(let day, let start): NunaNapView(dayKey: day, napStart: start)
            case .fitnessAge: NunaFitnessAgeView()
            case .bodyClock: NunaBodyClockView()
            case .bodyClockPlan: NunaBodyClockPlanView()
            case .deepTimeline: NunaDeepTimelineView()
            case .mood: NunaMoodView()
            case .weight: NunaWeightView()
            case .nutrition: NunaNutritionView()
            case .labBook: NunaLabBookView()
            case .cycle: NunaCycleView()
            case .rhythm: NunaRhythmView()
            case .smartAlarm: NunaSmartAlarmView()
            case .windDown: NunaWindDownView()
            case .hydration: NunaHydrationView()
            case .vitalSigns: NunaHealthView(vitalsOnly: true)
            case .sleepSettings: NunaSleepSettingsView()
            case .sleepOverview: NunaHealthView()
            }
        }
    }
}

// MARK: - Early warning

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
                                .font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true).textCase(nil)
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
                            .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            .frame(maxWidth: .infinity, alignment: .leading).textCase(nil)
                    }
                }
                Text("On-device estimate. Not a diagnosis.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                if coachEnabled { NunaAnyaCard(title: "Ask Anya about this") { showCoach = true } }
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "early warning") }
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
