import Foundation

// EnvironmentClient.swift - a read-only client for OpenWeather and IQAir, for a person who brings their own API keys.
//
// Foundation-only and pure: the network is a closure the caller supplies (`Transport`), so the requests, the fall-back between the two
// services and the parsing run in tests against canned bodies. Only GET requests, to two fixed hosts. The place is rounded to two
// decimals (about a kilometre) before it is put in any request, so a street address can never leave the phone. Every field is read
// tolerantly: this is other servers' data.
//
//   OpenWeather   api.openweathermap.org   /data/2.5/weather, /data/2.5/forecast, /data/2.5/air_pollution   (free plan)
//   IQAir         api.airvisual.com        /v2/nearest_city                                                  (Community plan)

public struct EnvironmentClient: Sendable {
    public enum Provider: String, Equatable, Sendable { case openWeather, iqAir }

    public enum Failure: Error, Equatable, Sendable {
        case noKey
        case unauthorized(Provider)
        case rateLimited(Provider)
        case http(Provider, Int)
        case network(Provider)
        case noData
    }

    public struct Response: Sendable {
        public let status: Int
        public let body: Data
        public init(status: Int, body: Data) { self.status = status; self.body = body }
    }

    /// GET `https://<host><path>?<query>`; the host is one of the two fixed ones.
    public typealias Transport = @Sendable (_ host: String, _ path: String, _ query: [String: String]) async throws -> Response

    public static let openWeatherHost = "api.openweathermap.org"
    public static let iqAirHost = "api.airvisual.com"

    private let openWeatherKey: String?
    private let iqAirKey: String?
    private let transport: Transport

    public init(openWeatherKey: String?, iqAirKey: String?, transport: @escaping Transport) {
        func clean(_ k: String?) -> String? { let t = k?.trimmingCharacters(in: .whitespacesAndNewlines); return (t?.isEmpty ?? true) ? nil : t }
        self.openWeatherKey = clean(openWeatherKey); self.iqAirKey = clean(iqAirKey); self.transport = transport
    }

    /// About a kilometre: enough for weather and air, not enough to name a street.
    public static func rounded(_ degrees: Double) -> Double { (degrees * 100).rounded() / 100 }

    // MARK: Snapshot

    /// The weather from OpenWeather and the air from IQAir, each falling back on what the other service can give. Throws only when
    /// neither could say anything; a key that is refused is reported even when the other service answered.
    public func snapshot(latitude: Double, longitude: Double, now: Date = Date()) async throws -> EnvironmentSnapshot {
        guard openWeatherKey != nil || iqAirKey != nil else { throw Failure.noKey }
        let lat = Self.rounded(latitude), lon = Self.rounded(longitude)
        var snap = EnvironmentSnapshot(ts: Int(now.timeIntervalSince1970))
        var refused: Failure?
        var lastFailure: Failure?

        func note(_ e: Error) {
            guard let f = e as? Failure else { lastFailure = .noData; return }
            if case .unauthorized = f { refused = refused ?? f }
            lastFailure = f
        }

        if let key = openWeatherKey {
            do { try await applyOpenWeather(&snap, lat: lat, lon: lon, key: key) } catch { note(error) }
        }
        if let key = iqAirKey {
            do { try await applyIQAir(&snap, lat: lat, lon: lon, key: key) } catch { note(error) }
        }
        // No particle reading from IQAir: OpenWeather's air-pollution reading stands in.
        if !snap.hasAir, let key = openWeatherKey {
            do { try await applyOpenWeatherAir(&snap, lat: lat, lon: lon, key: key) } catch { note(error) }
        }
        if let refused { throw refused }
        guard snap.hasWeather || snap.hasAir else { throw lastFailure ?? Failure.noData }
        return snap
    }

    /// Cheap check of one key, for the settings screen: one request, no more.
    public func check(_ provider: Provider, latitude: Double, longitude: Double) async throws {
        let lat = Self.rounded(latitude), lon = Self.rounded(longitude)
        switch provider {
        case .openWeather:
            guard let key = openWeatherKey else { throw Failure.noKey }
            var s = EnvironmentSnapshot(ts: 0)
            try await applyOpenWeather(&s, lat: lat, lon: lon, key: key, withForecast: false)
        case .iqAir:
            guard let key = iqAirKey else { throw Failure.noKey }
            var s = EnvironmentSnapshot(ts: 0)
            try await applyIQAir(&s, lat: lat, lon: lon, key: key)
        }
    }

    // MARK: OpenWeather

