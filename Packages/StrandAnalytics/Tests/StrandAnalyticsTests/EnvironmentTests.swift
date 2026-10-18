import XCTest
@testable import StrandAnalytics

final class EnvironmentTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    // MARK: Air quality

    func testUsAqiFromPm25FollowsTheEpaBands() {
        XCTAssertEqual(AirQuality.usAqi(pm25: 0), 0)
        XCTAssertEqual(AirQuality.usAqi(pm25: 9.0), 50)
        XCTAssertEqual(AirQuality.usAqi(pm25: 35.4), 100)
        XCTAssertEqual(AirQuality.usAqi(pm25: 55.4), 150)
        XCTAssertEqual(AirQuality.usAqi(pm25: 125.4), 200)
        // The middle of a band is in the middle of its index range.
        XCTAssertEqual(AirQuality.usAqi(pm25: 22.25)!, 76, accuracy: 1)
        XCTAssertNil(AirQuality.usAqi(pm25: -1))
        XCTAssertEqual(AirQuality.band(usAqi: 50), .good)
        XCTAssertEqual(AirQuality.band(usAqi: 101), .unhealthyForSensitive)
        XCTAssertEqual(AirQuality.band(usAqi: 320), .hazardous)
    }

    // MARK: Advice

    private func snap(feels: Double? = 28, humidity: Double? = 60, aqi: Int? = 40, id: Int? = 800, wind: Double? = 3,
                      forecast: [EnvironmentSnapshot.Hour] = []) -> EnvironmentSnapshot {
        EnvironmentSnapshot(ts: 1_000_000, tempC: feels, feelsLikeC: feels, humidityPct: humidity, windMps: wind, conditionId: id, usAqi: aqi, forecast: forecast)
    }

    func testAMildCleanDayIsGood() {
        let a = EnvironmentAdvice.analyze(snap())!
        XCTAssertEqual(a.level, .good); XCTAssertTrue(a.reasons.isEmpty)
    }

    func testHeatHumidityAirStormAndColdEachMove_theLevel() {
        XCTAssertEqual(EnvironmentAdvice.analyze(snap(feels: 34))!.level, .adjust)
        XCTAssertEqual(EnvironmentAdvice.analyze(snap(feels: 31, humidity: 80))!.level, .adjust)   // humid heat
        XCTAssertEqual(EnvironmentAdvice.analyze(snap(feels: 31, humidity: 50))!.level, .good)
        XCTAssertEqual(EnvironmentAdvice.analyze(snap(feels: 39))!.level, .indoors)
        XCTAssertEqual(EnvironmentAdvice.analyze(snap(aqi: 120))!.level, .adjust)
        XCTAssertEqual(EnvironmentAdvice.analyze(snap(aqi: 180))!.level, .indoors)
        XCTAssertEqual(EnvironmentAdvice.analyze(snap(aqi: 80))!.level, .good)                     // moderate air is only a note
        XCTAssertEqual(EnvironmentAdvice.analyze(snap(id: 211))!.level, .indoors)                  // thunderstorm
        XCTAssertEqual(EnvironmentAdvice.analyze(snap(id: 501))!.level, .adjust)                   // rain
        XCTAssertEqual(EnvironmentAdvice.analyze(snap(feels: 2))!.level, .adjust)
        XCTAssertEqual(EnvironmentAdvice.analyze(snap(feels: -12))!.level, .indoors)
        XCTAssertEqual(EnvironmentAdvice.analyze(snap(wind: 14))!.level, .adjust)
    }

    func testTheWorstReasonWinsAndAllAreListed() {
        let a = EnvironmentAdvice.analyze(snap(feels: 35, aqi: 160))!
        XCTAssertEqual(a.level, .indoors)
        XCTAssertEqual(a.reasons.count, 2)
    }

    func testACoolerHourIsOfferedOnlyWhenHotAndClearlyKinder() {
        let later = EnvironmentSnapshot.Hour(ts: 1_000_000 + 6 * 3600, feelsLikeC: 28, rainChance: 0.1)
        let a = EnvironmentAdvice.analyze(snap(feels: 34, forecast: [later]), calendar: utc)!
        XCTAssertEqual(a.cooler?.ts, later.ts)
        // At night it is no use: the same kinder hour at 23:00 is not offered.
        let night = EnvironmentSnapshot.Hour(ts: 1_000_000 + 9 * 3600 + 15 * 60, feelsLikeC: 26, rainChance: 0.1)   // 23:01 UTC
        XCTAssertNil(EnvironmentAdvice.analyze(snap(feels: 34, forecast: [night]), calendar: utc)!.cooler)
        // Not hot now: nothing to offer.
        XCTAssertNil(EnvironmentAdvice.analyze(snap(feels: 27, forecast: [later]), calendar: utc)!.cooler)
        // Barely cooler, or wet: nothing to offer.
        let barely = EnvironmentSnapshot.Hour(ts: 1_000_000 + 3 * 3600, feelsLikeC: 32, rainChance: 0.1)
        XCTAssertNil(EnvironmentAdvice.analyze(snap(feels: 34, forecast: [barely]), calendar: utc)!.cooler)
        let wet = EnvironmentSnapshot.Hour(ts: 1_000_000 + 3 * 3600, feelsLikeC: 26, rainChance: 0.8)
        XCTAssertNil(EnvironmentAdvice.analyze(snap(feels: 34, forecast: [wet]), calendar: utc)!.cooler)
    }

    func testNothingToAdviseWithoutFigures() {
        XCTAssertNil(EnvironmentAdvice.analyze(EnvironmentSnapshot(ts: 1)))
    }

    // MARK: Client

    private final class Log: @unchecked Sendable { var calls: [(host: String, path: String, query: [String: String])] = [] }

    private func transport(_ log: Log, _ answers: [String: (Int, String)]) -> EnvironmentClient.Transport {
        { host, path, query in
            log.calls.append((host, path, query))
            guard let a = answers[host + path] else { return .init(status: 404, body: Data()) }
            return .init(status: a.0, body: Data(a.1.utf8))
        }
    }

    private let owNow = #"{"name":"Jakarta","weather":[{"id":803,"description":"broken clouds"}],"main":{"temp":31.2,"feels_like":37.6,"humidity":74},"wind":{"speed":2.4}}"#
    private let owForecast = #"{"list":[{"dt":1000100,"main":{"feels_like":36.0},"pop":0.1},{"dt":1010900,"main":{"feels_like":29.5},"pop":0.05}]}"#
    private let owAir = #"{"list":[{"main":{"aqi":3},"components":{"pm2_5":40.2}}]}"#
    private let iqAir = #"{"status":"success","data":{"city":"Jakarta","current":{"pollution":{"aqius":132,"mainus":"p2"},"weather":{"tp":30,"hu":70,"ws":3.1}}}}"#

    func testBothKeysTakeWeatherFromOpenWeatherAndAirFromIQAir() async throws {
        let log = Log()
        let c = EnvironmentClient(openWeatherKey: "ow", iqAirKey: "iq", transport: transport(log, [
            "api.openweathermap.org/data/2.5/weather": (200, owNow), "api.openweathermap.org/data/2.5/forecast": (200, owForecast),
            "api.airvisual.com/v2/nearest_city": (200, iqAir),
        ]))
        let s = try await c.snapshot(latitude: -6.20876, longitude: 106.84560, now: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(s.feelsLikeC, 37.6); XCTAssertEqual(s.humidityPct, 74); XCTAssertEqual(s.conditionId, 803)
        XCTAssertEqual(s.usAqi, 132); XCTAssertEqual(s.airSource, "iqair"); XCTAssertEqual(s.place, "Jakarta")
        XCTAssertEqual(s.forecast.count, 2)
        // The place went out rounded to about a kilometre, to the two fixed hosts only.
        XCTAssertTrue(log.calls.allSatisfy { $0.query["lat"] == "-6.21" && $0.query["lon"] == "106.85" })
        XCTAssertEqual(Set(log.calls.map(\.host)), ["api.openweathermap.org", "api.airvisual.com"])
        XCTAssertFalse(log.calls.contains { $0.path.contains("air_pollution") })   // IQAir answered, so no second air request
    }

    func testOpenWeatherAloneFillsTheAirFromParticles() async throws {
        let c = EnvironmentClient(openWeatherKey: "ow", iqAirKey: nil, transport: transport(Log(), [
            "api.openweathermap.org/data/2.5/weather": (200, owNow), "api.openweathermap.org/data/2.5/air_pollution": (200, owAir),
        ]))
        let s = try await c.snapshot(latitude: 1, longitude: 2)
        XCTAssertEqual(s.airSource, "openweather"); XCTAssertEqual(s.usAqi, AirQuality.usAqi(pm25: 40.2)); XCTAssertEqual(s.pm25, 40.2)
        XCTAssertTrue(s.forecast.isEmpty)   // a failed forecast does not fail the reading
    }

    func testIQAirAloneGivesAirAndItsOwnWeather() async throws {
        let c = EnvironmentClient(openWeatherKey: nil, iqAirKey: "iq", transport: transport(Log(), ["api.airvisual.com/v2/nearest_city": (200, iqAir)]))
        let s = try await c.snapshot(latitude: 1, longitude: 2)
        XCTAssertEqual(s.usAqi, 132); XCTAssertEqual(s.tempC, 30); XCTAssertNil(s.feelsLikeC)
    }

    func testARefusedKeyIsReportedEvenWhenTheOtherServiceAnswered() async {
        let c = EnvironmentClient(openWeatherKey: "bad", iqAirKey: "iq", transport: transport(Log(), [
            "api.openweathermap.org/data/2.5/weather": (401, "{}"), "api.airvisual.com/v2/nearest_city": (200, iqAir),
        ]))
        do { _ = try await c.snapshot(latitude: 1, longitude: 2); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? EnvironmentClient.Failure, .unauthorized(.openWeather)) }
    }

    func testIQAirFailBodyMeansABadKey() async {
        let body = #"{"status":"fail","data":{"message":"incorrect_api_key"}}"#
        let c = EnvironmentClient(openWeatherKey: nil, iqAirKey: "x", transport: transport(Log(), ["api.airvisual.com/v2/nearest_city": (200, body)]))
        do { _ = try await c.snapshot(latitude: 1, longitude: 2); XCTFail() }
        catch { XCTAssertEqual(error as? EnvironmentClient.Failure, .unauthorized(.iqAir)) }
    }

    func testIQAirQuotaFallsBackOnOpenWeatherAir() async throws {
        let quota = #"{"status":"fail","data":{"message":"call_limit_reached"}}"#
        let c = EnvironmentClient(openWeatherKey: "ow", iqAirKey: "iq", transport: transport(Log(), [
            "api.openweathermap.org/data/2.5/weather": (200, owNow), "api.airvisual.com/v2/nearest_city": (200, quota),
            "api.openweathermap.org/data/2.5/air_pollution": (200, owAir),
        ]))
        let s = try await c.snapshot(latitude: 1, longitude: 2)
        XCTAssertEqual(s.airSource, "openweather"); XCTAssertEqual(s.feelsLikeC, 37.6)
    }

    func testNoKeyAndNoDataAreDistinct() async {
        do { _ = try await EnvironmentClient(openWeatherKey: " ", iqAirKey: nil, transport: transport(Log(), [:])).snapshot(latitude: 0, longitude: 0); XCTFail() }
        catch { XCTAssertEqual(error as? EnvironmentClient.Failure, .noKey) }
        do { _ = try await EnvironmentClient(openWeatherKey: "k", iqAirKey: nil, transport: transport(Log(), [:])).snapshot(latitude: 0, longitude: 0); XCTFail() }
        catch { XCTAssertEqual(error as? EnvironmentClient.Failure, .http(.openWeather, 404)) }
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let s = EnvironmentSnapshot(ts: 5, place: "X", tempC: 30, feelsLikeC: 35, usAqi: 90, airSource: "iqair", forecast: [.init(ts: 9, feelsLikeC: 28, rainChance: 0.2)])
        XCTAssertEqual(try JSONDecoder().decode(EnvironmentSnapshot.self, from: JSONEncoder().encode(s)), s)
    }
}
