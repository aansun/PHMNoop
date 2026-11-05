#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// The goals a plan is made of. A plan exists as soon as one of them is set; the same stored goals the target screens write.
enum NunaPlanKind: String, CaseIterable, Identifiable {
    case steps, zonesEasy, zonesHard, strength, sleepConsistency, sleepPerformance
    var id: String { rawValue }

    var storageKey: String {
        switch self {
        case .steps: return NunaGoals.steps
        case .zonesEasy: return NunaGoals.zonesEasyMinutes
        case .zonesHard: return NunaGoals.zonesHardMinutes
        case .strength: return NunaGoals.strengthMinutes
        case .sleepConsistency: return NunaGoals.sleepConsistency
        case .sleepPerformance: return NunaGoals.sleepPerformance
        }
    }
    /// Steps a day, or minutes a week.
    var goal: Int { UserDefaults.standard.integer(forKey: storageKey) }
    var isSet: Bool { goal > 0 }
    var weekly: NunaWeeklyTarget? {
        switch self {
        case .steps, .sleepConsistency, .sleepPerformance: return nil
        case .zonesEasy: return .zonesEasy
        case .zonesHard: return .zonesHard
        case .strength: return .strength
        }
    }
    var tint: Color {
        switch self {
        case .steps: return NunaPalette.effortModerate
        case .zonesEasy: return NunaZoneWeeklyCard.color(1)
        case .zonesHard: return NunaZoneWeeklyCard.color(3)
        case .strength: return NunaPalette.effort
        case .sleepConsistency, .sleepPerformance: return NunaPalette.rest
        }
    }
    var zoneIndexes: [Int] { self == .zonesEasy ? [0, 1, 2] : (self == .zonesHard ? [3, 4] : []) }

    /// The name in the Edit menu.
    var menuTitle: String {
        switch self {
        case .steps: return String(localized: "Steps")
        case .zonesEasy: return String(localized: "HR Zones 1–3")
        case .zonesHard: return String(localized: "HR Zones 4–5")
        case .strength: return String(localized: "Strength Activity Time")
        case .sleepConsistency: return String(localized: "Sleep Consistency")
        case .sleepPerformance: return String(localized: "Sleep Performance")
        }
    }
    /// The title of the page section.
    var sectionTitle: String {
        switch self {
        case .steps: return String(localized: "Steps")
        case .zonesEasy: return String(localized: "HR Zones 1–3 Training")
        case .zonesHard: return String(localized: "HR Zones 4–5 Training")
        case .strength: return String(localized: "Strength Training")
        case .sleepConsistency: return String(localized: "Sleep Consistency")
        case .sleepPerformance: return String(localized: "Sleep Performance")
        }
    }
    /// The label above the figures.
    var cardLabel: String {
        switch self {
        case .steps: return String(localized: "\(NunaPlanFormat.thousands(Double(goal)))+ Steps")
        case .zonesEasy: return String(localized: "HR Zones 1–3 Time")
        case .zonesHard: return String(localized: "HR Zones 4–5 Time")
        case .strength: return String(localized: "Strength Activity Time")
        case .sleepConsistency: return String(localized: "Sleep Consistency")
        case .sleepPerformance: return String(localized: "Sleep Performance")
        }
    }
    /// The row on Today: the goal with its name.
    var rowTitle: String {
        let amount = NunaPlanFormat.goalClock(Double(goal))
        switch self {
        case .steps: return String(localized: "\(NunaPlanFormat.thousands(Double(goal)))+ Steps")
        case .zonesEasy: return String(localized: "\(amount)+ HR Zones 1-3 Time")
        case .zonesHard: return String(localized: "\(amount)+ HR Zones 4-5 Time")
        case .strength: return String(localized: "\(amount)+ Strength Activity Time")
        case .sleepConsistency: return String(localized: "\(goal)%+ Sleep Consistency")
        case .sleepPerformance: return String(localized: "\(goal)%+ Sleep Performance")
        }
    }
}

