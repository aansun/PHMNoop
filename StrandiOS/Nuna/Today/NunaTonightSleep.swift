#if os(iOS)
import SwiftUI
import StrandDesign

/// "Tonight's sleep": the bedtime to aim for and the alarm that wakes the wearer, with a button to change the alarm.
///
/// The recommended bedtime is the usual wake time less the sleep need (the same figures the bedtime reminder is timed from, without its
/// lead). The alarm is the strap's smart alarm; while it is off the card says so and the button turns it on.
struct NunaTonightSleep: View {
    @EnvironmentObject private var behavior: BehaviorStore
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var model: AppModel
    /// A 5/MG strap is sent the alarm only while this is on, so the card does not say "Alarm on" for one that was never armed.
    @AppStorage(PuffinExperiment.defaultsKey) private var strapAlarm5 = false
    @AppStorage(NunaGoals.sleepMinutes) private var sleepGoal = 0
    /// The strap buzzes only while wrist alerts are on, so the card says "Alarm on" only then.
    @AppStorage(AppModel.wristAlertsMasterKey) private var wristAlerts = false

    /// The same bedtime the Sleep planner names, worked out in one place.
    private var bedtimeMinutes: Int {
        NunaSleepPlan(wakeMinutes: behavior.smartAlarmMinutes, needMinutes: NunaSleepPlan.needMinutes(goal: sleepGoal),
                      goalPercent: behavior.smartAlarmGoal).bedtimeMinutes
    }

    /// Whether the strap will be sent the alarm: every strap but a 5/MG always, a 5/MG once its alarm is turned on in Experiments.
    private var strapArms: Bool { !(model.whoop5Detected && !strapAlarm5) }

    private var whp: Bool { NunaThemePrefs.skin == .whp }
    /// Measured on the reference: the card, the button on it, and the grey of the small labels.
    private var cardFill: Color? { whp ? Color(red: 0.200, green: 0.220, blue: 0.235) : nil }
    private var buttonFill: Color { whp ? Color(red: 0.271, green: 0.286, blue: 0.298) : NunaPalette.ink.opacity(0.1) }
    private let labelGrey = Color(red: 0.757, green: 0.765, blue: 0.769)
    private let mint = Color(red: 0.431, green: 0.929, blue: 0.647)

    var body: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16), fill: cardFill) {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink(value: NunaTodayRoute.smartAlarm) {
                    HStack {
                        Text("Tonight's sleep").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(Color(red: 0.92, green: 0.92, blue: 0.925))
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(Color(red: 0.58, green: 0.59, blue: 0.60))
                    }
                    .frame(height: 16)
                }
                .buttonStyle(.plain)
                // Two blocks of one width at the sides and a dashed line between them, as on the reference.
                HStack(alignment: .top, spacing: 0) {
                    block(icon: NunaTracedIcon.sunrise, time: NunaAlarmFormat.clock(bedtimeMinutes), lines: [Text("Recommended"), Text("bedtime")], tint: nil)
                        .frame(width: 125)
                    Spacer(minLength: 0)
                    Path { p in p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 60, y: 0)) }
                        .stroke(Color(red: 0.404, green: 0.42, blue: 0.431), style: StrokeStyle(lineWidth: 0.7, dash: [4, 2]))
                        .frame(width: 60, height: 1).padding(.top, 15)
                    Spacer(minLength: 0)
                    block(icon: NunaTracedIcon.alarmStrap, time: NunaAlarmFormat.clock(behavior.smartAlarmMinutes),
                          lines: [Text(!behavior.smartAlarmEnabled ? "Alarm off" : (!strapArms ? "Strap not armed" : (wristAlerts ? "Alarm on" : "Wrist alerts off")))],
                          tint: !behavior.smartAlarmEnabled ? NunaPalette.textMuted : ((wristAlerts && strapArms) ? mint : NunaPalette.warning),
                          footer: Text("Latest alarm"))
                        .frame(width: 125)
                }
                .padding(.top, 17)
                NavigationLink(value: NunaTodayRoute.smartAlarm) {
                    HStack(spacing: 9) {
                        NunaTracedIconView(icon: NunaTracedIcon.pencil)
                        Text("Edit alarm").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 40)
                    .background(buttonFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain).padding(.top, 14)
            }
        }
    }

    private func block(icon: NunaTracedIcon, time: String, lines: [Text], tint: Color?, footer: Text? = nil) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                NunaTracedIconView(icon: icon).foregroundStyle(labelGrey)
                Text(verbatim: time).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(.white)
            }
            .frame(height: 30)
            VStack(spacing: 0) {
                if let tint {
                    HStack(spacing: 6) {
                        Circle().fill(tint).frame(width: 8, height: 8)
                        lines[0].font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(tint)
                    }
                    .frame(height: 15)
                } else {
                    ForEach(lines.indices, id: \.self) { i in
                        lines[i].font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(labelGrey)
                            .frame(height: 15)
                    }
                }
                if let footer {
                    footer.font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(labelGrey)
                        .frame(height: 15).padding(.top, 2.7)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
