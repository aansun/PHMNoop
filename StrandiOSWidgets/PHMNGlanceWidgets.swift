import StrandDesign
import SwiftUI
import WidgetKit

// The four glance widgets: the three scores in a row (medium), the Sleep ring alone (small), Recovery and Strain as two rings with a mark in
// the middle (small), and the same two rings with HRV and Calories beside them (medium). All of them carry the day streak at the top left and
// the strap battery at the top right, on a dark card, and open the app. They draw only what the app wrote into the shared snapshot.

private enum Glance {
    static let steel = Color(red: 0.51, green: 0.63, blue: 0.74)
    static let flame = Color(red: 1.0, green: 0.45, blue: 0.16)
    static let ink = Color.white
    static let muted = Color(red: 0.62, green: 0.64, blue: 0.66)
    static let track = Color.white.opacity(0.13)
    static let card = LinearGradient(colors: [Color(red: 0.18, green: 0.20, blue: 0.22), Color(red: 0.12, green: 0.14, blue: 0.15)], startPoint: .top, endPoint: .bottom)
    static let open = URL(string: "noop://today")!
}

private struct GlanceData {
    let s: WidgetSnapshot
    var recovery: Double? { s.recovery.map(Double.init) }
    var recoveryColor: Color { s.recovery.map { NunaScoreStyle.chargeColor(Double($0)) } ?? Glance.muted }
    var strainColor: Color { s.effort.map { NunaScoreStyle.effortColor(Double($0)) } ?? Glance.muted }
    var strainGradient: [Color]? { s.effort.map { NunaScoreStyle.effortGradient(Double($0)) } }
    var strainText: String { s.effortDisplay ?? s.effort.map(String.init) ?? "–" }
    var sleepFraction: Double { s.rest.map { Double($0) / 100 } ?? 0 }
    var recoveryFraction: Double { s.recovery.map { Double($0) / 100 } ?? 0 }
    var strainFraction: Double { s.effort.map { Double($0) / 100 } ?? 0 }
    var summary: String {
        "Sleep \(s.rest.map { "\($0)%" } ?? "–"), Recovery \(s.recovery.map { "\($0)%" } ?? "–"), Strain \(strainText)"
    }
}

/// A ring: a grey track and an arc from the top, round-capped, with the figure (or anything else) in the middle.
private struct GlanceRing<Centre: View>: View {
    let fraction: Double
    let color: Color
    var gradient: [Color]? = nil
    let width: CGFloat
    @ViewBuilder var centre: () -> Centre

    var body: some View {
        let p = min(max(fraction, 0), 1)
        let shown = p > 0 ? max(p, 0.015) : 0
        ZStack {
            Circle().stroke(Glance.track, lineWidth: width)
            Circle().trim(from: 0, to: shown)
                .stroke(gradient.map { AnyShapeStyle(AngularGradient(colors: $0, center: .center, startAngle: .degrees(0), endAngle: .degrees(max(360 * shown, 1)))) } ?? AnyShapeStyle(color),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            centre()
        }
    }
}

/// Figure with its small percent sign, in the bold figure face.
private struct GlanceFigure: View {
    let value: String
    var percent = false
    let size: CGFloat
    var color: Color = Glance.ink

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text(verbatim: value).font(.nunaBoldFigure(size: size)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            if percent { Text(verbatim: "%").font(.nunaBoldFigure(size: size * 0.5)).foregroundStyle(color) }
        }
    }
}

private struct GlanceCaption: View {
    let text: String
    var color: Color = Glance.ink
    var size: CGFloat = 11
    var body: some View {
        Text(verbatim: text.uppercased()).font(.system(size: size, weight: .heavy)).tracking(size * 0.14).foregroundStyle(color).lineLimit(1)
    }
}

private struct GlanceStreak: View {
    let days: Int?
    var stacked = false
    var body: some View {
        Group {
            if stacked { VStack(spacing: 2) { flame; count } } else { HStack(spacing: 4) { flame; count } }
        }
        .accessibilityLabel(Text(verbatim: days.map { "Day streak \($0)" } ?? "Day streak"))
    }
    private var flame: some View {
        Image(systemName: "flame.fill").font(.system(size: stacked ? 15 : 14, weight: .bold)).foregroundStyle(Glance.flame)
    }
    private var count: some View {
        Text(verbatim: days.map(String.init) ?? "–").font(.nunaBoldFigure(size: stacked ? 14 : 14)).foregroundStyle(Glance.ink)
    }
}

