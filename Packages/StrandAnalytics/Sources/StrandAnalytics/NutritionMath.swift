import Foundation

// NutritionMath.swift — the arithmetic behind the Nutrition screens: a smoothed weight, what the body spends, a daily target for a chosen pace
// and the weekly check-in.
//
// PURE and unit-tested; days are `yyyy-MM-dd` strings handled as literal civil dates (no time zone, no Calendar). Everything is an estimate built
// from the person's own food and weight, and the check-in only ever SUGGESTS a change: nothing here applies one, and nothing is medical advice.
//
//  • Trend weight: an exponential smoothing at 10% a day, widened by the gap since the last weigh-in, so water and salt swings do not read as
//    fat. The first weigh-in is the first trend value.
//  • Expenditure: over a window of days, what was eaten minus what the trend weight stored or released, at 7700 kcal per kg of body-weight change.
//  • Target: expenditure plus the pace, 7700 kcal per kg spread over 7 days, never below a floor.
//  • Macros: protein by body weight, fat as a share of calories, carbohydrate the rest.

public enum NutritionMath {
    /// Energy in one kg of body-weight change, the figure the whole tool uses.
    public static let kcalPerKg = 7700.0
    /// The lowest daily target the tool will set.
    public static let floorKcal = 1200.0

    // MARK: Days

    /// Days since 1970-01-01 for a `yyyy-MM-dd` string, nil for anything else (Howard Hinnant's civil-from-days, inverted).
    public static func dayIndex(_ day: String) -> Int? {
        let p = day.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m), (1...31).contains(d), (1800...2200).contains(y) else { return nil }
        let yy = m <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    // MARK: Trend weight

    public struct WeightPoint: Equatable, Sendable {
        public var day: String
        public var kg: Double
        public init(day: String, kg: Double) { self.day = day; self.kg = kg }
    }

    /// The smoothed weight at each weigh-in, oldest first. Several weigh-ins on a day count as their mean; non-positive or non-finite values are ignored.
    public static func trend(_ weights: [WeightPoint]) -> [WeightPoint] {
        var byDay: [Int: (day: String, sum: Double, n: Int)] = [:]
        for w in weights where w.kg.isFinite && w.kg > 0 {
            guard let i = dayIndex(w.day) else { continue }
            let cur = byDay[i] ?? (w.day, 0, 0)
            byDay[i] = (cur.day, cur.sum + w.kg, cur.n + 1)
        }
        var out: [WeightPoint] = []
        var prev: (index: Int, value: Double)?
        for i in byDay.keys.sorted() {
            let e = byDay[i]!
            let raw = e.sum / Double(e.n)
            let value: Double
            if let p = prev {
                let alpha = 1 - pow(0.9, Double(max(1, i - p.index)))
                value = p.value + alpha * (raw - p.value)
            } else {
                value = raw
            }
            out.append(WeightPoint(day: e.day, kg: value))
            prev = (i, value)
        }
        return out
    }

    /// The trend weight on or before `day` (the nearest earlier weigh-in), nil without one.
    static func trendValue(_ trend: [WeightPoint], onOrBefore day: String) -> (index: Int, kg: Double)? {
        guard let target = dayIndex(day) else { return nil }
        var best: (Int, Double)?
        for p in trend { if let i = dayIndex(p.day), i <= target { best = (i, p.kg) } }
        return best.map { (index: $0.0, kg: $0.1) }
    }

    // MARK: Expenditure

    /// What the body spent per day over the `windowDays` ending at `endDay`, worked out from what was eaten and how the trend weight moved.
    /// nil unless at least `minLogged` of those days have an intake and the trend spans at least 10 of them.
    public static func expenditure(intake: [String: Double], trend: [WeightPoint], endDay: String, windowDays: Int = 14, minLogged: Int = 10) -> Double? {
        guard let end = dayIndex(endDay), windowDays >= 7 else { return nil }
        let start = end - windowDays + 1
        let logged = intake.compactMap { (k, v) -> Double? in
            guard let i = dayIndex(k), i >= start, i <= end, v.isFinite, v > 0 else { return nil }
            return v
        }
        guard logged.count >= minLogged else { return nil }
        guard let a = trendValue(trend, onOrBefore: ymd(start)), let b = trendValue(trend, onOrBefore: endDay), b.index - a.index >= 10 else { return nil }
        let meanIntake = logged.reduce(0, +) / Double(logged.count)
        let deltaKg = b.kg - a.kg
        let span = Double(b.index - a.index)
        return meanIntake - deltaKg * kcalPerKg / span
    }

