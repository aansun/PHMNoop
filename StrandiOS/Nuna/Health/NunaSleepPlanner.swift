#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// What the planner says about tonight, from the alarm's wake time and the share of the sleep need aimed for. The one place the suggested bedtime is
/// worked out, so the planner and the Tonight's sleep card on Today cannot name different times.
///
/// Time in bed is the sleep need at the chosen share, spread over the share of the night actually spent asleep (`assumedEfficiency`). The strap is
/// armed at the wake time in every mode; the share decides how early the person should be in bed and, with the early wake on, when the Sleep goal
/// mode may buzz before that time.
struct NunaSleepPlan: Equatable {
    /// The wake time, minutes since midnight.
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
    var bedtimeMinutes: Int { Self.wrap(wakeMinutes - timeInBedMinutes) }

    /// The window the sleep need itself asks for: the need ending at the wake time, with nothing added for falling asleep. It starts later than the
    /// bedtime above, which leaves a margin before it.
    var optimalStartMinutes: Int { Self.wrap(wakeMinutes - needMinutes) }

    /// Where `optimalStartMinutes` falls between the bedtime (0) and the wake time (1), held inside that span.
    var optimalFraction: Double {
        guard timeInBedMinutes > 0 else { return 0 }
        let fromBed = Double(needMinutes < timeInBedMinutes ? timeInBedMinutes - needMinutes : 0)
        return min(max(fromBed / Double(timeInBedMinutes), 0), 1)
    }

    private static func wrap(_ m: Int) -> Int { ((m % 1440) + 1440) % 1440 }
}

/// The alarm modes of the planner.
enum NunaAlarmMode: String, CaseIterable {
    case exact, goal, green
}

