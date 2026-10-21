import Foundation

// AnyaActions.swift — what Anya can hand back besides prose: a chart, a gym program, a workout, lab results, meals and a nutrition plan to review.
//
// PURE and unit-tested. The provider is told (see `instruction`) to put each such item in a fenced block tagged
// `anya-chart`, `anya-program`, `anya-workout`, `anya-lab`, `anya-food` or `anya-plan` holding a small JSON object. The app parses them out of the reply and draws
// native cards. A chart names a metric and a window, never numbers: the app draws it from the readings stored on the phone, so
// a chart can never show a figure the model made up. Everything is clamped to sane ranges; a block that does not parse or fails
// validation falls back to plain text and is never executed.

public struct AnyaChartSpec: Equatable, Sendable {
    public var title: String?
    /// Metric keys from `AnyaActions.chartMetrics`, at most three.
    public var metrics: [String]
    public var days: Int
}

public struct AnyaProgramItem: Equatable, Sendable {
    public var exercise: String
    public var sets: Int?
    public var repsLow: Int?
    public var repsHigh: Int?
    public var restSec: Int?
    public var note: String?
}

public struct AnyaProgramDay: Equatable, Sendable {
    public var title: String
    public var items: [AnyaProgramItem]
}

public struct AnyaProgramSpec: Equatable, Sendable {
    public var name: String
    public var note: String?
    public var days: [AnyaProgramDay]
}

public struct AnyaWorkoutSpec: Equatable, Sendable {
    public var title: String
    public var sport: String?
    public var minutes: Int
    public var zone: Int?
    public var note: String?
}

/// One lab result Anya read out of what the person typed or attached, copied as written: the unit and the range are verbatim, never converted.
public struct AnyaLabResult: Equatable, Sendable {
    public var marker: String
    public var value: Double
    public var unit: String?
    /// `yyyy-MM-dd`, when the source states the day this result was taken.
    public var day: String?
    public var range: String?
    public var note: String?
}

/// One food or drink Anya estimated from what the person described, for the portion they named. Numbers are an estimate, shown as one.
public struct AnyaFoodItem: Equatable, Sendable {
    public var name: String
    /// The portion the estimate is for, in the person's words ("1 plate", "2 eggs"), or what Anya assumed.
    public var amount: String?
    public var kcal: Double
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public init(name: String, amount: String? = nil, kcal: Double, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil) {
        self.name = name; self.amount = amount; self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
    }
}

/// A meal to check before it goes in the diary.
public struct AnyaFoodSpec: Equatable, Sendable {
    /// breakfast | lunch | dinner | snack, when the person said or implied it.
    public var meal: String?
    /// `yyyy-MM-dd`, only when the person named a day.
    public var day: String?
    public var items: [AnyaFoodItem]
    public init(meal: String? = nil, day: String? = nil, items: [AnyaFoodItem]) { self.meal = meal; self.day = day; self.items = items }
}

/// A nutrition plan Anya worked out from the person's own data, for them to read and apply. Every number is clamped here, so a reply can never
/// set a target outside what the app allows.
public struct AnyaPlanSpec: Equatable, Sendable {
    public var targetKcal: Double
    /// Kg of body weight per week, negative to lose.
    public var paceKgPerWeek: Double?
    public var proteinPerKg: Double?
    public var fatShare: Double?
    /// A few sentences on how the plan follows from the person's data, naming the data used and, where relevant, the WHO reference it is measured against.
    public var explanation: String?
    /// Why, one line each, pointing at the data the plan rests on.
    public var reasons: [String]
    /// What to watch or take to a clinician, one line each.
    public var cautions: [String]
}

/// Results for the person to check before anything is saved to the Lab Book. `day` is the day of the whole report, used for a result without its own.
public struct AnyaLabSpec: Equatable, Sendable {
    public var title: String?
    public var day: String?
    public var results: [AnyaLabResult]
}

public enum AnyaBlock: Equatable, Sendable {
    case text(String)
    case chart(AnyaChartSpec)
    case program(AnyaProgramSpec)
    case workout(AnyaWorkoutSpec)
    case lab(AnyaLabSpec)
    case food(AnyaFoodSpec)
    case plan(AnyaPlanSpec)
}

public enum AnyaActions {
    /// The metrics a chart may name (the keys the app stores daily series under).
    public static let chartMetrics: Set<String> = [
        "recovery", "strain", "sleep_performance", "hrv", "rhr", "resp_rate", "spo2", "skin_temp", "stress", "weight", "steps",
    ]

