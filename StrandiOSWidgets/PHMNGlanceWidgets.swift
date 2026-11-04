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
    /// The figure face of the reference: DIN Bold, sharp at small sizes (the face bundled with the widget).
    static func din(_ size: CGFloat) -> Font { .custom("D-DIN-PRO-Bold", size: size) }
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

/// Figure with its small percent sign (60% of the figure's size), in DIN Bold.
private struct GlanceFigure: View {
    let value: String
    var percent = false
    let size: CGFloat
    var color: Color = Glance.ink

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0.5) {
            Text(verbatim: value).font(Glance.din(size)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            if percent { Text(verbatim: "%").font(Glance.din(size * 0.6)).foregroundStyle(color) }
        }
    }
}

private struct GlanceCaption: View {
    let text: String
    var color: Color = Glance.ink
    var size: CGFloat = 9.5
    var body: some View {
        Text(verbatim: text.uppercased()).font(.system(size: size, weight: .heavy)).tracking(size * 0.13).foregroundStyle(color).lineLimit(1)
    }
}

private struct GlanceStreak: View {
    let days: Int?
    var stacked = false
    var body: some View {
        Group {
            if stacked { VStack(spacing: 1) { flame; count } } else { HStack(spacing: 8) { flame; count } }
        }
        .accessibilityLabel(Text(verbatim: days.map { "Day streak \($0)" } ?? "Day streak"))
    }
    private var flame: some View {
        Image(systemName: "flame.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Glance.flame)
    }
    private var count: some View {
        Text(verbatim: days.map(String.init) ?? "–").font(Glance.din(10.5)).foregroundStyle(Glance.ink)
    }
}

/// The strap battery: its percentage and a small outline with the charge filled in grey, 14 x 7.4 pt as on the reference.
private struct GlanceBattery: View {
    let pct: Int?
    var stacked = false
    var body: some View {
        Group {
            if stacked { VStack(spacing: 2) { icon; text } } else { HStack(spacing: 4.8) { text; icon } }
        }
        .accessibilityLabel(Text(verbatim: pct.map { "Battery \($0)%" } ?? "Battery unavailable"))
    }
    private var text: some View { Text(verbatim: pct.map { "\($0)%" } ?? "–").font(Glance.din(10.5)).foregroundStyle(Glance.ink) }
    private var icon: some View {
        let f = CGFloat(min(max(pct ?? 0, 0), 100)) / 100
        return HStack(spacing: 0.8) {
            RoundedRectangle(cornerRadius: 1.8, style: .continuous).strokeBorder(Glance.ink, lineWidth: 1)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 0.8, style: .continuous).fill(Color(red: 0.62, green: 0.63, blue: 0.64))
                        .frame(width: max(0, 11.4 * f), height: 4.6).padding(.leading, 1.5)
                }
                .frame(width: 13, height: 7.4)
            RoundedRectangle(cornerRadius: 0.5).fill(Glance.ink).frame(width: 1.2, height: 3)
        }
    }
}

// MARK: - Medium: three rings

private struct TriRingsView: View {
    let d: GlanceData

    // Measured on the reference (3.1 px per point): the header row is centred 23 pt under the top edge, the rings are 75.5 pt across with a
    // 4.6 pt line and start 42 pt down, three columns 104 pt apart, and each label sits about 8 pt under its ring.
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PHMNWordmark(height: 9.4, color: Color(red: 0.62, green: 0.64, blue: 0.66)).scaleEffect(x: 1.3)
                HStack { GlanceStreak(days: d.s.dayStreak); Spacer(); GlanceBattery(pct: d.s.batteryPct) }
                    .padding(.leading, 20).padding(.trailing, 15.5)
            }
            .frame(height: 12).padding(.top, 17)
            HStack(spacing: 0) {
                column(ring: ring(d.sleepFraction, Glance.steel, nil, d.s.rest.map(String.init) ?? "–", percent: d.s.rest != nil), "Sleep")
                column(ring: ring(d.recoveryFraction, d.recoveryColor, nil, d.s.recovery.map(String.init) ?? "–", percent: d.s.recovery != nil), "Recovery")
                column(ring: ring(d.strainFraction, d.strainColor, d.strainGradient, d.strainText, percent: false), "Strain")
            }
            .padding(.top, 13)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func ring(_ f: Double, _ c: Color, _ g: [Color]?, _ value: String, percent: Bool) -> some View {
        GlanceRing(fraction: f, color: c, gradient: g, width: 4.6) { GlanceFigure(value: value, percent: percent, size: 23) }.frame(width: 75.5, height: 75.5)
    }

    private func column<R: View>(ring: R, _ label: String) -> some View {
        VStack(spacing: 0) { ring; GlanceCaption(text: label).frame(height: 12).padding(.top, 8.5) }.frame(width: 104)
    }
}