enum NunaPlanFormat {
    static func thousands(_ v: Double) -> String { nunaThousands(v) }
    /// "1:20" for 80 minutes.
    static func goalClock(_ minutes: Double) -> String { let m = Int(minutes.rounded()); return String(format: "%d:%02d", m / 60, m % 60) }
    /// "0:37", whole minutes down.
    static func clock(_ minutes: Double) -> String { let m = Int(max(0, minutes)); return String(format: "%d:%02d", m / 60, m % 60) }
    /// "0:37:54".
    static func clockSeconds(_ minutes: Double) -> String {
        let s = Int((max(0, minutes) * 60).rounded())
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
    /// "1 hr 14 min", "53 min", rounded up.
    static func spoken(_ minutes: Double) -> String {
        let m = Int(max(0, minutes).rounded(.up))
        if m >= 60 { return m % 60 == 0 ? String(localized: "\(m / 60) hr") : String(localized: "\(m / 60) hr \(m % 60) min") }
        return String(localized: "\(m) min")
    }
}

/// One week of a plan: for every goal that is set, the week's figure, each day's figure and what it was made of.
@MainActor
final class NunaPlanModel: ObservableObject {
    /// `sport` is nil for the remainder of the day's movement outside activities.
    struct Line: Identifiable { let id: String; let name: String; let sport: String?; let minutes: Double }
    struct Item: Identifiable {
        let kind: NunaPlanKind
        /// Steps a day, or minutes in the week.
        let goal: Double
        /// Steps in the week, or minutes in the week.
        let value: Double
        let perDay: [Double]
        let lines: [Line]
        var id: String { kind.rawValue }
        var hitDays: Int { perDay.filter { $0 >= goal }.count }
        /// 0 to 1: days reached out of seven for steps, the share of the weekly goal for the rest.
        var fraction: Double { kind == .steps ? min(1, Double(hitDays) / 7) : (goal > 0 ? min(1, value / goal) : 0) }
    }

    /// A behavior of the plan: the days of the week it was logged (as asked) out of the days it asks for.
    struct BehaviorItem: Identifiable {
        let id: String
        let title: String
        let goal: Int
        let done: Int
        var fraction: Double { goal > 0 ? min(1, Double(done) / Double(goal)) : 0 }
    }
    /// An activity of the plan: the days of the week it was done out of the days it asks for.
    struct ActivityItem: Identifiable {
        let id: String
        let title: String
        let goal: Int
        let done: Int
        var fraction: Double { goal > 0 ? min(1, Double(done) / Double(goal)) : 0 }
        var complete: Bool { done >= goal }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var behaviors: [BehaviorItem] = []
    @Published private(set) var activities: [ActivityItem] = []
    @Published private(set) var spec = NunaPlanSpec()
    @Published private(set) var weekDays: [Date] = []
    @Published private(set) var loaded = false

    /// Weeks run Monday to Sunday.
    static var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }

    static func monday(of day: Date) -> Date {
        let c = calendar
        let start = c.startOfDay(for: day)
        let back = (c.component(.weekday, from: start) + 5) % 7
        return c.date(byAdding: .day, value: -back, to: start) ?? start
    }

    /// The average share done across every goal of the plan: metrics, behaviors and activities.
    var accomplished: Double {
        let all = items.map(\.fraction) + behaviors.map(\.fraction) + activities.map(\.fraction)
        return all.isEmpty ? 0 : all.reduce(0, +) / Double(all.count)
    }

    /// Days of this week still ahead, today included; nil for a week that is over.
    var daysLeft: Int? {
        guard let last = weekDays.last else { return nil }
        let today = Self.calendar.startOfDay(for: Date())
        guard today <= last else { return nil }
        return (Self.calendar.dateComponents([.day], from: today, to: last).day ?? 0) + 1
    }