    /// Appended to the system prompt. Written so a model that ignores it still produces a normal answer.
    public static let instruction = """
    ACTIONS: When the person asks you to show a chart or graph, build a gym program, or plan a workout, answer in prose AND add one fenced block for it, \
    exactly as below (valid JSON, no comments). Use a block only when asked; never invent numbers inside a chart block.
    ```anya-chart
    {"title":"HRV, last 14 days","metrics":["hrv"],"days":14}
    ```
    metrics are keys from: recovery (Charge), strain (Effort), sleep_performance (Rest), hrv, rhr, resp_rate, spo2, skin_temp, stress, weight, steps; at most 3; days 7 to 365. \
    The app draws the chart from the person's stored data.
    ```anya-program
    {"name":"Beginner full body","note":"3 days a week","days":[{"title":"Day A","items":[{"exercise":"Goblet squat","sets":3,"repsLow":8,"repsHigh":10,"restSec":90}]}]}
    ```
    Up to 7 days and 12 exercises a day; sets 1 to 10; reps 1 to 100; restSec 0 to 600; the app lets the person save each day as a program. Name each exercise the way a standard exercise library does, in English and in full (for example "Barbell Bench Press - Medium Grip", "Lat Pulldown"), and plan only equipment the person has.
    ```anya-workout
    {"title":"Easy zone 2 run","sport":"Running","minutes":40,"zone":2}
    ```
    minutes 5 to 240; zone 1 to 5 (optional); sport optional. The app offers a Start button. \
    LAB RESULTS: When the person types lab results (a medical check-up, a blood panel, a blood pressure) or attaches a lab report and wants them in their Lab Book, \
    answer with one short line of prose AND one block listing what you read. Copy each name, value, unit and range exactly as the source writes them; never convert a unit, \
    estimate, add or fix a value, and leave out anything you cannot read. Give blood pressure as two results, "Systolic blood pressure" and "Diastolic blood pressure". \
    Do not judge, rate or diagnose any value: the person checks the card and saves it themselves.
    ```anya-lab
    {"day":"2026-10-07","results":[{"marker":"LDL cholesterol","value":3.1,"unit":"mmol/L","range":"<3.4"},{"marker":"Vitamin D","value":68,"unit":"nmol/L","day":"2026-10-07"}]}
    ```
    day is the day the sample was taken, yyyy-MM-dd, when the source says so (leave it out when it does not); up to 60 results; range and note are optional.
    FOOD LOG: When the person says what they ate or drank (in any language) and wants it logged, answer with one short line of prose AND one block with an estimate for each item at the \
    portion they named. Use typical values; for Indonesian and other local dishes use the usual home or street-food serving. If the portion is unclear, assume a typical serving and say so in amount. \
    Say it is an estimate. Do not judge, rate or advise on the food.
    ```anya-food
    {"meal":"lunch","items":[{"name":"Nasi goreng","amount":"1 plate","kcal":520,"proteinG":14,"carbsG":68,"fatG":21},{"name":"Fried egg","amount":"1","kcal":90,"proteinG":6,"carbsG":0,"fatG":7}]}
    ```
    meal is breakfast, lunch, dinner or snack, only when said or clear from the time; day is yyyy-MM-dd, only when the person names one; up to 20 items; kcal is per item as eaten, macros in grams.
    NUTRITION PLAN: When the person asks you to set or adjust their nutrition targets, answer with one short line of prose AND one block, working only from the data above (profile, weight, \
    sleep, recovery, training, food diary and, when shown, the Lab Book values with the ranges from their own reports). Say in reasons which of that data each choice rests on. Never diagnose; \
    when a value is outside its own report range or the data is thin, say so in cautions and suggest talking to their clinician.
    ```anya-plan
    {"targetKcal":2150,"paceKgPerWeek":-0.4,"proteinPerKg":1.8,"fatShare":0.28,"reasons":["Weight 75 kg trending down 0.2 kg a week"],"cautions":["Your ferritin is below its report range; ask your clinician before cutting calories further"]}
    ```
    targetKcal 1200 to 4500, paceKgPerWeek -1 to 0.5, proteinPerKg 0.8 to 2.4, fatShare 0.20 to 0.40; the app lets the person apply it.
    Keep the prose short and put the details in the block.
    """

