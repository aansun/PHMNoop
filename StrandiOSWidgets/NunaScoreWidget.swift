import SwiftUI
import WidgetKit
import AppIntents
import StrandDesign

// The Score widget (Widgets and WidgetsLock mockups): Charge, Effort and Rest as rings. Small shows Charge with the other two beside it,
// medium three rings, large three rings with HRV, resting heart rate, steps and calories. On the Lock Screen it is a ring (the metric
// is chosen when the widget is added), a three-line "Today" card, or one line above the clock.

enum NunaScoreMetric: String, AppEnum {
    case charge, effort, rest, heart

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Score" }
    static var caseDisplayRepresentations: [NunaScoreMetric: DisplayRepresentation] {
        [.charge: "Charge", .effort: "Effort", .rest: "Rest", .heart: "Heart rate"]
    }
}

struct NunaScoreIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Score" }
    static var description: IntentDescription { "Charge, Effort and Rest at a glance." }

    @Parameter(title: "Lock Screen ring", default: .charge)
    var lockMetric: NunaScoreMetric
}

struct NunaScoreEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let lockMetric: NunaScoreMetric
}

struct NunaScoreProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NunaScoreEntry { NunaScoreEntry(date: Date(), snapshot: .placeholder, lockMetric: .charge) }

    func snapshot(for configuration: NunaScoreIntent, in context: Context) async -> NunaScoreEntry {
        NunaScoreEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? (context.isPreview ? .placeholder : .unavailable), lockMetric: configuration.lockMetric)
    }

    func timeline(for configuration: NunaScoreIntent, in context: Context) async -> Timeline<NunaScoreEntry> {
        let entry = NunaScoreEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .unavailable, lockMetric: configuration.lockMetric)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
    }
}

