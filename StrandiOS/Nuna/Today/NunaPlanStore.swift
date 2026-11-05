#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// A behavior the plan asks for on some days of the week. It is a journal question, so a yes (or, when avoiding it, a no) logged in the journal counts.
struct NunaPlanBehavior: Codable, Identifiable, Equatable {
    /// The journal question, verbatim: the key the journal stores its answers under.
    var id: String
    var title: String
    var subtitle: String
    var days: Int
    /// The goal is to NOT do it: a day counts when the journal says no.
    var avoid = false
}

/// An activity the plan asks for on some days of the week: any strain, strength or recovery activity, or one sport by name.
struct NunaPlanActivity: Codable, Identifiable, Equatable {
    /// "generic:strain", "generic:strength", "generic:recovery", or "sport:<name>".
    var id: String
    var title: String
    var days: Int

    static let strain = "generic:strain", strength = "generic:strength", recovery = "generic:recovery"
    var sportName: String? { id.hasPrefix("sport:") ? String(id.dropFirst(6)) : nil }

    static func generic(_ id: String) -> NunaPlanActivity {
        let title: String
        switch id {
        case strain: title = String(localized: "Any Strain Activity")
        case strength: title = String(localized: "Any Strength Training Activity")
        default: title = String(localized: "Any Recovery Activity")
        }
        return NunaPlanActivity(id: id, title: title, days: 1)
    }
    static func sport(_ name: String) -> NunaPlanActivity { NunaPlanActivity(id: "sport:" + name, title: name, days: 1) }
}

/// The plan as stored: its template (nil for a custom plan), the order its metric goals were chosen in, and its behaviors and activities. The metric goals
/// themselves stay in `NunaGoals`, where the target screens, the widgets and the trend pages already read them.
struct NunaPlanSpec: Codable, Equatable {
    var template: String?
    var order: [String] = []
    var behaviors: [NunaPlanBehavior] = []
    var activities: [NunaPlanActivity] = []
}

/// The ready-made plans. Each is a starting point the wearer can edit before starting it.
enum NunaPlanTemplate: String, CaseIterable, Identifiable {
    case boostFitness, feelBetter, sleepDeeper
    var id: String { rawValue }

    var name: String {
        switch self {
        case .boostFitness: return String(localized: "Boost Fitness")
        case .feelBetter: return String(localized: "Feel Better")
        case .sleepDeeper: return String(localized: "Sleep Deeper")
        }
    }
    var blurb: String {
        switch self {
        case .boostFitness: return String(localized: "Improve fitness with high-intensity training, tracking your protein, and recovering like a pro.")
        case .feelBetter: return String(localized: "Feel your best by moving more, focusing on recovery activities, and staying hydrated.")
        case .sleepDeeper: return String(localized: "Turn great nights into a habit. Build a calming nightly routine and stick to a consistent bedtime.")
        }
    }
    var symbol: String {
        switch self { case .boostFitness: return "met:heart-rate-zones-4-5"; case .feelBetter: return "face.smiling"; case .sleepDeeper: return "moon" }
    }
    var accent: Color {
        switch self { case .boostFitness: return Color(hex: "#F26B2D"); case .feelBetter: return Color(hex: "#4FBF9A"); case .sleepDeeper: return Color(hex: "#8FA8C4") }
    }
    var wash: Color {
        switch self { case .boostFitness: return Color(hex: "#4A2112"); case .feelBetter: return Color(hex: "#133B2E"); case .sleepDeeper: return Color(hex: "#1C2A3B") }
    }

    var metrics: [NunaPlanKind] {
        switch self { case .boostFitness: return [.zonesHard]; case .feelBetter: return [.steps]; case .sleepDeeper: return [.sleepConsistency, .sleepPerformance] }
    }
    var behaviors: [NunaPlanBehavior] {
        switch self {
        case .boostFitness: return [NunaPlanBehavior.protein(days: 4)]
        case .feelBetter: return [NunaPlanBehavior.hydration(days: 4)]
        case .sleepDeeper: return [NunaPlanBehavior.lateMeal(days: 3)]
        }
    }
    var activities: [NunaPlanActivity] {
        switch self {
        case .boostFitness: return [NunaPlanActivity(id: NunaPlanActivity.strength, title: NunaPlanActivity.generic(NunaPlanActivity.strength).title, days: 1)]
        case .feelBetter: return [NunaPlanActivity(id: NunaPlanActivity.recovery, title: NunaPlanActivity.generic(NunaPlanActivity.recovery).title, days: 3)]
        case .sleepDeeper: return []
        }
    }
}

