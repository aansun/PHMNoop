#if os(iOS)
import SwiftUI
import StrandDesign

/// The day picked on Today (0 = today, 1 = yesterday, ...), as the Charge, Effort and Rest pages need it: its date, and the wording that
/// stands in for "Today" once it is another day. `NavRouter.todayDayOffset` carries the choice from Today to the pages it opens.
@MainActor enum NunaSelectedDay {
    /// Midnight of the picked day.
    static func date(offset: Int) -> Date {
        let cal = Calendar.current
        let base = Repository.logicalDay(Date())
        return cal.startOfDay(for: cal.date(byAdding: .day, value: -max(offset, 0), to: base) ?? base)
    }

    static func key(offset: Int) -> String { Repository.localDayKey(date(offset: offset)) }

    /// "Yesterday", or "Tuesday 20 Oct"; nil for today, whose pages keep their own wording ("Today", "Last night").
    static func title(offset: Int) -> String? {
        guard offset > 0 else { return nil }
        if offset == 1 { return String(localized: "Yesterday") }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        return f.string(from: date(offset: offset))
    }

    /// The hero caption: `today` for today, else the day's title.
    static func caption(offset: Int, today: LocalizedStringKey) -> LocalizedStringKey {
        title(offset: offset).map { LocalizedStringKey($0) } ?? today
    }
}

extension NunaSeriesModel {
    /// The newest reading on or before a day key (nil = no limit), so a past day's page reads that day and not today's.
    func latest(asOf cutoff: String?) -> (day: String, value: Double)? {
        guard let k = byDay.keys.filter({ cutoff == nil || $0 <= cutoff! }).sorted().last, let v = byDay[k] else { return nil }
        return (k, v)
    }

    /// How that reading moved from the one before it; nil when there is only one.
    func change(asOf cutoff: String?) -> Double? {
        let keys = byDay.keys.filter { cutoff == nil || $0 <= cutoff! }.sorted()
        guard keys.count >= 2, let a = byDay[keys[keys.count - 1]], let b = byDay[keys[keys.count - 2]] else { return nil }
        return a - b
    }
}
#endif
