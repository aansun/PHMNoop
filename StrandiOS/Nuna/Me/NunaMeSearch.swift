#if os(iOS)
import SwiftUI
import StrandDesign

/// One screen of the Me hub that search can open. `title` and `group` are the English keys the screens themselves use, so they translate
/// with the rest of the app; `keywords` are extra English words people reach for (kg, dark, siri) and are matched but never shown.
struct NunaMeItem: Identifiable {
    let route: NunaMeRoute
    let title: String
    let icon: String
    let group: String
    var keywords = ""
    var id: String { String(describing: route) }
}

/// Everything under Me, in the order the hub lists it.
enum NunaMeIndex {
    static let all: [NunaMeItem] = [
        .init(route: .persona, title: "Persona", icon: "person.fill", group: "Account and device", keywords: "profile age height weight sex birthday"),
        .init(route: .zones, title: "Heart-rate zones", icon: "heart", group: "Account and device", keywords: "max heart rate zone hrmax"),
        .init(route: .goals, title: "Targets", icon: "target", group: "Account and device", keywords: "goal steps sleep need effort"),
        .init(route: .devices, title: "Devices", icon: "applewatch", group: "Account and device", keywords: "strap whoop oura pair bluetooth battery"),
        .init(route: .anya, title: "Anya", icon: NunaGlyph.anya, group: "Account and device", keywords: "coach ai key memory voice assistant"),
        .init(route: .appearance, title: "Appearance", icon: "slider.horizontal.3", group: "Appearance", keywords: "theme dark light colour color font style experience nuna icon"),
        .init(route: .units, title: "Units", icon: "ruler", group: "Appearance", keywords: "metric imperial kg lb km miles temperature"),
        .init(route: .language, title: "Language", icon: "globe", group: "Appearance", keywords: "bahasa english translation"),
        .init(route: .widgets, title: "Widgets and Lock Screen", icon: "square.grid.2x2.fill", group: "Appearance", keywords: "home screen live activity"),
        .init(route: .notifications, title: "Notifications", icon: "bell.fill", group: "Notifications and automation", keywords: "alerts reminder brief journal battery"),
        .init(route: .automations, title: "Strap automations", icon: "applewatch.radiowaves.left.and.right", group: "Notifications and automation", keywords: "wrist haptic buzz"),
        .init(route: .doubleTap, title: "Double tap", icon: "hand.tap", group: "Notifications and automation", keywords: "gesture strap action"),
        .init(route: .presence, title: "Strap on and off", icon: "figure.stand", group: "Notifications and automation", keywords: "wear presence detect"),
        .init(route: .sessionCues, title: "Session cues", icon: "speaker.wave.2", group: "Notifications and automation", keywords: "audio coach voice workout"),
        .init(route: .sedentary, title: "Sitting too long", icon: "chair", group: "Notifications and automation", keywords: "sedentary inactivity move"),
        .init(route: .shortcuts, title: "Siri and Shortcuts", icon: "mic", group: "Notifications and automation", keywords: "siri intent automation"),
        .init(route: .alarm, title: "Smart alarm", icon: "alarm", group: "Notifications and automation", keywords: "wake sleep window"),
        .init(route: .features, title: "Optional features", icon: "checkmark.circle.fill", group: "Notifications and automation", keywords: "water hydration journal auto workouts"),
        .init(route: .data, title: "Data and integrations", icon: "square.and.arrow.up", group: "Data", keywords: "export csv share"),
        .init(route: .backup, title: "Backup", icon: "clock.arrow.circlepath", group: "Data", keywords: "restore folder icloud"),
        .init(route: .imports, title: "Import data", icon: "square.and.arrow.down", group: "Data", keywords: "whoop export csv nutrition lifting"),
        .init(route: .appleHealth, title: "Apple Health", icon: "heart.text.square", group: "Data", keywords: "healthkit steps weight"),
        .init(route: .strava, title: "Strava", icon: "figure.run", group: "Data", keywords: "upload activities"),
        .init(route: .privacy, title: "Privacy", icon: "lock.shield.fill", group: "Data", keywords: "data local on device"),
        .init(route: .advanced, title: "Advanced", icon: "flame.fill", group: "More", keywords: "baseline hrv"),
        .init(route: .experiments, title: "Experiments", icon: "flask", group: "More", keywords: "experimental flags"),
        .init(route: .testCentre, title: "Test Centre", icon: "testtube.2", group: "More", keywords: "debug diagnostics logs"),
        .init(route: .about, title: "About and help", icon: "info.circle.fill", group: "More", keywords: "version credits how it works"),
    ]

