import SwiftUI
import WidgetKit
import AppIntents
import StrandDesign

// The Vital sign widget (WidgetVital, WidgetVitalConfig and WidgetsLock mockups): last night's HRV, resting heart rate, SpO2, breathing
// rate and skin temperature, with stress for the day. Small shows the first two chosen metrics, medium up to five, large all of them
// against the wearer's own normal range. Yellow marks only a metric outside that range. The numbers are finished values from the app.

enum NunaVitalMetric: String, AppEnum {
    case hrv, rhr, spo2, resp, skin, stress

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Vital sign" }
    static var caseDisplayRepresentations: [NunaVitalMetric: DisplayRepresentation] {
        [.hrv: DisplayRepresentation(title: "HRV", subtitle: "Average overnight"),
         .rhr: DisplayRepresentation(title: "Resting HR", subtitle: "Lowest overnight"),
         .spo2: DisplayRepresentation(title: "SpO₂", subtitle: "Blood oxygen"),
         .resp: DisplayRepresentation(title: "Breathing", subtitle: "Breaths per minute"),
         .skin: DisplayRepresentation(title: "Skin temp", subtitle: "Difference from baseline"),
         .stress: DisplayRepresentation(title: "Stress", subtitle: "Average, 0 to 3")]
    }
    var key: NunaVitalKey { NunaVitalKey(rawValue: rawValue) ?? .hrv }
}

struct NunaVitalIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Vital sign" }
    static var description: IntentDescription { "Choose the vitals the widget shows." }

    @Parameter(title: "Metrics", default: [.hrv, .rhr, .spo2, .resp, .skin])
    var metrics: [NunaVitalMetric]

    @Parameter(title: "Show change from baseline", default: true)
    var showDelta: Bool

    @Parameter(title: "Highlight what is out of range", default: true)
    var highlight: Bool
}

struct NunaVitalEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let keys: [NunaVitalKey]
    let showDelta: Bool
    let highlight: Bool
}

struct NunaVitalProvider: AppIntentTimelineProvider {
    private func keys(_ c: NunaVitalIntent) -> [NunaVitalKey] {
        // At most five, in the order chosen; an empty choice falls back to the usual five.
        let picked = c.metrics.prefix(5).map(\.key)
        return picked.isEmpty ? [.hrv, .rhr, .spo2, .resp, .skin] : Array(picked)
    }

    func placeholder(in context: Context) -> NunaVitalEntry {
        NunaVitalEntry(date: Date(), snapshot: .placeholder, keys: [.hrv, .rhr, .spo2, .resp, .skin], showDelta: true, highlight: true)
    }

    func snapshot(for configuration: NunaVitalIntent, in context: Context) async -> NunaVitalEntry {
        NunaVitalEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? (context.isPreview ? .placeholder : .unavailable),
                       keys: keys(configuration), showDelta: configuration.showDelta, highlight: configuration.highlight)
    }

    func timeline(for configuration: NunaVitalIntent, in context: Context) async -> Timeline<NunaVitalEntry> {
        let e = NunaVitalEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .unavailable,
                               keys: keys(configuration), showDelta: configuration.showDelta, highlight: configuration.highlight)
        return Timeline(entries: [e], policy: .after(Date().addingTimeInterval(1800)))
    }
}