    /// The `yyyy-MM-dd` for a day index (the inverse of `dayIndex`).
    public static func ymd(_ index: Int) -> String {
        let z = index + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp + (mp < 10 ? 3 : -9)
        return String(format: "%04d-%02d-%02d", y + (m <= 2 ? 1 : 0), m, d)
    }

    /// A rough maintenance figure from the profile alone (Mifflin-St Jeor times a light-activity factor), for when nothing better exists yet.
    public static func profileMaintenance(sex: String, ageYears: Double, weightKg: Double, heightCm: Double, activityFactor: Double = 1.4) -> Double? {
        guard weightKg > 20, heightCm > 100, ageYears > 10 else { return nil }
        let base = 10 * weightKg + 6.25 * heightCm - 5 * ageYears
        let bmr = base + (sex.lowercased() == "male" ? 5 : (sex.lowercased() == "female" ? -161 : -78))
        return bmr * activityFactor
    }

    // MARK: Target and macros

    /// The daily calories for a pace: `weeklyChangeKg` is negative to lose, positive to gain. Never below the floor.
    public static func dailyTarget(maintenanceKcal: Double, weeklyChangeKg: Double) -> Double {
        max(floorKcal, (maintenanceKcal + weeklyChangeKg * kcalPerKg / 7).rounded())
    }

    public struct Macros: Equatable, Sendable {
        public var proteinG: Double
        public var carbsG: Double
        public var fatG: Double
    }

    /// Protein by body weight, fat as a share of the calories, carbohydrate what is left (never negative).
    public static func macroTargets(kcal: Double, weightKg: Double, proteinPerKg: Double, fatShare: Double) -> Macros {
        let protein = max(0, proteinPerKg * weightKg)
        let fat = max(0, kcal * min(max(fatShare, 0), 0.6) / 9)
        let carbs = max(0, (kcal - protein * 4 - fat * 9) / 4)
        return Macros(proteinG: protein.rounded(), carbsG: carbs.rounded(), fatG: fat.rounded())
    }

    /// Calories from macros, 4 / 4 / 9.
    public static func kcal(proteinG: Double?, carbsG: Double?, fatG: Double?) -> Double {
        ((proteinG ?? 0) * 4 + (carbsG ?? 0) * 4 + (fatG ?? 0) * 9).rounded()
    }

    // MARK: Weekly check-in

    public struct CheckIn: Equatable, Sendable {
        /// What the trend weight actually did per week over the last 7 to 14 days (negative = lost).
        public var actualKgPerWeek: Double
        public var plannedKgPerWeek: Double
        /// The suggested move of the daily target, in kcal (negative = eat less).
        public var changeKcal: Double
        public var newTarget: Double
    }

    /// Compares the trend with the planned pace and suggests a nudge to the target that would close the gap, in steps of 10 and at most 250 either way.
    /// nil when there is too little to go on (under 5 days logged in the week, or a trend shorter than 7 days) or the gap is under 50 kcal.
    public static func checkIn(trend: [WeightPoint], intake: [String: Double], endDay: String, plannedKgPerWeek: Double, currentTarget: Double) -> CheckIn? {
        guard let end = dayIndex(endDay) else { return nil }
        let loggedThisWeek = intake.filter { (k, v) in if let i = dayIndex(k) { return i > end - 7 && i <= end && v > 0 } else { return false } }.count
        guard loggedThisWeek >= 5 else { return nil }
        guard let b = trendValue(trend, onOrBefore: endDay) else { return nil }
        var a: (index: Int, kg: Double)?
        for back in 7...14 { if let t = trendValue(trend, onOrBefore: ymd(end - back)), b.index - t.index >= 7 { a = t; break } }
        guard let a else { return nil }
        let perWeek = (b.kg - a.kg) / Double(b.index - a.index) * 7
        let raw = -(perWeek - plannedKgPerWeek) * kcalPerKg / 7
        let capped = min(250, max(-250, raw))
        let rounded = (capped / 10).rounded() * 10
        guard abs(rounded) >= 50 else { return nil }
        return CheckIn(actualKgPerWeek: perWeek, plannedKgPerWeek: plannedKgPerWeek, changeKcal: rounded, newTarget: max(floorKcal, currentTarget + rounded))
    }
}
