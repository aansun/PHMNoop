#if os(iOS)
import SwiftUI
import StrandDesign

/// The look of the Settings pages: a small tracked heading, and rows that are one translucent card each with a thin icon at the left and the
/// name in tracked capitals (a second line in plain type when a row needs one). No arrow at the end: the whole card is the button.
struct NunaSettingsHeading: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text).font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.35).textCase(.uppercase)
            .foregroundStyle(Color(red: 0.62, green: 0.64, blue: 0.66)).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct NunaSettingsCardRow: View {
    let icon: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var tint: Color?

    var body: some View {
        HStack(spacing: 18) {
            NunaIcon(name: icon, size: 19).foregroundStyle(tint ?? Color(red: 0.62, green: 0.64, blue: 0.66)).frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.2).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle).font(.nuna(size: 13, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 18).frame(minHeight: 55).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Opens this app's page in the iOS Settings app, where the language of the app is chosen (iOS keeps one language per app there).
func nunaOpenIOSSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}

/// A link to a Me route. Language has no page of its own in the app: it goes straight to iOS Settings, so every place that lists a route
/// opens it through here.
@ViewBuilder func nunaMeLink<Label: View>(_ route: NunaMeRoute, @ViewBuilder label: () -> Label) -> some View {
    if route == .language { Button(action: nunaOpenIOSSettings, label: label) } else { NavigationLink(value: route, label: label) }
}

/// A Settings row that opens one of the Me routes (and is remembered for the search page's "recent").
struct NunaSettingsLink: View {
    let route: NunaMeRoute
    let icon: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        nunaMeLink(route) { NunaSettingsCardRow(icon: icon, title: title, subtitle: subtitle) }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { NunaMeRecents.record(route) })
    }
}
#endif