/// The alarm's edit page, as a planner: the bedtime to aim for and the time in bed it leaves, over a sheet that sets the alarm in steps (its mode, the
/// sleep goal, the wake time). The strap is armed at the wake time. With the experimental early wake on, Sleep goal and In the green may also buzz
/// in the hour before it (see `SmartWake`); the words on the page say which of the two applies.
///
/// The sizes below are read off the reference, in points. The words are `.nuna` roles (so they follow the active look), and the figures use the
/// figure design, except the wheel, which is drawn light to match the reference's thin numerals.
struct NunaSmartAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore
    @AppStorage("alarm.rejectStreak") private var rejectStreak = 0
    @AppStorage(NunaGoals.sleepMinutes) private var sleepGoal = 0
    /// Wrist alerts, the master switch of every strap buzz: the alarm buzzes only while it is on.
    @AppStorage(AppModel.wristAlertsMasterKey) private var wristAlerts = false
    /// The experimental early wake (see `EarlyWake`).
    @AppStorage(EarlyWake.enabledKey) private var earlyWake = false
    @State private var schedule = AlarmSchedule.load()
    @State private var step: Step = .summary
    @State private var showHelp = false
    @State private var showSchedule = false
    /// The goal sheet was opened from the pill, so it saves the goal alone.
    @State private var goalOnly = false
    // What is being set in the steps; written to the alarm only on Save.
    @State private var draftMode: NunaAlarmMode = .goal
    @State private var draftGoal = 100
    @State private var draftWake = Date()

    private enum Step { case summary, mode, goal, wake }

    private static let mint = NunaRestChart.need
    private static let green = Color(red: 0.17, green: 0.85, blue: 0.29)

    /// What the page shows: the saved alarm, or the choices being made while a step is open, so the figures follow the sheet as in the reference.
    private var previewing: Bool { step != .summary }
    private var mode: NunaAlarmMode { previewing ? draftMode : (NunaAlarmMode(rawValue: behavior.smartAlarmMode) ?? .exact) }
    private var goalPercent: Int { previewing ? draftGoal : behavior.smartAlarmGoal }
    private var wakeMinutes: Int { previewing && !goalOnly ? NunaAlarmFormat.minutes(draftWake) : nextMinutes }
    /// The time of the alarm that comes next: a day can have a time of its own.
    private var nextMinutes: Int {
        behavior.smartAlarmEnabled ? (model.nextAlarmDate().map(NunaAlarmFormat.minutes) ?? behavior.smartAlarmMinutes) : behavior.smartAlarmMinutes
    }
    private var plan: NunaSleepPlan {
        NunaSleepPlan(wakeMinutes: wakeMinutes, needMinutes: NunaSleepPlan.needMinutes(goal: sleepGoal), goalPercent: goalPercent)
    }
    /// Whether the mode shown may buzz before the wake time.
    private var wakesEarly: Bool { earlyWake && mode != .exact }
    private static func hourBefore(_ minutes: Int) -> Int { (minutes - Int(SmartWake.windowSeconds / 60) + 1440) % 1440 }
    private var accent: Color { mode == .exact ? .white : (mode == .green ? Self.green : Self.mint) }
    private var willArm: Bool { !(model.whoop5Detected && !PuffinExperiment.isEnabled) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .bottom) {
                background
                VStack(spacing: 0) {
                    header(width: w)
                    if step == .summary { message(width: w) }
                    Spacer(minLength: 0)
                    // A short screen has no room for it; the goal is then set through the Sleep goal mode.
                    if step == .summary, geo.size.height >= 740 { goalPill.padding(.bottom, 18) }
                    figures(width: w)
                    Spacer().frame(height: step == .summary ? 28 : 45)
                    sheet(width: w, bottomInset: geo.safeAreaInsets.bottom)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: behavior.smartAlarmEnabled) { _, _ in model.applySmartAlarm() }
        .onChange(of: behavior.smartAlarmMinutes) { _, _ in model.applySmartAlarm() }
        .onChange(of: behavior.smartAlarmWeekdays) { _, _ in model.applySmartAlarm() }
        .onChange(of: wristAlerts) { _, _ in model.applySmartAlarm() }
        .onChange(of: earlyWake) { _, _ in model.applySmartAlarm() }
        .onAppear {
            model.mirrorScheduledAlarm()
            schedule = AlarmSchedule.load()
#if DEBUG
            // `--alarm-step=mode|goal|wake|schedule` opens the planner on that step, to look at it.
            switch CommandLine.arguments.first(where: { $0.hasPrefix("--alarm-step=") })?.dropFirst("--alarm-step=".count) {
            case "mode": openMode()
            case "goal": openGoal()
            case "wake": openWake()
            case "schedule": showSchedule = true
            default: break
            }
#endif
        }
        .onChange(of: showSchedule) { _, open in if !open { schedule = AlarmSchedule.load() } }
        .navigationDestination(isPresented: $showSchedule) { NunaAlarmScheduleView() }
        .sheet(isPresented: $showHelp) { helpSheet }
    }

    // MARK: Page

    private var background: some View {
        LinearGradient(stops: [.init(color: Color(red: 0.25, green: 0.30, blue: 0.34), location: 0), .init(color: Color(red: 0.10, green: 0.13, blue: 0.15), location: 0.36),
                               .init(color: Color(red: 0.04, green: 0.05, blue: 0.06), location: 0.72)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    /// A thin circle with a question mark, the way the reference marks "about this".
    private func helpButton(size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "questionmark").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(Color.white.opacity(0.62))
                .frame(width: size, height: size).overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.2))
                .padding(10).contentShape(Rectangle()).padding(-10)
        }
        .buttonStyle(.plain).accessibilityLabel(Text("About the sleep planner"))
    }

    private func header(width w: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Text("Sleep planner").font(.nuna(size: 13, weight: .heavy)).tracking(1.5).textCase(.uppercase).foregroundStyle(Color.white)
                .overlay(alignment: .trailing) { helpButton(size: 17) { showHelp = true }.offset(x: 26) }
                .frame(height: 44)
            HStack(alignment: .top) {
                if step == .summary {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.white).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Close"))
                }
                Spacer()
                VStack(spacing: 9) {
                    Button { showSchedule = true } label: {
                        PlannerCalendarIcon(size: 17).foregroundStyle(Color.white)
                            .frame(width: 36, height: 36).overlay(Circle().strokeBorder(Color.white, lineWidth: 1.8))
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("My schedule"))
                    // Whether My Schedule drives the alarm.
                    Text(schedule.drives ? "On" : "Off")
                        .font(.nuna(size: 12, weight: .heavy)).tracking(1.0).textCase(.uppercase)
                        .foregroundStyle(schedule.drives ? Self.mint : Color.white.opacity(0.55)).padding(.horizontal, 8).frame(height: 20)
                        .background((schedule.drives ? Self.mint : Color.white).opacity(0.14), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                .padding(.top, 4)
            }
        }
        .frame(height: 69, alignment: .top)
        .padding(.leading, 12).padding(.trailing, 17).padding(.top, 8)
        .overlay(alignment: .bottom) {
            // A hairline under the header while a step is open.
            if step != .summary { Rectangle().fill(Color.black.opacity(0.55)).frame(height: 1).offset(y: -16) }
        }
    }

    /// The mark in a ring and what the strap will do, centred under the header.
    private func message(width w: CGFloat) -> some View {
        VStack(spacing: 14) {
            AnyaMark(size: 23).frame(width: 36, height: 36).overlay(Circle().strokeBorder(Color.white, lineWidth: 1.8))
            Text(verbatim: messageText).font(.nuna(size: 18, weight: .regular)).foregroundStyle(Color.white).textCase(nil)
                .multilineTextAlignment(.center).lineSpacing(5.5).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 50)
            if behavior.smartAlarmEnabled && willArm && !wristAlerts {
                // The alarm is on but the strap will not buzz: say so, and give the way out.
                smallCapsule("Turn on wrist alerts") { wristAlerts = true }
            } else if behavior.smartAlarmEnabled && willArm && mode != .exact && !earlyWake {
                // A mode that can wake early, with the experiment off: the way to turn it on.
                smallCapsule("Turn on early wake") { earlyWake = true }
            } else if behavior.smartAlarmEnabled && willArm && wakesEarly {
                Text("Early wake is experimental. Keep a backup alarm, and double-tap your strap to turn the buzz off.")
                    .font(.nuna(size: 12.5, weight: .regular)).foregroundStyle(Color.white.opacity(0.6)).textCase(nil)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 40)
            } else if behavior.smartAlarmEnabled && willArm {
                Text("Double-tap your strap to turn the alarm off.").font(.nuna(size: 13, weight: .regular)).foregroundStyle(Color.white.opacity(0.6)).textCase(nil)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            if let warn = armWarning {
                Text(verbatim: warn).font(.nuna(size: 13, weight: .regular)).foregroundStyle(NunaPalette.warning).textCase(nil)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
        }
        .padding(.top, 9)
    }

    private func smallCapsule(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nuna(size: 12.5, weight: .heavy)).tracking(1.2).textCase(.uppercase).foregroundStyle(Color.white)
                .padding(.horizontal, 18).frame(height: 36).overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.4))
        }
        .buttonStyle(.plain)
    }

    /// What the bedtime below is planned for; a tap changes it.
    private var goalPill: some View {
        VStack(spacing: 8) {
            Text("Tomorrow I want to").font(.nuna(size: 11, weight: .heavy)).tracking(1.2).textCase(.uppercase).foregroundStyle(Color.white.opacity(0.45))
            Button { openGoal() } label: {
                Text(verbatim: behavior.smartAlarmGoal == 100 ? String(localized: "Reach my sleep need")
                                                              : String(localized: "Reach \(behavior.smartAlarmGoal)% of my sleep need"))
                    .font(.nuna(size: 12.5, weight: .heavy)).tracking(1.1).textCase(.uppercase).foregroundStyle(Color.white.opacity(0.8))
                    .padding(.horizontal, 18).frame(height: 38).overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.4))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var messageText: String {
        guard behavior.smartAlarmEnabled else { return String(localized: "Your alarm is off. Turn it on below to buzz your wrist at your wake time.") }
        if willArm && !wristAlerts {
            return String(localized: "Wrist alerts are off, so your strap will not buzz. Your phone will notify you at \(NunaAlarmFormat.clock(nextMinutes)).")
        }
        let wake = NunaAlarmFormat.clock(nextMinutes), bed = NunaAlarmFormat.clock(plan.bedtimeMinutes)
        let from = NunaAlarmFormat.clock(Self.hourBefore(nextMinutes))
        switch mode {
        case .exact: return String(localized: "Your alarm will go off at \(wake).")
        case .goal:
            return earlyWake
                ? String(localized: "Your alarm will go off once you've slept \(behavior.smartAlarmGoal)% of your sleep need, from \(from), but no later than \(wake).")
                : String(localized: "Your strap will buzz at \(wake). Be in bed by \(bed) to have time for \(behavior.smartAlarmGoal)% of your Sleep Need.")
        case .green:
            return earlyWake
                ? String(localized: "Your alarm will go off if you're at least 67% Recovered from \(from), but no later than \(wake).")
                : String(localized: "Your strap will buzz at \(wake). Be in bed by \(bed) for the best chance of a green Recovery.")
        }
    }

    /// Shown while the strap is not armed or does not accept the alarm.
    private var armWarning: String? {
        if behavior.smartAlarmEnabled && !willArm { return String(localized: "Your WHOOP 5/MG is not armed until its wake alarm is turned on in Experiments.") }
        if behavior.smartAlarmEnabled && rejectStreak >= 2 { return String(localized: "Your strap isn't accepting the alarm. See the help for what to do.") }
        return nil
    }

    // MARK: Figures

    /// The bedtime and the goal over the time in bed: two dotted rules down to a hatched bar with its length in a pill, and under it the window the
    /// sleep need itself asks for.
    private func figures(width w: CGFloat) -> some View {
        let left = w * 0.169, right = w * 0.836, barEnd = w * 0.9
        let open = mode != .exact
        return VStack(spacing: 0) {
            // The figures, their captions under them.
            ZStack {
                stat(NunaAlarmFormat.clock(plan.bedtimeMinutes), unit: nil, "Suggested time to bed").position(x: w * 0.221, y: 35.5)
                switch mode {
                case .exact: stat(NunaAlarmFormat.clock(wakeMinutes), unit: nil, "Your wake time").position(x: w * 0.777, y: 35.5)
                case .goal: stat("\(goalPercent)", unit: "%", "Sleep need goal").position(x: w * 0.777, y: 35.5)
                case .green: stat(">66", unit: "%", "Recovery goal").position(x: w * 0.777, y: 35.5)
                }
            }
            .frame(width: w, height: 64.5)
            // The two dotted rules, down to just above the bar, and the label between them.
            ZStack(alignment: .topLeading) {
                DottedRule(color: accent).frame(width: 2, height: 36).offset(x: left - 1)
                DottedRule(color: accent).frame(width: 2, height: 36).offset(x: right - 1)
                Text("Time in bed").font(.nuna(size: 10, weight: .heavy)).tracking(1.0).textCase(.uppercase).foregroundStyle(accent)
                    .frame(width: w).offset(y: 17.5)
            }
            .frame(width: w, height: 36, alignment: .topLeading)
            ZStack(alignment: .leading) {
                PlannerHatch(color: accent, fades: open).frame(width: (open ? barEnd : right) - left, height: 20).offset(x: left)
                Rectangle().fill(accent).frame(width: 2.2, height: 20).offset(x: left - 1.1)
                if !open { Rectangle().fill(accent).frame(width: 2.2, height: 20).offset(x: right - 1.1) }
                Text(verbatim: Self.hm(plan.timeInBedMinutes)).font(.nuna(size: 17, weight: .semibold, design: NunaType.design)).foregroundStyle(accent)
                    .padding(.horizontal, 15).frame(height: 29).background(Color(red: 0.07, green: 0.09, blue: 0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(accent, lineWidth: 1.7)).frame(width: w)
            }
            .frame(width: w, height: 29)
            optimal(left: left, right: right, width: w).padding(.top, 3)
        }
    }

    private func stat(_ big: String, unit: String?, _ caption: LocalizedStringKey) -> some View {
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: big).font(.nuna(size: 25, weight: .bold, design: NunaType.design)).foregroundStyle(Color.white)
                if let unit { Text(verbatim: unit).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(Color.white) }
            }
            .lineLimit(1).fixedSize()
            // The caption sits in a box two lines high and is centred in it, so a one-line caption lines up with the middle of a two-line one.
            Text(caption).font(.nuna(size: 11.5, weight: .heavy)).tracking(0.3).textCase(.uppercase).foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true).frame(width: 112, height: 28)
        }
        .frame(width: 150)
    }

    /// The dashed bracket under the bar, from where the sleep need starts to the wake time, with its range under it.
    private func optimal(left: CGFloat, right: CGFloat, width w: CGFloat) -> some View {
        let start = left + (right - left) * plan.optimalFraction
        let tone = Color(red: 0.43, green: 0.55, blue: 0.67)
        return ZStack(alignment: .topLeading) {
            OptimalBracket(from: start, to: right - 1, gap: 84).stroke(tone, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3.5]))
                .frame(width: w, height: 36)
            Text("Optimal").font(.nuna(size: 11, weight: .heavy)).tracking(1.2).textCase(.uppercase).foregroundStyle(tone)
                .position(x: (start + right) / 2, y: 35)
            Text(verbatim: "\(NunaAlarmFormat.clock(plan.optimalStartMinutes)) - \(NunaAlarmFormat.clock(wakeMinutes))")
                .font(.nuna(size: 10.5, weight: .medium)).foregroundStyle(tone).textCase(nil).position(x: (start + right) / 2, y: 56)
        }
        .frame(width: w, height: 62, alignment: .topLeading)
    }

    // MARK: The sheet

    private func sheet(width w: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            switch step {
            case .summary: summarySheet(width: w)
            case .mode: modeSheet(width: w)
            case .goal: goalSheet(width: w, inset: bottomInset)
            case .wake: wakeSheet(width: w, inset: bottomInset)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: (step == .summary ? 183 : 463) - bottomInset, alignment: .top)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34)
                .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.30, blue: 0.34), Color(red: 0.11, green: 0.14, blue: 0.16), Color(red: 0.06, green: 0.08, blue: 0.09)], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private func summarySheet(width w: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 4) {
                    Text("Alarm").font(.nuna(size: 13, weight: .heavy)).tracking(1.6).textCase(.uppercase).foregroundStyle(Color.white)
                    Text(verbatim: String(localized: "For \(nextDayName)")).font(.nuna(size: 10.5, weight: .medium)).tracking(1.2).textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                HStack {
                    Image(systemName: "applewatch.radiowaves.left.and.right").font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Color.white).padding(.leading, 2).accessibilityHidden(true)
                    Spacer()
                    Toggle("", isOn: $behavior.smartAlarmEnabled).labelsHidden().tint(Self.mint)
                        .accessibilityLabel(Text("Smart strap alarm"))
                }
            }
            .padding(.horizontal, 20).padding(.top, 20)
            HStack(spacing: 11) {
                outlined(top: "Alarm set to", bottom: Text(modeTitle).font(.nuna(size: 13, weight: .heavy)).tracking(1.0), action: openMode)
                outlined(top: wakesEarly ? "Latest wake time" : "Wake time",
                         bottom: Text(verbatim: NunaAlarmFormat.clock(nextMinutes)).font(.nuna(size: 13, weight: .heavy)), action: openWake)
            }
            .frame(height: 63).padding(.horizontal, 20).padding(.top, 20)
        }
    }

    private var modeTitle: LocalizedStringKey {
        switch mode { case .exact: return "Exact time"; case .goal: return "Sleep goal"; case .green: return "In the green" }
    }

    /// An outlined box: a small grey line over a bold white one.
    private func outlined(top: LocalizedStringKey, bottom: some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Text(top).font(.nuna(size: 11, weight: .medium)).tracking(1.4).textCase(.uppercase).foregroundStyle(Color.white.opacity(0.55))
                bottom.textCase(.uppercase).foregroundStyle(Color.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.white.opacity(0.42), lineWidth: 1.3))
        }
        .buttonStyle(.plain)
    }

    /// A step's title between a back chevron and a question mark.
    private func sheetTitle(_ text: LocalizedStringKey, back: @escaping () -> Void) -> some View {
        ZStack {
            Text(text).font(.nuna(size: 16, weight: .regular)).foregroundStyle(Color.white).textCase(nil)
            HStack {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 23, weight: .bold)).foregroundStyle(Color.white).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Back"))
                Spacer()
                helpButton(size: 17) { showHelp = true }.padding(.trailing, 11)
            }
            .padding(.leading, 22).padding(.trailing, 14)
        }
        .frame(height: 60)
    }

    // The three steps

    private func modeSheet(width w: CGFloat) -> some View {
        VStack(spacing: 7) {
            sheetTitle("Choose your alarm mode.", back: { step = .summary })
            VStack(spacing: 11) {
                modeCard("Exact time", "Wake up at a specific time.", .exact)
                modeCard("Sleep goal", earlyWake ? "Wake up once you've hit your sleep goal." : "Be in bed long enough for your sleep goal.", .goal)
                modeCard("In the green", earlyWake ? "Wake up once you've achieved a green Recovery." : "Be in bed for the best chance of a green Recovery.", .green)
                Toggle(isOn: $earlyWake) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Early wake · experimental").font(.nuna(size: 12.5, weight: .heavy)).tracking(0.8).textCase(.uppercase).foregroundStyle(Color.white)
                        Text(earlyWake ? "Sleep goal and In the green may buzz up to an hour early." : "Off: every mode buzzes at your wake time.")
                            .font(.nuna(size: 11.5, weight: .regular)).foregroundStyle(Color.white.opacity(0.6)).textCase(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Self.mint).padding(.top, 2)
            }
            .padding(.horizontal, w * 0.122)
        }
    }

    private func modeCard(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ m: NunaAlarmMode) -> some View {
        Button {
            draftMode = m
            switch m { case .goal: step = .goal; case .exact, .green: step = .wake }
        } label: {
            VStack(spacing: 8) {
                Text(title).font(.nuna(size: 14, weight: .heavy)).tracking(1.2).textCase(.uppercase).foregroundStyle(Color.white)
                Text(subtitle).font(.nuna(size: 12, weight: .regular)).foregroundStyle(Color.white.opacity(0.68)).textCase(nil).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30).frame(maxWidth: .infinity).frame(height: 95)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.white.opacity(0.38), lineWidth: 1.3))
        }
        .buttonStyle(.plain)
    }

    private func goalSheet(width w: CGFloat, inset: CGFloat) -> some View {
        VStack(spacing: 0) {
            sheetTitle("Select your Sleep Goal.", back: { step = goalOnly ? .summary : .mode; goalOnly = false })
            VStack(alignment: .leading, spacing: 20) {
                ForEach([100, 85, 70], id: \.self) { g in
                    Button { draftGoal = g } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().strokeBorder(draftGoal == g ? Self.mint : Color.white, lineWidth: 1.7).frame(width: 30, height: 30)
                                if draftGoal == g { Circle().fill(Self.mint).frame(width: 30, height: 30); Circle().fill(Color.black).frame(width: 9, height: 9) }
                            }
                            Text(verbatim: String(localized: "\(g)% of my sleep need")).font(.nuna(size: 13, weight: .heavy)).tracking(0.9).textCase(.uppercase)
                                .foregroundStyle(draftGoal == g ? Self.mint : Color.white.opacity(0.62))
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 40).padding(.trailing, 20).padding(.top, 77)
            Spacer(minLength: 0)
            bigButton(goalOnly ? "Save" : "Next", mint: true) { if goalOnly { saveGoal() } else { step = .wake } }.padding(.bottom, max(54 - inset, 12))
        }
    }

    private func wakeSheet(width w: CGFloat, inset: CGFloat) -> some View {
        let early = earlyWake && draftMode != .exact
        let chosen = NunaAlarmFormat.minutes(draftWake)
        return VStack(spacing: 0) {
            sheetTitle(early ? "Set your latest wake time." : "Set your wake time.", back: { step = draftMode == .goal ? .goal : .mode })
            PlannerTimeWheel(date: $draftWake).frame(height: 168).padding(.top, 52)
            Spacer(minLength: 0)
            Text(verbatim: early ? String(localized: "Alarm will vibrate between \(NunaAlarmFormat.clock(Self.hourBefore(chosen))) - \(NunaAlarmFormat.clock(chosen))")
                                 : String(localized: "Your strap will buzz at \(NunaAlarmFormat.clock(chosen))."))
                .font(.nuna(size: 14, weight: .regular)).foregroundStyle(Color.white.opacity(0.85)).textCase(nil).padding(.bottom, scheduledDays == nil ? 14 : 4)
            if let days = scheduledDays {
                // While My Schedule is on, Save changes the days that share the next alarm.
                Text(verbatim: String(localized: "Changes \(days) in My Schedule")).font(.nuna(size: 11.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55)).textCase(nil).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 10)
            }
            bigButton("Save & set alarm", mint: false) { save() }.padding(.bottom, max(54 - inset, 12))
        }
    }

    /// An outlined capsule: white for the exact time, the colour of the mode otherwise.
    private func bigButton(_ title: LocalizedStringKey, mint: Bool, action: @escaping () -> Void) -> some View {
        let tone: Color = draftMode == .exact ? .white : (draftMode == .green ? Self.green : Self.mint)
        let c = (mint || draftMode != .exact) ? tone : Color.white
        return Button(action: action) {
            Text(title).font(.nuna(size: 14, weight: .heavy)).tracking(2.0).textCase(.uppercase).foregroundStyle(c)
                .frame(maxWidth: .infinity).frame(height: 42)
                .overlay(Capsule().strokeBorder(c, lineWidth: 1.7))
        }
        .buttonStyle(.plain).padding(.horizontal, 20)
    }

    // MARK: Steps and saving

    private func openMode() { startDraft(); step = .mode }
    private func openWake() { startDraft(); step = .wake }
    private func openGoal() { startDraft(); goalOnly = true; step = .goal }
    private func startDraft() {
        goalOnly = false
        draftMode = NunaAlarmMode(rawValue: behavior.smartAlarmMode) ?? .exact
        draftGoal = behavior.smartAlarmGoal
        draftWake = NunaAlarmFormat.date(minutes: nextMinutes)
    }

    /// The weekday of the alarm that comes next.
    private var nextWeekday: Int {
        Calendar.current.component(.weekday, from: model.nextAlarmDate() ?? Date().addingTimeInterval(86_400))
    }

    /// "Mon · Tue" for the days a save changes while My Schedule drives the alarm; nil otherwise.
    private var scheduledDays: String? {
        guard schedule.drives else { return nil }
        return schedule.group(of: nextWeekday).map(NunaAlarmFormat.weekdayShort).joined(separator: " · ")
    }

    /// Writes the choices to the alarm and arms the strap.
    private func save() {
        write(AlarmDayPlan(minutes: NunaAlarmFormat.minutes(draftWake), mode: draftMode.rawValue, goal: draftMode == .goal ? draftGoal : behavior.smartAlarmGoal))
        if !behavior.smartAlarmEnabled { behavior.smartAlarmEnabled = true }
        step = .summary
    }

    /// The goal alone, from the pill.
    private func saveGoal() {
        write(AlarmDayPlan(minutes: nextMinutes, mode: behavior.smartAlarmMode, goal: draftGoal))
        goalOnly = false
        step = .summary
    }

    private func write(_ plan: AlarmDayPlan) {
        if schedule.drives {
            var changed = schedule
            changed.set(plan, on: changed.group(of: nextWeekday))
            model.setAlarmSchedule(changed)
            schedule = AlarmSchedule.load()
        } else {
            let weekday = nextWeekday
            behavior.smartAlarmMode = plan.mode
            behavior.smartAlarmGoal = plan.goal
            behavior.smartAlarmMinutes = plan.minutes
            // A day with a time of its own keeps winning over the usual one, so the new time goes to it as well.
            if WindDownNudge.perDayWakeOverrides[weekday] != nil { WindDownNudge.setWakeOverride(weekday: weekday, minutes: plan.minutes) }
            model.applySmartAlarm()
        }
    }

    // MARK: Help

    private var helpSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sleep planner").font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                note("The strap is armed at your wake time in every mode. The sleep goal decides the bedtime to aim for, the time in bed it leaves, and the Tonight's sleep card on Today.")
                note("Early wake (experimental): in the hour before your wake time, PHMN reads the night so far on your iPhone and buzzes the strap once your sleep goal is reached, or once Recovery worked out so far is 67% or more after at least four hours of sleep. These are estimates from records that arrive about every ten minutes, and iOS can delay the app, so the buzz may come late or not early at all. The wake time stays armed on the strap, and the phone notification stays at that time.")
                note("Optimal is the window your sleep need itself asks for, ending at your wake time. The suggested bedtime starts a little earlier, to leave time to fall asleep.")
                note("The buzz is the same one as your other wrist alerts, so it follows the Wrist alerts switch in Strap automations: with it off the strap stays silent and only the phone notification wakes you. To turn the alarm off, double-tap your strap while it buzzes.")
                note("The buzz is silent, from the strap's own firmware, so it works even if your phone is asleep or PHMN is closed. A backup notification is scheduled too, but Focus or silent mode can mute it. Keep your phone's Clock alarm as your real backup.")
                if model.whoop5Detected && !PuffinExperiment.isEnabled {
                    note("Your WHOOP 5/MG won't arm this until its wake alarm is turned on in Settings, Experiments. Right now your wake time is saved but the strap is NOT armed.", warn: true)
                } else if model.whoop5Detected {
                    note("Armed on the strap itself with the experimental 5/MG command. A strap-driven wake is still unconfirmed on 5/MG, so keep a backup alarm.")
                } else {
                    Button { model.ble.getStrapAlarm() } label: {
                        Text("Check what the strap has stored").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 46)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain)
                }
                if behavior.smartAlarmEnabled && rejectStreak >= 2 {
                    note("Your strap keeps reporting a different time than PHMN sends, so its alarm won't fire at your wake time. Reset the strap in the official WHOOP app (or fully charge it and reconnect), and keep your phone's Clock alarm as your wake until it takes.", warn: true)
                }
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NunaBackdrop())
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
            ? (model.nextAlarmDate() ?? Date().addingTimeInterval(86_400))
            : Date().addingTimeInterval(86_400)
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date)
    }

    /// 9:45.
    private static func hm(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }
}

