#if os(iOS)
import SwiftUI
import Combine
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Everything the Health tab draws, read in one go and handed over at once. Each card used to read for itself after the tab opened, so the first visit
/// showed half-built cards (a fitness age "not ready", a Lab Book at nought) that then filled and grew one by one, pushing the page about. The root
/// reads this ahead of the first visit, and the page shows nothing until the whole of it is there.
@MainActor
final class NunaHealthStore: ObservableObject {
    struct Snapshot {
        var hrv: Double?
        var restingHr: Double?
        var spo2: Double?
        var respiratory: Double?
        var skinTemp: Double?
        var stressReady: Bool
        var stressNights: Int
        var stressCurve: DaytimeStress.Result?
        var stressTypicalMin: Int?
        var isToday: Bool
        /// The Body Age stored each week, which the pace of aging is read from.
        var bodyAges: [(day: String, value: Double)]
        /// The age of the latest seven days, the figure on the orb.
        var fitness: NunaHealthspanResult?
        var labRows: [LabMarkerRow]
        var pressure: [NunaBPReading]
    }

    @Published private(set) var snapshot: Snapshot?
    /// The series behind the health monitor card's usual ranges; loaded before the snapshot that goes with them is handed over.
    let hrvS = NunaSeriesModel()
    let rhrS = NunaSeriesModel()
    let respS = NunaSeriesModel()
    let skinS = NunaSeriesModel()
    private let day = NunaTodayModel()
    private var loadedKey: String?
    private var loading: (key: String, task: Task<Void, Never>)?
    private var following: AnyCancellable?

    /// Reads ahead: a moment after the app's data is up, and again a moment after it changes. Subscribed once, from the root.
    func follow(repo: Repository, profile: ProfileStore) {
        guard following == nil else { return }
        following = repo.$refreshSeq
            .filter { $0 > 0 }
            .debounce(for: .seconds(1.2), scheduler: RunLoop.main)
            .sink { [weak self, weak repo, weak profile] _ in
                Task { @MainActor in
                    guard let self, let repo, let profile, UIApplication.shared.applicationState != .background else { return }
                    await self.load(repo: repo, profile: profile)
                }
            }
    }

    /// Reads the page's figures unless they are already those for this state of the data. A call while the same read is under way waits for it.
    func load(repo: Repository, profile: ProfileStore) async {
        guard await repo.nunaAwaitFirstRead() else { return }
        let key = "\(repo.refreshSeq)-\(NunaDataChanges.shared.seq)-\(day.dayKey(repo: repo))-\(profile.age)-\(profile.sex)-\(profile.waistCm)"
        if key == loadedKey { return }
        if let loading {
            await loading.task.value
            if loading.key == key { return }
        }
        // Its own task, so leaving the page part-way does not throw the read away.
        let task = Task { await read(repo: repo, profile: profile) }
        loading = (key, task)
        await task.value
        if loading?.key == key { loading = nil; loadedKey = key }
    }

    private func read(repo: Repository, profile: ProfileStore) async {
        async let today: Void = day.load(repo: repo, profile: profile)
        async let hrv: Void = hrvS.load(repo: repo, key: "hrv", source: "my-whoop", days: 400)
        async let rhr: Void = rhrS.load(repo: repo, key: "rhr", source: "my-whoop", days: 400)
        async let resp: Void = respS.load(repo: repo, key: "resp_rate", source: "my-whoop")
        async let skin: Void = skinS.load(repo: repo, key: "skin_temp", source: "my-whoop")
        async let ages = repo.exploreSeries(key: "body_age", source: "my-whoop", days: 200)
        async let fitness = NunaHealthspan.latest(repo: repo, profile: profile)
        async let rows = NunaLabStore.load(repo)
        async let pressure = NunaBP.load(repo)
        _ = await (today, hrv, rhr, resp, skin)
        let (a, f, l, p) = await (ages, fitness, rows, pressure)
        snapshot = Snapshot(hrv: day.hrv, restingHr: day.restingHr, spo2: day.spo2, respiratory: day.respiratory, skinTemp: day.extras["skin_temp"],
                            stressReady: day.stressStatus.isReady, stressNights: day.stressStatus.nights, stressCurve: day.stressCurve,
                            stressTypicalMin: day.stressTypicalMin, isToday: day.isToday, bodyAges: a, fitness: f, labRows: l, pressure: p)
    }
}
#endif
