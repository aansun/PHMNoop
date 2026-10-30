#if os(iOS)
import SwiftUI
import StrandDesign

/// What the planner says about tonight, from the alarm's wake time and the share of the sleep need aimed for. The one place the suggested bedtime is
/// worked out, so the planner and the Tonight's sleep card on Today cannot name different times.
///
/// Time in bed is the sleep need at the chosen share, spread over the share of the night actually spent asleep (`assumedEfficiency`). The strap is
/// armed at the wake time in every mode; the share only decides how early the person should be in bed.
struct NunaSleepPlan: Equatable {
    /// The latest (or exact) wake time, minutes since midnight.
    let wakeMinutes: Int
    /// The sleep need, minutes asleep.
    let needMinutes: Int
    /// 100, 85 or 70.
    let goalPercent: Int

    /// The share of time in bed that is sleep, until the person's own is known.
    static let assumedEfficiency = 0.90

    static func needMinutes(goal: Int) -> Int { goal > 0 ? goal : 8 * 60 }

    /// Minutes in bed for the goal, to the nearest five.
    var timeInBedMinutes: Int {
        let raw = Double(needMinutes) * Double(goalPercent) / 100 / Self.assumedEfficiency
        return Int((raw / 5).rounded()) * 5
    }

    /// The bedtime that leaves `timeInBedMinutes` before the wake time, minutes since midnight.
    var bedtimeMinutes: Int { (((wakeMinutes - timeInBedMinutes) % 1440) + 1440) % 1440 }
}

/// The alarm modes of the planner.
enum NunaAlarmMode: String, CaseIterable {
    case exact, goal, green
}