// MARK: - Drawing

/// A calendar with a crescent in it: the mark of the repeat button and of the alarm row.
private struct PlannerCalendarIcon: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous).strokeBorder(lineWidth: max(1.4, size * 0.085)).frame(width: size, height: size * 0.92).offset(y: size * 0.06)
            Rectangle().frame(width: size, height: max(1.4, size * 0.085)).offset(y: -size * 0.2)
            HStack(spacing: size * 0.42) {
                Capsule().frame(width: max(1.4, size * 0.085), height: size * 0.22)
                Capsule().frame(width: max(1.4, size * 0.085), height: size * 0.22)
            }
            .offset(y: -size * 0.44)
            Image(systemName: "moon.fill").font(.system(size: size * 0.38, weight: .regular)).offset(x: size * 0.12, y: size * 0.22)
        }
        .frame(width: size * 1.1, height: size * 1.1)
    }
}

/// Fine slanted stripes across a bar. With `fades` the stripes thin out towards the right edge: the bar has no end, because the wake can come later.
private struct PlannerHatch: View {
    let color: Color
    var fades = false
    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path(); p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.stroke(p, with: .color(color.opacity(0.9)), lineWidth: 2.3)
                x += 6.4
            }
        }
        .mask(LinearGradient(stops: fades ? [.init(color: .white, location: 0), .init(color: .white, location: 0.55), .init(color: .white.opacity(0), location: 1)]
                                          : [.init(color: .white, location: 0), .init(color: .white, location: 1)], startPoint: .leading, endPoint: .trailing))
    }
}

