import SwiftUI
import WidgetKit
import StrandDesign

// The Steps widget (Widgets mockup): today's steps against the wearer's target, small on the Home Screen.

struct NunaStepsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct NunaStepsProvider: TimelineProvider {
    func placeholder(in context: Context) -> NunaStepsEntry { NunaStepsEntry(date: Date(), snapshot: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (NunaStepsEntry) -> Void) {
        completion(NunaStepsEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? (context.isPreview ? .placeholder : .unavailable)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NunaStepsEntry>) -> Void) {
        completion(Timeline(entries: [NunaStepsEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .unavailable)], policy: .after(Date().addingTimeInterval(900))))
    }
}

struct NunaStepsWidget: Widget {
    static let kind = "NunaStepsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NunaStepsProvider()) { entry in
            NunaStepsView(snapshot: entry.snapshot).widgetURL(NunaWLink.today).nunaWidgetBackground()
        }
        .configurationDisplayName("Steps")
        .description("Today's steps and your target.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

private struct NunaStepsView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot
    private var goal: Int { max(snapshot.stepGoal ?? 10_000, 1) }
    private var fraction: Double { Double(snapshot.steps ?? 0) / Double(goal) }

    var body: some View {
        if family == .accessoryCircular { circular } else { small.padding(14) }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                NunaWCap(text: Text("Steps"))
                Spacer()
                Image(systemName: "figure.walk").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.restText)
            }
            Text(verbatim: snapshot.steps.map { NunaW.number(Double($0)) } ?? "–").font(.nuna(size: 30, weight: .bold, design: NunaType.design))
                .foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1).padding(.top, 10)
            Text("\(Int((fraction * 100).rounded()))% of \(NunaW.number(Double(goal)))").font(.nuna(size: 10.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).padding(.top, 4)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule().fill(fraction >= 1 ? NunaPalette.charge : NunaPalette.charge).frame(width: geo.size.width * min(fraction, 1))
                }
            }.frame(height: 7).padding(.top, 10)
            Spacer(minLength: 0)
            NunaW.updated(snapshot.updated).font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            NunaWRing(fraction: fraction, color: .primary, lineWidth: 5) {
                VStack(spacing: -1) {
                    Image(systemName: "figure.walk").font(.system(size: 10, weight: .bold))
                    Text(verbatim: snapshot.steps.map { $0 >= 1000 ? NunaW.number(Double($0) / 1000, decimals: 1) + "k" : String($0) } ?? "–")
                        .font(.system(size: 14, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                }
            }.padding(3)
        }
        .widgetAccentable()
    }
}