    /// What Anya is told when the Strategy screen asks her for a plan. The person's data comes before it.
    public static let planInstruction = """
    Work out a daily nutrition plan for this person, using only the data above and the NUTRITION SNAPSHOT below: profile, weight trend, food diary, sleep, recovery, training and, when present, \
    the Lab Book values with the ranges from their own reports. Reply with ONE short line and ONE fenced block, exactly as below, valid JSON, no comments. \
    explanation: 3 to 6 sentences, in plain words, saying how you got to the target, pace and macros: name the actual figures you used (weight, trend, sleep, recovery, training load, intake, any Lab Book value) \
    and, where it helps, measure the choice against these WHO references and no others: healthy adult BMI 18.5 to 24.9; protein safe level 0.83 g per kg a day; total fat 20 to 35 percent of energy; \
    carbohydrate 55 to 75 percent of energy; free sugars under 10 percent of energy; salt under 5 g a day. Say plainly when the person's own situation (training, goal, Lab Book) is why you go beyond a reference. \
    reasons: up to 5 short lines, one per data point used. Never diagnose and never call a value normal or abnormal yourself, only say where it sits against the range on their own report; \
    if a Lab Book value is outside its report range, or the data is thin, say so in cautions (up to 3 short lines) and suggest talking to their clinician. \
    Keep the target at or above 1200 kcal, the pace within -1 to 0.5 kg a week and protein between 0.8 and 2.4 g per kg (a kidney marker outside its range means keeping protein modest); \
    when the person has a goal weight, choose the pace that reaches it in a reasonable time without going past those limits, and when they are already at it, choose maintenance.
    ```anya-plan
    {"targetKcal":2150,"paceKgPerWeek":-0.4,"proteinPerKg":1.8,"fatShare":0.28,"explanation":"...","reasons":["..."],"cautions":["..."]}
    ```
    """

    /// What Anya is told when the person describes a meal inside the Add food sheet: only this, with none of their health data.
    public static let foodInstruction = """
    You estimate calories and macros for a food diary. The person describes what they ate or drank, in any language. Reply with ONE short line (say it is an estimate) \
    and ONE fenced block, exactly as below, valid JSON, no comments. Give each item its own estimate at the portion they named; use typical values, and for Indonesian and other local dishes \
    the usual home or street-food serving. If the portion is unclear, assume a typical serving and say so in amount. meal is breakfast, lunch, dinner or snack only when said or clear; \
    day is yyyy-MM-dd only when named. Up to 20 items. Never judge, rate or advise on the food.
    ```anya-food
    {"meal":"lunch","items":[{"name":"Nasi goreng","amount":"1 plate","kcal":520,"proteinG":14,"carbsG":68,"fatG":21}]}
    ```
    """

