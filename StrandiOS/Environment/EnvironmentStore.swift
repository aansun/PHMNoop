#if os(iOS)
import Foundation
import StrandAnalytics

/// The weather and air around the person, fetched on demand and kept for a while.
///
/// Nothing is requested unless Weather and air is turned on and at least one key is saved. A reading is reused for 30 minutes, so the
/// free plans of both services are nowhere near their limits; each fresh one is also kept in a short history (a week, at most one every
/// 20 minutes) so a finished session can be read against the conditions it was done in.
@MainActor
final class EnvironmentStore: ObservableObject {
    static let shared = EnvironmentStore()

    @Published private(set) var snapshot: EnvironmentSnapshot?
    @Published private(set) var isRefreshing = false
    /// A sentence for the settings screen when the last attempt failed; nil after a success.
    @Published private(set) var lastError: String?

    private static let historyKey = "noop.environment.history"
    private static let maxEntries = 60
    private static let keepSeconds = 7 * 86_400
    private(set) var history: [EnvironmentSnapshot]

    private init() {
        let stored = UserDefaults.standard.data(forKey: Self.historyKey).flatMap { try? JSONDecoder().decode([EnvironmentSnapshot].self, from: $0) } ?? []
        history = stored
        snapshot = stored.last
        #if DEBUG
        // `--demo-environment`: a hot, hazy morning, with no request and no key, to look at the screens that read it.
        if Self.isDemo {
            let now = Int(Date().timeIntervalSince1970)
            // Five hot, hazy days in Jakarta: 3-hour steps (a daily swing in the heat, a wet afternoon on the second and fourth day, a storm on the fifth) and the air hour by
            // hour (worst in the morning rush, better after the rain).
            let skyByDay: [Int] = [803, 501, 802, 500, 211]
            let steps: [EnvironmentSnapshot.Hour] = (1...40).map { k in
                let ts = now + k * 3 * 3600
                let hour = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(ts)))
                let day = (k * 3) / 24
                let swing = 4.0 * Foundation.sin(Double.pi * Double(hour - 8) / 12)
                let temp = 29.0 + (hour >= 6 && hour <= 20 ? swing : -3) - Double(day % 2)
                let wet = (day == 1 || day == 3) && (12...18).contains(hour)
                let id = wet ? 501 : (day == 4 && (13...19).contains(hour) ? 211 : (hour >= 19 || hour < 5 ? 800 : skyByDay[min(day, 4)] == 501 ? 802 : skyByDay[min(day, 4)]))
                return .init(ts: ts, feelsLikeC: temp + 4, rainChance: wet || id == 211 ? 0.7 : 0.1, tempC: temp, windMps: 2.5 + Double(hour % 4), conditionId: id, humidityPct: 72)
            }
            let air: [EnvironmentSnapshot.AirHour] = (0..<96).map { i in
                let hour = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(now + i * 3600)))
                let rush = (6...9).contains(hour) ? 40 : ((17...19).contains(hour) ? 25 : 0)
                return .init(ts: now + i * 3600, usAqi: 62 + rush + (i / 24) * 7 + (i % 5))
            }
            snapshot = EnvironmentSnapshot(ts: now, place: "Jakarta", tempC: 32, feelsLikeC: 38, humidityPct: 72, windMps: 2.4, conditionId: 803,
                                           conditionText: "broken clouds", usAqi: 132, pm25: 48, airSource: "iqair", forecast: steps, airForecast: air)
            // And one from this morning, when the demo walk was done, so that session can be read against it.
            let morning = Calendar.current.date(bySettingHour: 9, minute: 40, second: 0, of: Date()).map { Int($0.timeIntervalSince1970) } ?? now
            var then = snapshot!; then.ts = morning
            history = [then, snapshot!]
        }
        #endif
    }

    #if DEBUG
    static var isDemo: Bool { CommandLine.arguments.contains("--demo-environment") }
    #else
    static var isDemo: Bool { false }
    #endif

    var isEnabled: Bool { Self.isDemo || EnvironmentExperiment.isEnabled }
    var hasKeys: Bool { Self.isDemo || EnvironmentKeyStore.hasAny }
    /// On and with a key: the only state in which anything is requested.
    var isActive: Bool { isEnabled && hasKeys }

    var advice: EnvironmentAdvice? { snapshot.flatMap { EnvironmentAdvice.analyze($0) } }

    /// The reading closest to a moment, when one was taken within three hours of it.
    func snapshot(near ts: Int, within seconds: Int = 3 * 3600) -> EnvironmentSnapshot? {
        history.filter { abs($0.ts - ts) <= seconds }.min { abs($0.ts - ts) < abs($1.ts - ts) }
    }

    func message(for failure: Error) -> String {
        guard let f = failure as? EnvironmentClient.Failure else { return failure.localizedDescription }
        func name(_ p: EnvironmentClient.Provider) -> String { p == .openWeather ? "OpenWeather" : "IQAir" }
        switch f {
        case .noKey: return String(localized: "Add an OpenWeather or an IQAir key first.")
        case .unauthorized(let p): return String(localized: "\(name(p)) refused the key. Check that it is typed right and active; a new OpenWeather key can take up to two hours to start working.")
        case .rateLimited(let p): return String(localized: "\(name(p)) asked to slow down. Try again in a few minutes.")
        case .http(let p, let code): return String(localized: "\(name(p)) answered with an error (\(code)). Try again later.")
        case .network(let p): return String(localized: "Could not reach \(name(p)). Check the connection and try again.")
        case .noData: return String(localized: "The services had nothing for this place.")
        }
    }

    func client() -> EnvironmentClient {
        EnvironmentClient(openWeatherKey: EnvironmentKeyStore.read(.openWeather), iqAirKey: EnvironmentKeyStore.read(.iqAir), transport: EnvironmentTransport.live())
    }

    /// A fresh reading unless one younger than `maxAge` is held. Does nothing while off, without a key, or while another is under way.
    func refreshIfNeeded(maxAge: TimeInterval = 30 * 60) async {
        guard isActive, !Self.isDemo else { return }
        if let s = snapshot, Date().timeIntervalSince1970 - Double(s.ts) < maxAge { return }
        await refresh()
    }

    func refresh() async {
        guard isActive, !Self.isDemo, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        guard let place = await EnvironmentLocation.shared.current() else {
            lastError = String(localized: "No location yet. Allow location for PHMN in Settings, then try again.")
            return
        }
        do {
            let s = try await client().snapshot(latitude: place.latitude, longitude: place.longitude)
            snapshot = s; lastError = nil
            remember(s)
        } catch {
            lastError = message(for: error)
        }
    }

    /// Settings: one request to one service, to say whether its key works.
    func check(_ provider: EnvironmentClient.Provider) async -> String? {
        guard let place = await EnvironmentLocation.shared.current() else {
            return String(localized: "No location yet. Allow location for PHMN in Settings, then try again.")
        }
        do { try await client().check(provider, latitude: place.latitude, longitude: place.longitude); return nil }
        catch { return message(for: error) }
    }

    private func remember(_ s: EnvironmentSnapshot) {
        if let last = history.last, s.ts - last.ts < 20 * 60 { history[history.count - 1] = s }
        else { history.append(s) }
        let floor = s.ts - Self.keepSeconds
        history = Array(history.filter { $0.ts >= floor }.suffix(Self.maxEntries))
        // Only the latest reading keeps its forecast; the older ones are there to say what the weather was, so the stored history stays small.
        for i in history.indices.dropLast() { history[i].forecast = []; history[i].airForecast = [] }
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: Self.historyKey) }
    }

    /// Turning it off forgets what was read; the keys stay until they are removed.
    func forget() {
        snapshot = nil; history = []; lastError = nil
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
        EnvironmentLocation.shared.clearSaved()
    }
}
#endif
