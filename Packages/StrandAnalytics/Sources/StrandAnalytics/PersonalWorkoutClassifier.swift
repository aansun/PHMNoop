import Foundation

// PersonalWorkoutClassifier.swift — a small classifier trained on the person's OWN labelled workouts, run in SHADOW MODE.
//
// SHADOW MODE means: it is trained, it predicts, its predictions are written to a local log beside the rule-based classifier's, and the two are compared
// against what the person finally chose. NOTHING reads its output to decide what is offered, shown or scored. It is promoted only by a person's decision,
// after the comparison (leave-one-out below, and the shadow log) shows it beating the rules on their own history. See the learning-prep notes in
// `WorkoutClassReplay`.
//
// THE MODEL is deliberately plain: a diagonal Gaussian naive Bayes over eight shape features. With tens of labelled workouts, anything bigger
// memorises the few it has seen. Each class keeps a mean and a spread per feature; the spread is pulled toward the spread of all windows
// (`shrinkage` pseudo-windows) so a class with a handful of examples is not over-confident; the class prior is how often the person logs it.
//
// WHAT IT TRAINS ON. Only windows with motion behind them (`WorkoutWindowEvidence.full`) and only the five specific classes. A heart-rate-only window
// carries no gait, and a learner taught from it would read a bike, an elliptical and housework as the same thing. A class must have at least
// `minTrainingPerClass` windows to be predicted at all, and the model needs two such classes to say anything.
//
// Pure and deterministic. All time is passed in. NOT medical advice.

/// The trained parameters. Codable so the app can keep them between launches (UserDefaults) without a database change.
public struct PersonalClassifierModel: Codable, Equatable, Sendable {
    public struct ClassStats: Codable, Equatable, Sendable {
        public let n: Int
        public let mean: [Double]
        public let std: [Double]
    }
    /// Unix seconds the model was trained.
    public let trainedAt: Int
    /// Windows it was trained on.
    public let total: Int
    /// Keyed by `CoarseWorkoutClass.rawValue`; only classes with enough windows are here.
    public let classes: [String: ClassStats]
    /// Version of the feature vector, so a model saved by an older layout is dropped, not misread.
    public let featureVersion: Int
}

public enum PersonalClassifierFeatures {
    public static let version = 1
    /// The features, in order: effort (%HRR, 0 to 1), heart-rate variability of the window, the still, walking and running shares of the activity
    /// ticks, the log of the motion variance, the burstiness of the motion, and the log of the duration in minutes.
    public static let names = ["hrr", "hrCV", "still", "walk", "run", "logMotionVariance", "motionCV", "logMinutes"]
    /// The smallest spread worth believing per feature, so two near-identical windows do not make a class that nothing else can ever match.
    static let spreadFloor: [Double] = [0.05, 0.03, 0.05, 0.05, 0.05, 0.4, 0.15, 0.2]

    public static func vector(_ f: WorkoutClassFeatures) -> [Double] {
        let hrr = f.meanHRRPct.map { min(max($0, 0), 100) / 100 } ?? min(max(f.meanHR / 200, 0), 1)
        return [hrr, min(f.hrCV, 1), f.stillFraction, f.walkFraction, f.runFraction,
                log(1 + max(f.motionVariance, 0) * 1_000), min(max(f.motionCV, 0), 3), log(max(f.durationSec, 60) / 60)]
    }
}

public struct PersonalWorkoutClassifier: WorkoutTypeClassifying {
    /// Fewest windows a class needs to be predicted by the learner at all.
    public static let minTrainingPerClass = 3
    /// How many pseudo-windows of the overall spread each class's own spread is blended with.
    static let shrinkage = 5.0
    /// Below this posterior the learner abstains (`.other`) rather than naming a sport.
    public static let abstainBelow = 0.5

    public let model: PersonalClassifierModel

    public init(model: PersonalClassifierModel) { self.model = model }

    /// Train on labelled windows. The caller passes only windows with motion behind them (the replay's `fullWindows`); a heart-rate-only window must never
    /// reach here. Returns nil when there is nothing to learn: fewer than two classes have `minTrainingPerClass` full-evidence windows.
    public static func train(_ windows: [LabelledWorkoutWindow], now: Int) -> PersonalClassifierModel? {
        let usable = windows.filter { $0.label != .other }
        var byClass: [CoarseWorkoutClass: [[Double]]] = [:]
        for w in usable { byClass[w.label, default: []].append(PersonalClassifierFeatures.vector(w.features)) }
        let kept = byClass.filter { $0.value.count >= minTrainingPerClass }
        guard kept.count >= 2 else { return nil }

        let all = kept.values.flatMap { $0 }
        let dim = PersonalClassifierFeatures.names.count
        func mean(_ rows: [[Double]], _ i: Int) -> Double { rows.reduce(0) { $0 + $1[i] } / Double(rows.count) }
        func spread(_ rows: [[Double]], _ i: Int) -> Double {
            let m = mean(rows, i)
            return (rows.reduce(0) { $0 + ($1[i] - m) * ($1[i] - m) } / Double(rows.count)).squareRoot()
        }
        let overall = (0..<dim).map { max(spread(all, $0), PersonalClassifierFeatures.spreadFloor[$0]) }

        var classes: [String: PersonalClassifierModel.ClassStats] = [:]
        for (cls, rows) in kept {
            let n = Double(rows.count)
            let means = (0..<dim).map { mean(rows, $0) }
            let spreads = (0..<dim).map { i -> Double in
                let own = spread(rows, i)
                let blended = ((n * own * own + shrinkage * overall[i] * overall[i]) / (n + shrinkage)).squareRoot()
                return max(blended, PersonalClassifierFeatures.spreadFloor[i])
            }
            classes[cls.rawValue] = .init(n: rows.count, mean: means, std: spreads)
        }
        return PersonalClassifierModel(trainedAt: now, total: all.count, classes: classes, featureVersion: PersonalClassifierFeatures.version)
    }

