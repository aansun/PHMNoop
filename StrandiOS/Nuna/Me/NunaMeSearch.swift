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

    /// What a search finds: a whole screen, or one setting on a screen. Both open the screen.
    struct Hit: Identifiable {
        let route: NunaMeRoute
        let title: String
        let parent: String        // the screen's own title, shown under a setting
        let icon: String
        let group: String
        let isSetting: Bool
        var id: String { "\(route)-\(title)-\(isSetting)" }
    }

    /// Screens and settings that contain every word typed, in the app language or in English. What is named by the search comes first, a
    /// screen and then the settings on screens; what only matches through keywords or notes follows.
    static func search(_ query: String) -> [Hit] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        func hay(_ parts: [String]) -> String {
            fold(parts.flatMap { [$0, String(localized: String.LocalizationValue($0))] }.joined(separator: " "))
        }
        func matches(_ text: String) -> Bool { words.allSatisfy { text.contains($0) } }

        var screens: [Hit] = [], screensByKeyword: [Hit] = []
        for item in all {
            let hit = Hit(route: item.route, title: item.title, parent: item.group, icon: item.icon, group: item.group, isSetting: false)
            if matches(hay([item.title])) { screens.append(hit) }
            else if matches(hay([item.title, item.group]) + " " + fold(item.keywords)) { screensByKeyword.append(hit) }
        }
        var byName: [Hit] = [], byNote: [Hit] = []
        var seen = Set((screens + screensByKeyword).map { "\($0.route)|\($0.title)" })
        for st in NunaMeSettingsIndex.all {
            guard let owner = all.first(where: { $0.route == st.route }) else { continue }
            let key = "\(st.route)|\(st.title)"
            guard !seen.contains(key) else { continue }
            let hit = Hit(route: st.route, title: st.title, parent: owner.title, icon: owner.icon, group: owner.group, isSetting: true)
            if matches(hay([st.title])) { byName.append(hit); seen.insert(key) }
            else if matches(hay([st.title, st.note, owner.title])) { byNote.append(hit); seen.insert(key) }
        }
        return screens + byName + screensByKeyword + byNote
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
                let hits = found.filter { $0.group == g }
                if !hits.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        NunaRuledHeader(LocalizedStringKey(g), count: hits.count)
                        hitsCard(hits)
                    }
                }
            }
        }
    }

    /// Title, how many, then a hairline to the edge: the Journal's section header.
    private func header(_ title: LocalizedStringKey, count: Int, trailing: AnyView?) -> some View {
        NunaRuledHeader(title, count: count) { if let trailing { trailing } }
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

    /// A screen shows its group as the note; a setting shows the screen it lives on.
    private func hitsCard(_ hits: [NunaMeIndex.Hit]) -> some View {
        NunaCard(small: true) {
            VStack(spacing: 0) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                    if i > 0 { NunaDivider() }
                    NavigationLink(value: hit.route) {
                        let base = NunaListRow(LocalizedStringKey(hit.title), subtitle: LocalizedStringKey(hit.isSetting ? hit.parent : hit.group),
                                               systemImage: hit.icon, showsChevron: true)
                        if hit.route == .anya && !hit.isSetting { base.textCase(nil) } else { base }
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { NunaMeRecents.record(hit.route) })
                }
            }
        }
    }
}
#endif
