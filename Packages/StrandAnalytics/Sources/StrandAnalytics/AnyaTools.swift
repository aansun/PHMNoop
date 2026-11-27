import Foundation

/// What Anya can look up for herself, and the plain arithmetic on what comes back. The app runs the lookups on the phone; only the answer to
/// a lookup goes to the provider, with the same consent as the rest of what she is told. Pure.
public enum AnyaTools {
    public enum Name: String, CaseIterable, Sendable {
        case dailyMetrics = "get_daily_metrics"
        case sleepNights = "get_sleep_nights"
        case workouts = "get_workouts"
        case bodyTrend = "get_body_trend"
        case foodDiary = "get_food_diary"
        case healthLog = "get_health_log"
        case profile = "get_profile"
        /// The one tool that writes: a standing fact the person told her, onto their "About you" page.
        case saveAboutYou = "save_about_you"
    }

    /// The daily figures she can ask for, by the name used in a request.
    public static let metrics = ["recovery", "strain", "sleep_hours", "deep_hours", "rem_hours", "sleep_efficiency", "hrv", "resting_hr",
                                 "respiratory_rate", "spo2", "skin_temp_change", "steps", "active_kcal"]
    public static let bodySeries = ["weight", "body_age", "vo2max"]
    public static let logKinds = ["journal", "blood_pressure", "lab_results"]