struct NunaVitalWidget: Widget {
    static let kind = "NunaVitalWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: NunaVitalIntent.self, provider: NunaVitalProvider()) { entry in
            NunaVitalView(entry: entry).widgetURL(NunaWLink.health).nunaWidgetBackground()
        }
        .configurationDisplayName("Vital sign")
        .description("Last night's vitals against your own normal range.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private struct NunaVitalView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NunaVitalEntry
    private var s: WidgetSnapshot { entry.snapshot }
    private var values: [NunaVitalValue] { s.vitalValues(for: entry.keys) }
    private var flagged: Int { values.filter(\.outOfRange).count }

    private func color(_ v: NunaVitalValue) -> Color { entry.highlight && v.outOfRange ? NunaPalette.warning : NunaPalette.textPrimary }

    private var statusPill: some View {
        Group {
            if values.isEmpty { NunaWPill(text: Text("No data"), color: NunaPalette.textMuted) }
            else if flagged == 0 { NunaWPill(text: Text("All in range"), color: NunaPalette.charge) }
            else { NunaWPill(text: Text("\(flagged) out of range"), color: NunaPalette.warning) }
        }
    }

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

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                NunaWCap(text: Text("Vital"))
                Spacer()
                if values.isEmpty { Color.clear.frame(height: 20) } else if flagged == 0 { NunaWPill(text: Text("Normal"), color: NunaPalette.charge) } else { NunaWPill(text: Text("Check"), color: NunaPalette.warning) }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(values.prefix(2)) { v in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.key.label).font(.nuna(size: 9.5, weight: .heavy)).tracking(0.6).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(verbatim: v.text).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(color(v))
                            Text(verbatim: v.key.unit).font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                }
                if values.isEmpty { Text("No vitals yet").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
            }.padding(.top, 12)
            Spacer(minLength: 0)
            NunaW.updated(s.updated).font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { NunaWCap(text: Text("Last night's vitals")); Spacer(); statusPill }
            HStack(alignment: .top, spacing: 6) {
                ForEach(values) { v in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.key.short).font(.nuna(size: 8.5, weight: .heavy)).tracking(0.4).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.6)
                        Text(verbatim: v.text).font(.nuna(size: 19, weight: .bold, design: NunaType.design)).foregroundStyle(color(v)).minimumScaleFactor(0.6).lineLimit(1)
                        Text(verbatim: v.key.unit).font(.nuna(size: 9, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        Capsule().fill(entry.highlight && v.outOfRange ? NunaPalette.warning : NunaPalette.charge).frame(height: 4).padding(.top, 6)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.top, 14)
            Spacer(minLength: 0)
            HStack {
                Text("Against your own baseline").font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                Spacer()
                NunaW.updated(s.updated).font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
    }

    private func deltaText(_ v: NunaVitalValue) -> Text? {
        guard entry.showDelta, let d = v.delta, abs(d) >= 0.5 else { return nil }
        let amount = NunaW.number(abs(d))
        let arrow = d > 0 ? "▲" : "▼"
        return v.deltaBasis == "previous" ? Text("\(arrow) \(amount) from yesterday") : Text("\(arrow) \(amount) from average")
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { NunaWCap(text: Text("Last night's vitals")); Spacer(); statusPill }
            VStack(spacing: 0) {
                ForEach(values) { v in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.key.label).font(.nuna(size: 10, weight: .heavy)).tracking(0.6).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1)
                            if let t = deltaText(v) {
                                t.font(.nuna(size: 10, weight: .heavy)).foregroundStyle(entry.highlight && v.outOfRange ? NunaPalette.warning : NunaPalette.charge).lineLimit(1).minimumScaleFactor(0.7)
                            } else if v.outOfRange {
                                Text("Outside your range").font(.nuna(size: 10, weight: .heavy)).foregroundStyle(entry.highlight ? NunaPalette.warning : NunaPalette.textSecondary).lineLimit(1)
                            }
                        }.frame(width: 104, alignment: .leading)
                        track(v)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(verbatim: v.text).font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(color(v)).minimumScaleFactor(0.6).lineLimit(1)
                            Text(verbatim: v.key.unit).font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1)
                        }.frame(width: 78, alignment: .trailing)
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) { Rectangle().fill(NunaPalette.hairlineSoft).frame(height: 1) }
                }
                if values.isEmpty { Text("No vitals yet").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).padding(.top, 20) }
            }.padding(.top, 8)
            Spacer(minLength: 0)
            HStack {
                Text("Green band is your normal range").font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                Spacer()
                NunaW.updated(s.updated).font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
    }

    /// The wearer's own range as a track: the normal band is the middle half, the marker is last night's value.
    @ViewBuilder private func track(_ v: NunaVitalValue) -> some View {
        if let p = v.position {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule().fill(NunaPalette.charge.opacity(0.35)).frame(width: geo.size.width * 0.5).offset(x: geo.size.width * 0.25)
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(NunaPalette.textPrimary).frame(width: 5, height: 12)
                        .offset(x: geo.size.width * p - 2.5)
                }.frame(height: 6).frame(maxHeight: .infinity)
            }.frame(height: 14)
        } else {
            Color.clear.frame(height: 14)
        }
    }

    // MARK: Lock Screen

    private var circular: some View {
        let first = values.first
        return ZStack {
            AccessoryWidgetBackground()
            if let v = first {
                VStack(spacing: -1) {
                    Text(v.key.short).font(.system(size: 8, weight: .heavy)).opacity(0.7).textCase(.uppercase)
                    Text(verbatim: v.text).font(.system(size: 18, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                    Text(verbatim: v.key.unit).font(.system(size: 8, weight: .heavy)).opacity(0.7)
                }
            } else {
                Text("–").font(.system(size: 18, weight: .bold))
            }
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Vital").font(.system(size: 12, weight: .heavy))
                Spacer()
                if values.isEmpty { Text("No data").font(.system(size: 10, weight: .semibold)).opacity(0.7) }
                else if flagged == 0 { Text("Normal").font(.system(size: 10, weight: .semibold)).opacity(0.7) }
                else { Text("\(flagged) out of range").font(.system(size: 10, weight: .semibold)) }
            }
            ForEach(values.prefix(3)) { v in
                HStack {
                    Text(v.key.short).font(.system(size: 11, weight: .semibold)).opacity(0.75)
                    Spacer()
                    Text(verbatim: v.text + (v.key == .spo2 ? "%" : "")).font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var inline: some View {
        let parts = values.prefix(3).map { "\(String(localized: $0.key.shortInline)) \($0.text)" + ($0.key == .spo2 ? "%" : "") }
        return Text(verbatim: parts.isEmpty ? String(localized: "No data") : parts.joined(separator: " · "))
    }
}

extension NunaVitalKey {
    /// Plain-string form of the short label, for the one-line Lock Screen widget.
    var shortInline: String.LocalizationValue {
        switch self {
        case .hrv: "HRV"
        case .rhr: "RHR"
        case .spo2: "SpO₂"
        case .resp: "Breathing"
        case .skin: "Skin"
        case .stress: "Stress"
        }
    }
}
