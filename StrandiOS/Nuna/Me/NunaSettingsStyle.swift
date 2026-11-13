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

// MARK: - One card per setting

/// A heading and the cards under it. The page-wide shape of the Settings pages: one small ruled heading for each thing the page does, and under it one
/// card for each setting, so a card is one choice and nothing shares a card with something else (Appearance is the model).
struct NunaSettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaRuledHeader(title)
            content
        }
    }
}

/// The card one setting sits in, inset like the cards on the Appearance page.
struct NunaSettingsCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) { VStack(spacing: 0) { content } }
    }
}

/// A switch on a card of its own.
struct NunaSettingsSwitch: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var systemImage: String?
    @Binding var isOn: Bool
    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, systemImage: String? = nil, isOn: Binding<Bool>) {
        self.title = title; self.subtitle = subtitle; self.systemImage = systemImage; self._isOn = isOn
    }
    var body: some View {
        NunaSettingsCard { NunaToggleRow(title, subtitle: subtitle, systemImage: systemImage, isOn: $isOn).padding(.vertical, 8) }
    }
}

/// A choice among several as one row (put it in a `NunaSettingsCard`): the name, the choice in force and an up-down arrow. It opens the app's bottom-sheet
/// drop-down with the current option ticked, so the page stays short however many options there are.
struct NunaChoiceRow<Value: Hashable>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let systemImage: String?
    let options: [(value: Value, title: LocalizedStringKey)]
    @Binding var selection: Value

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, systemImage: String? = nil,
         options: [(value: Value, title: LocalizedStringKey)], selection: Binding<Value>) {
        self.title = title; self.subtitle = subtitle; self.systemImage = systemImage; self.options = options; self._selection = selection
    }

    private var current: LocalizedStringKey { options.first { $0.value == selection }?.title ?? options[0].title }

    var body: some View {
        NunaMenu {
            ForEach(options.indices, id: \.self) { i in
                NunaMenuItem(options[i].title, selected: options[i].value == selection) { selection = options[i].value }
            }
        } label: {
            NunaListRow(title, subtitle: subtitle, systemImage: systemImage) {
                HStack(spacing: 6) {
                    Text(current).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    Image(systemName: "chevron.up.chevron.down").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
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
