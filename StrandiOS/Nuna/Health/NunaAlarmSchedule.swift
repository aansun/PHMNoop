#if os(iOS)
import SwiftUI
import StrandDesign

/// My Schedule: an alarm for each weekday, shown as one card for the days that share a time, a mode and a goal. A card opens to change its days, time
/// and mode. The switch at the top decides whether the schedule drives the alarm; off, the alarm goes back to what it was.
struct NunaAlarmScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore
    @AppStorage(EarlyWake.enabledKey) private var earlyWake = false
    @State private var schedule = AlarmSchedule.load()
    @State private var editing: Draft?

    /// A card being changed: the days it had, the days chosen now and their alarm.
    private struct Draft: Equatable {
        var original: [Int]
        var days: Set<Int>
        var plan: AlarmDayPlan
        var time: Date { get { NunaAlarmFormat.date(minutes: plan.minutes) } set { plan.minutes = NunaAlarmFormat.minutes(newValue) } }
    }

    private static let mint = NunaRestChart.need
    private static let green = Color(red: 0.17, green: 0.85, blue: 0.29)

    var body: some View {
        ZStack {
            LinearGradient(stops: [.init(color: Color(red: 0.17, green: 0.21, blue: 0.24), location: 0), .init(color: Color(red: 0.07, green: 0.09, blue: 0.1), location: 0.55)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 18) {
                        if !schedule.on {
                            note("The schedule is off, so your alarm follows the planner. Turn it on to use these times.")
                        } else if !behavior.smartAlarmEnabled {
                            note("Your alarm is off. Turn it on in the sleep planner to use this schedule.")
                        }
                        ForEach(Array(schedule.groups.enumerated()), id: \.element.days) { _, group in
                            card(days: group.days, plan: group.plan)
                        }
                        if let draft = editing, draft.original.isEmpty { editorCard(title: dayLine(Array(draft.days)), draft: draft) }
                        footer
                    }
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: load)
    }

    private var header: some View {
        ZStack {
            Text("My schedule").font(.nuna(size: 13, weight: .heavy)).tracking(1.5).textCase(.uppercase).foregroundStyle(Color.white)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 23, weight: .bold)).foregroundStyle(Color.white).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Back"))
                Spacer()
                Toggle("", isOn: Binding(get: { schedule.on }, set: { turn($0) })).labelsHidden().tint(Self.mint)
                    .accessibilityLabel(Text("My schedule"))
            }
        }
        .padding(.leading, 8).padding(.trailing, 20).padding(.top, 6).frame(height: 56)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.nuna(size: 13, weight: .regular)).foregroundStyle(Color.white.opacity(0.65)).textCase(nil)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).padding(.horizontal, 12)
    }

    // MARK: Cards

    @ViewBuilder private func card(days: [Int], plan: AlarmDayPlan) -> some View {
        if let draft = editing, draft.original == days {
            editorCard(title: dayLine(days), draft: draft)
        } else {
            Button { editing = Draft(original: days, days: Set(days), plan: plan) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        dayLine(days)
                        Text(verbatim: NunaAlarmFormat.clock(plan.minutes)).font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(Color.white)
                        chip(plan)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 16, weight: .heavy)).foregroundStyle(Color.white)
                }
                .padding(.horizontal, 20).padding(.vertical, 18)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(schedule.on ? 1 : 0.6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// "MON • TUE • WED".
    private func dayLine(_ days: [Int]) -> Text {
        let names = AlarmSchedule.weekOrder.filter(days.contains).map(NunaAlarmFormat.weekdayShort)
        return Text(verbatim: names.isEmpty ? String(localized: "No day chosen") : names.joined(separator: " • ").uppercased(with: AppLanguage.activeLocale))
            .font(.nuna(size: 11.5, weight: .heavy)).tracking(0.8).foregroundColor(Color.white.opacity(0.6))
    }

    private func chip(_ plan: AlarmDayPlan) -> some View {
        let tone = plan.mode == "green" ? Self.green : (plan.mode == "goal" ? Self.mint : Color.white)
        return HStack(spacing: 7) {
            Image(systemName: "applewatch.radiowaves.left.and.right").font(.system(size: 13, weight: .semibold))
            Text(modeName(plan.mode)).font(.nuna(size: 11.5, weight: .heavy)).tracking(1.0).textCase(.uppercase)
            if plan.mode == "goal" { Text(verbatim: "\(plan.goal)%").font(.nuna(size: 11.5, weight: .heavy)) }
        }
        .foregroundStyle(tone).padding(.horizontal, 11).frame(height: 30)
        .background(tone.opacity(0.13), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func modeName(_ mode: String) -> LocalizedStringKey {
        mode == "green" ? "In the green" : (mode == "goal" ? "Sleep goal" : "Exact time")
    }

    // MARK: Editing

    private func editorCard(title: Text, draft: Draft) -> some View {
        VStack(spacing: 16) {
            Button { editing = nil } label: {
                HStack {
                    dayLine(Array(draft.days))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up").font(.system(size: 16, weight: .heavy)).foregroundStyle(Color.white)
                }
                .frame(minHeight: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(Text("Close without saving"))
            HStack(spacing: 6) {
                ForEach(AlarmSchedule.weekOrder, id: \.self) { d in
                    let on = draft.days.contains(d)
                    Button { toggle(d) } label: {
                        // The short name, not its first letter: several days share one in some languages.
                        Text(verbatim: NunaAlarmFormat.weekdayShort(d)).font(.nuna(size: 11.5, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7).textCase(nil)
                            .foregroundStyle(on ? Color.black : Color.white.opacity(0.7)).frame(maxWidth: .infinity).frame(height: 40)
                            .background(on ? Color.white : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text(verbatim: NunaAlarmFormat.weekdayName(d))).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            DatePicker("", selection: Binding(get: { editing?.time ?? draft.time }, set: { editing?.time = $0 }), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel).labelsHidden().frame(maxHeight: 150).clipped().colorScheme(.dark)
                .accessibilityLabel(Text("Wake time"))
            choices(["exact", "goal", "green"], selected: draft.plan.mode, title: modeName) { editing?.plan.mode = $0 }
            if draft.plan.mode == "goal" {
                choices([100, 85, 70], selected: draft.plan.goal, title: { "\($0)%" }) { editing?.plan.goal = $0 }
            }
            if draft.plan.mode != "exact" {
                note(earlyWake ? "Early wake is on: this day may buzz up to an hour before the time." : "Early wake is off, so this day buzzes at the time. It is in the planner and in Experiments.")
            }
            Button(action: saveDraft) {
                Text("Save").font(.nuna(size: 13.5, weight: .heavy)).tracking(1.8).textCase(.uppercase).foregroundStyle(Self.mint)
                    .frame(maxWidth: .infinity).frame(height: 42).overlay(Capsule().strokeBorder(Self.mint, lineWidth: 1.7)).contentShape(Capsule())
            }
            .buttonStyle(.plain).disabled(draft.days.isEmpty && draft.original.isEmpty).opacity(draft.days.isEmpty && draft.original.isEmpty ? 0.4 : 1)
            if !draft.original.isEmpty {
                Button { editing?.days = []; saveDraft() } label: {
                    Text("Remove these days").font(.nuna(size: 12.5, weight: .heavy)).tracking(1.0).textCase(.uppercase).foregroundStyle(Color.white.opacity(0.6))
                        .frame(maxWidth: .infinity).frame(height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 18)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func choices<T: Hashable>(_ values: [T], selected: T, title: @escaping (T) -> LocalizedStringKey, pick: @escaping (T) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self) { v in
                let on = v == selected
                Button { pick(v) } label: {
                    Text(title(v)).font(.nuna(size: 11.5, weight: .heavy)).tracking(0.6).textCase(.uppercase).foregroundStyle(on ? Color.black : Color.white.opacity(0.75))
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8).frame(maxWidth: .infinity, minHeight: 42).padding(.horizontal, 4)
                        .background(on ? Color.white : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    // MARK: Footer

    private var uncovered: [Int] { AlarmSchedule.weekOrder.filter { schedule.days[$0] == nil } }

    @ViewBuilder private var footer: some View {
        if uncovered.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Self.mint)
                Text("Your schedule is complete").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(Self.mint).textCase(nil)
            }
            .padding(.top, 22)
        } else if editing?.original.isEmpty != true {
            VStack(spacing: 12) {
                Text(verbatim: String(localized: "No alarm on \(uncovered.map(NunaAlarmFormat.weekdayShort).joined(separator: " · "))"))
                    .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.65)).textCase(nil)
                Button {
                    editing = Draft(original: [], days: Set(uncovered),
                                    plan: AlarmDayPlan(minutes: behavior.smartAlarmMinutes, mode: behavior.smartAlarmMode, goal: behavior.smartAlarmGoal))
                } label: {
                    Text("Add an alarm for these days").font(.nuna(size: 12.5, weight: .heavy)).tracking(1.0).textCase(.uppercase).foregroundStyle(Color.white)
                        .padding(.horizontal, 18).frame(height: 38).overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.4)).contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
    }

    // MARK: Changes

    /// The stored schedule; before there is one, the days and times the alarm has now.
    private func load() {
        var stored = AlarmSchedule.load()
        if stored.days.isEmpty, !stored.on {
            let own = WindDownNudge.perDayWakeOverrides
            let days = behavior.smartAlarmWeekdays.isEmpty ? Set(1...7) : behavior.smartAlarmWeekdays
            for d in days {
                stored.days[d] = AlarmDayPlan(minutes: own[d] ?? behavior.smartAlarmMinutes, mode: behavior.smartAlarmMode, goal: behavior.smartAlarmGoal)
            }
        }
        schedule = stored
    }

    private func turn(_ on: Bool) {
        var changed = schedule
        changed.on = on
        commit(changed)
        // A schedule that is on is meant to ring.
        if on, changed.drives, !behavior.smartAlarmEnabled { behavior.smartAlarmEnabled = true; model.applySmartAlarm() }
    }

    private func toggle(_ day: Int) {
        guard var draft = editing else { return }
        if draft.days.contains(day) { draft.days.remove(day) } else { draft.days.insert(day) }
        editing = draft
    }

    private func saveDraft() {
        guard let draft = editing else { return }
        var changed = schedule
        changed.set(draft.plan, on: Array(draft.days), replacing: draft.original)
        if changed.days.isEmpty { changed.on = false }
        editing = nil
        commit(changed)
    }

    private func commit(_ changed: AlarmSchedule) {
        model.setAlarmSchedule(changed)
        // What was stored, with the alarm it replaced kept for turning the schedule off.
        schedule = AlarmSchedule.load()
    }
}
#endif
