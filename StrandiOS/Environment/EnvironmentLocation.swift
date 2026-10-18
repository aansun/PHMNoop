#if os(iOS)
import Foundation
import CoreLocation
import StrandAnalytics

/// Where the person is, once, for the weather: a single coarse fix on request (kilometre accuracy, never tracking), kept rounded to
/// about a kilometre. Without permission or a fix, the last place that was known stands in.
@MainActor
final class EnvironmentLocation: NSObject, CLLocationManagerDelegate {
    static let shared = EnvironmentLocation()

    private let manager = CLLocationManager()
    private var fixWaiters: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []
    private var authWaiters: [CheckedContinuation<Void, Never>] = []
    private static let savedKey = "noop.environment.lastLocation"

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
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

    /// One coarse fix. Waits for the permission prompt when it is showing, and gives up after ten seconds without a fix.
    func current() async -> CLLocationCoordinate2D? {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            await withCheckedContinuation { cont in
                authWaiters.append(cont)
                Task { try? await Task.sleep(nanoseconds: 120_000_000_000); self.resumeAuth() }
            }
        }
        guard isAuthorized else { return saved }
        let fix: CLLocationCoordinate2D? = await withCheckedContinuation { cont in
            fixWaiters.append(cont)
            manager.requestLocation()
            Task { try? await Task.sleep(nanoseconds: 10_000_000_000); self.resolve(nil) }
        }
        if let fix { remember(fix); return fix }
        return manager.location.map { $0.coordinate } ?? saved
    }

    private func resolve(_ c: CLLocationCoordinate2D?) {
        let waiting = fixWaiters; fixWaiters = []
        waiting.forEach { $0.resume(returning: c) }
    }

    private func resumeAuth() {
        let waiting = authWaiters; authWaiters = []
        waiting.forEach { $0.resume() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let c = locations.last?.coordinate
        Task { @MainActor in self.resolve(c) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resolve(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in if self.manager.authorizationStatus != .notDetermined { self.resumeAuth() } }
    }
}
#endif
