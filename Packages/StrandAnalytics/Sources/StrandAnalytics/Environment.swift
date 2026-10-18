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
        public init(ts: Int, feelsLikeC: Double, rainChance: Double) { self.ts = ts; self.feelsLikeC = feelsLikeC; self.rainChance = rainChance }
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

    public init(ts: Int, place: String? = nil, tempC: Double? = nil, feelsLikeC: Double? = nil, humidityPct: Double? = nil,
                windMps: Double? = nil, conditionId: Int? = nil, conditionText: String? = nil, usAqi: Int? = nil, pm25: Double? = nil,
                airSource: String? = nil, forecast: [Hour] = []) {
        self.ts = ts; self.place = place; self.tempC = tempC; self.feelsLikeC = feelsLikeC; self.humidityPct = humidityPct
        self.windMps = windMps; self.conditionId = conditionId; self.conditionText = conditionText; self.usAqi = usAqi
        self.pm25 = pm25; self.airSource = airSource; self.forecast = forecast
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
