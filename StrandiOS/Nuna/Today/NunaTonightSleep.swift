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
    @AppStorage(NunaGoals.sleepMinutes) private var sleepGoal = 0
    /// The strap buzzes only while wrist alerts are on, so the card says "Alarm on" only then.
    @AppStorage(AppModel.wristAlertsMasterKey) private var wristAlerts = false

    /// The same bedtime the Sleep planner names, worked out in one place.
    private var bedtimeMinutes: Int {
        NunaSleepPlan(wakeMinutes: behavior.smartAlarmMinutes, needMinutes: NunaSleepPlan.needMinutes(goal: sleepGoal),
                      goalPercent: behavior.smartAlarmMode == "exact" ? 100 : behavior.smartAlarmGoal).bedtimeMinutes
    }

    var body: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink(value: NunaTodayRoute.smartAlarm) {
                    HStack {
                        Text("Tonight's sleep").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textPrimary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                }
                .buttonStyle(.plain)
                HStack(alignment: .top, spacing: 0) {
                    block(icon: "sunset", time: NunaAlarmFormat.clock(bedtimeMinutes), line: Text("Recommended bedtime"), tint: nil)
                    Rectangle().fill(NunaPalette.hairline).frame(height: 1).frame(width: 52).padding(.top, 20)
                    block(icon: "applewatch.watchface", time: NunaAlarmFormat.clock(behavior.smartAlarmMinutes),
                          line: Text(!behavior.smartAlarmEnabled ? "Alarm off" : (wristAlerts ? "Alarm on" : "Wrist alerts off")),
                          tint: !behavior.smartAlarmEnabled ? NunaPalette.textMuted : (wristAlerts ? NunaPalette.charge : NunaPalette.warning),
                          footer: Text("Latest alarm"))
                }
                NavigationLink(value: NunaTodayRoute.smartAlarm) {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil").font(.nuna(size: 13, weight: .semibold))
                        Text("Edit alarm").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    }
                    .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 46)
                    .background(NunaPalette.ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func block(icon: String, time: String, line: Text, tint: Color?, footer: Text? = nil) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.nuna(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                Text(verbatim: time).font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            }
            if let tint {
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 8, height: 8)
                    line.font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(tint)
                }
            } else {
                line.font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let footer {
                footer.font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