    static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }

    static func text(_ any: Any?, max n: Int) -> String? {
        guard let s = (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return String(s.prefix(n))
    }

    static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double, d.isFinite { return Int(d.rounded()) }
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    // MARK: Parsing one block

    static func chart(_ o: [String: Any]) -> AnyaChartSpec? {
        var keys: [String] = []
        let raw = (o["metrics"] as? [Any]) ?? (o["metric"] as? String).map { [$0] } ?? []
        for m in raw {
            guard let k = (m as? String)?.lowercased(), chartMetrics.contains(k), !keys.contains(k) else { continue }
            keys.append(k)
        }
        guard !keys.isEmpty else { return nil }
        return AnyaChartSpec(title: text(o["title"], max: 80), metrics: Array(keys.prefix(3)), days: clamp(int(o["days"]) ?? 14, 7, 365))
    }

    static func program(_ o: [String: Any]) -> AnyaProgramSpec? {
        guard let name = text(o["name"], max: 80) else { return nil }
        var days: [AnyaProgramDay] = []
        for (i, d) in ((o["days"] as? [Any]) ?? []).prefix(7).enumerated() {
            guard let dd = d as? [String: Any] else { continue }
            var items: [AnyaProgramItem] = []
            for it in ((dd["items"] as? [Any]) ?? []).prefix(12) {
                guard let io = it as? [String: Any], let ex = text(io["exercise"], max: 60) else { continue }
                var lo = int(io["repsLow"]).map { clamp($0, 1, 100) }
                var hi = int(io["repsHigh"]).map { clamp($0, 1, 100) }
                if let a = lo, let b = hi, b < a { lo = b; hi = a }
                items.append(AnyaProgramItem(exercise: ex, sets: int(io["sets"]).map { clamp($0, 1, 10) }, repsLow: lo, repsHigh: hi,
                                             restSec: int(io["restSec"]).map { clamp($0, 0, 600) }, note: text(io["note"], max: 120)))
            }
            guard !items.isEmpty else { continue }
            days.append(AnyaProgramDay(title: text(dd["title"], max: 40) ?? "Day \(i + 1)", items: items))
        }
        guard !days.isEmpty else { return nil }
        return AnyaProgramSpec(name: name, note: text(o["note"], max: 200), days: days)
    }

    static func workout(_ o: [String: Any]) -> AnyaWorkoutSpec? {
        guard let title = text(o["title"], max: 80), let minutes = int(o["minutes"]) else { return nil }
        return AnyaWorkoutSpec(title: title, sport: text(o["sport"], max: 40), minutes: clamp(minutes, 5, 240),
                               zone: int(o["zone"]).map { clamp($0, 1, 5) }, note: text(o["note"], max: 200))
    }

    static func double(_ any: Any?) -> Double? {
        if let d = any as? Double, d.isFinite { return d }
        if let i = any as? Int { return Double(i) }
        if let s = (any as? String)?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."), let d = Double(s), d.isFinite { return d }
        return nil
    }

    /// `yyyy-MM-dd` with a real month and day, or nil.
    static func day(_ any: Any?) -> String? {
        guard let s = text(any, max: 10), s.count == 10 else { return nil }
        let p = s.split(separator: "-")
        guard p.count == 3, p[0].count == 4, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), (1900...2100).contains(y), (1...12).contains(m), (1...31).contains(d) else { return nil }
        return s
    }

    /// What a card shows: a long lab file read on the phone, never more than this.
    static let maxLabResults = 200

    static func lab(_ o: [String: Any]) -> AnyaLabSpec? {
        var results: [AnyaLabResult] = []
        for r in ((o["results"] as? [Any]) ?? []).prefix(maxLabResults) {
            guard let ro = r as? [String: Any], let name = text(ro["marker"] ?? ro["name"], max: 60), let v = double(ro["value"]) else { continue }
            results.append(AnyaLabResult(marker: name, value: v, unit: text(ro["unit"], max: 20), day: day(ro["day"]), range: text(ro["range"], max: 60), note: text(ro["note"], max: 200)))
        }
        guard !results.isEmpty else { return nil }
        return AnyaLabSpec(title: text(o["title"], max: 80), day: day(o["day"]), results: results)
    }

    static func food(_ o: [String: Any]) -> AnyaFoodSpec? {
        var items: [AnyaFoodItem] = []
        func grams(_ any: Any?) -> Double? { double(any).flatMap { (0...1000).contains($0) ? $0 : nil } }
        for i in ((o["items"] as? [Any]) ?? []).prefix(20) {
            guard let io = i as? [String: Any], let name = text(io["name"], max: 60), let kcal = double(io["kcal"]), (0...6000).contains(kcal) else { continue }
            items.append(AnyaFoodItem(name: name, amount: text(io["amount"], max: 40), kcal: kcal, proteinG: grams(io["proteinG"]), carbsG: grams(io["carbsG"]), fatG: grams(io["fatG"])))
        }
        guard !items.isEmpty else { return nil }
        let meal = (o["meal"] as? String)?.lowercased()
        return AnyaFoodSpec(meal: ["breakfast", "lunch", "dinner", "snack"].contains(meal ?? "") ? meal : nil, day: day(o["day"]), items: items)
    }

    static func plan(_ o: [String: Any]) -> AnyaPlanSpec? {
        guard let kcal = double(o["targetKcal"]), kcal.isFinite else { return nil }
        func lines(_ any: Any?, _ cap: Int) -> [String] { ((any as? [Any]) ?? []).compactMap { text($0, max: 160) }.prefix(cap).map { $0 } }
        func clampD(_ v: Double?, _ lo: Double, _ hi: Double, step: Double) -> Double? {
            v.map { (((min(max($0, lo), hi)) / step).rounded() * step * 10_000).rounded() / 10_000 }
        }
        return AnyaPlanSpec(targetKcal: min(max(kcal, 1200), 4500).rounded(),
                            paceKgPerWeek: clampD(double(o["paceKgPerWeek"]), -1, 0.5, step: 0.05),
                            proteinPerKg: clampD(double(o["proteinPerKg"]), 0.8, 2.4, step: 0.1),
                            fatShare: clampD(double(o["fatShare"]), 0.20, 0.40, step: 0.01),
                            explanation: text(o["explanation"], max: 900),
                            reasons: lines(o["reasons"], 5), cautions: lines(o["cautions"], 3))
    }

    /// The meal in a reply, tolerant of small models: the `anya-food` block when it is there, else the first JSON object in the text (in a ```json fence or bare)
    /// that carries an `items` list.
    public static func parseFood(from reply: String) -> AnyaFoodSpec? {
        for b in parse(reply) { if case .food(let f) = b { return f } }
        guard let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"), open < close,
              let data = String(reply[open...close]).data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], obj["items"] != nil else { return nil }
        return food(obj)
    }

    // MARK: Parsing a reply

    /// Splits a reply into prose and action blocks, in order. An action fence that is still open (a reply that is streaming) or
    /// does not parse is dropped from the prose when it is open and kept as text when it is closed but invalid.
    public static func parse(_ reply: String) -> [AnyaBlock] {
        var out: [AnyaBlock] = []
        var rest = Substring(reply)
        func flush(_ s: Substring) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(.text(t)) }
        }
        while let open = rest.range(of: "```anya-") {
            flush(rest[rest.startIndex..<open.lowerBound])
            let afterTag = rest[open.upperBound...]
            guard let nl = afterTag.firstIndex(of: "\n") else { rest = ""; break }   // tag line not finished: still streaming
            let kind = afterTag[afterTag.startIndex..<nl].trimmingCharacters(in: .whitespaces).lowercased()
            let body = afterTag[afterTag.index(after: nl)...]
            guard let close = body.range(of: "```") else { rest = ""; break }         // fence still open: hide it
            let json = body[body.startIndex..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            rest = body[close.upperBound...]
            guard let data = json.data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                flush(Substring(json)); continue
            }
            switch kind {
            case "chart": if let c = chart(obj) { out.append(.chart(c)) }
            case "program": if let p = program(obj) { out.append(.program(p)) }
            case "workout": if let w = workout(obj) { out.append(.workout(w)) }
            case "lab": if let l = lab(obj) { out.append(.lab(l)) }
            case "food": if let f = food(obj) { out.append(.food(f)) }
            case "plan": if let p = plan(obj) { out.append(.plan(p)) }
            default: break
            }
        }
        flush(rest)
        return out
    }

    /// The program in a reply, from a fenced block or, for a small model that skipped the fence, from a bare JSON object with `days`.
    public static func parseProgram(from reply: String) -> AnyaProgramSpec? {
        for b in parse(reply) { if case .program(let p) = b { return p } }
        guard let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"), open < close,
              let data = String(reply[open...close]).data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], obj["days"] != nil else { return nil }
        return program(obj)
    }

    /// The reply with every action block removed: what to copy, share, save to the journal or show where cards are not drawn.
    public static func proseOnly(_ reply: String) -> String {
        parse(reply).compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined(separator: "\n\n")
    }
}