    func load(repo: Repository, age: Int, weekOffset: Int) async {
        let cal = Self.calendar
        let thisMonday = Self.monday(of: Date())
        let start = cal.date(byAdding: .day, value: -7 * weekOffset, to: thisMonday) ?? thisMonday
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let plan = NunaPlanStore.load()
        let kinds = NunaPlanKind.allCases.filter(\.isSet)
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        let from = Int(start.timeIntervalSince1970), to = Int(end.timeIntervalSince1970)
        let rows = await repo.workoutRows().filter { $0.startTs >= from && $0.startTs < to }
        var out: [Item] = []

        if kinds.contains(.steps) {
            var st: [String: Double] = [:]
            for source in ["my-whoop", MetricCatalog.combinedStepsSource] {
                for p in await repo.exploreSeries(key: "steps", source: source, days: 400) where p.value > 0 { st[p.day] = p.value }
            }
            for p in await repo.exploreSeries(key: "steps_est", source: "my-whoop", days: 400) where p.value > 0 && st[p.day] == nil { st[p.day] = p.value }
            let per = days.map { st[Repository.localDayKey($0)] ?? 0 }
            out.append(Item(kind: .steps, goal: Double(NunaPlanKind.steps.goal), value: per.reduce(0, +), perDay: per, lines: []))
        }

        let zoneKinds = kinds.filter { $0 == .zonesEasy || $0 == .zonesHard }
        if !zoneKinds.isEmpty {
            let byDay = await NunaZoneMinutes.perDay(repo: repo, age: age, days: days)
            // What each workout holds of the week's zone time; the rest of the day's movement is the remainder.
            var inWorkout: [(row: WorkoutRow, zones: [Double])] = []
            for row in rows {
                let day = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(row.startTs)))
                inWorkout.append((row, await NunaZoneMinutes.inWindow(repo: repo, age: age, from: row.startTs, to: max(row.endTs, row.startTs + 1), day: day)))
            }
            for kind in zoneKinds {
                let per = days.map { d in kind.zoneIndexes.reduce(0.0) { $0 + (byDay[d]?[$1] ?? 0) } }
                let total = per.reduce(0, +)
                var bySport: [String: Double] = [:]
                for w in inWorkout {
                    let minutes = kind.zoneIndexes.reduce(0.0) { $0 + w.zones[$1] }
                    guard minutes > 0 else { continue }
                    bySport[WorkoutSource.displaySport(w.row.sport), default: 0] += minutes
                }
                // A sport with under a minute is part of the remainder, so the rows always add up to the week's time.
                var lines = bySport.filter { $0.value >= 1 }.sorted { $0.value > $1.value }.map { Line(id: $0.key, name: $0.key, sport: $0.key, minutes: $0.value) }
                let rest = total - lines.reduce(0) { $0 + $1.minutes }
                if rest >= 1 { lines.append(Line(id: "rest", name: String(localized: "Outside activities"), sport: nil, minutes: rest)) }
                out.append(Item(kind: kind, goal: Double(kind.goal), value: total, perDay: per, lines: lines))
            }
        }

        if kinds.contains(.strength) {
            let strength = rows.filter(NunaWorkoutKind.isStrength)
            func minutes(_ r: WorkoutRow) -> Double { (r.durationS ?? Double(r.endTs - r.startTs)) / 60 }
            let per = days.map { d -> Double in
                let a = Int(d.timeIntervalSince1970), b = Int((cal.date(byAdding: .day, value: 1, to: d) ?? d).timeIntervalSince1970)
                return strength.filter { $0.startTs >= a && $0.startTs < b }.reduce(0) { $0 + minutes($1) }
            }
            var bySport: [String: Double] = [:]
            for r in strength { bySport[WorkoutSource.displaySport(r.sport), default: 0] += minutes(r) }
            let lines = bySport.sorted { $0.value > $1.value }.map { Line(id: $0.key, name: $0.key, sport: $0.key, minutes: $0.value) }
            out.append(Item(kind: .strength, goal: Double(NunaPlanKind.strength.goal), value: per.reduce(0, +), perDay: per, lines: lines))
        }

        for kind in kinds where kind.isPercent {
            let series = await Self.percentSeries(kind, repo: repo)
            let per = days.map { series[Repository.localDayKey($0)] ?? 0 }
            let present = per.filter { $0 > 0 }
            let average = present.isEmpty ? 0 : present.reduce(0, +) / Double(present.count)
            out.append(Item(kind: kind, goal: Double(kind.goal), value: average, perDay: per, lines: []))
        }

        let order = NunaPlanStore.orderedKinds(plan)
        items = out.sorted { (order.firstIndex(of: $0.kind) ?? 99) < (order.firstIndex(of: $1.kind) ?? 99) }

        // Behaviors: the days up to today that the journal says yes to (or no, when the goal is to avoid it).
        let today = cal.startOfDay(for: Date())
        var answersByDay: [String: [String: Bool]] = [:]
        if !plan.behaviors.isEmpty {
            for d in days where d <= today { answersByDay[Repository.localDayKey(d)] = await repo.nativeJournalAnswers(day: Repository.localDayKey(d)) }
        }
        behaviors = plan.behaviors.map { b in
            let done = answersByDay.values.filter { $0[b.id] == !b.avoid }.count
            return BehaviorItem(id: b.id, title: b.title, goal: b.days, done: done)
        }

