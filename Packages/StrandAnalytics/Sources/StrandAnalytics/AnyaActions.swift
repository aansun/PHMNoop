import Foundation

// AnyaActions.swift — what Anya can hand back besides prose: a chart, a gym program, a workout.
//
// PURE and unit-tested. The provider is told (see `instruction`) to put each such item in a fenced block tagged
// `anya-chart`, `anya-program` or `anya-workout` holding a small JSON object. The app parses them out of the reply and draws
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

public enum AnyaBlock: Equatable, Sendable {
    case text(String)
    case chart(AnyaChartSpec)
    case program(AnyaProgramSpec)
    case workout(AnyaWorkoutSpec)
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
    Up to 7 days and 12 exercises a day; sets 1 to 10; reps 1 to 100; restSec 0 to 600; the app lets the person save each day as a program.
    ```anya-workout
    {"title":"Easy zone 2 run","sport":"Running","minutes":40,"zone":2}
    ```
    minutes 5 to 240; zone 1 to 5 (optional); sport optional. The app offers a Start button. \
    Keep the prose short and put the details in the block.
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
            default: break
            }
        }
        flush(rest)
        return out
    }

    /// The reply with every action block removed: what to copy, share, save to the journal or show where cards are not drawn.
    public static func proseOnly(_ reply: String) -> String {
        parse(reply).compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined(separator: "\n\n")
    }
}
