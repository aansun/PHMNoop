import Foundation

// Environment.swift - the weather and the air around an outdoor session, and what they mean for it.
//
// A snapshot is what OpenWeather and IQAir answered for one place at one moment. The advice is arithmetic over it: how hot it feels,
// how clean the air is, whether it is storming. Pure and Foundation-only, so it runs in tests against fixed figures; the sentences are
// composed in the app layer, where they are localised. Nothing here reaches the network (see `EnvironmentClient`).
//
// HONESTY. The advice names a cause only as far as the numbers go and gives no verdict without them. It is general guidance for a
// healthy adult, not medical advice; the US AQI bands are the ones the EPA publishes.

public struct EnvironmentSnapshot: Codable, Equatable, Sendable {
    /// One step of the short forecast that follows the reading (3-hourly).
    public struct Hour: Codable, Equatable, Sendable {
        public var ts: Int
        public var feelsLikeC: Double
        /// Chance of rain, 0...1.
        public var rainChance: Double
        /// What the step carries beyond the feel and the rain. Optional, so a reading saved before they existed still decodes.
        public var tempC: Double?
        public var windMps: Double?
        public var conditionId: Int?
        public init(ts: Int, feelsLikeC: Double, rainChance: Double, tempC: Double? = nil, windMps: Double? = nil, conditionId: Int? = nil) {
            self.ts = ts; self.feelsLikeC = feelsLikeC; self.rainChance = rainChance
            self.tempC = tempC; self.windMps = windMps; self.conditionId = conditionId
        }
    }

    /// One hour of the air forecast: the US AQI worked out from the forecast PM2.5.
    public struct AirHour: Codable, Equatable, Sendable {
        public var ts: Int
        public var usAqi: Int
        public init(ts: Int, usAqi: Int) { self.ts = ts; self.usAqi = usAqi }
    }

    /// Unix seconds the figures were read at.
    public var ts: Int
    public var place: String?
    public var tempC: Double?
    public var feelsLikeC: Double?
    public var humidityPct: Double?
    public var windMps: Double?
    /// OpenWeather condition code (2xx storm, 3xx drizzle, 5xx rain, 6xx snow, 7xx haze or dust, 800 clear, 80x clouds).
    public var conditionId: Int?
    public var conditionText: String?
    /// US AQI (0-500) and the PM2.5 behind it, in micrograms per cubic metre.
    public var usAqi: Int?
    public var pm25: Double?
    /// Who the air figures came from: "iqair" or "openweather".
    public var airSource: String?
    public var forecast: [Hour]
    /// The air for the next hours, hour by hour (OpenWeather's air-pollution forecast). Empty when there is no OpenWeather key.
    public var airForecast: [AirHour]

    public init(ts: Int, place: String? = nil, tempC: Double? = nil, feelsLikeC: Double? = nil, humidityPct: Double? = nil,
                windMps: Double? = nil, conditionId: Int? = nil, conditionText: String? = nil, usAqi: Int? = nil, pm25: Double? = nil,
                airSource: String? = nil, forecast: [Hour] = [], airForecast: [AirHour] = []) {
        self.ts = ts; self.place = place; self.tempC = tempC; self.feelsLikeC = feelsLikeC; self.humidityPct = humidityPct
        self.windMps = windMps; self.conditionId = conditionId; self.conditionText = conditionText; self.usAqi = usAqi
        self.pm25 = pm25; self.airSource = airSource; self.forecast = forecast; self.airForecast = airForecast
    }

