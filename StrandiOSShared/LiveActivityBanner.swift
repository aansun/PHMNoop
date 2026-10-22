import WidgetKit
import SwiftUI
import StrandDesign
#if canImport(UIKit)
import UIKit
#endif
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
    static let soft = Color(hex: "#DDE3E8")

    /// D-DIN-PRO, the typeface of the reference design (the app and the extension both carry it). The system's condensed bold stands in if it is missing.
    static func din(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        let name: String
        switch weight {
        case .regular: name = "D-DIN-PRO-Regular"
        case .medium: name = "D-DIN-PRO-Medium"
        case .semibold: name = "D-DIN-PRO-SemiBold"
        default: name = "D-DIN-PRO-Bold"
        }
        #if canImport(UIKit)
        if UIFont(name: name, size: size) != nil { return .custom(name, size: size) }
        #endif
        return .system(size: size, weight: weight, design: .default).width(.condensed)
    }

    /// The zones, easy to hard: slate, blue, teal, bronze, rust.
    static func zone(_ n: Int) -> Color {
        [Color(hex: "#6C7B88"), Color(hex: "#4FA3D9"), Color(hex: "#3FA391"), Color(hex: "#C08A4E"), Color(hex: "#D2603F")][min(max(n, 1), 5) - 1]
    }
}

struct NOOPBannerLockScreen: View {
    let state: NOOPActivityAttributes.ContentState

    private var paused: Bool { state.pausedAt != nil }
    private var zone: Int? { state.heartRateZone }

    /// Laid out as the reference: a lighter upper band (clock at the left, the mark in the middle, heart and heart rate at the right) over a
    /// darker lower one (the five zones with their names, then two figures under the zones, each with its name below). A Lock Screen
    /// Live Activity has about 160 pt; the two bands add up to about 156.
    var body: some View {
        VStack(spacing: 0) {
            topBand
            bottomBand
        }
    }

    // MARK: Upper band

    private var topBand: some View {
        ZStack {
            HStack(alignment: .center, spacing: 0) {
                clockText
                Spacer(minLength: 0)
                heartRate
            }
            mark
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
        .background(NOOPBannerPalette.top)
    }

    /// The session clock; it stands still, amber, with a pause mark while the session is paused.
    private var clockText: some View {
        HStack(spacing: 5) {
            if paused { Image(systemName: "pause.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(NOOPBannerPalette.paused) }
            Group {
                if let start = state.activityStartedAt {
                    Text(timerInterval: start...start.addingTimeInterval(86_400), pauseTime: state.pausedAt, countsDown: false)
                } else {
                    Text(verbatim: "–")
                }
            }
            .font(NOOPBannerPalette.din(38)).monospacedDigit()
            .foregroundStyle(paused ? NOOPBannerPalette.paused : NOOPBannerPalette.ink)
            .lineLimit(1)
            // A timer text takes all the width it is offered; give it its own: m:ss until the first hour, h:mm:ss after it.
            .frame(width: (state.activityStartedAt.map { Date().timeIntervalSince($0) } ?? 0) >= 3600 ? 170 : 140, alignment: .leading)
        }
    }

    /// The PHMN mark in the middle, in grey and not in its colours: it carries its own thin ring.
    private var mark: some View {
        Image("PHMNMarkMono").renderingMode(.template).resizable().scaledToFit()
            .frame(width: 46, height: 46)
            .foregroundStyle(NOOPBannerPalette.muted)
            .accessibilityHidden(true)
    }

    /// A muted heart before the number, the number large, "bpm" small beside it, all on one baseline.
    private var heartRate: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: "heart.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(NOOPBannerPalette.muted)
                .alignmentGuide(.firstTextBaseline) { d in d[.top] + 27 }
            Text(verbatim: state.bpm.map(String.init) ?? "–").font(NOOPBannerPalette.din(38)).monospacedDigit()
                .foregroundStyle(NOOPBannerPalette.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text("bpm").font(NOOPBannerPalette.din(17, .medium)).foregroundStyle(NOOPBannerPalette.muted)
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
        .padding(.horizontal, 17).padding(.top, 7).padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(NOOPBannerPalette.bottom)
    }

    private var zoneBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { n in
                        Capsule().fill(NOOPBannerPalette.zone(n).opacity(zone == n ? 1 : 0.4)).frame(height: 4)
                    }
                }
                if let p = state.zonePosition {
                    Circle().fill(Color.white).frame(width: 9, height: 9)
                        .offset(x: min(max(CGFloat(p) * w - 4.5, 0), w - 9))
                }
            }
            .frame(height: 9)
        }
        .frame(height: 9)
    }

    private var zoneNames: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { n in
                Text("Zone \(n)").font(NOOPBannerPalette.din(16))
                    .foregroundStyle(zone == n ? NOOPBannerPalette.zone(n) : NOOPBannerPalette.zone(n).opacity(0.5))
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

    /// The figures sit exactly under the middle of Zone 2 and of Zone 4 (3/10 and 7/10 of the bar), so the pair is symmetric about the centre mark.
    private var figures: some View {
        let items = figureList
        return GeometryReader { geo in
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                VStack(spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(verbatim: item.value).font(NOOPBannerPalette.din(28)).monospacedDigit()
                            .foregroundStyle(NOOPBannerPalette.ink).lineLimit(1).minimumScaleFactor(0.6)
                        if !item.unit.isEmpty { Text(verbatim: item.unit).font(NOOPBannerPalette.din(15, .medium)).foregroundStyle(NOOPBannerPalette.muted) }
                    }
                    Text(item.label).font(NOOPBannerPalette.din(11, .medium)).tracking(1).foregroundStyle(NOOPBannerPalette.muted)
                }
                .fixedSize()
                .position(x: geo.size.width * (i == 0 ? 0.3 : 0.7), y: geo.size.height / 2)
            }
        }
        .frame(height: 44)
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