    private func get(_ provider: Provider, host: String, path: String, query: [String: String]) async throws -> [String: Any] {
        let r: Response
        do { r = try await transport(host, path, query) } catch is CancellationError { throw CancellationError() } catch { throw Failure.network(provider) }
        switch r.status {
        case 200..<300: break
        case 401, 403: throw Failure.unauthorized(provider)
        case 429: throw Failure.rateLimited(provider)
        default: throw Failure.http(provider, r.status)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: r.body) as? [String: Any] else { throw Failure.noData }
        return obj
    }

    private func applyOpenWeather(_ s: inout EnvironmentSnapshot, lat: Double, lon: Double, key: String, withForecast: Bool = true) async throws {
        let q = ["lat": Self.fixed(lat), "lon": Self.fixed(lon), "units": "metric", "appid": key]
        let now = try await get(.openWeather, host: Self.openWeatherHost, path: "/data/2.5/weather", query: q)
        let main = now["main"] as? [String: Any]
        s.tempC = Self.number(main?["temp"]); s.feelsLikeC = Self.number(main?["feels_like"]); s.humidityPct = Self.number(main?["humidity"])
        s.windMps = Self.number((now["wind"] as? [String: Any])?["speed"])
        if let w = (now["weather"] as? [[String: Any]])?.first {
            s.conditionId = (w["id"] as? NSNumber)?.intValue
            s.conditionText = w["description"] as? String
        }
        if let name = now["name"] as? String, !name.isEmpty { s.place = name }

        guard withForecast else { return }
        // The forecast is a bonus: when it fails, the reading above still stands.
        if let f = try? await get(.openWeather, host: Self.openWeatherHost, path: "/data/2.5/forecast", query: q.merging(["cnt": "5"]) { $1 }),
           let list = f["list"] as? [[String: Any]] {
            s.forecast = list.compactMap { row in
                guard let ts = (row["dt"] as? NSNumber)?.intValue,
                      let feels = Self.number((row["main"] as? [String: Any])?["feels_like"]) else { return nil }
                return EnvironmentSnapshot.Hour(ts: ts, feelsLikeC: feels, rainChance: Self.number(row["pop"]) ?? 0)
            }
        }
    }

    private func applyOpenWeatherAir(_ s: inout EnvironmentSnapshot, lat: Double, lon: Double, key: String) async throws {
        let q = ["lat": Self.fixed(lat), "lon": Self.fixed(lon), "appid": key]
        let r = try await get(.openWeather, host: Self.openWeatherHost, path: "/data/2.5/air_pollution", query: q)
        guard let row = (r["list"] as? [[String: Any]])?.first,
              let pm = Self.number((row["components"] as? [String: Any])?["pm2_5"]), let aqi = AirQuality.usAqi(pm25: pm) else { throw Failure.noData }
        s.pm25 = pm; s.usAqi = aqi; s.airSource = "openweather"
    }

    // MARK: IQAir

    private func applyIQAir(_ s: inout EnvironmentSnapshot, lat: Double, lon: Double, key: String) async throws {
        let q = ["lat": Self.fixed(lat), "lon": Self.fixed(lon), "key": key]
        let r = try await get(.iqAir, host: Self.iqAirHost, path: "/v2/nearest_city", query: q)
        // IQAir answers 200 with {"status":"fail"} for a bad key or a spent quota.
        if (r["status"] as? String) == "fail" {
            let message = ((r["data"] as? [String: Any])?["message"] as? String) ?? ""
            if message.contains("api_key") || message.contains("key") { throw Failure.unauthorized(.iqAir) }
            if message.contains("many_requests") || message.contains("limit") { throw Failure.rateLimited(.iqAir) }
            throw Failure.noData
        }
        guard let data = r["data"] as? [String: Any], let current = data["current"] as? [String: Any] else { throw Failure.noData }
        if let aqi = (current["pollution"] as? [String: Any])?["aqius"] as? NSNumber { s.usAqi = aqi.intValue; s.airSource = "iqair" }
        // IQAir also carries the weather at its station: used only for what OpenWeather did not give.
        let w = current["weather"] as? [String: Any]
        if s.tempC == nil { s.tempC = Self.number(w?["tp"]) }
        if s.humidityPct == nil { s.humidityPct = Self.number(w?["hu"]) }
        if s.windMps == nil { s.windMps = Self.number(w?["ws"]) }
        if s.place == nil, let city = data["city"] as? String, !city.isEmpty { s.place = city }
    }

    // MARK: Helpers

    private static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { let d = n.doubleValue; return d.isFinite ? d : nil }
        if let s = v as? String { return Double(s) }
        return nil
    }

    private static func fixed(_ d: Double) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), d) }
}
