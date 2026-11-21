#if os(iOS)
import Foundation
import CoreLocation
import StrandAnalytics

/// Where the person is, once, for the weather: a short burst of fixes on request (never tracking), accepted only when it is recent and tight enough to
/// mean the place the person is in, and kept rounded to about a kilometre. Without permission or a good fix, the last place that was known stands in.
@MainActor
final class EnvironmentLocation: NSObject, CLLocationManagerDelegate {
    static let shared = EnvironmentLocation()

    private let manager = CLLocationManager()
    private var fixWaiters: [CheckedContinuation<CLLocation?, Never>] = []
    private var authWaiters: [CheckedContinuation<Void, Never>] = []
    private var best: CLLocation?
    /// Which wait a timer belongs to, so an earlier wait's timer cannot end a later one.
    private var waitToken = 0
    private static let savedKey = "noop.environment.lastLocation"
    /// A fix tighter than this ends the wait at once; the best one inside `usableAccuracy` is taken when the time is up.
    private static let goodAccuracy: CLLocationAccuracy = 500
    private static let usableAccuracy: CLLocationAccuracy = 5_000

    private override init() {
        super.init()
        manager.delegate = self
        // A kilometre of accuracy lets iOS answer from a cell tower, which can be tens of kilometres off away from a city; a hundred metres uses Wi-Fi and GPS.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool { [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) }
    var isDenied: Bool { [.denied, .restricted].contains(manager.authorizationStatus) }

    /// The last place that was known, rounded.
    var saved: CLLocationCoordinate2D? {
        guard let a = UserDefaults.standard.array(forKey: Self.savedKey) as? [Double], a.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: a[0], longitude: a[1])
    }

    private func remember(_ c: CLLocationCoordinate2D) {
        UserDefaults.standard.set([EnvironmentClient.rounded(c.latitude), EnvironmentClient.rounded(c.longitude)], forKey: Self.savedKey)
    }

    func clearSaved() { UserDefaults.standard.removeObject(forKey: Self.savedKey) }

    /// Asks for permission the first time; a no-op afterwards.
    func requestAuthorization() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    /// The place now. Waits for the permission prompt when it is showing, asks for exact location once when the person gave only an approximate one, takes
    /// fixes for up to eight seconds and keeps the tightest recent one. A cached or loose fix is not taken for the place the person is in.
    func current() async -> CLLocationCoordinate2D? {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            await withCheckedContinuation { cont in
                authWaiters.append(cont)
                Task { try? await Task.sleep(nanoseconds: 120_000_000_000); self.resumeAuth() }
            }
        }
        guard isAuthorized else { return saved }
        if manager.accuracyAuthorization == .reducedAccuracy {
            // Approximate location is a box of many kilometres: ask, once for this use, for the exact one.
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "Weather") { _ in cont.resume() }
            }
        }
        best = nil
        waitToken += 1
        let token = waitToken
        let fix: CLLocation? = await withCheckedContinuation { cont in
            fixWaiters.append(cont)
            manager.startUpdatingLocation()
            Task { try? await Task.sleep(nanoseconds: 8_000_000_000); if self.waitToken == token { self.finish() } }
        }
        manager.stopUpdatingLocation()
        if let fix { remember(fix.coordinate); note(fix.coordinate, accuracy: fix.horizontalAccuracy, source: String(localized: "fresh fix")); return fix.coordinate }
        if let cached = manager.location, Self.isUsable(cached, maxAge: 1_800) {
            note(cached.coordinate, accuracy: cached.horizontalAccuracy, source: String(localized: "recent fix"))
            return cached.coordinate
        }
        if let old = saved { note(old, accuracy: nil, source: String(localized: "saved place, no fix")) }
        return saved
    }

    private static let infoKey = "noop.environment.lastFixInfo"

    private func note(_ c: CLLocationCoordinate2D, accuracy: CLLocationAccuracy?, source: String) {
        var info: [String: Any] = ["lat": EnvironmentClient.rounded(c.latitude), "lon": EnvironmentClient.rounded(c.longitude), "ts": Date().timeIntervalSince1970, "source": source]
        if let accuracy, accuracy >= 0 { info["acc"] = accuracy }
        UserDefaults.standard.set(info, forKey: Self.infoKey)
    }

    /// The place the last reading was asked for, how tight the fix was and when, for the Weather and air page: "-1.82, 115.91 · ±35 m · 19.54 · fresh fix".
    var lastFixDescription: String? {
        guard let i = UserDefaults.standard.dictionary(forKey: Self.infoKey), let lat = i["lat"] as? Double, let lon = i["lon"] as? Double else { return nil }
        var parts = [String(format: "%.2f, %.2f", lat, lon)]
        if let acc = i["acc"] as? Double { parts.append("±\(Int(acc.rounded())) m") }
        if let ts = i["ts"] as? Double {
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("HH:mm")
            parts.append(f.string(from: Date(timeIntervalSince1970: ts)))
        }
        if let src = i["source"] as? String { parts.append(src) }
        return parts.joined(separator: " · ")
    }

    private static func isUsable(_ l: CLLocation, maxAge: TimeInterval) -> Bool {
        l.horizontalAccuracy >= 0 && l.horizontalAccuracy <= usableAccuracy && -l.timestamp.timeIntervalSinceNow <= maxAge
    }

    /// Ends the wait with the best fix so far (nil when none was usable).
    private func finish() {
        guard !fixWaiters.isEmpty else { return }
        let waiting = fixWaiters; fixWaiters = []
        let result = best
        manager.stopUpdatingLocation()
        waiting.forEach { $0.resume(returning: result) }
    }

    private func resumeAuth() {
        let waiting = authWaiters; authWaiters = []
        waiting.forEach { $0.resume() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for l in locations where Self.isUsable(l, maxAge: 120) {
                if self.best == nil || l.horizontalAccuracy < self.best!.horizontalAccuracy { self.best = l }
            }
            if let b = self.best, b.horizontalAccuracy <= Self.goodAccuracy { self.finish() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix leaves the wait to run out its time: another one may still arrive.
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in if self.manager.authorizationStatus != .notDetermined { self.resumeAuth() } }
    }
}
#endif