        // Activities: the days with a workout that counts.
        func dayKey(_ r: WorkoutRow) -> String { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(r.startTs))) }
        activities = plan.activities.map { a in
            let matching: [WorkoutRow]
            switch a.id {
            case NunaPlanActivity.strain: matching = rows.filter { !NunaActivityKind.isCharge(WorkoutSource.displaySport($0.sport)) && !NunaActivityKind.isRest(WorkoutSource.displaySport($0.sport)) }
            case NunaPlanActivity.strength: matching = rows.filter(NunaWorkoutKind.isStrength)
            case NunaPlanActivity.recovery: matching = rows.filter { NunaActivityKind.isCharge(WorkoutSource.displaySport($0.sport)) }
            default: matching = rows.filter { WorkoutSource.displaySport($0.sport).caseInsensitiveCompare(a.sportName ?? "") == .orderedSame }
            }
            return ActivityItem(id: a.id, title: a.title, goal: a.days, done: Set(matching.map(dayKey)).count)
        }
        spec = plan
        weekDays = days
        loaded = true
    }

    /// A sleep score by day, in percent, as the strap and the sleep model keep it.
    static func percentSeries(_ kind: NunaPlanKind, repo: Repository) async -> [String: Double] {
        let key = kind == .sleepConsistency ? "sleep_consistency" : "sleep_performance"
        var out: [String: Double] = [:]
        for p in await repo.exploreSeries(key: key, source: "my-whoop", days: 400) where p.value > 0 { out[p.day] = p.value <= 1 ? p.value * 100 : p.value }
        return out
    }

    /// The weekly minutes of the four weeks before today, averaged: the figure the target screen sets a goal against.
    static func fourWeekAverage(_ kind: NunaPlanKind, repo: Repository, age: Int) async -> Double? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch kind {
        case .steps: return nil
        case .sleepConsistency, .sleepPerformance:
            // Not minutes: the mean of the last thirty days that have a score, today left out.
            let series = await percentSeries(kind, repo: repo)
            let recent = (1...30).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.compactMap { series[Repository.localDayKey($0)] }
            return recent.isEmpty ? nil : recent.reduce(0, +) / Double(recent.count)
        case .strength:
            let from = Int((cal.date(byAdding: .day, value: -28, to: today) ?? today).timeIntervalSince1970), to = Int(today.timeIntervalSince1970)
            let total = await repo.workoutRows().filter { $0.startTs >= from && $0.startTs < to && NunaWorkoutKind.isStrength($0) }
                .reduce(0.0) { $0 + ($1.durationS ?? Double($1.endTs - $1.startTs)) / 60 }
            return total > 0 ? total / 4 : nil
        case .zonesEasy, .zonesHard:
            let days = (1...28).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
            let minutes = await NunaZoneMinutes.perDay(repo: repo, age: age, days: days)
            let total = minutes.values.reduce(0.0) { sum, zones in sum + kind.zoneIndexes.reduce(0.0) { $0 + zones[$1] } }
            return total > 0 ? total / 4 : nil
        }
    }
}

// MARK: - Pieces

/// A small ring with a figure in it: an arc for the share done, or seven dashes for the days of a week.
private struct NunaPlanRing: View {
    let fraction: Double
    let label: String
    let tint: Color
    var dashed = false

    var body: some View {
        ZStack {
            if dashed {
                Circle().stroke(NunaPalette.ringTrack, style: StrokeStyle(lineWidth: 3, dash: [12.3, 3.4]))
            } else {
                Circle().stroke(NunaPalette.ringTrack, lineWidth: 3)
            }
            Circle().trim(from: 0, to: max(0.01, min(1, fraction))).stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: dashed ? .butt : .round))
                .rotationEffect(.degrees(-90)).opacity(fraction > 0 ? 1 : 0)
            Text(verbatim: label).font(.nuna(size: 11.5, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(width: 40, height: 40)
    }
}

private func nunaPlanBar(_ fraction: Double, tint: Color, height: CGFloat = 7) -> some View {
    GeometryReader { geo in
        ZStack(alignment: .leading) {
            Capsule().fill(NunaPalette.ringTrack)
            Capsule().fill(tint).frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
        }
    }
    .frame(height: height)
}

private func nunaPlanRing(_ item: NunaPlanModel.Item) -> NunaPlanRing {
    if item.kind == .steps { return NunaPlanRing(fraction: item.fraction, label: "\(item.hitDays)/7", tint: NunaPalette.charge, dashed: true) }
    if item.kind.isPercent { return NunaPlanRing(fraction: item.fraction, label: "\(Int(item.value.rounded()))%", tint: NunaPalette.charge) }
    return NunaPlanRing(fraction: item.fraction, label: NunaPlanFormat.clock(item.value), tint: NunaPalette.charge)
}

// MARK: - Today

/// "My Plan" on Today: the week's goals and how far each has come. Draws nothing until a goal has been set.
struct NunaPlanCard: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @StateObject private var model = NunaPlanModel()
    /// Whether the card is open. It lives in view state so folding it touches nothing else: writing a default straight away runs every
    /// listener on the whole app (journal reminders, motion policy, audio coaching) in the middle of the animation. It is saved when the card
    /// leaves the screen or the app goes to the background.
    @State private var expanded: Bool
    @Environment(\.scenePhase) private var scenePhase
    private static let expandedKey = "nuna.plan.expanded"
    init() { _expanded = State(initialValue: UserDefaults.standard.object(forKey: Self.expandedKey) as? Bool ?? true) }
    @AppStorage(NunaGoals.steps) private var steps = 0
    @AppStorage(NunaGoals.zonesEasyMinutes) private var easy = 0
    @AppStorage(NunaGoals.zonesHardMinutes) private var hard = 0
    @AppStorage(NunaGoals.strengthMinutes) private var strength = 0
    @AppStorage(NunaPlanStore.key) private var planRaw = ""

