import WidgetKit
import SwiftUI
import StrandDesign
#if os(iOS)
import ActivityKit
#endif

// The "Banner" design of the workout Live Activity: a dark card in two bands. In the upper band the session clock at the left, the PHMN mark in the
// middle and the heart rate at the right; in the lower, darker one the five heart-rate zones as a bar with a marker, each zone named under its
// segment, and the session's two main figures beneath. Every colour is fixed, so it reads the same on any wallpaper and in either appearance.

enum NOOPBannerPalette {
    static let top = Color(hex: "#212C37")
    static let bottom = Color(hex: "#151E27")
    static let ink = Color.white
    static let paused = Color(hex: "#F5B02E")
    static let muted = Color(hex: "#8794A1")
    static let track = Color(hex: "#3A4652")

    /// The zones, easy to hard: slate, blue, teal, bronze, rust.
    static func zone(_ n: Int) -> Color {
        [Color(hex: "#6C7B88"), Color(hex: "#4FA3D9"), Color(hex: "#3FA391"), Color(hex: "#C08A4E"), Color(hex: "#D2603F")][min(max(n, 1), 5) - 1]
    }
}

struct NOOPBannerLockScreen: View {
    let state: NOOPActivityAttributes.ContentState

    private var paused: Bool { state.pausedAt != nil }
    private var zone: Int? { state.heartRateZone }

    /// A Lock Screen Live Activity may be about 160 pt tall; anything taller is squeezed and its rows collide. The two bands add up to about 140.
    var body: some View {
        VStack(spacing: 0) {
            topBand
            bottomBand
        }
    }

    // MARK: Upper band

    private var topBand: some View {
        HStack(alignment: .center, spacing: 8) {
            clockText.frame(maxWidth: .infinity, alignment: .leading)
            mark
            heartRate.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .frame(height: 58)
        .background(NOOPBannerPalette.top)
    }

    /// The session clock; it stands still, in amber with a pause mark, while the session is paused.
    private var clockText: some View {
        HStack(spacing: 5) {
            if paused { Image(systemName: "pause.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(NOOPBannerPalette.paused) }
            Group {
                if let start = state.activityStartedAt {
                    Text(timerInterval: start...start.addingTimeInterval(86_400), pauseTime: state.pausedAt, countsDown: false)
                } else {
                    Text(verbatim: "–")
                }
            }
            .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(paused ? NOOPBannerPalette.paused : NOOPBannerPalette.ink)
            .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    /// The PHMN mark in a thin ring.
    private var mark: some View {
        ZStack {
            Circle().strokeBorder(NOOPBannerPalette.muted.opacity(0.7), lineWidth: 1.4)
            Image("PHMNMark").resizable().scaledToFill().frame(width: 32, height: 32).clipShape(Circle())
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }

    private var heartRate: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: "heart.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(NOOPBannerPalette.muted)
            Text(verbatim: state.bpm.map(String.init) ?? "–").font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(NOOPBannerPalette.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text("bpm").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(NOOPBannerPalette.muted)
        }
        .fixedSize()
    }

    // MARK: Lower band

    private var bottomBand: some View {
        VStack(spacing: 5) {
            zoneBar
            zoneNames
            figures
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(NOOPBannerPalette.bottom)
    }

    private var zoneBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { n in
                        Capsule().fill(NOOPBannerPalette.zone(n).opacity(zone == n ? 1 : 0.45)).frame(height: 4)
                    }
                }
                if let p = state.zonePosition {
                    Circle().fill(Color.white).frame(width: 10, height: 10)
                        .offset(x: min(max(CGFloat(p) * w - 5, 0), w - 10))
                }
            }
            .frame(height: 10)
        }
        .frame(height: 10)
    }

    private var zoneNames: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { n in
                Text("Zone \(n)").font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(zone == n ? NOOPBannerPalette.zone(n) : NOOPBannerPalette.zone(n).opacity(0.55))
                    .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Figures

    private struct Figure: Identifiable {
        let id: String
        let label: LocalizedStringKey
        let value: String
        var unit = ""
    }

    private var onFoot: Bool { state.activityName.map(ActivitySport.countsSteps) ?? false }
    private var isCycling: Bool { state.activityName == "Cycling" }
    private var isRoute: Bool { state.activityName.map { ActivitySport.isRoute($0) } == true || state.distance != nil || state.pace != nil }

    /// "3.42 km" -> ("3.42", "km"); a value with no unit comes back whole.
    private static func split(_ s: String?) -> (String, String) {
        guard let s, !s.isEmpty else { return ("–", "") }
        guard let i = s.lastIndex(of: " ") else { return (s, "") }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }

    /// Two figures: distance and pace (speed on a bike) with a route; otherwise steps or calories, and calories or the session's Effort.
    private var figureList: [Figure] {
        let calories = Figure(id: "calories", label: "CALORIES", value: state.calories.map(String.init) ?? "–", unit: state.calories == nil ? "" : String(localized: "kcal"))
        if isRoute {
            let d = Self.split(state.distance)
            let p = Self.split(isCycling ? state.speed : state.pace)
            return [Figure(id: "distance", label: "DISTANCE", value: d.0, unit: d.1),
                    Figure(id: "pace", label: isCycling ? "SPEED" : "PACE", value: p.0, unit: p.1)]
        }
        let effort = Figure(id: "effort", label: "EFFORT", value: state.effortLabel ?? state.effort.map(String.init) ?? "–")
        if onFoot, let steps = state.steps { return [Figure(id: "steps", label: "STEPS", value: String(steps)), calories] }
        return [calories, effort]
    }

    /// The first figure sits about a third of the way across the bar and the second about two thirds, as under zones 1 to 2 and 3 to 4.
    private var figures: some View {
        let items = figureList
        return GeometryReader { geo in
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(verbatim: item.value).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(NOOPBannerPalette.ink).lineLimit(1).minimumScaleFactor(0.6)
                        if !item.unit.isEmpty { Text(verbatim: item.unit).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(NOOPBannerPalette.muted) }
                    }
                    Text(item.label).font(.system(size: 10.5, weight: .heavy, design: .rounded)).tracking(0.8).foregroundStyle(NOOPBannerPalette.muted)
                }
                .fixedSize()
                .position(x: geo.size.width * (i == 0 ? 0.31 : 0.64), y: geo.size.height / 2)
            }
        }
        .frame(height: 44)
        .padding(.top, 4)
    }
}

extension NOOPActivityAttributes.ContentState {
    /// A running session with made-up figures, to show the Banner design in Settings.
    static func bannerDemo(now: Date = Date()) -> NOOPActivityAttributes.ContentState {
        NOOPActivityAttributes.ContentState(
            bpm: 138, recovery: nil, bonded: true, batteryPct: 68, effort: 4,
            heartRateZone: 3, activityName: "Running", activityStartedAt: now.addingTimeInterval(-(14 * 60 + 27)),
            averageBPM: 131, peakBPM: 152, distance: "2.31 km", pace: "6:12 /km", calories: 186,
            zonePosition: 0.56, effortLabel: "4.1", design: "banner")
    }
}