extension NunaPlanBehavior {
    /// Protein is not a starter journal question, so the plan adds it (as "Protein") the first time it is started.
    static let proteinQuestion = "Did you consume protein?"
    static func protein(days: Int) -> NunaPlanBehavior {
        NunaPlanBehavior(id: proteinQuestion, title: String(localized: "Protein"), subtitle: String(localized: "Consumed protein?"), days: days)
    }

    /// Hydration is not a starter journal question either; it is added as "Hydration".
    static let hydrationQuestion = "Did you stay hydrated?"
    static func hydration(days: Int) -> NunaPlanBehavior {
        NunaPlanBehavior(id: hydrationQuestion, title: String(localized: "Hydration"), subtitle: String(localized: "Stayed hydrated?"), days: days)
    }
    /// A starter journal question, goes by "Late meal" in the plan, and the goal is to avoid it.
    static let lateMealQuestion = "Did you eat close to bedtime?"
    static func lateMeal(days: Int) -> NunaPlanBehavior {
        NunaPlanBehavior(id: lateMealQuestion, title: String(localized: "Late meal"), subtitle: String(localized: "Ate close to bedtime?"), days: days, avoid: true)
    }

    /// "Did you drink any alcohol?" → "Drink any alcohol": the short name a question goes by in the plan.
    static func shortTitle(_ question: String) -> String {
        var t = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix("?") { t.removeLast() }
        for prefix in ["Did you ", "Have you ", "Were you ", "Do you "] where t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)); break }
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}

enum NunaPlanStore {
    static let key = "nuna.plan.v1"

    static func load(_ raw: String? = nil) -> NunaPlanSpec {
        let s = raw ?? UserDefaults.standard.string(forKey: key) ?? ""
        return (try? JSONDecoder().decode(NunaPlanSpec.self, from: Data(s.utf8))) ?? NunaPlanSpec()
    }

