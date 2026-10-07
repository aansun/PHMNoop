#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// The small trend lines under the Key Metrics when "Detailed tiles" is on: the last `days` days of each shown metric, oldest first,
/// with days that have no reading left out. The daily figures come from the cached days; weight and skin temperature are read from
/// their own series.
@MainActor
final class NunaKeySparkModel: ObservableObject {
    @Published private(set) var values: [String: [Double]] = [:]

    func load(repo: Repository, metrics: [KeyMetric], days: Int) async {
        let cal = Calendar.current
        let keys: [String] = (0..<days).reversed().map { Repository.localDayKey(cal.date(byAdding: .day, value: -$0, to: Date()) ?? Date()) }
        let daily = Dictionary(repo.days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        func fromDays(_ pick: (DailyMetric) -> Double?) -> [Double] { keys.compactMap { daily[$0].flatMap(pick) } }
        func fromSeries(_ key: String, _ source: String, also: String? = nil) async -> [Double] {
            var byDay = Dictionary((await repo.exploreSeries(key: key, source: source, days: days + 2)).map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
            if let also { for r in await repo.exploreSeries(key: key, source: also, days: days + 2) { byDay[r.day] = r.value } }
            return keys.compactMap { byDay[$0] }
        }
        var out: [String: [Double]] = [:]
        for m in metrics {
            switch m {
            case .hrv: out[m.rawValue] = fromDays { $0.avgHrv }
            case .restingHr: out[m.rawValue] = fromDays { $0.restingHr.map(Double.init) }
            case .bloodOxygen: out[m.rawValue] = fromDays { $0.spo2Pct }
            case .respiratory: out[m.rawValue] = fromDays { $0.respRateBpm }
            case .steps: out[m.rawValue] = fromDays { $0.steps.map(Double.init) }
            case .calories: out[m.rawValue] = fromDays { $0.activeKcalEst }
            case .rest: out[m.rawValue] = fromDays { $0.totalSleepMin }
            case .weight: out[m.rawValue] = await fromSeries("weight", "apple-health", also: nunaManualSource)
            case .skinTemp: out[m.rawValue] = await fromSeries("skin_temp", "my-whoop")
            case .charge, .effort: break
            }
        }
        values = out
    }
}
#endif