// MARK: - Small: the Sleep ring

private struct SleepRingView: View {
    let d: GlanceData

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) { GlanceStreak(days: d.s.dayStreak, stacked: true); Spacer(); GlanceBattery(pct: d.s.batteryPct, stacked: true) }
            Spacer(minLength: 0)
            GlanceRing(fraction: d.sleepFraction, color: Glance.steel, width: 6) {
                GlanceFigure(value: d.s.rest.map(String.init) ?? "–", percent: d.s.rest != nil, size: 34)
            }
            .frame(width: 98, height: 98).padding(.top, 2)
            Spacer(minLength: 0)
            ZStack {
                GlanceCaption(text: "Sleep", size: 10.5)
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
    /// The outer ring is `size` across, the inner one 77% of it, each with a line 6% of `size` (102 pt, 78.7 pt and 6.2 pt on the reference).
    var body: some View {
        let line = size * 0.061
        ZStack {
            // The outer ring is Strain, the inner ring Recovery, the same order as the app's day rings.
            GlanceRing(fraction: d.strainFraction, color: d.strainColor, gradient: d.strainGradient, width: line) { Color.clear }.frame(width: size - line, height: size - line)
            GlanceRing(fraction: d.recoveryFraction, color: d.recoveryColor, width: line) { Color.clear }.frame(width: size * 0.77 - line, height: size * 0.77 - line)
            PHMNButterflyShape().fill(Glance.ink).frame(width: size * 0.18, height: size * 0.18)
        }
        .frame(width: size, height: size)
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
                GlanceFigure(value: d.s.recovery.map(String.init) ?? "–", percent: d.s.recovery != nil, size: 17, color: d.recoveryColor)
                Spacer()
                GlanceFigure(value: d.strainText, size: 17, color: d.strainColor)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
    }
}

private struct WideDualView: View {
    let d: GlanceData
    // Measured on the reference: the rings are 102 pt across (the inner one 78.7 pt), centred 75 pt under the top edge; the figures are 16 pt, the
    // captions 9.5 pt, HRV and Calories 14 pt in grey; the columns end 17 pt from the rings.
    var body: some View {
        VStack(spacing: 0) {
            HStack { GlanceStreak(days: d.s.dayStreak); Spacer(); GlanceBattery(pct: d.s.batteryPct) }
                .padding(.leading, 20).padding(.trailing, 15.5).frame(height: 12).padding(.top, 17)
            HStack(spacing: 0) {
                column(alignment: .trailing, figure: GlanceFigure(value: d.s.recovery.map(String.init) ?? "–", percent: d.s.recovery != nil, size: 16, color: d.recoveryColor),
                       caption: "Recovery", captionColor: d.recoveryColor, second: "HRV", value: d.s.hrv.map(String.init) ?? "–")
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 17)
                DualRing(d: d, size: 102)
                column(alignment: .leading, figure: GlanceFigure(value: d.strainText, size: 16, color: d.strainColor),
                       caption: "Strain", captionColor: d.strainColor, second: "Calories", value: d.s.caloriesKcal?.formatted() ?? "–")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16.5)
            }
            .padding(.top, -5)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func column(alignment: HorizontalAlignment, figure: GlanceFigure, caption: String, captionColor: Color, second: String, value: String) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            figure.frame(height: 19)
            GlanceCaption(text: caption, color: captionColor).frame(height: 12)
            GlanceCaption(text: second, color: Glance.muted).frame(height: 12).padding(.top, 9)
            Text(verbatim: value).font(Glance.din(14.3)).foregroundStyle(Glance.muted).frame(height: 17).padding(.top, 2.6)
        }
        .padding(.top, 19.3)
        .frame(height: 102, alignment: .top)
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