// MARK: - Building a gym program from a goal

extension AnyaActions {
    /// The brief for a program built from what the person asked for: goal, days, session length, equipment and their own words. Only a summary
    /// of their training goes with it. The reply is a short explanation and one `anya-program` block, which the app turns into a card to check and save.
    public static let programInstruction = """
    You build ONE gym program for the person from their goal, how many days they train, how long a session may last, the equipment they have, their level and \
    their own instructions, and from the training summary below (what they already do, how much per muscle, how recovered they are). Reply with a short paragraph \
    (about 60 words) saying how the days are split and how to progress, then ONE fenced block exactly like the example, valid JSON, no comments.
    ```anya-program
    {"name":"Upper / lower, 4 days","note":"Add the smallest weight step once every set reaches the top of the rep range","days":[{"title":"Day A: Upper","items":[{"exercise":"Dumbbell Bench Press","sets":3,"repsLow":8,"repsHigh":10,"restSec":120,"note":"Shoulder blades pinched"}]}]}
    ```
    Rules. One day per training day asked for, 7 at most. Fit the session length: count about 3.5 minutes per working set including the rest, so a 45 minute \
    session has 10 to 13 sets in 4 to 6 exercises. Compound lifts first. Name every exercise the way a standard exercise library does, in English and in full \
    ("Barbell Bench Press - Medium Grip", "Lat Pulldown", "Romanian Deadlift", "Dumbbell Lateral Raise"), never a nickname or a brand. Use ONLY equipment the person \
    has. Rep ranges by goal: strength 3 to 6 with 150 to 240 s rest, muscle 6 to 12 with 60 to 120 s, endurance or fat loss 12 to 20 with 30 to 60 s. For muscle, aim at \
    10 to 20 working sets a week for each big muscle, balance push and pull, and do not leave out legs or core unless told. Build on what they already do when it fits, and \
    go easier on a muscle the summary shows is not recovered. Obey their instructions, including movements to avoid. Never invent weights. Put a note only where one short \
    cue helps. If the instructions mention pain, an injury or a medical condition, choose gentle, general movements and say in the paragraph to check with a clinician first. \
    If you cannot make a program from what was given, say what is missing and leave out the block.
    """
}