private struct GlanceBattery: View {
    let pct: Int?
    var stacked = false
    var body: some View {
        Group {
            if stacked { VStack(spacing: 2) { icon; text } } else { HStack(spacing: 5) { text; icon } }
        }
        .accessibilityLabel(Text(verbatim: pct.map { "Battery \($0)%" } ?? "Battery unavailable"))
    }
    private var text: some View { Text(verbatim: pct.map { "\($0)%" } ?? "–").font(.nunaBoldFigure(size: 14)).foregroundStyle(Glance.ink) }
    private var icon: some View {
        Image(systemName: Self.symbol(pct)).font(.system(size: stacked ? 15 : 14, weight: .semibold)).foregroundStyle(Glance.ink)
    }
    static func symbol(_ p: Int?) -> String {
        guard let p else { return "battery.0" }
        return p >= 88 ? "battery.100" : (p >= 63 ? "battery.75" : (p >= 38 ? "battery.50" : (p >= 13 ? "battery.25" : "battery.0")))
    }
}

// MARK: - Medium: three rings

private struct TriRingsView: View {
    let d: GlanceData

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PHMNWordmark(height: 11, color: Glance.muted)
                HStack { GlanceStreak(days: d.s.dayStreak); Spacer(); GlanceBattery(pct: d.s.batteryPct) }
            }
            Spacer(minLength: 6)
            HStack(spacing: 0) {
                column(ring: ring(d.sleepFraction, Glance.steel, nil, d.s.rest.map(String.init) ?? "–", percent: d.s.rest != nil), "Sleep")
                column(ring: ring(d.recoveryFraction, d.recoveryColor, nil, d.s.recovery.map(String.init) ?? "–", percent: d.s.recovery != nil), "Recovery")
                column(ring: ring(d.strainFraction, d.strainColor, d.strainGradient, d.strainText, percent: false), "Strain")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func ring(_ f: Double, _ c: Color, _ g: [Color]?, _ value: String, percent: Bool) -> some View {
        GlanceRing(fraction: f, color: c, gradient: g, width: 5.5) { GlanceFigure(value: value, percent: percent, size: 24) }.frame(width: 79, height: 79)
    }

    private func column<R: View>(ring: R, _ label: String) -> some View {
        VStack(spacing: 8) { ring; GlanceCaption(text: label) }.frame(maxWidth: .infinity)
    }
}

// MARK: - Small: the Sleep ring

private struct SleepRingView: View {
    let d: GlanceData

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) { GlanceStreak(days: d.s.dayStreak, stacked: true); Spacer(); GlanceBattery(pct: d.s.batteryPct, stacked: true) }
            Spacer(minLength: 0)
            GlanceRing(fraction: d.sleepFraction, color: Glance.steel, width: 7) {
                GlanceFigure(value: d.s.rest.map(String.init) ?? "–", percent: d.s.rest != nil, size: 38)
            }
            .frame(width: 98, height: 98).padding(.top, 2)
            Spacer(minLength: 0)
            ZStack {
                GlanceCaption(text: "Sleep", size: 11.5)
                HStack { PHMNMark(.circle, size: 20, color: Glance.muted); Spacer() }
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
    }
}

// MARK: - Dual ring (shared by the small and the wide widget)

private struct DualRing: View {
    let d: GlanceData
    let size: CGFloat
    var body: some View {
        let outer = size * 0.085, inner = size * 0.075
        ZStack {
            // The outer ring is Strain, the inner ring Recovery, the same order as the app's day rings.
            GlanceRing(fraction: d.strainFraction, color: d.strainColor, gradient: d.strainGradient, width: outer) { Color.clear }.frame(width: size, height: size)
            GlanceRing(fraction: d.recoveryFraction, color: d.recoveryColor, width: inner) { Color.clear }.frame(width: size * 0.74, height: size * 0.74)
            PHMNButterflyShape().fill(Glance.ink).frame(width: size * 0.26, height: size * 0.26)
        }
    }
}

private struct SmallDualView: View {
    let d: GlanceData
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) { GlanceStreak(days: d.s.dayStreak, stacked: true); Spacer(); GlanceBattery(pct: d.s.batteryPct, stacked: true) }
            Spacer(minLength: 0)
            DualRing(d: d, size: 100).padding(.top, 2)
            Spacer(minLength: 0)
            HStack {
                GlanceFigure(value: d.s.recovery.map(String.init) ?? "–", percent: d.s.recovery != nil, size: 19, color: d.recoveryColor)
                Spacer()
                GlanceFigure(value: d.strainText, size: 19, color: d.strainColor)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
    }
}

