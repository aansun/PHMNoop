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
        XCTAssertFalse(log.calls.contains { $0.path == "/data/2.5/air_pollution" })   // IQAir answered, so no second request for the air now
    }

    /// IQAir answers with its nearest city. A station tens of kilometres away is not the air here, so OpenWeather's reading at the exact place stands in;
    /// a station close by is taken, and one that sends no coordinates is taken as before.
    func testAFarIQAirStationIsLeftOutAndANearOneIsKept() async throws {
        func body(lon: Double, lat: Double) -> String {
            #"{"status":"success","data":{"city":"Far","location":{"type":"Point","coordinates":["# + "\(lon),\(lat)" + #"]},"current":{"pollution":{"aqius":132,"mainus":"p2"},"weather":{"tp":30,"hu":70,"ws":3.1}}}}"#
        }
        let routes: (String) -> [String: (Int, String)] = { iq in
            ["api.openweathermap.org/data/2.5/weather": (200, self.owNow), "api.openweathermap.org/data/2.5/air_pollution": (200, self.owAir),
             "api.airvisual.com/v2/nearest_city": (200, iq)]
        }
        // About 100 km east of the place asked.
        let far = try await EnvironmentClient(openWeatherKey: "ow", iqAirKey: "iq", transport: transport(Log(), routes(body(lon: 1.9, lat: 0.0))))
            .snapshot(latitude: 0.0, longitude: 1.0)
        XCTAssertEqual(far.airSource, "openweather"); XCTAssertEqual(far.usAqi, AirQuality.usAqi(pm25: 40.2))
        // About 3 km away.
        let near = try await EnvironmentClient(openWeatherKey: "ow", iqAirKey: "iq", transport: transport(Log(), routes(body(lon: 1.03, lat: 0.0))))
            .snapshot(latitude: 0.0, longitude: 1.0)
        XCTAssertEqual(near.airSource, "iqair"); XCTAssertEqual(near.usAqi, 132)
        XCTAssertEqual(EnvironmentClient.distanceKm(lat1: 0, lon1: 0, lat2: 0, lon2: 1).rounded(), 111)
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

    private let owForecast9 = #"{"list":[{"dt":1000100,"main":{"feels_like":36.0,"temp":33.0},"wind":{"speed":3.5},"weather":[{"id":500}],"pop":0.6},{"dt":1010900,"main":{"feels_like":29.5,"temp":28.0},"pop":0.05}]}"#
    private let owAirForecast = #"{"list":[{"dt":1000200,"components":{"pm2_5":40.2}},{"dt":1003800,"components":{"pm2_5":8.0}},{"dt":2000000,"components":{"pm2_5":8.0}}]}"#

    func testTheForecastCarriesTempWindSkyAndTheAirForTheNextHours() async throws {
        let c = EnvironmentClient(openWeatherKey: "ow", iqAirKey: "iq", transport: transport(Log(), [
            "api.openweathermap.org/data/2.5/weather": (200, owNow), "api.openweathermap.org/data/2.5/forecast": (200, owForecast9),
            "api.openweathermap.org/data/2.5/air_pollution/forecast": (200, owAirForecast), "api.airvisual.com/v2/nearest_city": (200, iqAir),
        ]))
        let s = try await c.snapshot(latitude: 1, longitude: 2, now: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(s.forecast.first?.tempC, 33.0); XCTAssertEqual(s.forecast.first?.windMps, 3.5); XCTAssertEqual(s.forecast.first?.conditionId, 500)
        XCTAssertNil(s.forecast.last?.windMps)
        // Two hours inside the next 28 hours; the one days away is left out. The reading now still comes from IQAir.
        XCTAssertEqual(s.airForecast.map(\.usAqi), [AirQuality.usAqi(pm25: 40.2)!, AirQuality.usAqi(pm25: 8.0)!])
        XCTAssertEqual(s.usAqi, 132); XCTAssertEqual(s.airSource, "iqair")
    }

    func testAReadingSavedBeforeTheAirForecastStillDecodes() throws {
        let old = #"{"ts":5,"place":"X","tempC":30,"usAqi":90,"forecast":[{"ts":9,"feelsLikeC":28,"rainChance":0.2}]}"#
        let s = try JSONDecoder().decode(EnvironmentSnapshot.self, from: Data(old.utf8))
        XCTAssertEqual(s.forecast.count, 1); XCTAssertNil(s.forecast[0].tempC); XCTAssertTrue(s.airForecast.isEmpty)
    }

    // MARK: Outlook

    /// Nine 3-hourly steps from 06:00 UTC on a hot day.
    private func hotDay(air: [EnvironmentSnapshot.AirHour] = []) -> EnvironmentSnapshot {
        let t0 = 1_800_000_000 - 1_800_000_000 % 86_400 + 6 * 3600
        let feels: [Double] = [26, 30, 36, 37, 33, 29, 27, 26, 26]
        let rain: [Double] = [0, 0, 0.1, 0.5, 0.2, 0, 0, 0, 0]
        return EnvironmentSnapshot(ts: t0, tempC: 25, feelsLikeC: 26,
                                   forecast: feels.indices.map { .init(ts: t0 + $0 * 3 * 3600, feelsLikeC: feels[$0], rainChance: rain[$0]) }, airForecast: air)
    }

    func testTheDayIsFourSessionsInTheOrderTheyCome() throws {
        let o = try XCTUnwrap(EnvironmentOutlook.make(hotDay(), calendar: utc))
        // From 06:00: the morning is under way, then the afternoon (12, 15), the evening (18, 21) and the night (00, 03).
        XCTAssertEqual(o.slots.map(\.part), [.morning, .afternoon, .evening, .night])
        XCTAssertTrue(o.slots[0].isCurrent); XCTAssertFalse(o.slots[1].isCurrent)
        XCTAssertEqual(o.slots[0].start, hotDay().ts)                       // the one under way starts now
        XCTAssertEqual(o.slots[0].end - hotDay().ts, 5 * 3600)               // and ends when the afternoon begins, at 11:00
        XCTAssertEqual(o.slots[1].rainChance, 0.5)
        XCTAssertEqual(o.slots[1].peakFeelsLikeC, 37)
        // No step of this fixture has an air temperature, so the range is the feel's: the afternoon runs 36 to 37 (steps at 12:00 and 15:00).
        XCTAssertEqual(o.slots[1].lowC, 36); XCTAssertEqual(o.slots[1].highC, 37)
    }

    func testEachSessionSaysIfItSuitsTimeOutdoorsAndWhatIsInTheWay() throws {
        let o = try XCTUnwrap(EnvironmentOutlook.make(hotDay(), calendar: utc))
        XCTAssertEqual(o.slots[0].fit, .good)            // 26 to 30 and dry
        XCTAssertEqual(o.slots[0].reasons, [])
        XCTAssertEqual(o.slots[1].fit, .adjust)          // a peak of 37 and a 50% chance of rain
        XCTAssertTrue(o.slots[1].reasons.contains(.hot(feelsLikeC: 37)))
        XCTAssertTrue(o.slots[1].rainLikely)
        XCTAssertEqual(o.slots[3].fit, .good)
        // Dirty air makes the session one to spend indoors, and is the first thing named.
        let t0 = hotDay().ts
        var s = hotDay(air: (0..<28).map { .init(ts: t0 + $0 * 3600, usAqi: 170) }); s.usAqi = 170
        let dirty = try XCTUnwrap(EnvironmentOutlook.make(s, calendar: utc))
        XCTAssertTrue(dirty.slots.allSatisfy { $0.fit == .indoors })
        if case .air(let aqi, _)? = dirty.slots[0].reasons.first { XCTAssertEqual(aqi, 170) } else { XCTFail("the air should lead") }
    }

    func testTheBestStretchIsTheCoolDryCleanOne_andTheAirCanMoveIt() throws {
        let clean = try XCTUnwrap(EnvironmentOutlook.make(hotDay(), calendar: utc))
        XCTAssertEqual(clean.best?.start, hotDay().ts)   // 06:00 feels 26 and the air is fine
        // Dirty air at 06:00 and clean in every hour after it takes the best stretch off 06:00, onto an hour with clean air.
        let t0 = hotDay().ts
        let air: [EnvironmentSnapshot.AirHour] = (0..<9).map { .init(ts: t0 + $0 * 3 * 3600, usAqi: $0 == 0 ? 160 : 45) }
        var s = hotDay(air: air); s.usAqi = 160
        let moved = try XCTUnwrap(EnvironmentOutlook.make(s, calendar: utc))
        XCTAssertNotEqual(moved.best?.start, t0)
        XCTAssertEqual(moved.best?.usAqi, 45)
    }

    // MARK: Training

    func testEachStepIsGradedForTimeOutdoors() throws {
        let o = try XCTUnwrap(EnvironmentOutlook.make(hotDay(), calendar: utc))
        // 06:00 feels 26 (good), 15:00 feels 37 with rain 0.5 (adjust), nothing hits the indoor mark.
        XCTAssertEqual(o.steps.first?.fit, .good)
        XCTAssertEqual(o.steps.count, 9)
        XCTAssertTrue(o.steps.contains { $0.fit == .adjust })
        XCTAssertEqual(OutdoorFit.of(feelsLikeC: 39, humidityPct: 50, usAqi: 40, rainChance: 0, windMps: 1, conditionId: 800), .indoors)
        XCTAssertEqual(OutdoorFit.of(feelsLikeC: 22, humidityPct: 50, usAqi: 170, rainChance: 0, windMps: 1, conditionId: 800), .indoors)
        XCTAssertEqual(OutdoorFit.of(feelsLikeC: 22, humidityPct: 50, usAqi: 120, rainChance: 0, windMps: 1, conditionId: 800), .adjust)
        XCTAssertEqual(OutdoorFit.of(feelsLikeC: 22, humidityPct: 50, usAqi: 40, rainChance: 0.1, windMps: 1, conditionId: 800), .good)
    }

    func testTheForecastIsSummedUpDayByDay() throws {
        // Three days of 3-hourly steps from 06:00 UTC: each day has a low, a high, a sky and the worst air of it.
        let t0 = 1_800_000_000 - 1_800_000_000 % 86_400 + 6 * 3600
        var steps: [EnvironmentSnapshot.Hour] = []
        for k in 0..<22 {
            let ts = t0 + k * 3 * 3600
            let hourOfDay = (ts % 86_400) / 3600
            let temp = 22.0 + (hourOfDay >= 9 && hourOfDay <= 15 ? 8 : 0)
            // The second day is wet from 12:00 to 18:00.
            let day = (ts - (t0 - 6 * 3600)) / 86_400
            let wet = day == 1 && (12...18).contains(hourOfDay)
            steps.append(.init(ts: ts, feelsLikeC: temp + 2, rainChance: wet ? 0.7 : 0, tempC: temp, conditionId: wet ? 501 : 800))
        }
        let air = (0..<96).map { EnvironmentSnapshot.AirHour(ts: t0 + $0 * 3600, usAqi: $0 < 24 ? 120 : 60) }
        let s = EnvironmentSnapshot(ts: t0, tempC: 24, feelsLikeC: 26, usAqi: 120, forecast: steps, airForecast: air)
        let o = try XCTUnwrap(EnvironmentOutlook.make(s, calendar: utc))
        XCTAssertEqual(o.days.count, 3)
        XCTAssertEqual(o.days[0].lowC, 22); XCTAssertEqual(o.days[0].highC, 30)
        XCTAssertEqual(o.days[0].conditionId, 800)
        XCTAssertEqual(o.days[1].conditionId, 501)          // the wet afternoon names the day
        XCTAssertEqual(o.days[1].rainChance, 0.7)
        XCTAssertEqual(o.days[0].usAqi, 120)                // the worst air of the day
        XCTAssertEqual(o.days[2].usAqi, 60)
        XCTAssertEqual(o.days[1].start - o.days[0].start, 86_400)
        XCTAssertEqual(o.days[0].peakFeelsLikeC, 32)         // the feel runs two above the air in this fixture
    }

    func testNoForecastNoOutlook() {
        XCTAssertNil(EnvironmentOutlook.make(EnvironmentSnapshot(ts: 5, tempC: 30), calendar: utc))
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let s = EnvironmentSnapshot(ts: 5, place: "X", tempC: 30, feelsLikeC: 35, usAqi: 90, airSource: "iqair", forecast: [.init(ts: 9, feelsLikeC: 28, rainChance: 0.2)])
        XCTAssertEqual(try JSONDecoder().decode(EnvironmentSnapshot.self, from: JSONEncoder().encode(s)), s)
    }
}