// MARK: - Classifying an exercise the person made up

/// What Anya worked out about an exercise that is not in the library: which muscles it works, what it is done with and how a set of it is
/// logged. Every word is checked against the library's own names here, so a reply can never invent a muscle.
public struct AnyaExerciseSpec: Equatable, Sendable {
    /// The library's muscle names (free-exercise-db): "chest", "lats", "quadriceps".
    public var primary: [String]
    public var secondary: [String]
    /// barbell, dumbbell, cable, machine, body only, kettlebells, bands or other.
    public var equipment: String?
    /// weighted, bodyweight or timed.
    public var kind: String?
    public init(primary: [String], secondary: [String] = [], equipment: String? = nil, kind: String? = nil) {
        self.primary = primary; self.secondary = secondary; self.equipment = equipment; self.kind = kind
    }
}

extension AnyaActions {
    public static let exerciseMuscles: Set<String> = ["abdominals", "abductors", "adductors", "biceps", "calves", "chest", "forearms", "glutes", "hamstrings",
                                                      "lats", "lower back", "middle back", "neck", "quadriceps", "shoulders", "traps", "triceps"]
    public static let exerciseEquipment: Set<String> = ["barbell", "dumbbell", "cable", "machine", "body only", "kettlebells", "bands", "other"]
    public static let exerciseKinds: Set<String> = ["weighted", "bodyweight", "timed"]

    /// Asks only about the exercise's name; nothing about the person goes with it.
    public static let exerciseInstruction = """
    You classify one gym exercise for a training log. The name may be in any language and may carry a brand or app suffix; ignore that and judge the movement. \
    Reply with ONE fenced block, valid JSON, no comments and no other text. primary is the 1 or 2 muscles that do the work, secondary up to 3 that assist. \
    Use ONLY these muscle names: abdominals, abductors, adductors, biceps, calves, chest, forearms, glutes, hamstrings, lats, lower back, middle back, neck, \
    quadriceps, shoulders, traps, triceps. equipment is one of: barbell, dumbbell, cable, machine, body only, kettlebells, bands, other. \
    kind is weighted when a load is lifted, bodyweight when reps of the body are counted, timed when it is a hold for time. If you are not sure what the movement is, reply {"unknown":true}.
    ```anya-exercise
    {"primary":["chest"],"secondary":["triceps","shoulders"],"equipment":"machine","kind":"weighted"}
    ```
    """

    /// The classification in a reply, from a fenced block or a bare JSON object; nil when the reply says it does not know or names no valid muscle.
    public static func parseExercise(from reply: String) -> AnyaExerciseSpec? {
        guard let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"), open < close,
              let data = String(reply[open...close]).data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], obj["unknown"] as? Bool != true else { return nil }
        func muscles(_ any: Any?) -> [String] {
            let raw = (any as? [Any]) ?? (any as? String).map { [$0] } ?? []
            var out: [String] = []
            for m in raw {
                guard let k = (m as? String)?.trimmingCharacters(in: .whitespaces).lowercased(), exerciseMuscles.contains(k), !out.contains(k) else { continue }
                out.append(k)
            }
            return out
        }
        let primary = Array(muscles(obj["primary"]).prefix(2))
        guard !primary.isEmpty else { return nil }
        let secondary = Array(muscles(obj["secondary"]).filter { !primary.contains($0) }.prefix(3))
        func pick(_ any: Any?, from allowed: Set<String>) -> String? {
            guard let s = (any as? String)?.trimmingCharacters(in: .whitespaces).lowercased(), allowed.contains(s) else { return nil }
            return s
        }
        let equipment = pick(obj["equipment"], from: exerciseEquipment)
        let kind = pick(obj["kind"], from: exerciseKinds)
        return AnyaExerciseSpec(primary: primary, secondary: secondary, equipment: equipment, kind: kind)
    }
}
