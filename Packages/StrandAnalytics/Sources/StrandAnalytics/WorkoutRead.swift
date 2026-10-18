import Foundation

// WorkoutRead.swift - what a finished session MEANS against the wearer's own last 30 days of the same sport.
//
// The old line said "You spent 25 min in zone 2, 59% of the session": what the zone bars already show. This read compares the session
// with the person's own usual (pace against heart rate, length, Effort, where the time went) and with the day it sits in (the Effort
// range today's Charge supports). Pure arithmetic over figures the screen already holds; the sentences are composed in the app layer,
// where they are localised. No verdict without a baseline of at least two other sessions.

public struct WorkoutFacts: Equatable, Sendable {
    public var durationS: Double
    public var distanceM: Double?
    public var avgHr: Double?
    /// Stored 0-100 Effort of the session.
    public var effort: Double?
    /// Minutes in each of the five zones.
    public var zoneMin: [Double]?

    public init(durationS: Double, distanceM: Double? = nil, avgHr: Double? = nil, effort: Double? = nil, zoneMin: [Double]? = nil) {
        self.durationS = durationS; self.distanceM = distanceM; self.avgHr = avgHr; self.effort = effort; self.zoneMin = zoneMin
    }
}

/// The person's own other sessions of the same sport over the last 30 days (at least two of them).
public struct WorkoutBaseline: Equatable, Sendable {
    public var count: Int
    public var durationS: Double
    public var distanceM: Double?
    public var avgHr: Double?
    public var effort: Double?
    public var zoneMin: [Double]?

    public init(count: Int, durationS: Double, distanceM: Double? = nil, avgHr: Double? = nil, effort: Double? = nil, zoneMin: [Double]? = nil) {
        self.count = count; self.durationS = durationS; self.distanceM = distanceM; self.avgHr = avgHr; self.effort = effort; self.zoneMin = zoneMin
    }
}

/// The day the session belongs to: its Effort once the session is in, and the range today's Charge supports (stored axis).
public struct WorkoutDayContext: Equatable, Sendable {
    public var dayEffort: Double
    public var rangeLow: Double
    public var rangeHigh: Double
    public var charge: Double

    public init(dayEffort: Double, rangeLow: Double, rangeHigh: Double, charge: Double) {
        self.dayEffort = dayEffort; self.rangeLow = rangeLow; self.rangeHigh = rangeHigh; self.charge = charge
    }
}

public struct WorkoutRead: Equatable, Sendable {
    public enum Efficiency: Equatable, Sendable {
        case fasterLowerHr, fasterSameHr, fasterHigherHr
        case slowerLowerHr, slowerSameHr, slowerHigherHr
        case samePaceLowerHr, samePaceHigherHr
    }

    public enum DayState: Equatable, Sendable { case below, inside, above }

    public enum Finding: Equatable, Sendable {
        /// Pace against heart rate, in seconds per kilometre, and the heart-rate gap in bpm (+ above the usual).
        case efficiency(Efficiency, paceSecPerKm: Double, usualSecPerKm: Double, hrDeltaBpm: Double)
        case duration(minutes: Double, usualMinutes: Double)
        case effort(stored: Double, usualStored: Double)
        case zone(number: Int, minutes: Int, usualMinutes: Int)
        case day(DayState, dayEffort: Double, low: Double, high: Double, charge: Double)
        /// Nothing stood out: the session sat on the person's own norms.
        case typical
    }

    /// The finding that matters most, then up to two more.
    public let headline: Finding
    public let more: [Finding]

    static let paceMargin = 0.03
    static let hrMargin = 3.0
    static let sizeMargin = 0.15

    public static func analyze(_ s: WorkoutFacts, baseline b: WorkoutBaseline?, day: WorkoutDayContext?) -> WorkoutRead? {
        var ranked: [(score: Double, finding: Finding)] = []

        if let b, b.count >= 2 {
            // Pace against heart rate: the one comparison that says whether fitness or fatigue is behind the session.
            if let d = s.distanceM, d > 500, let bd = b.distanceM, bd > 500, s.durationS > 0, b.durationS > 0 {
                let pace = s.durationS / (d / 1000), usual = b.durationS / (bd / 1000)
                let gap = (usual - pace) / usual   // + faster
                let hr = (s.avgHr != nil && b.avgHr != nil) ? s.avgHr! - b.avgHr! : nil
                let faster = gap >= paceMargin, slower = gap <= -paceMargin
                let lowerHr = (hr ?? 0) <= -hrMargin, higherHr = (hr ?? 0) >= hrMargin
                var kind: Efficiency?
                if faster { kind = lowerHr ? .fasterLowerHr : (higherHr ? .fasterHigherHr : .fasterSameHr) }
                else if slower { kind = lowerHr ? .slowerLowerHr : (higherHr ? .slowerHigherHr : .slowerSameHr) }
                else if hr != nil, lowerHr { kind = .samePaceLowerHr }
                else if hr != nil, higherHr { kind = .samePaceHigherHr }
                if let kind {
                    ranked.append((100 + abs(gap) * 100, .efficiency(kind, paceSecPerKm: pace, usualSecPerKm: usual, hrDeltaBpm: hr ?? 0)))
                }
            }
            if let e = s.effort, let be = b.effort, be > 0, abs(e - be) / be >= sizeMargin {
                ranked.append((60 + abs(e - be) / be * 50, .effort(stored: e, usualStored: be)))
            }
            let mins = s.durationS / 60, usualMins = b.durationS / 60
            if usualMins > 0, abs(mins - usualMins) / usualMins >= sizeMargin {
                ranked.append((40 + abs(mins - usualMins) / usualMins * 50, .duration(minutes: mins, usualMinutes: usualMins)))
            }
            if let z = s.zoneMin, z.count >= 5, let bz = b.zoneMin, bz.count >= 5, z.reduce(0, +) > 0,
               let top = z.enumerated().max(by: { $0.element < $1.element }) {
                let minutes = Int(top.element.rounded()), usual = Int(bz[top.offset].rounded())
                if minutes >= 1, Double(minutes) >= bz[top.offset] * 1.25 + 1 || Double(minutes) <= bz[top.offset] * 0.75 - 1 {
                    ranked.append((50, .zone(number: top.offset + 1, minutes: minutes, usualMinutes: usual)))
                }
            }
        }

        if let day, day.rangeHigh > day.rangeLow {
            let state: DayState = day.dayEffort < day.rangeLow ? .below : (day.dayEffort <= day.rangeHigh ? .inside : .above)
            // The day is worth a line when it ended outside the range, and is a closing line when it is the only thing to say.
            ranked.append((state == .inside ? 20 : 45, .day(state, dayEffort: day.dayEffort, low: day.rangeLow, high: day.rangeHigh, charge: day.charge)))
        }

        ranked.sort { $0.score > $1.score }
        if ranked.isEmpty { return (b?.count ?? 0) >= 2 ? WorkoutRead(headline: .typical, more: []) : nil }
        return WorkoutRead(headline: ranked[0].finding, more: ranked.dropFirst().prefix(2).map(\.finding))
    }
}
