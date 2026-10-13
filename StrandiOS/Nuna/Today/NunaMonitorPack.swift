#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The Health monitor and Stress monitor pair on Today: two small cards side by side. The first says how many of the five vital signs
/// (HRV, resting heart rate, blood oxygen, respiratory rate, skin temperature) sit in their usual range and opens the vital signs page;
/// the second shows the latest stress reading with its level and time and opens the stress monitor.
struct NunaMonitorPackCard: View {
    let hrv: Double?
    let restingHr: Double?
    let spo2: Double?
    let respiratory: Double?
    let skinTemp: Double?
    let stress: Double?
    let stressCurve: DaytimeStress.Result?

    @EnvironmentObject private var repo: Repository
    @StateObject private var hrvS = NunaSeriesModel()
    @StateObject private var rhrS = NunaSeriesModel()
    @StateObject private var respS = NunaSeriesModel()

    /// How many of the vital signs with a reading are in range, and how many have one.
    private var vitals: (within: Int, known: Int) {
        var within = 0, known = 0
        func tally(_ ok: Bool?) { if let ok { known += 1; if ok { within += 1 } } }
        tally(hrv.flatMap { v in hrvS.band.map { abs(v - $0.mean) <= max($0.sd, 1) } })
        tally(restingHr.flatMap { v in rhrS.band.map { abs(v - $0.mean) <= max($0.sd, 1) } })
        tally(spo2.map { $0 >= 95 })
        tally(respiratory.flatMap { v in respS.band.map { abs(v - $0.mean) <= max($0.sd, 0.3) } })
        tally(skinTemp.map { abs($0) < 0.5 })
        return (within, known)
    }

    /// The latest scored reading of the day's curve and when it was taken; the day's own score when there is no curve.
    private var reading: (value: Double, time: String?)? {
        if let curve = stressCurve, let level = StressDayCurve.latestLevel(curve) {
            let ts = curve.hours.last(where: { $0.level != nil })?.startTs
            return (min(max(level, 0), 3), ts.map { NunaSleepFormat.clock(Date(timeIntervalSince1970: TimeInterval($0))) })
        }
        return stress.map { (min(max($0, 0), 3), nil) }
    }

    private var stressRoute: NunaTodayRoute {
        MetricCatalog.metric(key: "stress", source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(value: NunaTodayRoute.vitalSigns) { vitalTile }.buttonStyle(.plain)
            NavigationLink(value: stressRoute) { stressTile }.buttonStyle(.plain)
        }
        .task(id: repo.refreshSeq) {
            await hrvS.load(repo: repo, key: "hrv", source: "my-whoop", days: 400)
            await rhrS.load(repo: repo, key: "rhr", source: "my-whoop", days: 400)
            await respS.load(repo: repo, key: "resp_rate", source: "my-whoop")
        }
    }

    // MARK: Tiles

    private func shell<Body: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Body) -> some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Text(title).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var vitalTile: some View {
        let v = vitals
        let allIn = v.known > 0 && v.within == v.known
        let tint = v.known == 0 ? NunaPalette.textMuted : (allIn ? NunaPalette.charge : NunaPalette.warning)
        return shell("Vital signs") {
            HStack(spacing: 10) {
                tile(tint: tint) {
                    Image(systemName: v.known == 0 ? "minus" : (allIn ? "checkmark" : "exclamationmark")).font(.nuna(size: 16, weight: .heavy)).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.known == 0 ? "No data" : (allIn ? "Within range" : "Outside range"))
                        .font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(tint)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if v.known > 0 {
                        Text(verbatim: String(localized: "\(v.within)/\(v.known) Metrics")).font(.nuna(size: 12.5, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
            }
        }
    }

    private var stressTile: some View {
        let r = reading
        let tint: Color = r.map { NunaStressBars.color($0.value) } ?? NunaPalette.textMuted
        let word: LocalizedStringKey = r.map { $0.value < 1 ? "Low" : ($0.value < 2 ? "Medium" : "High") } ?? "No data"
        return shell("Stress monitor") {
            HStack(spacing: 10) {
                tile(tint: tint) {
                    Text(verbatim: r.map { String(format: "%.1f", locale: AppLanguage.activeLocale, $0.value) } ?? "–")
                        .font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(tint).minimumScaleFactor(0.7).lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(word).font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(tint)
                    if let time = r?.time {
                        Text(verbatim: time).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
            }
        }
    }

    /// The small rounded square that carries the icon or the number, tinted by status.
    private func tile<Content: View>(tint: Color, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
    }
}
#endif