    // A reading saved before the air forecast existed has no such key: it decodes as no forecast, not as an error.
    private enum CodingKeys: String, CodingKey {
        case ts, place, tempC, feelsLikeC, humidityPct, windMps, conditionId, conditionText, usAqi, pm25, airSource, forecast, airForecast
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ts = try c.decode(Int.self, forKey: .ts)
        place = try c.decodeIfPresent(String.self, forKey: .place)
        tempC = try c.decodeIfPresent(Double.self, forKey: .tempC)
        feelsLikeC = try c.decodeIfPresent(Double.self, forKey: .feelsLikeC)
        humidityPct = try c.decodeIfPresent(Double.self, forKey: .humidityPct)
        windMps = try c.decodeIfPresent(Double.self, forKey: .windMps)
        conditionId = try c.decodeIfPresent(Int.self, forKey: .conditionId)
        conditionText = try c.decodeIfPresent(String.self, forKey: .conditionText)
        usAqi = try c.decodeIfPresent(Int.self, forKey: .usAqi)
        pm25 = try c.decodeIfPresent(Double.self, forKey: .pm25)
        airSource = try c.decodeIfPresent(String.self, forKey: .airSource)
        forecast = try c.decodeIfPresent([Hour].self, forKey: .forecast) ?? []
        airForecast = try c.decodeIfPresent([AirHour].self, forKey: .airForecast) ?? []
    }

    /// The figure a body reacts to: the feels-like temperature, otherwise the air temperature.
    public var effectiveC: Double? { feelsLikeC ?? tempC }
    public var hasWeather: Bool { tempC != nil || feelsLikeC != nil }
    public var hasAir: Bool { usAqi != nil }
}

// MARK: - Air quality

public enum AirQuality {
    public enum Band: Int, Equatable, Sendable, Comparable {
        case good, moderate, unhealthyForSensitive, unhealthy, veryUnhealthy, hazardous
        public static func < (a: Band, b: Band) -> Bool { a.rawValue < b.rawValue }
    }

    public static func band(usAqi: Int) -> Band {
        switch usAqi {
        case ..<51: return .good
        case 51...100: return .moderate
        case 101...150: return .unhealthyForSensitive
        case 151...200: return .unhealthy
        case 201...300: return .veryUnhealthy
        default: return .hazardous
        }
    }

    /// US AQI from a PM2.5 reading (EPA breakpoints, 2024), for when only the particle count is known.
    public static func usAqi(pm25: Double) -> Int? {
        guard pm25.isFinite, pm25 >= 0 else { return nil }
        let c = (min(pm25, 500.4) * 10).rounded(.down) / 10
        // (concentration low, high, index low, high)
        let table: [(Double, Double, Double, Double)] = [
            (0, 9.0, 0, 50), (9.1, 35.4, 51, 100), (35.5, 55.4, 101, 150), (55.5, 125.4, 151, 200),
            (125.5, 225.4, 201, 300), (225.5, 500.4, 301, 500),
        ]
        guard let row = table.first(where: { c <= $0.1 }) ?? table.last else { return nil }
        return Int(((row.3 - row.2) / (row.1 - row.0) * (c - row.0) + row.2).rounded())
    }
}

// MARK: - Advice

public struct EnvironmentAdvice: Equatable, Sendable {
    public enum Level: Int, Equatable, Sendable, Comparable {
        /// Nothing in the way.
        case good
        /// Go, but shorter, easier or at another time.
        case adjust
        /// Better indoors today.
        case indoors
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Reason: Equatable, Sendable {
        case veryHot(feelsLikeC: Double)
        case hot(feelsLikeC: Double)
        case cold(feelsLikeC: Double)
        case freezing(feelsLikeC: Double)
        case air(usAqi: Int, band: AirQuality.Band)
        case storm
        case rain
        case wind(mps: Double)
    }

    public let level: Level
    public let reasons: [Reason]
    /// A cooler stretch within the next 12 hours (unix seconds, feels-like) when it is hot now and the later hour is clearly kinder.
    public let cooler: (ts: Int, feelsLikeC: Double)?

    public static func == (a: EnvironmentAdvice, b: EnvironmentAdvice) -> Bool {
        a.level == b.level && a.reasons == b.reasons && a.cooler?.ts == b.cooler?.ts && a.cooler?.feelsLikeC == b.cooler?.feelsLikeC
    }

    static let veryHotC = 38.0, hotC = 33.0, coldC = 5.0, freezingC = -10.0, windMps = 12.0