struct NunaScoreWidget: Widget {
    static let kind = "NunaScoreWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: NunaScoreIntent.self, provider: NunaScoreProvider()) { entry in
            NunaScoreView(entry: entry).widgetURL(NunaWLink.today).nunaWidgetBackground()
        }
        .configurationDisplayName("Score")
        .description("Charge, Effort and Rest as rings.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private struct NunaScoreView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NunaScoreEntry
    private var s: WidgetSnapshot { entry.snapshot }

    private var effortText: String { s.effortDisplay ?? s.effort.map(String.init) ?? "–" }
    private var effortFraction: Double { Double(s.effort ?? 0) / 100 }
    private var charge: Int? { s.recovery }

    var body: some View {
        switch family {
        case .systemSmall: small.padding(14)
        case .systemMedium: medium.padding(14)
        case .systemLarge: large.padding(16)
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small.padding(14)
        }
    }

    // MARK: Home Screen

    private func scoreRing(_ fraction: Double, _ color: Color, _ text: String, unit: String? = nil, size: CGFloat, font: CGFloat, line: CGFloat) -> some View {
        NunaWRing(fraction: fraction, color: color, lineWidth: line) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: text).font(.nuna(size: font, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                if let unit { Text(verbatim: unit).font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
            }
            .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(width: size, height: size)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                NunaWCap(text: Text("Today"))
                Spacer()
                Circle().fill(NunaW.chargeColor(charge)).frame(width: 8, height: 8)
            }
            HStack(spacing: 10) {
                scoreRing(Double(charge ?? 0) / 100, NunaW.chargeColor(charge), charge.map(String.init) ?? "–", unit: charge == nil ? nil : "%", size: 74, font: 19, line: 9)
                VStack(alignment: .leading, spacing: 8) {
                    miniScore("EFFORT", effortText, NunaPalette.effortText)
                    miniScore("REST", s.rest.map { "\($0)%" } ?? "–", NunaPalette.restText)
                }
            }.padding(.top, 12)
            Spacer(minLength: 0)
            NunaW.updated(s.updated).font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
        }
    }

    private func miniScore(_ label: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.nuna(size: 9, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(color).minimumScaleFactor(0.7).lineLimit(1)
        }
    }

    private var rings: some View {
        HStack {
            Spacer(minLength: 0)
            ringColumn("Charge", Double(charge ?? 0) / 100, NunaW.chargeColor(charge), charge.map(String.init) ?? "–", unit: charge == nil ? nil : "%")
            Spacer(minLength: 0)
            ringColumn("Effort", effortFraction, NunaPalette.effortText, effortText, unit: nil)
            Spacer(minLength: 0)
            ringColumn("Rest", Double(s.rest ?? 0) / 100, NunaPalette.restText, s.rest.map(String.init) ?? "–", unit: s.rest == nil ? nil : "%")
            Spacer(minLength: 0)
        }
    }

    private func ringColumn(_ title: LocalizedStringKey, _ f: Double, _ c: Color, _ v: String, unit: String?) -> some View {
        let size: CGFloat = family == .systemLarge ? 92 : 80
        return VStack(spacing: 5) {
            scoreRing(f, c, v, unit: unit, size: size, font: family == .systemLarge ? 24 : 21, line: family == .systemLarge ? 10 : 9)
            if family == .systemLarge { Text(title).font(.nuna(size: 10, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary) }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                NunaWCap(text: Text("Charge · Effort · Rest"))
                Spacer()
                if let bpm = s.bpm {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                        Text(verbatim: "\(bpm)").font(.nuna(size: 11, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    }
                }
            }
            rings.padding(.top, 10)
            Spacer(minLength: 0)
            HStack {
                NunaW.updated(s.updated).font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                Spacer()
                NunaWBattery(percent: s.batteryPct)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                NunaWCap(text: Text(NunaW.chargeWord(charge)))
                Spacer()
                NunaW.updated(s.updated).font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
            rings.padding(.top, 14)
            let hrv = s.vitals?.first(where: { $0.key == "hrv" })
            let rhr = s.vitals?.first(where: { $0.key == "rhr" })
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                gridCell("HRV", s.hrv.map(String.init) ?? "–", "ms", delta: hrv?.delta, goodWhenUp: true, color: hrv.map { $0.outOfRange ? NunaPalette.warning : NunaPalette.charge })
                gridCell("Resting HR", s.restingHr.map(String.init) ?? "–", "bpm", delta: rhr?.delta, goodWhenUp: false, color: rhr.map { $0.outOfRange ? NunaPalette.warning : NunaPalette.charge })
                gridCell("Steps", s.steps.map { NunaW.number(Double($0)) } ?? "–", "", delta: nil, goodWhenUp: true, color: nil)
                gridCell("Calories", s.caloriesKcal.map { NunaW.number(Double($0)) } ?? "–", "kcal", delta: nil, goodWhenUp: true, color: nil)
            }
            .padding(.top, 18).overlay(alignment: .top) { Rectangle().fill(NunaPalette.hairline).frame(height: 1).offset(y: 2) }
            Spacer(minLength: 0)
            HStack {
                HStack(spacing: 6) { Image(systemName: "applewatch").font(.system(size: 11, weight: .bold)); NunaWBattery(percent: s.batteryPct) }.foregroundStyle(NunaPalette.textSecondary)
                Spacer()
                if let bpm = s.bpm {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                        Text("\(bpm) bpm").font(.nuna(size: 11, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    }
                }
            }
        }
    }

    private func gridCell(_ label: LocalizedStringKey, _ value: String, _ unit: String, delta: Double?, goodWhenUp: Bool, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.nuna(size: 9.5, weight: .heavy)).tracking(0.6).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(color ?? NunaPalette.textPrimary).minimumScaleFactor(0.7).lineLimit(1)
                if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
            }
            if let delta, abs(delta) >= 0.5 {
                Text(verbatim: "\(delta > 0 ? "▲" : "▼") \(NunaW.number(abs(delta)))").font(.nuna(size: 10, weight: .heavy))
                    .foregroundStyle((delta > 0) == goodWhenUp ? NunaPalette.charge : NunaPalette.warning)
            }
        }
    }

    // MARK: Lock Screen

    private var lockValue: (fraction: Double, text: String, caption: LocalizedStringKey) {
        switch entry.lockMetric {
        case .charge: return (Double(charge ?? 0) / 100, charge.map(String.init) ?? "–", "CHARGE")
        case .effort: return (effortFraction, effortText, "EFFORT")
        case .rest: return (Double(s.rest ?? 0) / 100, s.rest.map(String.init) ?? "–", "REST")
        case .heart: return (min(Double(s.bpm ?? 0) / 200, 1), s.bpm.map(String.init) ?? "–", "BPM")
        }
    }

    private var circular: some View {
        let v = lockValue
        return ZStack {
            AccessoryWidgetBackground()
            NunaWRing(fraction: v.fraction, color: .primary, lineWidth: 5) {
                VStack(spacing: -1) {
                    Text(verbatim: v.text).font(.system(size: 17, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                    Text(v.caption).font(.system(size: 7, weight: .heavy)).opacity(0.7)
                }
            }.padding(3)
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Today").font(.system(size: 12, weight: .heavy))
                Spacer()
                Text(s.updated, style: .time).font(.system(size: 10, weight: .semibold)).opacity(0.7)
            }
            lockLine("Charge", charge.map { "\($0)%" } ?? "–")
            lockLine("Effort", effortText)
            lockLine("Rest", s.rest.map { "\($0)%" } ?? "–")
        }
    }

    private func lockLine(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11, weight: .semibold)).opacity(0.75)
            Spacer()
            Text(verbatim: value).font(.system(size: 12, weight: .bold, design: .rounded))
        }
    }

    private var inline: some View {
        let parts = [charge.map { String(localized: "Charge \($0)%") }, s.hrv.map { String(localized: "HRV \($0)") }].compactMap { $0 }
        return Text(verbatim: parts.isEmpty ? String(localized: "No data") : parts.joined(separator: " · "))
    }
}
