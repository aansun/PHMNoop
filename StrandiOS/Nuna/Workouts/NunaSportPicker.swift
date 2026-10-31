#if os(iOS)
import SwiftUI
import StrandDesign

/// What a pick belongs to: an activity that adds Effort (the sport catalogue), one that helps Charge (recovery work) or one that is rest
/// (a nap, a night). The recovery and rest names are this app's own and are kept in `NunaActivityKind`.
enum NunaActivityKind: String, CaseIterable, Identifiable {
    case all, effort, charge, rest
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self { case .all: return "All"; case .effort: return "Effort"; case .charge: return "Charge"; case .rest: return "Rest" }
    }

    /// Recovery activities, the Charge tab. Saved like any other manual activity under the name as typed here.
    static let chargeNames = [
        "Acupuncture", "Air Compression", "Air Compression (Normatec)", "Breathwork", "Bright Light Therapy", "Chiropractor", "Cuddling with Child",
        "Cold Shower", "Contrast Therapy", "Dry Sauna", "Foam Rolling", "Guided Breathing - Increase Alertness", "Guided Breathing - Increase Relaxation",
        "Hot Tub", "Ice Bath", "Infrared Sauna", "Knitting", "Massage Therapy", "Meditation", "Non-sleep, deep rest", "Other - Recovery",
        "Percussive Massage", "Percussive Massage (Hypervolt)", "Playing with Child", "QiGong", "Red Light Therapy", "Restorative Yoga", "Sound healing",
        "Steam Room", "Stretching", "Tai Chi", "Warm Bath",
    ]
    /// Rest, the Rest tab. A pick here is added as a nap or a night of sleep, not as a workout.
    static let restNames = ["Nap", "Sleep"]

    static func isRest(_ name: String) -> Bool { restNames.contains { $0.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) == .orderedSame } }
    static func isCharge(_ name: String) -> Bool { chargeNames.contains { $0.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) == .orderedSame } }
}

/// The activity list as a Nuna page: a back arrow and the title, a search field, tabs for All, Effort, Charge and Rest, and one flat card per
/// activity with its symbol at the left. With `allowsCustom` a typed name that is not in the lists can be used as typed, and the most-recent
/// picks sit above the full list while the search is empty. `includesRest` offers the Rest tab (adding an activity by hand can be a nap; starting
/// one live or editing a workout cannot).
struct NunaSportPicker: View {
    @Binding var selection: String
    var allowsCustom = false
    var includesRest = false
    let onClose: () -> Void
    @State private var query = ""
    @State private var tab = NunaActivityKind.all

    /// A neutral symbol for a sport, by what its name says.
    static func symbol(for name: String) -> String { ActivitySport.symbol(for: name) }

    private var tabs: [NunaActivityKind] { includesRest ? NunaActivityKind.allCases : NunaActivityKind.allCases.filter { $0 != .rest } }
    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private struct Item: Identifiable { let name: String; let route: Bool; var id: String { name } }

    /// What the chosen tab lists, filtered by the search and in alphabetical order.
    private var items: [Item] {
        var out: [Item] = []
        func add(_ names: [String], route: (String) -> Bool = { _ in false }) { for n in names where !out.contains(where: { $0.name == n }) { out.append(Item(name: n, route: route(n))) } }
        let sports = WorkoutCatalog.matching(query)
        if tab == .all || tab == .effort { add(sports.map(\.name).filter { !NunaActivityKind.isCharge($0) }, route: { WorkoutCatalog.sport(named: $0)?.isDistanceSport == true }) }
        if tab == .all || tab == .charge { add(NunaActivityKind.chargeNames.filter { trimmed.isEmpty || $0.range(of: trimmed, options: .caseInsensitive) != nil }) }
        if includesRest, tab == .all || tab == .rest { add(NunaActivityKind.restNames.filter { trimmed.isEmpty || $0.range(of: trimmed, options: .caseInsensitive) != nil }) }
        return out.sorted { a, b in
            if a.name == "Other" { return false }
            if b.name == "Other" { return true }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
    /// Both the live-start and manual-log paths surface the same most-recent-first list. Searching intentionally hides it so the results stay
    /// focused; the preference contract caps this list at five entries.
    private var recents: [String] { trimmed.isEmpty && tab == .all ? RecentSportsPrefs.recent() : [] }
    private var showCustom: Bool {
        allowsCustom && !trimmed.isEmpty && WorkoutCatalog.sport(named: trimmed) == nil && !NunaActivityKind.isCharge(trimmed) && !NunaActivityKind.isRest(trimmed)
    }

    private func pick(_ name: String) { selection = name; onClose() }

    private func row(_ name: String, route: Bool) -> some View {
        let on = name.caseInsensitiveCompare(selection) == .orderedSame
        return Button { pick(name) } label: {
            HStack(spacing: 14) {
                NunaActivityGlyph(name: name, size: 28)
                    .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary).frame(width: 34, height: 34)
                Text(LocalizedStringKey(name)).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingHead(1)).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if route { Image(systemName: "location").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted) }
                if on { Image(systemName: "checkmark").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }
            }
            .padding(.horizontal, 12).frame(height: 54).frame(maxWidth: .infinity)
            .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var tabBar: some View {
        HStack(spacing: 24) {
            ForEach(tabs) { t in
                let on = tab == t
                Button { withAnimation(.easeInOut(duration: 0.2)) { tab = t } } label: {
                    VStack(spacing: 7) {
                        Text(t.title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingHead(1)).textCase(.uppercase)
                            .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                        Rectangle().fill(on ? NunaPalette.textPrimary : Color.clear).frame(height: 2)
                    }
                    .fixedSize().frame(minHeight: 40).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Select activity").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingHead(1.2)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left").font(.nuna(size: 23, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(width: 52, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel(Text("Back"))
                    Spacer()
                }
            }
            .padding(.horizontal, 8).padding(.top, 14).frame(height: 62)
            // The search and the tabs stay at the top while the list scrolls under them.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                    TextField("", text: $query, prompt: Text("Search for Activities").foregroundStyle(NunaPalette.textSecondary))
                        .font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().textCase(nil)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(NunaPalette.textMuted) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).frame(height: 48)
                .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NunaPalette.textPrimary.opacity(0.1), lineWidth: 1))
                tabBar
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 4).padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if showCustom {
                        Button { pick(trimmed) } label: {
                            HStack(spacing: 14) {
                                NunaGlyph("pencil", pointSize: 20, weight: .regular).foregroundStyle(NunaPalette.textSecondary).frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use as typed").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                                    Text(verbatim: trimmed).font(.nuna(size: 15, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).frame(height: 54).frame(maxWidth: .infinity)
                            .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                    if !recents.isEmpty {
                        nunaTrendsCap("Most recent")
                        ForEach(recents, id: \.self) { name in row(name, route: WorkoutCatalog.sport(named: name)?.isDistanceSport == true) }
                        nunaTrendsCap("All activities A–Z")
                    }
                    if items.isEmpty && !showCustom {
                        Text("No sport matches").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        ForEach(items) { row($0.name, route: $0.route) }
                        if tab != .rest, tab != .charge, items.contains(where: \.route) {
                            Text("The location icon marks sports that record a route.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 32)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }
        .background(NunaBackdrop())
        .presentationDragIndicator(.visible)
        .preferredColorScheme(NunaTheme.colorScheme)
        .onAppear { if NunaActivityKind.isRest(selection) { tab = .rest } else if NunaActivityKind.isCharge(selection) { tab = .charge } }
    }
}
#endif
