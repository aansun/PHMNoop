#if os(iOS)
import SwiftUI
import WidgetKit
import StrandDesign

/// Widgets and Lock Screen (WidgetSettings.dc): how fresh the data the widgets show is, a refresh, the widgets that exist and
/// how to add one. Widgets only draw numbers the app has already computed and shared; they compute nothing themselves.
struct NunaWidgetSettingsView: View {
    @State private var snapshot = WidgetSnapshot.load()
    @State private var refreshed = false

    private struct Item: Identifiable { let id = UUID(); let title: LocalizedStringKey; let note: LocalizedStringKey; let sizes: LocalizedStringKey; let icon: String }
    private let items: [Item] = [
        Item(title: "Scores", note: "Charge, Effort and Rest", sizes: "S · M · L · Lock Screen", icon: "circle.dashed"),
        Item(title: "Vital sign", note: "HRV, resting heart rate, SpO₂, breathing, skin temperature. Choose which ones when you add it.", sizes: "S · M · L · Lock Screen", icon: "waveform.path.ecg.rectangle"),
        Item(title: "Heart rate", note: "Live heart rate and the last 3 hours", sizes: "M", icon: "heart"),
        Item(title: "Stress", note: "Stress curve by hour", sizes: "M", icon: "waveform.path.ecg"),
        Item(title: "Anya brief", note: "The morning brief from Anya", sizes: "S · Lock Screen", icon: NunaGlyph.anya),
        Item(title: "Steps", note: "Today's steps and your target", sizes: "S · Lock Screen", icon: "figure.walk"),
    ]

    private var age: TimeInterval? { snapshot.map { Date().timeIntervalSince($0.updated) } }
    private var fresh: Bool { (age ?? .infinity) < 6 * 3600 }

    var body: some View {
        NunaDetailScreen("Widgets and Lock Screen") {
            Text("See your scores and vitals without opening the app. Widgets use ready-made numbers from the app and do not compute anything themselves.")
                .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            NunaCard(highlight: fresh) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { nunaTrendsCap("Widget data"); Spacer()
                        NunaChip(snapshot == nil ? "No data yet" : (fresh ? "Fresh" : "Old"), color: snapshot != nil && fresh ? NunaPalette.charge : nil) }
                    HStack {
                        stat("Last updated", snapshot.map { NunaDeviceFormat.clock($0.updated.timeIntervalSince1970) } ?? "–", snapshot.map { NunaDeviceFormat.ago($0.updated.timeIntervalSince1970) })
                        stat("Source", snapshot == nil ? "–" : (snapshot?.bonded == true ? String(localized: "Strap") : String(localized: "Last known")), nil)
                    }
                    Button {
                        WidgetCenter.shared.reloadAllTimelines(); snapshot = WidgetSnapshot.load(); refreshed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { refreshed = false }
                    } label: {
                        Text(refreshed ? "Asked iOS to refresh" : "Refresh now").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 50).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
            NunaSettingsGroup("Available widgets") {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                    if i > 0 { NunaDivider() }
                    NunaListRow(it.title, description: it.note, systemImage: it.icon) { Text(it.sizes).font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                }
            }
            NunaSettingsGroup("How to add one") {
                step(1, "Hold the Home Screen until the icons wiggle, then tap +.")
                NunaDivider()
                step(2, "Find PHMN and choose a widget and its size.")
                NunaDivider()
                step(3, "For the Lock Screen, hold the Lock Screen and tap Customize.")
            }
            nunaFootnote("Widget data is shared through an App Group on this iPhone. Nothing goes to a server. iOS limits how often widgets refresh, so they can be a few minutes behind.")
        }
        .task { snapshot = WidgetSnapshot.load() }
    }

    private func stat(_ l: LocalizedStringKey, _ v: String, _ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: v).font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            if let note { Text(verbatim: note).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ n: Int, _ t: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(verbatim: "\(n)").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(width: 30, height: 30).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
            Text(t).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            Spacer(minLength: 0)
        }.padding(.vertical, 12)
    }
}
#endif
