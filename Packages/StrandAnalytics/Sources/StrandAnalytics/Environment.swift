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
        public var humidityPct: Double?
        public init(ts: Int, feelsLikeC: Double, rainChance: Double, tempC: Double? = nil, windMps: Double? = nil, conditionId: Int? = nil, humidityPct: Double? = nil) {
            self.ts = ts; self.feelsLikeC = feelsLikeC; self.rainChance = rainChance
            self.tempC = tempC; self.windMps = windMps; self.conditionId = conditionId; self.humidityPct = humidityPct
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

/// The next 24 hours in four sessions of the day, and the best stretch of them for a session: what the card and the page about the weather and the
/// air show. Pure arithmetic over a snapshot's forecast; it says nothing the forecast does not.
public struct EnvironmentOutlook: Equatable, Sendable {
    public enum Part: Int, CaseIterable, Sendable {
        case morning, afternoon, evening, night

        /// Morning 5-11, afternoon 11-17, evening 17-22, night 22-5 (local hours).
        public static func of(hour: Int) -> Part {
            switch hour {
            case 5..<11: return .morning
            case 11..<17: return .afternoon
            case 17..<22: return .evening
            default: return .night
            }
        }

        /// The hour each session starts at.
        public static let startHours = [5, 11, 17, 22]
    }

    /// One session of the day with everything the panel says about it and whether it suits time outdoors.
    public struct Slot: Equatable, Sendable, Identifiable {
        public var id: Int { start }
        public let part: Part
        /// Unix seconds: when the session starts (for the one under way, now) and when it ends.
        public let start: Int
        public let end: Int
        /// True for the session that is under way.
        public let isCurrent: Bool
        public let tempC: Double?
        /// The feel across the session, and its highest (what decides whether it is hot).
        public let feelsLikeC: Double
        public let peakFeelsLikeC: Double
        /// The lowest and the highest air temperature across the session (the feel, where a step has no air temperature).
        public let lowC: Double
        public let highC: Double
        public let rainChance: Double
        public let windMps: Double?
        public let humidityPct: Double?
        public let usAqi: Int?
        public let conditionId: Int?
        public let fit: OutdoorFit
        /// What is in the way of time outdoors in this session, the worst first; empty when nothing is.
        public let reasons: [EnvironmentAdvice.Reason]
        public let rainLikely: Bool
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

    /// One day of the forecast: its low and high, its sky and the air: what the daily forecast shows.
    public struct Day: Equatable, Sendable, Identifiable {
        public var id: Int { start }
        /// Unix seconds of the local midnight that starts the day.
        public let start: Int
        public let lowC: Double
        public let highC: Double
        public let conditionId: Int?
        public let rainChance: Double
        /// The worst air of the day, when the forecast covers it.
        public let usAqi: Int?
        /// The highest feel of the day, the average wind and humidity: what is said about the day beside its temperature.
        public let peakFeelsLikeC: Double
        public let windMps: Double?
        public let humidityPct: Double?
    }

    /// One 3-hour step of the forecast with how well it suits time outdoors: what the timeline draws.
    public struct Step: Equatable, Sendable, Identifiable {
        public var id: Int { ts }
        public let ts: Int
        public let feelsLikeC: Double
        public let tempC: Double?
        public let rainChance: Double
        public let conditionId: Int?
        public let usAqi: Int?
        public let fit: OutdoorFit
    }

    /// The parts of the coming 24 hours, in the order they come.
    public let slots: [Slot]
    /// Every 3-hour step of the coming 24 hours, in order, each with how well it suits time outdoors.
    public let steps: [Step]
    /// Today and the days after it (up to five), from the whole forecast.
    public let days: [Day]
    /// The kindest 3-hour stretch between 05:00 and 21:00 in the coming day, when the forecast has one (it can be tomorrow morning).
    public let best: Window?


    /// The air at a moment: the hourly forecast's nearest hour, within 90 minutes; else the reading when it is that close.
    public static func usAqi(at ts: Int, in s: EnvironmentSnapshot) -> Int? {
        if let h = s.airForecast.min(by: { abs($0.ts - ts) < abs($1.ts - ts) }), abs(h.ts - ts) <= 5400 { return h.usAqi }
        if let aqi = s.usAqi, abs(s.ts - ts) <= 5400 { return aqi }
        return nil
    }

    /// The worst first: a storm, then the air, then heat, then the rest.
    static func severity(_ r: EnvironmentAdvice.Reason) -> Int {
        switch r {
        case .storm: return 0
        case .air(_, let band): return band >= .unhealthy ? 1 : 3
        case .veryHot: return 1
        case .freezing: return 1
        case .hot: return 2
        case .cold: return 3
        case .rain: return 4
        case .wind: return 5
        }
    }

    public static func make(_ s: EnvironmentSnapshot, calendar: Calendar = .current, now: Int? = nil) -> EnvironmentOutlook? {
        let from = now ?? s.ts
        let steps = s.forecast.filter { $0.ts >= from - 3600 && $0.ts <= from + 24 * 3600 }.sorted { $0.ts < $1.ts }
        guard !steps.isEmpty else { return nil }
        func hour(_ ts: Int) -> Int { calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(ts))) }

        // The reading now is the first point of the session under way; every forecast step follows it. Group them by session, in the order they come (a session
        // that returns after a night is another slot, and only four are kept).
        var points: [EnvironmentSnapshot.Hour] = []
        if s.hasWeather {
            let rainNow = s.conditionId.map { (300..<600).contains($0) } == true ? 0.8 : 0.0
            points.append(.init(ts: from, feelsLikeC: s.effectiveC ?? 0, rainChance: rainNow, tempC: s.tempC, windMps: s.windMps, conditionId: s.conditionId, humidityPct: s.humidityPct))
        }
        points += steps.filter { $0.ts > from }
        var groups: [(Part, [EnvironmentSnapshot.Hour])] = []
        for point in points {
            let p = Part.of(hour: hour(point.ts))
            if let last = groups.last, last.0 == p { groups[groups.count - 1].1.append(point) } else { groups.append((p, [point])) }
        }
        func boundary(after ts: Int) -> Int {
            let date = Date(timeIntervalSince1970: TimeInterval(ts))
            let next = Part.startHours.compactMap { calendar.nextDate(after: date, matching: DateComponents(hour: $0, minute: 0, second: 0), matchingPolicy: .nextTime) }.min()
            return Int((next ?? date.addingTimeInterval(6 * 3600)).timeIntervalSince1970)
        }
        let currentPart = Part.of(hour: hour(from))
        let slots: [Slot] = groups.prefix(4).enumerated().map { i, g in
            let (part, hs) = g
            func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
            let feels = hs.map(\.feelsLikeC)
            let aqis = hs.compactMap { h in h.ts == from && h.ts == points.first?.ts ? (s.usAqi ?? usAqi(at: h.ts, in: s)) : usAqi(at: h.ts, in: s) }
            // The sky of the session is the one of its wettest step.
            let sky = hs.max { $0.rainChance < $1.rainChance }?.conditionId ?? hs.first?.conditionId
            let rain = hs.map(\.rainChance).max() ?? 0
            let peak = feels.max() ?? 0
            let wind = mean(hs.compactMap(\.windMps))
            let humidity = mean(hs.compactMap(\.humidityPct)) ?? s.humidityPct
            // What is in the way is read by the same rules as the advice, on the worst of the session.
            let probe = EnvironmentSnapshot(ts: hs[0].ts, tempC: mean(hs.compactMap(\.tempC)), feelsLikeC: peak, humidityPct: humidity,
                                            windMps: hs.compactMap(\.windMps).max(), conditionId: sky, usAqi: aqis.max())
            let advice = EnvironmentAdvice.analyze(probe, calendar: calendar, hours: 0...23)
            var fit: OutdoorFit = advice.map { $0.level == .indoors ? .indoors : ($0.level == .adjust ? .adjust : .good) } ?? .good
            if rain >= 0.5, fit < .adjust { fit = .adjust }
            let isCurrent = i == 0 && part == currentPart
            return Slot(part: part, start: isCurrent ? from : hs[0].ts, end: boundary(after: isCurrent ? from : hs[0].ts), isCurrent: isCurrent,
                        tempC: mean(hs.compactMap(\.tempC)), feelsLikeC: mean(feels) ?? peak, peakFeelsLikeC: peak,
                        lowC: hs.map { $0.tempC ?? $0.feelsLikeC }.min() ?? peak, highC: hs.map { $0.tempC ?? $0.feelsLikeC }.max() ?? peak, rainChance: rain, windMps: wind,
                        humidityPct: humidity, usAqi: aqis.max(), conditionId: sky, fit: fit,
                        reasons: (advice?.reasons ?? []).sorted { EnvironmentOutlook.severity($0) < EnvironmentOutlook.severity($1) }, rainLikely: rain >= 0.5)
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
        let timeline: [Step] = steps.map { h in
            let aqi = usAqi(at: h.ts, in: s)
            return Step(ts: h.ts, feelsLikeC: h.feelsLikeC, tempC: h.tempC, rainChance: h.rainChance, conditionId: h.conditionId, usAqi: aqi,
                        fit: OutdoorFit.of(feelsLikeC: h.feelsLikeC, humidityPct: s.humidityPct, usAqi: aqi, rainChance: h.rainChance, windMps: h.windMps, conditionId: h.conditionId))
        }
        // The days, from every step the forecast has (the reading now is a point of today).
        func midnight(_ ts: Int) -> Int { Int(calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(ts))).timeIntervalSince1970) }
        var byDay: [Int: [EnvironmentSnapshot.Hour]] = [:]
        for h in s.forecast.sorted(by: { $0.ts < $1.ts }) where h.ts >= from - 3600 { byDay[midnight(h.ts), default: []].append(h) }
        if s.hasWeather {
            byDay[midnight(from), default: []].append(.init(ts: from, feelsLikeC: s.effectiveC ?? 0, rainChance: 0, tempC: s.tempC, windMps: s.windMps, conditionId: s.conditionId, humidityPct: s.humidityPct))
        }
        let days: [Day] = byDay.keys.sorted().prefix(5).compactMap { day in
            guard let hs = byDay[day], !hs.isEmpty else { return nil }
            let temps = hs.map { $0.tempC ?? $0.feelsLikeC }
            // The sky of the day: a storm if there is one, else a wet step if the rain is likely, else the sky around the middle of the day.
            let storm = hs.first { $0.conditionId.map { (200..<300).contains($0) } == true }
            let wet = hs.filter { $0.rainChance >= 0.4 && $0.conditionId.map { (300..<600).contains($0) } == true }.max { $0.rainChance < $1.rainChance }
            let midday = hs.min { abs(hour($0.ts) - 13) < abs(hour($1.ts) - 13) }
            let sky = (storm ?? wet ?? midday)?.conditionId
            let aqis = s.airForecast.filter { $0.ts >= day && $0.ts < day + 86_400 }.map(\.usAqi) + (day == midnight(from) ? [s.usAqi].compactMap { $0 } : [])
            func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
            return Day(start: day, lowC: temps.min() ?? 0, highC: temps.max() ?? 0, conditionId: sky, rainChance: hs.map(\.rainChance).max() ?? 0, usAqi: aqis.max(),
                       peakFeelsLikeC: hs.map(\.feelsLikeC).max() ?? temps.max() ?? 0, windMps: mean(hs.compactMap(\.windMps)), humidityPct: mean(hs.compactMap(\.humidityPct)) ?? s.humidityPct)
        }
        return EnvironmentOutlook(slots: slots, steps: timeline, days: days, best: best)
    }
}