    static let groups = ["Account and device", "Appearance", "Notifications and automation", "Data", "More"]

    static func item(_ id: String) -> NunaMeItem? { all.first { $0.id == id } }

    /// Items whose name (in the app language or in English), group or keywords contain every word typed.
    static func search(_ query: String) -> [NunaMeItem] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return all.filter { item in
            let hay = fold([item.title, String(localized: String.LocalizationValue(item.title)), item.group,
                            String(localized: String.LocalizationValue(item.group)), item.keywords].joined(separator: " "))
            return words.allSatisfy { hay.contains($0) }
        }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).trimmingCharacters(in: .whitespaces)
    }
}

/// The last settings opened from Me, newest first.
enum NunaMeRecents {
    static let key = "nuna.me.recents"
    static let limit = 6

    static func ids(_ raw: String) -> [String] { raw.split(separator: ",").map(String.init) }

    static func record(_ route: NunaMeRoute) {
        let id = String(describing: route)
        guard NunaMeIndex.item(id) != nil else { return }
        let current = ids(UserDefaults.standard.string(forKey: key) ?? "").filter { $0 != id }
        UserDefaults.standard.set(([id] + current).prefix(limit).joined(separator: ","), forKey: key)
    }
}

/// Search over the settings, and the settings opened last. Sections carry the same ruled header as the Journal.
struct NunaMeSearchView: View {
    @AppStorage(NunaMeRecents.key) private var recentsRaw = ""
    @State private var query = ""
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var recent: [NunaMeItem] { NunaMeRecents.ids(recentsRaw).compactMap(NunaMeIndex.item) }

    var body: some View {
        NunaDetailScreen("Search") {
            field
            if trimmed.isEmpty { recentSection } else { resultSections }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focused = true } }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            TextField("", text: $query, prompt: Text("Search settings").foregroundStyle(NunaPalette.textMuted))
                .font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .focused($focused).submitLabel(.search).autocorrectionDisabled().textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.nuna(size: 17)).foregroundStyle(NunaPalette.textMuted)
                }.buttonStyle(.plain).accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 16).frame(height: 52)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
    }

    // MARK: Sections

    @ViewBuilder private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Recent", count: recent.count, trailing: recent.isEmpty ? nil : AnyView(
                Button { recentsRaw = "" } label: {
                    Text("Clear").font(.nuna(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary)
                }.buttonStyle(.plain)))
            if recent.isEmpty {
                Text("Settings you open show up here.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                card(recent)
            }
        }
    }

    @ViewBuilder private var resultSections: some View {
        let found = NunaMeIndex.search(trimmed)
        if found.isEmpty {
            Text("No settings match.").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        } else {
            ForEach(NunaMeIndex.groups, id: \.self) { g in
                let items = found.filter { $0.group == g }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        header(LocalizedStringKey(g), count: items.count, trailing: nil)
                        card(items)
                    }
                }
            }
        }
    }

    /// Title, how many, then a hairline to the edge: the Journal's section header.
    private func header(_ title: LocalizedStringKey, count: Int, trailing: AnyView?) -> some View {
        HStack(spacing: 10) {
            nunaTrendsCap(title).lineLimit(1).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "\(count)").font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            Rectangle().fill(NunaPalette.hairline).frame(height: 1)
            if let trailing { trailing }
        }
    }

    /// Anya's name is never set in capitals, as in the hub.
    @ViewBuilder private func row(_ item: NunaMeItem) -> some View {
        let base = NunaListRow(LocalizedStringKey(item.title), subtitle: LocalizedStringKey(item.group), systemImage: item.icon, showsChevron: true)
        if item.route == .anya { base.textCase(nil) } else { base }
    }

    private func card(_ items: [NunaMeItem]) -> some View {
        NunaCard(small: true) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { NunaDivider() }
                    NavigationLink(value: item.route) { row(item) }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { NunaMeRecents.record(item.route) })
                }
            }
        }
    }
}
#endif
