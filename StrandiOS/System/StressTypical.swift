import Foundation

/// How long a typical day, on the same weekday, spends in the high stress band: the mean over the previous four such days that had
/// scored hours. It is the figure Today and the Stress widget compare "today's high stress" against ("vs. typical Thu").
///
/// Scoring four earlier days reads their heart rate, so the answer is kept for the rest of the local day and the work is done once.
@MainActor
enum StressTypical {
    private static let key = "stress.typicalHigh.v1"

    /// What was worked out earlier today, or nil when it has not been (or could not be).
    static func cached(now: Date = Date()) -> Int? {
        guard let stored = UserDefaults.standard.array(forKey: key) as? [Int], stored.count == 2,
              stored[0] == StressDayCurve.localDayNumber(now) else { return nil }
        return stored[1] >= 0 ? stored[1] : nil
    }

    /// The typical high-stress minutes for today's weekday, or nil with fewer than two earlier days to average.
    static func load(repo: Repository, now: Date = Date()) async -> Int? {
        if let hit = cached(now: now) { return hit }
        let cal = Calendar.current
        var minutes: [Int] = []
        for week in 1...4 {
            guard let day = cal.date(byAdding: .day, value: -7 * week, to: now),
                  let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day)),
                  let end = cal.date(byAdding: .second, value: -1, to: next),
                  let scored = await StressDayCurve.today(repo: repo, now: end)?.result,
                  scored.hours.contains(where: { $0.level != nil }) else { continue }
            minutes.append(scored.highStressMinutes)
        }
        // Scoring an earlier day replaces the one-slot memo; put today's back so the next reader does not pay for it again.
        _ = await StressDayCurve.today(repo: repo, now: now)
        let typical: Int? = minutes.count >= 2 ? Int((Double(minutes.reduce(0, +)) / Double(minutes.count)).rounded()) : nil
        UserDefaults.standard.set([StressDayCurve.localDayNumber(now), typical ?? -1], forKey: key)
        return typical
    }
}