    static func save(_ spec: NunaPlanSpec) {
        let s = (try? JSONEncoder().encode(spec)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        UserDefaults.standard.set(s, forKey: key)
    }

    static func template(_ spec: NunaPlanSpec) -> NunaPlanTemplate? { spec.template.flatMap(NunaPlanTemplate.init(rawValue:)) }

    /// "Boost Fitness Plan" or "Custom Plan": the line above the plan on Today.
    static func displayName(_ spec: NunaPlanSpec) -> String {
        template(spec).map { String(localized: "\($0.name) Plan") } ?? String(localized: "Custom Plan")
    }

    /// The name on the Current plan row.
    static func shortName(_ spec: NunaPlanSpec) -> String { template(spec)?.name ?? String(localized: "Custom") }

    /// Whether anything is planned: a metric goal, a behavior or an activity.
    static func hasPlan(_ spec: NunaPlanSpec) -> Bool {
        NunaPlanKind.allCases.contains(where: \.isSet) || !spec.behaviors.isEmpty || !spec.activities.isEmpty
    }

    /// The metric goals in the order the plan lists them.
    static func orderedKinds(_ spec: NunaPlanSpec) -> [NunaPlanKind] {
        let chosen = spec.order.compactMap(NunaPlanKind.init(rawValue:))
        return (chosen + NunaPlanKind.allCases.filter { !chosen.contains($0) }).filter(\.isSet)
    }
}

// MARK: - Metric goals, as the plan editor shows them

enum NunaPlanBand {
    case poor, sufficient, optimal
    var color: Color {
        switch self {
        case .poor: return Color(hex: "#F5A623")
        case .sufficient: return NunaPalette.textSecondary
        case .optimal: return NunaPalette.charge
        }
    }
    var index: Int { self == .poor ? 0 : (self == .sufficient ? 1 : 2) }
}

extension NunaPlanKind {
    var isTime: Bool { self == .zonesEasy || self == .zonesHard || self == .strength }
    /// A sleep score in percent: the week's average against the target.
    var isPercent: Bool { self == .sleepConsistency || self == .sleepPerformance }
    var editTitle: String {
        switch self {
        case .steps: return String(localized: "Daily Steps")
        case .zonesEasy: return String(localized: "Heart Rate Zones 1-3")
        case .zonesHard: return String(localized: "Heart Rate Zones 4-5")
        case .strength: return String(localized: "Strength Activity Time")
        case .sleepConsistency: return String(localized: "Sleep Consistency")
        case .sleepPerformance: return String(localized: "Sleep Performance")
        }
    }
    var editIcon: String {
        switch self {
        case .steps: return "met:steps"
        case .zonesEasy: return "met:heart-rate-zones-1-3"
        case .zonesHard: return "met:heart-rate-zones-4-5"
        case .strength: return "act:strength-trainer"
        case .sleepConsistency: return "met:sleep-consistency"
        case .sleepPerformance: return "met:sleep-performance"
        }
    }
    var averageLabel: String { self == .steps || isPercent ? String(localized: "30-day avg.") : String(localized: "4-week avg.") }
    var unit: String { self == .steps ? String(localized: "steps") : (isPercent ? "%" : String(localized: "min")) }
    /// What the target stepper moves through.
    var targetRange: ClosedRange<Double> {
        switch self {
        case .steps: return 1_000...30_000
        case .zonesEasy: return 10...300
        case .zonesHard: return 1...60
        case .strength: return 10...720
        case .sleepConsistency, .sleepPerformance: return 40...100
        }
    }
    var targetStep: Double { self == .steps ? 500 : (self == .zonesHard || isPercent ? 1 : 5) }
    /// How much a week's target moves up from the average.
    var increment: Double {
        switch self { case .steps: return 500; case .zonesEasy: return 10; case .zonesHard: return 1; case .strength: return 15; case .sleepConsistency, .sleepPerformance: return 5 }
    }

    /// Poor, sufficient or optimal for an average (steps a day, or minutes a week).
    func band(_ average: Double) -> NunaPlanBand {
        let (poor, good): (Double, Double)
        switch self {
        case .steps: (poor, good) = (7_000, 10_000)
        case .zonesEasy: (poor, good) = (75, 150)
        case .zonesHard: (poor, good) = (10, 20)
        case .strength: (poor, good) = (45, 90)
        case .sleepConsistency: (poor, good) = (60, 80)
        case .sleepPerformance: (poor, good) = (70, 85)
        }
        return average < poor ? .poor : (average < good ? .sufficient : .optimal)
    }

    func averageText(_ v: Double) -> String { self == .steps ? nunaThousands(v) : (isPercent ? "\(Int(v.rounded()))%" : NunaPlanFormat.clock(v)) }
    /// "6,700", "50 min", "1:30 hrs".
    func targetText(_ v: Int) -> String {
        if self == .steps { return nunaThousands(Double(v)) }
        if isPercent { return "\(v)%" }
        return v >= 60 ? String(format: "%d:%02d hrs", v / 60, v % 60) : "\(v) min"
    }
    /// The line of a value row: "6,200 steps", "0:41 hours".
    func valueText(_ v: Double) -> String { isPercent ? averageText(v) : self == .steps ? "\(nunaThousands(v)) " + String(localized: "steps") : NunaPlanFormat.clock(v) + " " + String(localized: "hours") }

    /// A week's target a step above the average, rounded to what the stepper moves in.
    func suggested(average: Double?) -> Int {
        let raw = (isPercent ? (average ?? 0).rounded() : (average ?? 0)) + increment
        let stepped = (raw / targetStep).rounded(.up) * targetStep
        return Int(min(max(stepped, targetRange.lowerBound), targetRange.upperBound))
    }

    var recommendation: String? {
        switch self {
        case .steps:
            return String(localized: "We recommend increasing by 500 steps each week until your average is in the optimal range of 10,000 steps or more.")
        case .strength:
            return String(localized: "We recommend increasing by 0:15 hours each week until your average is in the optimal range of 1:30 hours or more.")
        default: return nil
        }
    }
}
#endif
