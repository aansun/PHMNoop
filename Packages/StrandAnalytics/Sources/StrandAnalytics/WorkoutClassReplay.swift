import Foundation

// WorkoutClassReplay.swift — how well does the shape classifier name the workouts a person has already labelled?
//
// The classifier (`WorkoutTypeClassifier`) has only ever been checked against synthetic fixtures. This file is the missing measurement: give it labelled
// windows (a class the person chose, and the features computed from the strap data of that same window) and it runs a classifier over each and reports
// what came out against what was true. It does not change any behaviour and nothing in the app depends on it.
//
// WHAT IT MEASURES, AND WHAT IT DOES NOT. It measures the NAMING of a window that exists. It says nothing about whether a window should have been offered
// at all: windows the person never logged have no label, and an unlogged workout is not a negative.
//
// Pure and deterministic. The classifier is a parameter, so a future learned classifier is measured by the same code, on the same windows, and the two can be
// compared directly.

/// One window with a class the person chose and the features the classifier sees.
public struct LabelledWorkoutWindow: Equatable, Sendable {
    public let id: String
    public let label: CoarseWorkoutClass
    public let features: WorkoutClassFeatures

    public init(id: String, label: CoarseWorkoutClass, features: WorkoutClassFeatures) {
        self.id = id; self.label = label; self.features = features
    }
}

/// What a classifier did over a set of labelled windows.
public struct WorkoutClassReplayReport: Equatable, Sendable {
    /// The classes in a fixed display order.
    public static let classOrder: [CoarseWorkoutClass] = [.walk, .run, .strength, .cycle, .ski, .other]

    public let total: Int
    /// `confusion[truth][predicted]` = how many windows of class `truth` the classifier called `predicted`.
    public let confusion: [CoarseWorkoutClass: [CoarseWorkoutClass: Int]]
    /// How many windows carry each label.
    public let labelCounts: [CoarseWorkoutClass: Int]
    public let correct: Int
    /// Windows whose true class is one of the five specific classes, and how many of those had the truth among the two best scores.
    public let specificTotal: Int
    public let topTwoHits: Int

    /// Share of all windows named correctly (`.other` truth counts as correct when the classifier said `.other`). nil when there are no windows.
    public var accuracy: Double? { total == 0 ? nil : Double(correct) / Double(total) }

    /// Of the windows that truly are `c`, the share the classifier called `c`. nil when there are none.
    public func recall(_ c: CoarseWorkoutClass) -> Double? {
        let n = labelCounts[c] ?? 0
        guard n > 0 else { return nil }
        return Double(confusion[c]?[c] ?? 0) / Double(n)
    }

    /// Of the windows the classifier called `c`, the share that truly are `c`. nil when it never said `c`.
    public func precision(_ c: CoarseWorkoutClass) -> Double? {
        let said = Self.classOrder.reduce(0) { $0 + (confusion[$1]?[c] ?? 0) }
        guard said > 0 else { return nil }
        return Double(confusion[c]?[c] ?? 0) / Double(said)
    }

    /// A specific sport was the truth and the classifier would not name it (it said `.other`). Not wrong, but not useful either.
    public var abstained: Int {
        Self.classOrder.filter { $0 != .other }.reduce(0) { $0 + (confusion[$1]?[.other] ?? 0) }
    }

    /// The classifier named a specific class that was not the truth. This is the harmful kind of miss.
    public var confidentlyWrong: Int {
        var n = 0
        for truth in Self.classOrder {
            for predicted in Self.classOrder where predicted != .other && predicted != truth { n += confusion[truth]?[predicted] ?? 0 }
        }
        return n
    }

    /// Share of specific-class windows with the truth among the two highest scores. nil when there are none.
    public var topTwoAccuracy: Double? { specificTotal == 0 ? nil : Double(topTwoHits) / Double(specificTotal) }
}

public enum WorkoutClassReplay {

    /// Fewest labelled windows per class below which a class is too thin to learn anything personal from.
    /// A planning figure, not a statistical guarantee: with fewer, one odd session moves a class's profile.
    public static let minLabelsPerClass = 15

    /// Run `classifier` over every window and tally the result.
    public static func evaluate(_ windows: [LabelledWorkoutWindow],
                                classifier: any WorkoutTypeClassifying = HeuristicWorkoutClassifier()) -> WorkoutClassReplayReport {
        var confusion: [CoarseWorkoutClass: [CoarseWorkoutClass: Int]] = [:]
        var labelCounts: [CoarseWorkoutClass: Int] = [:]
        var correct = 0, specificTotal = 0, topTwoHits = 0
        for w in windows {
            let prediction = classifier.classify(w.features)
            confusion[w.label, default: [:]][prediction.predictedClass, default: 0] += 1
            labelCounts[w.label, default: 0] += 1
            if prediction.predictedClass == w.label { correct += 1 }
            if w.label != .other {
                specificTotal += 1
                // Stable order on a tie, so the same input always gives the same report.
                let ranked = prediction.scores.sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }
                if ranked.prefix(2).contains(where: { $0.key == w.label }) { topTwoHits += 1 }
            }
        }
        return WorkoutClassReplayReport(total: windows.count, confusion: confusion, labelCounts: labelCounts, correct: correct,
                                        specificTotal: specificTotal, topTwoHits: topTwoHits)
    }

    /// Which classes have enough labelled windows to learn from, in display order.
    public static func classesReadyToLearn(_ labelCounts: [CoarseWorkoutClass: Int]) -> [CoarseWorkoutClass] {
        WorkoutClassReplayReport.classOrder.filter { $0 != .other && (labelCounts[$0] ?? 0) >= minLabelsPerClass }
    }

    private static func pct(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a" }

    /// The report as plain lines for a diagnostics screen. English on purpose: it is a developer diagnostic, not app copy.
    public static func summaryLines(_ r: WorkoutClassReplayReport) -> [String] {
        guard r.total > 0 else { return ["No labelled windows to check yet."] }
        var lines = [
            "Windows checked: \(r.total)",
            "Named correctly: \(pct(r.accuracy))",
            "Truth among the top two: \(pct(r.topTwoAccuracy)) (specific sports only, \(r.specificTotal) windows)",
            "Left generic on a named sport: \(r.abstained)",
            "Named the wrong sport: \(r.confidentlyWrong)",
        ]
        for c in WorkoutClassReplayReport.classOrder {
            let n = r.labelCounts[c] ?? 0
            guard n > 0 || r.precision(c) != nil else { continue }
            lines.append("\(c.rawValue): \(n) labelled, recall \(pct(r.recall(c))), precision \(pct(r.precision(c)))")
        }
        let ready = classesReadyToLearn(r.labelCounts)
        lines.append(ready.isEmpty
            ? "Enough labels to learn from (\(minLabelsPerClass) or more): none yet"
            : "Enough labels to learn from (\(minLabelsPerClass) or more): " + ready.map(\.rawValue).joined(separator: ", "))
        return lines
    }
}
