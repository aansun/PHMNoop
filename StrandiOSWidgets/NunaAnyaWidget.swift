import SwiftUI
import WidgetKit
import StrandDesign

// The Anya summary widget (Widgets and WidgetsLock mockups): the morning suggestion Anya wrote, small on the Home Screen and a card on the
// Lock Screen. The widget only shows the text the app stored in the shared App Group; it never reaches Anya or the network.

struct NunaAnyaEntry: TimelineEntry {
    let date: Date
    let text: String?
    let written: Date?
}

struct NunaAnyaProvider: TimelineProvider {
    /// App Group keys, the same ones `CoachBriefScheduler` writes.
    private static let textKey = "coachBrief.widgetText"
    private static let dateKey = "coachBrief.widgetDate"

    private func load() -> NunaAnyaEntry {
        let d = UserDefaults(suiteName: WidgetSnapshot.suiteName)
        return NunaAnyaEntry(date: Date(), text: d?.string(forKey: Self.textKey), written: d?.object(forKey: Self.dateKey) as? Date)
    }

    func placeholder(in context: Context) -> NunaAnyaEntry {
        let d = UserDefaults(suiteName: WidgetSnapshot.suiteName)
        return NunaAnyaEntry(date: Date(), text: d?.string(forKey: Self.textKey), written: d?.object(forKey: Self.dateKey) as? Date)
    }
    func getSnapshot(in context: Context, completion: @escaping (NunaAnyaEntry) -> Void) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NunaAnyaEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct NunaAnyaWidget: Widget {
    /// Also used by `CoachBriefScheduler.widgetKind` so a new brief reloads this widget.
    static let kind = "NunaAnyaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NunaAnyaProvider()) { entry in
            NunaAnyaView(entry: entry).widgetURL(NunaWLink.anya).nunaWidgetBackground()
        }
        .configurationDisplayName("Anya")
        .description("Anya's morning suggestion.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

private struct NunaAnyaView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NunaAnyaEntry

    var body: some View {
        if family == .accessoryRectangular { lock } else { home.padding(14) }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image("AnyaLogo").resizable().scaledToFit().frame(width: 22, height: 22)
                NunaWCap(text: Text("Anya"))
            }
            if let text = entry.text {
                Text(verbatim: text).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineSpacing(2).lineLimit(5).minimumScaleFactor(0.85).padding(.top, 10)
            } else {
                Text("No suggestion yet. Turn on the morning brief in Anya.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).padding(.top, 10)
            }
            Spacer(minLength: 0)
            if let w = entry.written { Text("Updated \(w.formatted(date: .omitted, time: .shortened))").font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textMuted) }
        }
    }

    private var lock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image("AnyaGlyph").renderingMode(.template).resizable().scaledToFit().frame(width: 14, height: 14).widgetAccentable()
                Text("Anya").font(.system(size: 12, weight: .heavy))
                Spacer()
                if let w = entry.written { Text(w, style: .time).font(.system(size: 10, weight: .semibold)).opacity(0.7) }
            }
            Text(verbatim: entry.text ?? String(localized: "No suggestion yet")).font(.system(size: 12, weight: .semibold)).lineLimit(3)
        }
    }
}