/// A vertical rule drawn in fine dots.
private struct DottedRule: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            Path { p in p.move(to: CGPoint(x: geo.size.width / 2, y: 0)); p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height)) }
                .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, dash: [1.6, 3.2]))
        }
    }
}

/// The bracket under the bar: down from each end, along the bottom with rounded corners, with a gap in the middle for its label.
private struct OptimalBracket: Shape {
    let from: CGFloat
    let to: CGFloat
    let gap: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r: CGFloat = 5, bottom = rect.maxY - 1, mid = (from + to) / 2
        p.move(to: CGPoint(x: from, y: 0)); p.addLine(to: CGPoint(x: from, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: from + r, y: bottom), control: CGPoint(x: from, y: bottom))
        p.addLine(to: CGPoint(x: max(mid - gap / 2, from + r), y: bottom))
        p.move(to: CGPoint(x: min(mid + gap / 2, to - r), y: bottom)); p.addLine(to: CGPoint(x: to - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: to, y: bottom - r), control: CGPoint(x: to, y: bottom))
        p.addLine(to: CGPoint(x: to, y: 0))
        return p
    }
}

/// The wake time as wheels: thin figures on a barrel that fades towards its ends, a rounded band behind the chosen row. Hours and minutes, and AM or
/// PM when the device is set to a 12-hour clock.
private struct PlannerTimeWheel: View {
    @Binding var date: Date
    private let rowHeight: CGFloat = 31
    private var twelveHour: Bool {
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: AppLanguage.activeLocale) ?? "").contains("a")
    }

    private var hour24: Int { Calendar.current.component(.hour, from: date) }
    private var minute: Int { Calendar.current.component(.minute, from: date) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.1)).frame(width: 224, height: 34)
            HStack(spacing: 22) {
                if twelveHour {
                    column(Array(1...12), selection: Binding(get: { hour24 % 12 == 0 ? 12 : hour24 % 12 },
                                                             set: { set(hour: $0 % 12 + (hour24 >= 12 ? 12 : 0)) })) { String($0) }
                } else {
                    column(Array(0...23), selection: Binding(get: { hour24 }, set: { set(hour: $0) })) { String(format: "%02d", $0) }
                }
                column(Array(0...59), selection: Binding(get: { minute }, set: { set(minute: $0) })) { String(format: "%02d", $0) }
                if twelveHour {
                    column([0, 1], selection: Binding(get: { hour24 >= 12 ? 1 : 0 }, set: { set(hour: hour24 % 12 + ($0 == 1 ? 12 : 0)) })) { $0 == 0 ? "AM" : "PM" }
                }
            }
        }
    }

    private func set(hour: Int? = nil, minute m: Int? = nil) {
        var c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        if let hour { c.hour = hour }
        if let m { c.minute = m }
        if let d = Calendar.current.date(from: c) { date = d }
    }

    private func column(_ values: [Int], selection: Binding<Int>, label: @escaping (Int) -> String) -> some View {
        WheelColumn(values: values, selection: selection, width: 52, rowHeight: rowHeight, label: label)
    }
}

private struct WheelColumn: View {
    let values: [Int]
    @Binding var selection: Int
    let width: CGFloat
    let rowHeight: CGFloat
    let label: (Int) -> String
    @State private var position: Int?

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(values, id: \.self) { v in
                        // Light figures, as thin as the reference's: the system font, not the look's, because the looks set every figure from 24 pt up in bold.
                        Text(verbatim: label(v)).font(.system(size: 26, weight: .light)).monospacedDigit().foregroundStyle(Color.white).textCase(nil)
                            .frame(width: width, height: rowHeight)
                            .scrollTransition(axis: .vertical) { c, phase in
                                c.opacity(1 - min(abs(phase.value), 1.0) * 0.72)
                                    .scaleEffect(1 - min(abs(phase.value), 1.0) * 0.16)
                                    .rotation3DEffect(.degrees(phase.value * -42), axis: (x: 1, y: 0, z: 0))
                            }
                            .id(v)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.vertical, (geo.size.height - rowHeight) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
            .onAppear { position = selection }
            .onChange(of: position) { _, new in if let new, new != selection { selection = new } }
        }
        .frame(width: width)
    }
}
#endif