    /// `hours` is the stretch of the local day worth offering for a session (a cooler 23:00 is no use to anyone).
    public static func analyze(_ s: EnvironmentSnapshot, calendar: Calendar = .current, hours: ClosedRange<Int> = 5...21) -> EnvironmentAdvice? {
        guard s.hasWeather || s.hasAir else { return nil }
        var level = Level.good
        var reasons: [Reason] = []
        func raise(_ l: Level) { if l > level { level = l } }

        if let t = s.effectiveC {
            // Humid air holds heat in: from 30 degrees with a lot of moisture it already counts as hot.
            let humidHot = t >= 30 && (s.humidityPct ?? 0) >= 70
            if t >= veryHotC { reasons.append(.veryHot(feelsLikeC: t)); raise(.indoors) }
            else if t >= hotC || humidHot { reasons.append(.hot(feelsLikeC: t)); raise(.adjust) }
            else if t <= freezingC { reasons.append(.freezing(feelsLikeC: t)); raise(.indoors) }
            else if t <= coldC { reasons.append(.cold(feelsLikeC: t)); raise(.adjust) }
        }
        if let aqi = s.usAqi {
            let band = AirQuality.band(usAqi: aqi)
            switch band {
            case .good, .moderate: break
            case .unhealthyForSensitive: reasons.append(.air(usAqi: aqi, band: band)); raise(.adjust)
            default: reasons.append(.air(usAqi: aqi, band: band)); raise(.indoors)
            }
        }
        if let id = s.conditionId {
            if (200..<300).contains(id) { reasons.append(.storm); raise(.indoors) }
            else if (300..<600).contains(id) { reasons.append(.rain); raise(.adjust) }
        }
        if let w = s.windMps, w >= windMps { reasons.append(.wind(mps: w)); raise(.adjust) }

        // A kinder hour later today, only worth saying when it is hot now.
        var cooler: (Int, Double)?
        if let now = s.effectiveC, now >= hotC - 2 {
            let horizon = s.ts + 12 * 3600
            let best = s.forecast.filter {
                $0.ts > s.ts && $0.ts <= horizon && $0.rainChance < 0.4
                    && hours.contains(calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval($0.ts))))
            }
                .min { $0.feelsLikeC < $1.feelsLikeC }
            if let best, now - best.feelsLikeC >= 3 { cooler = (best.ts, best.feelsLikeC) }
        }
        return EnvironmentAdvice(level: level, reasons: reasons, cooler: cooler)
    }
}

// MARK: - The day ahead

/// The next 24 hours in five parts of the day, and the best stretch of them for a session: what the card and the page about the weather and the
/// air show. Pure arithmetic over a snapshot's forecast; it says nothing the forecast does not.
public struct EnvironmentOutlook: Equatable, Sendable {
    public enum Part: Int, CaseIterable, Sendable {
        case morning, noon, afternoon, evening, night

        /// Morning 5-11, noon 11-15, afternoon 15-18, evening 18-22, night 22-5 (local hours).
        public static func of(hour: Int) -> Part {
            switch hour {
            case 5..<11: return .morning
            case 11..<15: return .noon
            case 15..<18: return .afternoon
            case 18..<22: return .evening
            default: return .night
            }
        }
    }

    public struct Slot: Equatable, Sendable, Identifiable {
        public var id: Int { start }
        public let part: Part
        /// Unix seconds of the first forecast step in this part.
        public let start: Int
        public let feelsLikeC: Double
        public let rainChance: Double
        public let usAqi: Int?
        public let conditionId: Int?
    }

    public struct Window: Equatable, Sendable {
        public let start: Int
        public let end: Int
        public let feelsLikeC: Double
        public let usAqi: Int?
        public let rainChance: Double
        public let windMps: Double?
        public let conditionId: Int?
    }

    /// One 3-hour step of the forecast with how well it suits time outdoors: what the timeline draws.
    public struct Step: Equatable, Sendable, Identifiable {
        public var id: Int { ts }
        public let ts: Int
        public let feelsLikeC: Double
        public let rainChance: Double
        public let usAqi: Int?
        public let fit: OutdoorFit
    }

    /// The parts of the coming 24 hours, in the order they come.
    public let slots: [Slot]
    /// Every 3-hour step of the coming 24 hours, in order, each with how well it suits time outdoors.
    public let steps: [Step]
    /// The kindest 3-hour stretch between 05:00 and 21:00 in the coming day, when the forecast has one (it can be tomorrow morning).
    public let best: Window?
    /// The same, but only within today's own hours: what an activity chosen for today can be planned in.
    public let bestToday: Window?

