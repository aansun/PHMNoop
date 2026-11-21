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

    func testTheDayIsSplitIntoPartsInTheOrderTheyCome() throws {
        let o = try XCTUnwrap(EnvironmentOutlook.make(hotDay(), calendar: utc))
        // 06, 09 morning; 12 noon; 15 afternoon; 18, 21 evening; 00, 03 night; 06 morning again.
        XCTAssertEqual(o.slots.map(\.part), [.morning, .noon, .afternoon, .evening, .night, .morning])
        XCTAssertEqual(o.slots[0].feelsLikeC, 28, accuracy: 0.001)
        XCTAssertEqual(o.slots[2].rainChance, 0.5)
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

    func testTheLoadFollowsTheStrainBandAndRecovery() {
        XCTAssertEqual(TrainingLoad.of(recoveryPct: 90, targetHigh: 18, soFar: 4), .hard)
        XCTAssertEqual(TrainingLoad.of(recoveryPct: 55, targetHigh: 13, soFar: nil), .moderate)
        XCTAssertEqual(TrainingLoad.of(recoveryPct: 40, targetHigh: 9, soFar: nil), .easy)
        XCTAssertEqual(TrainingLoad.of(recoveryPct: 90, targetHigh: 18, soFar: 17.8), .recover)   // the band is used up
        XCTAssertEqual(TrainingLoad.of(recoveryPct: 20, targetHigh: 18, soFar: nil), .easy)        // a red day caps it
        XCTAssertEqual(TrainingLoad.of(recoveryPct: 80, targetHigh: nil, soFar: nil), .hard)
        XCTAssertEqual(TrainingLoad.of(recoveryPct: nil, targetHigh: nil, soFar: nil), .moderate)
    }

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

    private func cleanMorning(aqi: Int = 40, feels: Double = 24) -> (EnvironmentSnapshot, EnvironmentOutlook) {
        let t0 = 1_800_000_000 - 1_800_000_000 % 86_400 + 5 * 3600
        let s = EnvironmentSnapshot(ts: t0, tempC: feels, feelsLikeC: feels, humidityPct: 50,
                                    forecast: (0..<9).map { .init(ts: t0 + $0 * 3 * 3600, feelsLikeC: feels, rainChance: 0) },
                                    airForecast: (0..<28).map { .init(ts: t0 + $0 * 3600, usAqi: aqi) })
        return (s, EnvironmentOutlook.make(s, calendar: utc)!)
    }

    func testAHardDayWithGoodConditionsIsSpentOutdoors() {
        let (s, o) = cleanMorning()
        let picks = EnvironmentTraining.picks(s, outlook: o, load: .hard)
        XCTAssertEqual(picks.first?.kind, .intervalRun)
        XCTAssertEqual(picks.first?.outdoors, true)
        XCTAssertNotNil(picks.first?.window)
        XCTAssertTrue(picks.first?.whys.contains(.fitsTarget) == true)
    }

    func testBadAirTakesEveryPickIndoors() {
        let (s, o) = cleanMorning(aqi: 170)
        for load in [TrainingLoad.recover, .easy, .moderate, .hard] {
            let picks = EnvironmentTraining.picks(s, outlook: o, load: load)
            XCTAssertFalse(picks.isEmpty)
            XCTAssertTrue(picks.allSatisfy { !$0.outdoors }, "\(load)")
        }
        XCTAssertTrue(EnvironmentTraining.picks(s, outlook: o, load: .hard).first?.whys.contains(.airTooPoor(usAqi: 170)) == true)
    }

    func testARecoverDayIsAWalkAndMobilityNotARun() {
        let (s, o) = cleanMorning()
        let kinds = EnvironmentTraining.picks(s, outlook: o, load: .recover).map(\.kind)
        XCTAssertEqual(kinds, [.easyWalk, .mobility, .breathwork])
    }

    func testHeatShortensAnOutdoorSession() {
        let (cool, oc) = cleanMorning(feels: 22)
        let (hot, oh) = cleanMorning(feels: 33)
        let a = EnvironmentTraining.picks(cool, outlook: oc, load: .moderate).first!
        let b = EnvironmentTraining.picks(hot, outlook: oh, load: .moderate).first!
        XCTAssertEqual(a.kind, .run); XCTAssertEqual(b.kind, .run)
        XCTAssertLessThan(b.minutes, a.minutes)
        XCTAssertTrue(b.whys.contains(.shortenedForHeat))
    }

    func testAnActivityForTodayIsPlannedInTodaysHoursNotTomorrowsMorning() throws {
        let t0 = 1_800_000_000 - 1_800_000_000 % 86_400 + 20 * 3600   // 20:00 UTC
        let feels: [Double] = [30, 28, 26, 24, 24]
        let s = EnvironmentSnapshot(ts: t0, tempC: 30, feelsLikeC: 30,
                                    forecast: feels.indices.map { .init(ts: t0 + $0 * 3 * 3600, feelsLikeC: feels[$0], rainChance: 0) })
        let o = try XCTUnwrap(EnvironmentOutlook.make(s, calendar: utc))
        XCTAssertNotEqual(o.best?.start, o.bestToday?.start)   // the kindest hours are tomorrow's
        let pick = try XCTUnwrap(EnvironmentTraining.picks(s, outlook: o, load: .moderate).first)
        XCTAssertEqual(pick.window?.start, o.bestToday?.start)
    }

    func testNoReasonIsListedTwice() {
        let (s, o) = cleanMorning(aqi: 170)
        for load in [TrainingLoad.recover, .easy, .moderate, .hard] {
            for p in EnvironmentTraining.picks(s, outlook: o, load: load) {
                XCTAssertEqual(p.whys.count, Set(p.whys.map { "\($0)" }).count, "\(load) \(p.kind)")
            }
        }
    }

    func testNoForecastMeansIndoorPicks() {
        let s = EnvironmentSnapshot(ts: 5, tempC: 25, feelsLikeC: 25)
        XCTAssertTrue(EnvironmentTraining.picks(s, outlook: nil, load: .moderate).allSatisfy { !$0.outdoors })
    }

    func testNoForecastNoOutlook() {
        XCTAssertNil(EnvironmentOutlook.make(EnvironmentSnapshot(ts: 5, tempC: 30), calendar: utc))
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let s = EnvironmentSnapshot(ts: 5, place: "X", tempC: 30, feelsLikeC: 35, usAqi: 90, airSource: "iqair", forecast: [.init(ts: 9, feelsLikeC: 28, rainChance: 0.2)])
        XCTAssertEqual(try JSONDecoder().decode(EnvironmentSnapshot.self, from: JSONEncoder().encode(s)), s)
    }
}