    private var anySet: Bool { NunaPlanStore.hasPlan(NunaPlanStore.load(planRaw)) }

    var body: some View {
        if anySet {
            VStack(alignment: .leading, spacing: 10) {
                Text("My Plan").font(.nuna(size: 19.5, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    .padding(.horizontal, 4)
                NunaCard {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if expanded {
                          VStack(alignment: .leading, spacing: 16) {
                            ForEach(model.items) { item in
                                planRow(item.kind.rowTitle, ring: nunaPlanRing(item))
                            }
                            ForEach(model.behaviors) { b in
                                planRow(b.title, ring: NunaPlanRing(fraction: b.fraction, label: "\(min(b.done, b.goal))/\(b.goal)", tint: NunaPalette.charge, dashed: true))
                            }
                            if !model.activities.isEmpty {
                                Rectangle().fill(NunaPalette.hairline).frame(height: 1)
                                ForEach(model.activities) { a in
                                    planRow(a.title, done: a.complete, ring: NunaPlanRing(fraction: a.fraction, label: "\(min(a.done, a.goal))/\(a.goal)", tint: NunaPalette.charge))
                                }
                            }
                            NavigationLink(value: NunaTodayRoute.plan) {
                                Text("View my plan").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                    .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 42)
                                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                            }
                            .buttonStyle(.plain)
                          }
                          .transition(.opacity)
                        }
                    }
                }
            }
            .onDisappear(perform: saveExpanded)
            .onChange(of: scenePhase) { _, phase in if phase != .active { saveExpanded() } }
            .task(id: "\(steps)-\(easy)-\(hard)-\(strength)-\(planRaw)-\(repo.refreshSeq)") { await model.load(repo: repo, age: profile.age, weekOffset: 0) }
        }
    }

    private func saveExpanded() { UserDefaults.standard.set(expanded, forKey: Self.expandedKey) }

    /// One goal of the plan: its words and its ring. A finished activity is set in green.
    private func planRow(_ title: String, done: Bool = false, ring: NunaPlanRing) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: title).font(.nuna(size: 15, weight: .semibold)).tracking(0).foregroundStyle(done ? NunaPalette.charge : NunaPalette.textPrimary)
                .textCase(nil).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            ring
        }
    }

    /// The compact card: its whole top is the button that folds the card, so there is no small target to miss.
    private var header: some View {
        Button { withAnimation(.smooth(duration: 0.25)) { expanded.toggle() } } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: NunaPlanStore.displayName(model.spec)).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        if let left = model.daysLeft {
                            Text(verbatim: left == 1 ? String(localized: "1 day left") : String(localized: "\(left) days left"))
                                .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.up").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .rotationEffect(.degrees(expanded ? 0 : 180))
                        .frame(width: 44, height: 28, alignment: .trailing)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(Int((model.accomplished * 100).rounded()))").font(.nuna(size: 18, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: "%").font(.nuna(size: 11.5, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    Text("Accomplished").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).padding(.leading, 2)
                }
                nunaPlanBar(model.accomplished, tint: NunaPalette.charge)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: NunaPlanStore.displayName(model.spec)))
        .accessibilityValue(Text(expanded ? "Expanded" : "Collapsed"))
        .accessibilityHint(Text(expanded ? "Collapses the plan" : "Expands the plan"))
    }
}

// MARK: - Plan overview