/// The alarm's edit page, as a planner: the bedtime to aim for and the time in bed it leaves, over a sheet that sets the alarm in steps (its mode, the
/// sleep goal, the wake time). The strap is armed at the wake time; NOOP cannot see sleep as it happens, so a goal never wakes anyone earlier.
struct NunaSmartAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore
    @AppStorage("alarm.rejectStreak") private var rejectStreak = 0
    @AppStorage(NunaGoals.sleepMinutes) private var sleepGoal = 0
    @State private var overrides = WindDownNudge.perDayWakeOverrides
    @State private var step: Step = .summary
    @State private var showHelp = false
    @State private var showRepeat = false
    // What is being set in the steps; written to the alarm only on Save.
    @State private var draftMode: NunaAlarmMode = .goal
    @State private var draftGoal = 100
    @State private var draftWake = Date()

    private enum Step { case summary, mode, goal, wake }

    private static let mint = NunaRestChart.need
    /// What the page shows: the saved alarm, or the choices being made while a step is open, so the figures follow the sheet as in the reference.
    private var previewing: Bool { step != .summary }
    private var mode: NunaAlarmMode { previewing ? draftMode : (NunaAlarmMode(rawValue: behavior.smartAlarmMode) ?? .exact) }
    private var goalPercent: Int { previewing ? draftGoal : behavior.smartAlarmGoal }
    private var wakeMinutes: Int { previewing ? NunaAlarmFormat.minutes(draftWake) : behavior.smartAlarmMinutes }
    private var plan: NunaSleepPlan {
        NunaSleepPlan(wakeMinutes: wakeMinutes, needMinutes: NunaSleepPlan.needMinutes(goal: sleepGoal), goalPercent: mode == .exact ? 100 : goalPercent)
    }
    private var willArm: Bool { !(model.whoop5Detected && !PuffinExperiment.isEnabled) }

    var body: some View {
        ZStack(alignment: .bottom) {
            background
            VStack(spacing: 0) {
                header
                Group {
                    if step == .summary { message.padding(.top, 8) }
                    Spacer(minLength: 12)
                    figures
                    Spacer(minLength: step == .summary ? 20 : 12)
                }
                .frame(maxHeight: .infinity)
                sheet
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: behavior.smartAlarmEnabled) { _, _ in model.applySmartAlarm() }
        .onChange(of: behavior.smartAlarmMinutes) { _, _ in model.applySmartAlarm() }
        .onChange(of: behavior.smartAlarmWeekdays) { _, _ in model.applySmartAlarm() }
        .onAppear { overrides = WindDownNudge.perDayWakeOverrides }
        .sheet(isPresented: $showHelp) { helpSheet }
        .sheet(isPresented: $showRepeat) { repeatSheet }
    }

    // MARK: Page

    private var background: some View {
        LinearGradient(stops: [.init(color: Color(red: 0.24, green: 0.29, blue: 0.33), location: 0), .init(color: Color(red: 0.10, green: 0.13, blue: 0.15), location: 0.38),
                               .init(color: Color(red: 0.04, green: 0.05, blue: 0.06), location: 0.7)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 8) {
                Text("Sleep planner").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel + 1.6).textCase(.uppercase).foregroundStyle(Color.white)
                Button { showHelp = true } label: {
                    Image(systemName: "questionmark").font(.nuna(size: 11, weight: .bold)).foregroundStyle(Color.white.opacity(0.65))
                        .frame(width: 22, height: 22).overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5))
                        .padding(8).contentShape(Rectangle()).padding(-8)
                }
                .buttonStyle(.plain).accessibilityLabel(Text("About the sleep planner"))
            }
            HStack(alignment: .top) {
                if step == .summary {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.nuna(size: 20, weight: .bold)).foregroundStyle(Color.white).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Close"))
                }
                Spacer()
                VStack(spacing: 8) {
                    Button { showRepeat = true } label: {
                        Image(systemName: "calendar").font(.nuna(size: 19, weight: .regular)).foregroundStyle(Color.white)
                            .frame(width: 44, height: 44).overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Repeat"))
                    Text(behavior.smartAlarmWeekdays.isEmpty || behavior.smartAlarmWeekdays.count == 7 ? "Daily" : "Custom")
                        .font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(Self.mint).padding(.horizontal, 10).frame(height: 24).background(Self.mint.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
        }
        .padding(.horizontal, NunaSpacing.screenH - 4).padding(.top, 8)
    }

    /// The line under the mark: what the strap will do, and the bedtime that leaves room for it.
    private var message: some View {
        VStack(spacing: 22) {
            AnyaMark(size: 40).frame(width: 52, height: 52).overlay(Circle().strokeBorder(Color.white, lineWidth: 2).padding(-12)).padding(.top, 12)
            Text(verbatim: messageText).font(.nuna(size: 22, weight: .medium)).foregroundStyle(Color.white).textCase(nil)
                .multilineTextAlignment(.center).lineSpacing(5).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 30)
            if let warn = armWarning {
                Text(verbatim: warn).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.warning).textCase(nil)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
            }
        }
    }

    private var messageText: String {
        guard behavior.smartAlarmEnabled else { return String(localized: "Your alarm is off. Turn it on below to buzz your wrist at your wake time.") }
        let wake = Self.time(behavior.smartAlarmMinutes), bed = NunaAlarmFormat.clock(plan.bedtimeMinutes)
        switch mode {
        case .exact: return String(localized: "Your strap will buzz at \(wake).")
        case .goal: return String(localized: "Your strap will buzz at \(wake) at the latest. Be in bed by \(bed) to have time for \(behavior.smartAlarmGoal)% of your Sleep Need.")
        case .green: return String(localized: "Your strap will buzz at \(wake) at the latest. Be in bed by \(bed) for the best chance of a green Charge.")
        }
    }

    /// Shown while the strap is not armed or does not accept the alarm.
    private var armWarning: String? {
        if behavior.smartAlarmEnabled && !willArm { return String(localized: "Your WHOOP 5/MG is not armed until Experimental mode is on.") }
        if behavior.smartAlarmEnabled && rejectStreak >= 2 { return String(localized: "Your strap isn't accepting the alarm. See the help for what to do.") }
        return nil
    }

    // MARK: Figures

    /// The bedtime and the goal over the time in bed: two dashed rules down to a hatched bar with its length in a pill.
    private var figures: some View {
        let accent: Color = mode == .exact ? Color.white : Self.mint
        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                stat(NunaAlarmFormat.clock(plan.bedtimeMinutes), "Suggested time to bed", width: 150)
                Spacer(minLength: 0)
                switch mode {
                case .exact: stat(NunaAlarmFormat.clock(wakeMinutes), "Your wake time", width: 150)
                case .goal: stat("\(goalPercent)%", "Sleep need goal", width: 150)
                case .green: stat(">66%", "Charge goal", width: 150)
                }
            }
            .padding(.horizontal, 22)
            // The rules run from under each figure down to the ends of the bar; the label sits on the bar's upper edge, clear of it.
            ZStack(alignment: .top) {
                HStack {
                    DashedLine(color: accent).frame(width: 2)
                    Spacer()
                    DashedLine(color: accent).frame(width: 2)
                }
                .padding(.horizontal, 54).frame(height: 62)
                Text("Time in bed").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel + 0.4).textCase(.uppercase).foregroundStyle(accent)
                    .padding(.top, 44)
            }
            ZStack {
                Hatch(color: accent).frame(height: 46).padding(.horizontal, 54)
                HStack(spacing: 0) {
                    Rectangle().fill(accent).frame(width: 3, height: 46)
                    Spacer()
                    if mode == .exact { Rectangle().fill(accent).frame(width: 3, height: 46) }
                }
                .padding(.horizontal, 54)
                Text(verbatim: Self.hm(plan.timeInBedMinutes)).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(accent)
                    .padding(.horizontal, 22).frame(height: 44).background(Color(red: 0.07, green: 0.09, blue: 0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(accent, lineWidth: 3))
            }
            .padding(.top, 8)
        }
    }

    private func stat(_ big: String, _ caption: LocalizedStringKey, width: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(verbatim: big).font(.nuna(size: 44, weight: .bold, design: NunaType.design)).foregroundStyle(Color.white).minimumScaleFactor(0.7).lineLimit(1)
            Text(caption).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel + 0.2).textCase(.uppercase).foregroundStyle(Color.white.opacity(0.62))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width)
    }

    // MARK: The sheet

    private var sheet: some View {
        VStack(spacing: 0) {
            switch step {
            case .summary: summarySheet
            case .mode: modeSheet
            case .goal: goalSheet
            case .wake: wakeSheet
            }
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .frame(height: step == .summary ? 290 : 470)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38)
                .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.30, blue: 0.34), Color(red: 0.11, green: 0.14, blue: 0.16), Color(red: 0.06, green: 0.08, blue: 0.09)], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private var summarySheet: some View {
        VStack(spacing: 22) {
            HStack {
                Image(systemName: "calendar").font(.nuna(size: 26, weight: .regular)).foregroundStyle(Color.white).frame(width: 48)
                Spacer()
                VStack(spacing: 4) {
                    Text("Alarm").font(.nuna(size: 17, weight: .heavy)).tracking(nunaTrackingLabel + 1.4).textCase(.uppercase).foregroundStyle(Color.white)
                    Text(verbatim: String(localized: "For \(nextDayName)")).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel + 0.6).textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer()
                Toggle("", isOn: $behavior.smartAlarmEnabled).labelsHidden().tint(Self.mint).accessibilityLabel(Text("Smart strap alarm"))
            }
            HStack(spacing: 14) {
                outlined(top: Text("Alarm set to"), bottom: Text(modeTitle), boldBottom: true) { openMode() }
                outlined(top: Text(mode == .exact ? "Wake time" : "Latest wake time"), bottom: Text(verbatim: NunaAlarmFormat.clock(behavior.smartAlarmMinutes)), boldBottom: false) { openWake() }
            }
            .frame(height: 112)
            Spacer(minLength: 0)
        }
    }

    private var modeTitle: LocalizedStringKey {
        switch mode { case .exact: return "Exact time"; case .goal: return "Sleep goal"; case .green: return "In the green" }
    }

    private func outlined(top: Text, bottom: Text, boldBottom: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                top.font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel + 0.8).textCase(.uppercase).foregroundStyle(Color.white.opacity(0.6))
                bottom.font(.nuna(size: boldBottom ? 16 : 19, weight: .heavy, design: boldBottom ? .default : NunaType.design)).tracking(boldBottom ? nunaTrackingLabel + 1 : 0)
                    .textCase(.uppercase).foregroundStyle(Color.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func sheetTitle(_ text: LocalizedStringKey, back: @escaping () -> Void, trailing: AnyView? = nil) -> some View {
        ZStack {
            Text(text).font(.nuna(size: 22, weight: .medium)).foregroundStyle(Color.white).textCase(nil)
            HStack {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.nuna(size: 22, weight: .bold)).foregroundStyle(Color.white).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Back"))
                Spacer()
                if let trailing { trailing } else {
                    Button { showHelp = true } label: {
                        Image(systemName: "questionmark").font(.nuna(size: 12, weight: .bold)).foregroundStyle(Color.white.opacity(0.65))
                            .frame(width: 30, height: 30).overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Help"))
                }
            }
        }
        .padding(.bottom, 8)
    }

    // The three steps

    private var modeSheet: some View {
        VStack(spacing: 14) {
            sheetTitle("Choose your alarm mode.", back: { step = .summary })
            modeCard("Exact time", "Wake up at a specific time.", .exact)
            modeCard("Sleep goal", "Be in bed long enough for your sleep goal.", .goal)
            modeCard("In the green", "Be in bed for the best chance of a green Charge.", .green)
            Spacer(minLength: 0)
        }
    }

    private func modeCard(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ m: NunaAlarmMode) -> some View {
        Button {
            draftMode = m
            switch m { case .goal: step = .goal; case .exact, .green: step = .wake }
        } label: {
            VStack(spacing: 8) {
                Text(title).font(.nuna(size: 17, weight: .heavy)).tracking(nunaTrackingLabel + 1.2).textCase(.uppercase).foregroundStyle(Color.white)
                Text(subtitle).font(.nuna(size: 15, weight: .medium)).foregroundStyle(Color.white.opacity(0.7)).textCase(nil).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(draftMode == m ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(draftMode == m ? Self.mint : Color.white.opacity(0.3), lineWidth: draftMode == m ? 2 : 1.5))
        }
        .buttonStyle(.plain)
    }

    private var goalSheet: some View {
        VStack(spacing: 0) {
            sheetTitle("Select your Sleep Goal.", back: { step = .mode })
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 34) {
                ForEach([100, 85, 70], id: \.self) { g in
                    Button { draftGoal = g } label: {
                        HStack(spacing: 22) {
                            ZStack {
                                Circle().strokeBorder(draftGoal == g ? Self.mint : Color.white, lineWidth: 2.5).frame(width: 34, height: 34)
                                if draftGoal == g { Circle().fill(Self.mint).frame(width: 34, height: 34); Circle().fill(Color.black).frame(width: 9, height: 9) }
                            }
                            Text(verbatim: String(localized: "\(g)% of my sleep need")).font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel + 1.2).textCase(.uppercase)
                                .foregroundStyle(draftGoal == g ? Self.mint : Color.white.opacity(0.7))
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            Spacer(minLength: 0)
            bigButton("Next", mint: true) { step = .wake }
        }
    }

    private var wakeSheet: some View {
        VStack(spacing: 0) {
            sheetTitle(draftMode == .exact ? "Set your wake time." : "Set your latest wake time.", back: { step = draftMode == .goal ? .goal : .mode },
                       trailing: draftMode == .green ? AnyView(Text(">66%").font(.nuna(size: 14, weight: .heavy, design: NunaType.design)).foregroundStyle(Self.mint)) : nil)
            Spacer(minLength: 0)
            DatePicker("", selection: $draftWake, displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden()
                .environment(\.colorScheme, .dark).frame(maxWidth: 300).accessibilityLabel(Text("Wake time"))
            Spacer(minLength: 0)
            Text(verbatim: draftMode == .exact ? String(localized: "Your strap will buzz at \(Self.time(NunaAlarmFormat.minutes(draftWake))).")
                 : String(localized: "Your strap will buzz at \(Self.time(NunaAlarmFormat.minutes(draftWake))) at the latest."))
                .font(.nuna(size: 15, weight: .medium)).foregroundStyle(Color.white.opacity(0.85)).textCase(nil).padding(.bottom, 14)
            bigButton("Save & set alarm", mint: draftMode != .exact) { save() }
        }
    }

    private func bigButton(_ title: LocalizedStringKey, mint: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nuna(size: 16, weight: .heavy)).tracking(nunaTrackingLabel + 1.4).textCase(.uppercase).foregroundStyle(mint ? Self.mint : Color.white)
                .frame(maxWidth: .infinity).frame(height: 58)
                .overlay(Capsule().strokeBorder(mint ? Self.mint : Color.white, lineWidth: 3))
        }
        .buttonStyle(.plain)
    }

    // MARK: Steps and saving

    private func openMode() { draftMode = mode; draftGoal = behavior.smartAlarmGoal; draftWake = NunaAlarmFormat.date(minutes: behavior.smartAlarmMinutes); step = .mode }
    private func openWake() { draftMode = mode; draftGoal = behavior.smartAlarmGoal; draftWake = NunaAlarmFormat.date(minutes: behavior.smartAlarmMinutes); step = .wake }

    /// Writes the choices to the alarm and arms the strap (the `onChange` handlers above re-arm when the time, the days or the switch change).
    private func save() {
        behavior.smartAlarmMode = draftMode.rawValue
        if draftMode == .goal { behavior.smartAlarmGoal = draftGoal }
        behavior.smartAlarmMinutes = NunaAlarmFormat.minutes(draftWake)
        if behavior.smartAlarmEnabled { model.applySmartAlarm() } else { behavior.smartAlarmEnabled = true }
        step = .summary
    }

    // MARK: Repeat and help

    private var repeatSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Repeat").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            HStack(spacing: 8) {
                ForEach(NunaAlarmFormat.weekdayOrder, id: \.self) { dow in
                    let on = SmartAlarmView.alarmWeekdayIsSelected(dow, in: behavior.smartAlarmWeekdays)
                    Button { behavior.smartAlarmWeekdays = SmartAlarmView.alarmToggledWeekday(dow, in: behavior.smartAlarmWeekdays) } label: {
                        Text(verbatim: String(NunaAlarmFormat.weekdayShort(dow).prefix(1))).font(.nuna(size: 14, weight: .heavy))
                            .foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textSecondary).frame(maxWidth: .infinity).frame(height: 44)
                            .background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text(verbatim: NunaAlarmFormat.weekdayName(dow))).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(verbatim: SmartAlarmView.alarmWeekdaySummary(behavior.smartAlarmWeekdays)).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            if !overrides.isEmpty {
                Text("Some days have a time of their own, set in the bedtime reminder.").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 0)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .presentationDetents([.height(280)]).presentationDragIndicator(.visible)
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    private var helpSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sleep planner").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                note("The strap buzzes at your wake time. In Sleep goal and In the green the wake time is your latest one: NOOP cannot see your sleep as it happens, so the buzz is never earlier. The goal decides the bedtime to aim for, the time in bed it leaves, and the Tonight's sleep card on Today.")
                note("The buzz is silent, from the strap's own firmware, so it works even if your phone is asleep or NOOP is closed. A backup notification is scheduled too, but Focus or silent mode can mute it. Keep your phone's Clock alarm as your real backup.")
                if model.whoop5Detected && !PuffinExperiment.isEnabled {
                    note("Your WHOOP 5/MG won't arm this until Experimental mode is on (Settings, Experimental). Right now your wake time is saved but the strap is NOT armed.", warn: true)
                } else if model.whoop5Detected {
                    note("Armed on the strap itself with the experimental 5/MG command. A strap-driven wake is still unconfirmed on 5/MG, so keep a backup alarm.")
                } else {
                    Button { model.ble.getStrapAlarm() } label: {
                        Text("Check what the strap has stored").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 46)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain)
                }
                if behavior.smartAlarmEnabled && rejectStreak >= 2 {
                    note("Your strap keeps reporting a different time than NOOP sends, so its alarm won't fire at your wake time. Reset the strap in the official WHOOP app (or fully charge it and reconnect), and keep your phone's Clock alarm as your wake until it takes.", warn: true)
                }
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    private func note(_ t: LocalizedStringKey, warn: Bool = false) -> some View {
        Text(t).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(warn ? NunaPalette.warning : NunaPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Formatting

    /// The weekday the next buzz falls on (tomorrow's while the alarm is off).
    private var nextDayName: String {
        let date: Date = behavior.smartAlarmEnabled && willArm
            ? (AppModel.nextSmartAlarmDate(minutes: behavior.smartAlarmMinutes, weekdays: behavior.smartAlarmWeekdays, overrides: overrides) ?? Date().addingTimeInterval(86_400))
            : Date().addingTimeInterval(86_400)
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date)
    }

    private static func time(_ minutes: Int) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: NunaAlarmFormat.date(minutes: minutes))
    }

    /// 9:45.
    private static func hm(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }
}

/// Fine diagonal stripes across a bar.
private struct Hatch: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path(); p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.stroke(p, with: .color(color.opacity(0.85)), lineWidth: 2)
                x += 6
            }
        }
        .mask(LinearGradient(colors: [.white, .white, .white.opacity(0.15)], startPoint: .leading, endPoint: .trailing))
    }
}

/// A vertical dashed rule.
private struct DashedLine: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            Path { p in p.move(to: CGPoint(x: geo.size.width / 2, y: 0)); p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height)) }
                .stroke(color.opacity(0.75), style: StrokeStyle(lineWidth: 1.6, dash: [3, 4]))
        }
    }
}
#endif