private struct WideDualView: View {
    let d: GlanceData
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) { GlanceStreak(days: d.s.dayStreak); Spacer(); GlanceBattery(pct: d.s.batteryPct) }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                VStack(alignment: .trailing, spacing: 0) {
                    GlanceFigure(value: d.s.recovery.map(String.init) ?? "–", percent: d.s.recovery != nil, size: 24, color: d.recoveryColor)
                    GlanceCaption(text: "Recovery", color: d.recoveryColor, size: 12).padding(.top, 2)
                    Rectangle().fill(Color.clear).frame(height: 14)
                    GlanceCaption(text: "HRV", color: Glance.muted, size: 12)
                    Text(verbatim: d.s.hrv.map(String.init) ?? "–").font(.nunaBoldFigure(size: 21)).foregroundStyle(Glance.muted).padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                DualRing(d: d, size: 118)
                VStack(alignment: .leading, spacing: 0) {
                    GlanceFigure(value: d.strainText, size: 24, color: d.strainColor)
                    GlanceCaption(text: "Strain", color: d.strainColor, size: 12).padding(.top, 2)
                    Rectangle().fill(Color.clear).frame(height: 14)
                    GlanceCaption(text: "Calories", color: Glance.muted, size: 12)
                    Text(verbatim: d.s.caloriesKcal?.formatted() ?? "–").font(.nunaBoldFigure(size: 21)).foregroundStyle(Glance.muted).padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

// MARK: - Provider and widgets

struct PHMNGlanceEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct PHMNGlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> PHMNGlanceEntry { PHMNGlanceEntry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (PHMNGlanceEntry) -> Void) {
        let fallback: WidgetSnapshot = context.isPreview ? .placeholder : .unavailable
        completion(PHMNGlanceEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? fallback))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PHMNGlanceEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? .unavailable
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [PHMNGlanceEntry(date: Date(), snapshot: snapshot)], policy: .after(next)))
    }
}

private struct GlanceCard<Content: View>: View {
    let entry: PHMNGlanceEntry
    @ViewBuilder let content: (GlanceData) -> Content
    var body: some View {
        let d = GlanceData(s: entry.snapshot)
        content(d)
            .widgetURL(Glance.open)
            .foregroundStyle(Glance.ink)
            .accessibilityElement(children: .combine).accessibilityLabel(Text(verbatim: d.summary))
            .containerBackground(Glance.card, for: .widget)
    }
}

struct PHMNTriRingsWidget: Widget {
    static let kind = "PHMNTriRingsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PHMNGlanceProvider()) { e in GlanceCard(entry: e) { TriRingsView(d: $0) } }
            .configurationDisplayName("PHMN Scores")
            .description("Sleep, Recovery and Strain, with your day streak and strap battery.")
            .supportedFamilies([.systemMedium]).contentMarginsDisabled()
    }
}

struct PHMNSleepRingWidget: Widget {
    static let kind = "PHMNSleepRingWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PHMNGlanceProvider()) { e in GlanceCard(entry: e) { SleepRingView(d: $0) } }
            .configurationDisplayName("PHMN Sleep")
            .description("Last night's Sleep score in one ring.")
            .supportedFamilies([.systemSmall]).contentMarginsDisabled()
    }
}

struct PHMNDualRingSmallWidget: Widget {
    static let kind = "PHMNDualRingSmallWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PHMNGlanceProvider()) { e in GlanceCard(entry: e) { SmallDualView(d: $0) } }
            .configurationDisplayName("PHMN Recovery and Strain")
            .description("Recovery and Strain as two rings.")
            .supportedFamilies([.systemSmall]).contentMarginsDisabled()
    }
}

struct PHMNDualRingWideWidget: Widget {
    static let kind = "PHMNDualRingWideWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PHMNGlanceProvider()) { e in GlanceCard(entry: e) { WideDualView(d: $0) } }
            .configurationDisplayName("PHMN Rings with HRV")
            .description("Recovery and Strain rings with HRV and Calories beside them.")
            .supportedFamilies([.systemMedium]).contentMarginsDisabled()
    }
}