struct NunaPlanOverviewView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @StateObject private var model = NunaPlanModel()
    @State private var week = 0
    @State private var editing: NunaPlanKind?
    /// The plan editor, open over this page: from the Current plan row (the list of plans) or from an Edit beside behaviors and activities (the details).
    @State private var editor: Editor?
    /// A sleep score goal being changed: a plain number sheet, since these have no target screen of their own.
    @State private var percentEditing: NunaPlanKind?
    @AppStorage(NunaGoals.steps) private var steps = 0
    @AppStorage(NunaGoals.zonesEasyMinutes) private var easy = 0
    @AppStorage(NunaGoals.zonesHardMinutes) private var hard = 0
    @AppStorage(NunaGoals.strengthMinutes) private var strength = 0
    @AppStorage(NunaPlanStore.key) private var planRaw = ""

    private enum Editor: Identifiable { case list, details; var id: Int { self == .list ? 0 : 1 } }

    private var weekLabel: String {
        guard let first = model.weekDays.first, let last = model.weekDays.last else { return "" }
        let a = DateFormatter(); a.locale = AppLanguage.activeLocale; a.setLocalizedDateFormatFromTemplate("MMM d")
        let b = DateFormatter(); b.locale = AppLanguage.activeLocale; b.setLocalizedDateFormatFromTemplate("MMM d, yy")
        return "\(a.string(from: first)) – \(b.string(from: last))"
    }

    var body: some View {
        NunaDetailScreen("Plan overview", centersTitle: true) {
            HStack {
                Spacer(minLength: 0)
                NunaDateStepper(label: weekLabel, canGoBack: week < 52, canGoForward: week > 0, back: { week += 1 }, forward: { week = max(0, week - 1) })
                Spacer(minLength: 0)
            }
            currentPlan
            progress
            ForEach(model.items) { item in section(item) }
            if !model.behaviors.isEmpty { listSection(String(localized: "Behaviors"), rows: model.behaviors.map { ($0.id, $0.title, $0.done, $0.goal, false) }) }
            if !model.activities.isEmpty { listSection(String(localized: "Activities"), rows: model.activities.map { ($0.id, $0.title, $0.done, $0.goal, $0.complete) }) }
        }
        .environment(\.nunaDetailSwitch, nil)
        .task(id: "\(week)-\(steps)-\(easy)-\(hard)-\(strength)-\(planRaw)-\(repo.refreshSeq)") { await model.load(repo: repo, age: profile.age, weekOffset: week) }
        .sheet(item: $percentEditing) { kind in
            NunaNumberSheet(title: LocalizedStringKey(kind.editTitle), unit: "%", initial: Double(max(kind.goal, 1)), range: kind.targetRange, step: kind.targetStep, decimals: 0) {
                UserDefaults.standard.set(Int($0), forKey: kind.storageKey)
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(item: $editor) { which in
            NunaPlanEditFlow(opensDetails: which == .details) { editor = nil }
        }
        .fullScreenCover(item: $editing) { kind in
            if let weekly = kind.weekly {
                NunaWeeklyTargetView(target: weekly, fourWeekAverage: { await NunaPlanModel.fourWeekAverage(kind, repo: repo, age: profile.age) }, onClose: { editing = nil })
            } else {
                NunaStepsTargetView { editing = nil }
            }
        }
    }

    private var currentPlan: some View {
        Button { editor = .list } label: {
            NunaCard(small: true) {
                HStack(spacing: 14) {
                    Image(systemName: "square.and.pencil").font(.nuna(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current plan").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: NunaPlanStore.shortName(model.spec)).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).tracking(0)
                    }
                    Spacer()
                    Image(systemName: "pencil").font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                }
                .padding(.vertical, 2)
            }
        }
        .buttonStyle(.plain)
    }

    /// Behaviors or activities: one card, a row for each with the days done out of the days asked.
    private func listSection(_ name: String, rows: [(id: String, title: String, done: Int, goal: Int, complete: Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: name).font(.nuna(size: 19.5, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).tracking(0)
                Spacer(minLength: 8)
                Button { editor = .details } label: {
                    HStack(spacing: 8) {
                        Text("Edit").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        Image(systemName: "pencil").font(.nuna(size: 15, weight: .regular))
                    }
                    .foregroundStyle(NunaPalette.textPrimary).frame(height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4).padding(.top, 10)
            NunaCard {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(rows, id: \.id) { r in
                        HStack(spacing: 12) {
                            Text(verbatim: r.title).font(.nuna(size: 15, weight: .semibold)).tracking(0).textCase(nil)
                                .foregroundStyle(r.complete ? NunaPalette.charge : NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            NunaPlanRing(fraction: r.goal > 0 ? min(1, Double(r.done) / Double(r.goal)) : 0, label: "\(min(r.done, r.goal))/\(r.goal)", tint: NunaPalette.charge, dashed: name == String(localized: "Behaviors"))
                        }
                    }
                }
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Progress").font(.nuna(size: 23, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).tracking(0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: "\(Int((model.accomplished * 100).rounded()))").font(.nuna(size: 18, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: "%").font(.nuna(size: 11.5, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text("Goals accomplished").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).padding(.leading, 2)
            }
            nunaPlanBar(model.accomplished, tint: NunaPalette.charge)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2).padding(.top, 8)
    }

    private func section(_ item: NunaPlanModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: item.kind.sectionTitle).font(.nuna(size: 19.5, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).tracking(0)
                Spacer(minLength: 8)
                Button { if item.kind.isPercent { percentEditing = item.kind } else { editing = item.kind } } label: {
                    HStack(spacing: 8) {
                        Text("Edit").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        Image(systemName: "pencil").font(.nuna(size: 15, weight: .regular))
                    }
                    .foregroundStyle(NunaPalette.textPrimary).frame(height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4).padding(.top, 10)
            if item.kind == .steps { stepsCard(item) } else if item.kind.isPercent { percentCard(item) } else { timeCard(item) }
        }
    }

    // MARK: Steps

    private func stepsCard(_ item: NunaPlanModel.Item) -> some View {
        let days = model.weekDays
        let today = Calendar.current.startOfDay(for: Date())
        let top = max(item.goal * 1.12, (item.perDay.max() ?? 0) * 1.1, 1)
        let elapsed = zip(days, item.perDay).filter { $0.0 <= today }.map(\.1)
        let average = elapsed.isEmpty ? 0 : elapsed.reduce(0, +) / Double(elapsed.count)
        let barArea: CGFloat = 190
        return NunaCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(verbatim: item.kind.cardLabel).font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    nunaPlanRing(item)
                }
                ZStack(alignment: .top) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                            let isToday = Calendar.current.isDate(day, inSameDayAs: today)
                            VStack(spacing: 10) {
                                Text(verbatim: weekday(day)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                dayMark(item.perDay[i] >= item.goal, past: day <= today)
                                ZStack(alignment: .bottom) {
                                    Color.clear.frame(height: barArea)
                                    VStack(spacing: 4) {
                                        if item.perDay[i] > 0 {
                                            Text(verbatim: nunaThousands(item.perDay[i])).font(.nuna(size: 11, weight: .heavy, design: NunaType.design)).foregroundStyle(item.kind.tint)
                                                .fixedSize().textCase(nil)
                                        }
                                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(item.kind.tint.opacity(0.75))
                                            .frame(width: 16, height: max(item.perDay[i] > 0 ? 3 : 0, barArea * 0.9 * CGFloat(item.perDay[i] / top)))
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isToday ? NunaPalette.glassStrong : Color.clear))
                        }
                    }
                    // The goal line, across the bars.
                    GeometryReader { geo in
                        let y = 10 + 15 + 10 + 28 + 10 + barArea - barArea * 0.9 * CGFloat(item.goal / top) - 0
                        ZStack(alignment: .topLeading) {
                            Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                                .stroke(NunaPalette.textPrimary, style: StrokeStyle(lineWidth: 1.3, dash: [4, 4]))
                            Text("Goal").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.canvas)
                                .padding(.horizontal, 10).padding(.vertical, 5).background(NunaPalette.textPrimary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .position(x: geo.size.width - 26, y: y)
                        }
                    }
                    .allowsHitTesting(false)
                }
                Text(verbatim: average > 0
                     ? String(localized: "Get \(nunaThousands(item.goal)) steps each day to complete your goal. Your average for this week is \(nunaThousands(average)).")
                     : String(localized: "Get \(nunaThousands(item.goal)) steps each day to complete your goal."))
                    .font(.nunaWords(size: 13)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(2).textCase(nil).fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(NunaPalette.hairline).frame(height: 1)
                taken(item.value)
            }
        }
    }

    private func dayMark(_ hit: Bool, past: Bool) -> some View {
        ZStack {
            Circle().stroke(hit ? NunaPalette.charge : NunaPalette.textMuted.opacity(0.7), lineWidth: 2)
            if hit {
                Circle().fill(NunaPalette.charge.opacity(0.18))
                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.charge)
            } else if past {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
        .frame(width: 28, height: 28)
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE"); return f.string(from: d)
    }

    /// Steps in the week against walks people know: a 5K is about 7,850 steps.
    private static let milestones: [(name: String, steps: Double)] = [
        ("5K", 7_850), ("10K", 15_700), ("10 miler", 25_300), ("Half marathon", 33_100), ("Marathon", 66_200),
    ]

    private func taken(_ total: Double) -> some View {
        let passed = Self.milestones.last { $0.steps <= total }
        let next = Self.milestones.first { $0.steps > total }
        let lower = passed?.steps ?? 0, upper = next?.steps ?? lower
        let share = next == nil ? 1 : (total - lower) / max(1, upper - lower)
        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: String(localized: "Steps Taken This Week: \(nunaThousands(total))")).font(.nuna(size: 15, weight: .semibold)).tracking(0).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Text(verbatim: passed.map { String(localized: "That's further than a \($0.name.lowercased()), which is about \(nunaThousands($0.steps)) steps. Keep it up.") }
                 ?? String(localized: "A 5K is about \(nunaThousands(Self.milestones[0].steps)) steps. Keep going."))
                .font(.nunaWords(size: 12)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(verbatim: passed?.name ?? "0").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Spacer()
                if let next { Text(verbatim: next.name).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary) }
            }
            .padding(.top, 6)
            nunaPlanBar(share, tint: NunaPlanKind.steps.tint, height: 9)
        }
    }

    // MARK: Sleep scores

    /// A sleep score goal: the week's average against the target.
    private func percentCard(_ item: NunaPlanModel.Item) -> some View {
        let reached = item.value >= item.goal
        return NunaCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(verbatim: item.kind.cardLabel).font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    nunaPlanRing(item)
                }
                HStack {
                    Text(verbatim: item.value > 0 ? "\(Int(item.value.rounded()))%" : "–").font(.nuna(size: 18, weight: .semibold, design: NunaType.design)).foregroundStyle(item.kind.tint)
                    Spacer()
                    Text(verbatim: "\(Int(item.goal))%").font(.nuna(size: 18, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }
                nunaPlanBar(item.fraction, tint: item.kind.tint, height: 8)
                Text(verbatim: item.value <= 0 ? String(localized: "Wear your strap to bed to track this.")
                     : (reached ? String(localized: "You hit your goal this week. Anything more is a bonus.")
                        : String(localized: "Your average this week is \(Int(item.value.rounded()))%. Aim for \(Int(item.goal))% or more.")))
                    .font(.nunaWords(size: 13)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(2).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Time

    private func timeCard(_ item: NunaPlanModel.Item) -> some View {
        let remaining = item.goal - item.value
        return NunaCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(verbatim: item.kind.cardLabel).font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    nunaPlanRing(item)
                }
                HStack {
                    Text(verbatim: NunaPlanFormat.clockSeconds(item.value)).font(.nuna(size: 18, weight: .semibold, design: NunaType.design)).foregroundStyle(item.kind.tint)
                    Spacer()
                    Text(verbatim: NunaPlanFormat.clockSeconds(item.goal)).font(.nuna(size: 18, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }
                nunaPlanBar(item.fraction, tint: item.kind.tint, height: 8)
                ForEach(item.lines) { line in
                    HStack(spacing: 12) {
                        Text(verbatim: NunaPlanFormat.clockSeconds(line.minutes)).font(.nuna(size: 15, weight: .semibold, design: NunaType.design)).foregroundStyle(item.kind.tint)
                        Group {
                            if let sport = line.sport { NunaActivityGlyph(name: sport, size: 22) } else { NunaGlyph("figure.walk", pointSize: 18).frame(width: 22, height: 22) }
                        }
                        .foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: line.name).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                Text(verbatim: hint(item, remaining: remaining))
                    .font(.nunaWords(size: 13)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(2).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func hint(_ item: NunaPlanModel.Item, remaining: Double) -> String {
        if remaining <= 0 { return String(localized: "You hit your goal this week. Anything more is a bonus.") }
        if week > 0 { return String(localized: "You reached \(Int((item.fraction * 100).rounded()))% of your goal this week.") }
        let more = NunaPlanFormat.spoken(remaining)
        switch item.kind {
        case .zonesEasy: return String(localized: "Get \(more) more of zone 1–3 time this week to hit your goal.")
        case .zonesHard: return String(localized: "Get \(more) more of zone 4–5 time this week to hit your goal.")
        default: return String(localized: "Get \(more) more of strength activity time this week to hit your goal.")
        }
    }
}
#endif