    public func classify(_ features: WorkoutClassFeatures) -> WorkoutClassPrediction {
        guard model.featureVersion == PersonalClassifierFeatures.version, !model.classes.isEmpty else {
            return WorkoutClassPrediction(predictedClass: .other, confidence: 0, scores: [:])
        }
        let x = PersonalClassifierFeatures.vector(features)
        let totalN = Double(model.classes.values.reduce(0) { $0 + $1.n })
        var logPost: [(cls: CoarseWorkoutClass, value: Double)] = []
        for (raw, stats) in model.classes {
            guard let cls = CoarseWorkoutClass(rawValue: raw), stats.mean.count == x.count, stats.std.count == x.count else { continue }
            var lp = log(Double(stats.n) / totalN)
            for i in x.indices {
                let z = (x[i] - stats.mean[i]) / stats.std[i]
                lp += -0.5 * z * z - log(stats.std[i])
            }
            logPost.append((cls, lp))
        }
        guard let top = logPost.map(\.value).max() else {
            return WorkoutClassPrediction(predictedClass: .other, confidence: 0, scores: [:])
        }
        let exps = logPost.map { exp($0.value - top) }
        let sum = exps.reduce(0, +)
        var scores: [CoarseWorkoutClass: Double] = [:]
        for (i, item) in logPost.enumerated() { scores[item.cls] = exps[i] / sum }
        // Stable on a tie so the same input always gives the same answer.
        let best = scores.max { ($0.value, $1.key.rawValue) < ($1.value, $0.key.rawValue) }!
        // Trusted only as far as the number of windows it learned from: a model of a dozen windows should not claim certainty.
        let trust = min(1, totalN / Double(WorkoutClassReplay.minLabelsPerClass * model.classes.count))
        let confidence = best.value * trust
        let abstain = best.value < Self.abstainBelow
        return WorkoutClassPrediction(predictedClass: abstain ? .other : best.key, confidence: confidence, scores: scores)
    }
}

/// The learner against the rules on the same labelled windows, measured fairly: each window is predicted by a model trained WITHOUT it (leave one out),
/// so the learner is never graded on a window it has memorised.
public struct PersonalLearnerComparison: Equatable, Sendable {
    /// Windows with motion behind them that were scored by both.
    public let windows: Int
    public let rulesCorrect: Int
    public let learnerCorrect: Int
    /// Windows whose true class the learner could have named (it had learned that class from the other windows).
    public let learnerCouldName: Int
    public let learnerCorrectWhenCouldName: Int
    public let rulesCorrectWhenCouldName: Int
    /// The learner named a specific class that was not the truth.
    public let learnerConfidentlyWrong: Int
    public let rulesConfidentlyWrong: Int

    public var rulesAccuracy: Double? { windows == 0 ? nil : Double(rulesCorrect) / Double(windows) }
    public var learnerAccuracy: Double? { windows == 0 ? nil : Double(learnerCorrect) / Double(windows) }
}

public enum PersonalLearnerReplay {
    /// Specific classes with at least `minTrainingPerClass` full-evidence windows (what the learner would predict).
    public static func trainedClasses(_ windows: [LabelledWorkoutWindow]) -> [CoarseWorkoutClass] {
        var counts: [CoarseWorkoutClass: Int] = [:]
        for w in windows where w.label != .other { counts[w.label, default: 0] += 1 }
        return WorkoutClassReplayReport.classOrder.filter { (counts[$0] ?? 0) >= PersonalWorkoutClassifier.minTrainingPerClass }
    }

    /// `windows` are the full-evidence windows only (see `PersonalWorkoutClassifier.train`).
    public static func leaveOneOut(_ windows: [LabelledWorkoutWindow], now: Int = 0) -> PersonalLearnerComparison {
        let scored = windows
        let rules = HeuristicWorkoutClassifier()
        var rulesCorrect = 0, learnerCorrect = 0, could = 0, learnerWhenCould = 0, rulesWhenCould = 0, lWrong = 0, rWrong = 0
        for (i, w) in scored.enumerated() {
            var rest = scored; rest.remove(at: i)
            let r = rules.classify(w.features).predictedClass
            if r == w.label { rulesCorrect += 1 }
            if r != .other && r != w.label { rWrong += 1 }
            var l: CoarseWorkoutClass = .other
            var couldName = false
            if let model = PersonalWorkoutClassifier.train(rest, now: now) {
                l = PersonalWorkoutClassifier(model: model).classify(w.features).predictedClass
                couldName = model.classes[w.label.rawValue] != nil
            }
            if l == w.label { learnerCorrect += 1 }
            if l != .other && l != w.label { lWrong += 1 }
            if couldName {
                could += 1
                if l == w.label { learnerWhenCould += 1 }
                if r == w.label { rulesWhenCould += 1 }
            }
        }
        return PersonalLearnerComparison(windows: scored.count, rulesCorrect: rulesCorrect, learnerCorrect: learnerCorrect, learnerCouldName: could,
                                         learnerCorrectWhenCouldName: learnerWhenCould, rulesCorrectWhenCouldName: rulesWhenCould,
                                         learnerConfidentlyWrong: lWrong, rulesConfidentlyWrong: rWrong)
    }
}