    /// The air at a moment: the hourly forecast's nearest hour, within 90 minutes; else the reading when it is that close.
    public static func usAqi(at ts: Int, in s: EnvironmentSnapshot) -> Int? {
        if let h = s.airForecast.min(by: { abs($0.ts - ts) < abs($1.ts - ts) }), abs(h.ts - ts) <= 5400 { return h.usAqi }
        if let aqi = s.usAqi, abs(s.ts - ts) <= 5400 { return aqi }
        return nil
    }

    public static func make(_ s: EnvironmentSnapshot, calendar: Calendar = .current, now: Int? = nil) -> EnvironmentOutlook? {
        let from = now ?? s.ts
        let steps = s.forecast.filter { $0.ts >= from - 3600 && $0.ts <= from + 24 * 3600 }.sorted { $0.ts < $1.ts }
        guard !steps.isEmpty else { return nil }
        func hour(_ ts: Int) -> Int { calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(ts))) }

        // Group the steps by part of day, keeping the order the parts first come in (a part that returns after a night is a different slot).
        var groups: [(Part, [EnvironmentSnapshot.Hour])] = []
        for step in steps {
            let p = Part.of(hour: hour(step.ts))
            if let last = groups.last, last.0 == p { groups[groups.count - 1].1.append(step) } else { groups.append((p, [step])) }
        }
        let slots: [Slot] = groups.map { part, hs in
            let feels = hs.map(\.feelsLikeC).reduce(0, +) / Double(hs.count)
            let aqis = hs.compactMap { usAqi(at: $0.ts, in: s) }
            // The sky of the part is the one of its wettest step.
            let sky = hs.max { $0.rainChance < $1.rainChance }?.conditionId ?? hs.first?.conditionId
            return Slot(part: part, start: hs[0].ts, feelsLikeC: feels, rainChance: hs.map(\.rainChance).max() ?? 0, usAqi: aqis.max(), conditionId: sky)
        }

        // The kindest step to be out in: not hot or cold, clean air, dry.
        func score(_ h: EnvironmentSnapshot.Hour) -> Double {
            let t = h.feelsLikeC
            var x = max(0, t - 20) * 1.0 + max(0, 10 - t) * 0.6
            if let aqi = usAqi(at: h.ts, in: s) { x += Double(max(0, aqi - 50)) * 0.12 }
            x += h.rainChance * 12
            if let w = h.windMps, w > 8 { x += (w - 8) * 0.8 }
            if let id = h.conditionId, (200..<300).contains(id) { x += 40 }
            return x
        }
        // The coming 21 hours, so a morning a day away does not beat every hour of today.
        let candidates = steps.filter { $0.ts >= from && $0.ts <= from + 21 * 3600 && (5...21).contains(hour($0.ts)) }
        func window(_ h: EnvironmentSnapshot.Hour) -> Window {
            Window(start: h.ts, end: h.ts + 3 * 3600, feelsLikeC: h.feelsLikeC, usAqi: usAqi(at: h.ts, in: s),
                   rainChance: h.rainChance, windMps: h.windMps, conditionId: h.conditionId)
        }
        let best = candidates.min { score($0) < score($1) }.map(window)
        let today = Date(timeIntervalSince1970: TimeInterval(from))
        let bestToday = candidates.filter { calendar.isDate(Date(timeIntervalSince1970: TimeInterval($0.ts)), inSameDayAs: today) }
            .min { score($0) < score($1) }.map(window)
        let timeline: [Step] = steps.map { h in
            let aqi = usAqi(at: h.ts, in: s)
            return Step(ts: h.ts, feelsLikeC: h.feelsLikeC, rainChance: h.rainChance, usAqi: aqi,
                        fit: OutdoorFit.of(feelsLikeC: h.feelsLikeC, humidityPct: s.humidityPct, usAqi: aqi, rainChance: h.rainChance, windMps: h.windMps, conditionId: h.conditionId))
        }
        return EnvironmentOutlook(slots: slots, steps: timeline, best: best, bestToday: bestToday)
    }
}