    /// The tool definitions in Anthropic's form (name, description, input_schema).
    public static var definitions: [[String: Any]] {
        func tool(_ name: Name, _ description: String, _ properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
            ["name": name.rawValue, "description": description,
             "input_schema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false] as [String: Any]]
        }
        func days(_ standard: Int, _ most: Int) -> [String: Any] {
            ["type": "integer", "description": "How many days back, counting the end date. Default \(standard), at most \(most)."]
        }
        let end: [String: Any] = ["type": "string", "description": "Last day of the range, yyyy-MM-dd. Default today. Use it to look at an earlier period, e.g. to compare two."]
        return [
            tool(.dailyMetrics, "Daily figures from the wearable over any period: trends, comparisons, a particular date, or anything older than the two weeks in the summary.",
                 ["metrics": ["type": "array", "items": ["type": "string", "enum": metrics], "description": "The figures wanted."] as [String: Any],
                  "days": days(30, 730), "end_date": end,
                  "group": ["type": "string", "enum": ["day", "week", "month"], "description": "Averages per week or month. Chosen from the length of the range when left out."] as [String: Any]],
                 required: ["metrics"]),
            tool(.sleepNights, "Each night's bed time, wake time, time asleep, stages, efficiency, heart rate and HRV, and naps.", ["days": days(7, 60), "end_date": end]),
            tool(.workouts, "Recorded workouts with duration, Strain, heart rate, zones, distance and energy.",
                 ["days": days(30, 365), "end_date": end, "sport": ["type": "string", "description": "Only sessions whose name contains this."] as [String: Any]]),
            tool(.bodyTrend, "How body weight, Body age or VO2 max has moved over time.",
                 ["series": ["type": "string", "enum": bodySeries] as [String: Any], "days": days(90, 730)], required: ["series"]),
            tool(.foodDiary, "What the person logged eating and drinking, with energy and protein per day.", ["days": days(7, 60), "end_date": end]),
            tool(.healthLog, "The person's own journal answers, blood pressure readings or lab results. Only available if they share patterns and the Lab Book.",
                 ["kind": ["type": "string", "enum": logKinds] as [String: Any], "days": days(30, 730)], required: ["kind"]),
            tool(.profile, "Age, sex, height, weight, waist, maximum heart rate and the goals the person has set."),
            tool(.saveAboutYou, "Save a lasting fact the person has just told you about themselves to their About you page, which you are given in every conversation.",
                 ["field": ["type": "string", "enum": AnyaAboutYou.Field.allCases.map(\.rawValue)] as [String: Any],
                  "text": ["type": "string", "description": "The fact in their own terms and language, short."] as [String: Any],
                  "replace": ["type": "boolean", "description": "True when it corrects what is there, so the old text is replaced."] as [String: Any]],
                 required: ["field", "text"]),
        ]
    }

    /// What she is told about looking things up. `today` is given because the model does not know the date.
    public static func instruction(today: String) -> String {
        """
        LOOKING THINGS UP: you can fetch the person's own data with the tools. Today is \(today). The summary you are given covers only the last two weeks. \
        When the question reaches further back, names something the summary does not hold (a particular night or session, bed times, food, weight, journal, \
        blood pressure, their age), or asks how something has changed, fetch it instead of saying you do not have it, and do not state a figure you have not \
        seen. Small talk needs no lookup. Do not mention tools or fetching; just answer.

        KEEPING IN MIND: when they tell you something lasting that helps you coach them (a goal, their usual training days, equipment, an injury or limit, \
        how they like to be coached), save it with save_about_you. Save only what they said, never a guess or a passing mood. The app tells them it was saved.
        """
    }

    // MARK: Arguments

    public static func days(_ input: [String: Any], standard: Int, most: Int) -> Int {
        let asked = (input["days"] as? Int) ?? (input["days"] as? Double).map { Int($0) } ?? (input["days"] as? String).flatMap(Int.init) ?? standard
        return min(max(asked, 1), most)
    }

    private static func parser() -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// The first and last day of the asked range as day keys; an end date that is missing, unreadable or in the future means today.
    public static func range(_ input: [String: Any], today: String, standard: Int, most: Int) -> (from: String, to: String, days: Int) {
        let f = parser()
        let asked = (input["end_date"] as? String).flatMap { f.date(from: $0) != nil && $0 <= today ? $0 : nil }
        let to = asked ?? today
        let n = days(input, standard: standard, most: most)
        let from = f.date(from: to).map { f.string(from: $0.addingTimeInterval(-Double(n - 1) * 86_400)) } ?? to
        return (from, to, n)
    }

    // MARK: Tables

    public enum Group: String, Sendable { case day, week, month }

    public static func group(_ input: [String: Any], days: Int) -> Group {
        if let g = (input["group"] as? String).flatMap(Group.init(rawValue:)) { return g }
        return days > 200 ? .month : (days > 45 ? .week : .day)
    }

    /// One row per day with its figures (nil when not measured), written as a table: per day as it is, or averaged per week or month with the
    /// number of days behind each average. A figure with no value shows as a dash; days with nothing at all are left out.
    public static func table(columns: [String], rows: [(day: String, values: [Double?])], group: Group) -> String {
        let measured = rows.filter { $0.values.contains { $0 != nil } }.sorted { $0.day < $1.day }
        guard !measured.isEmpty else { return "No data in this period." }
        let f = parser()
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = TimeZone(identifier: "UTC")!
        func bucket(_ day: String) -> String {
            switch group {
            case .day: return day
            case .month: return String(day.prefix(7))
            case .week:
                guard let d = f.date(from: day), let start = calendar.dateInterval(of: .weekOfYear, for: d)?.start else { return day }
                return "week of " + f.string(from: start)
            }
        }
        var order: [String] = []
        var grouped: [String: [[Double?]]] = [:]
        for r in measured {
            let key = bucket(r.day)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(r.values)
        }
        func number(_ v: Double) -> String { abs(v - v.rounded()) < 0.005 ? String(Int(v.rounded())) : String(format: "%.1f", v) }
        var lines = [(group == .day ? "date" : "period (averages, days measured in brackets)") + " | " + columns.joined(separator: " | ")]
        for key in order {
            let list = grouped[key] ?? []
            let cells = columns.indices.map { i -> String in
                let values = list.compactMap { $0.indices.contains(i) ? $0[i] : nil }
                guard !values.isEmpty else { return "-" }
                let mean = number(values.reduce(0, +) / Double(values.count))
                return group == .day ? mean : "\(mean) (\(values.count))"
            }
            lines.append(key + " | " + cells.joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }

    /// Totals the app counts itself, so the model never has to: sessions and minutes, overall and per sport, most frequent first.
    public static func sessionTotals(_ sessions: [(sport: String, minutes: Double?)]) -> String {
        let minutes = { (list: [(sport: String, minutes: Double?)]) in Int(list.reduce(0) { $0 + ($1.minutes ?? 0) }.rounded()) }
        let bySport = Dictionary(grouping: sessions, by: \.sport)
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .map { "\($0.key) \($0.value.count) (\(minutes($0.value)) min)" }
        return "TOTALS (counted by the app; quote these, do not count the lines): \(sessions.count) sessions, \(minutes(sessions)) min. By sport: " + bySport.joined(separator: ", ") + "."
    }

    /// A lookup's answer is kept within reason; the newest lines are the ones kept.
    public static func capped(_ text: String, limit: Int = 7000) -> String {
        guard text.count > limit else { return text }
        let lines = text.components(separatedBy: "\n")
        let head = lines.prefix { !$0.isEmpty && ($0 == lines.first || $0.hasPrefix("TOTALS")) }
        var kept: [String] = [], size = 0
        for line in lines.dropFirst(head.count).reversed() {
            if size + line.count > limit { break }
            kept.insert(line, at: 0); size += line.count + 1
        }
        return (Array(head) + ["(earlier lines left out; ask for a shorter range or weekly averages)"] + kept).joined(separator: "\n")
    }
}
