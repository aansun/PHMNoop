#if os(iOS)
import SwiftUI
import StrandDesign

/// The sport list as a Nuna sheet: a search field and one card of rows, each with a symbol, the sport, a location mark for route
/// sports and a check on the chosen one. With `allowsCustom` a typed name that is not in the catalogue can be used as typed,
/// and the last picks sit above the full list while the search is empty.
struct NunaSportPicker: View {
    @Binding var selection: String
    var allowsCustom = false
    let onClose: () -> Void
    @State private var query = ""

    /// A neutral symbol for a sport, by what its name says.
    static func symbol(for name: String) -> String { ActivitySport.symbol(for: name) }

    private var sports: [WorkoutCatalog.Sport] { WorkoutCatalog.matching(query) }
    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var recents: [String] { trimmed.isEmpty && allowsCustom ? RecentSportsPrefs.recent() : [] }
    private var showCustom: Bool { allowsCustom && !trimmed.isEmpty && WorkoutCatalog.sport(named: trimmed) == nil }

    private func pick(_ name: String) { selection = name; onClose() }

    private func row(_ name: String, route: Bool) -> some View {
        let on = name.caseInsensitiveCompare(selection) == .orderedSame
        return Button { pick(name) } label: {
            HStack(spacing: 12) {
                NunaIconTile(Self.symbol(for: name), tint: on ? NunaPalette.charge : nil)
                Text(LocalizedStringKey(name)).font(.nuna(size: 16, weight: on ? .heavy : .semibold)).foregroundStyle(NunaPalette.textPrimary)
                Spacer(minLength: 8)
                if route { Image(systemName: "location").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted) }
                if on { Image(systemName: "checkmark").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.charge) }
            }
            .padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                HStack {
                    Text("Sport").font(.nuna(size: NunaTypeSize.h2, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    Button(action: onClose) {
                        Text("Done").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(NunaPalette.textMuted)
                    TextField("", text: $query, prompt: Text("Search").foregroundStyle(NunaPalette.textMuted))
                        .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(NunaPalette.textMuted) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).frame(height: 48)
                .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
                if showCustom {
                    Button { pick(trimmed) } label: {
                        NunaCard(small: true) { NunaListRow("Use as typed", subtitle: LocalizedStringKey(trimmed), systemImage: "pencil", showsChevron: true) }
                    }.buttonStyle(.plain)
                }
                if !recents.isEmpty {
                    nunaTrendsCap("Recent")
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                        VStack(spacing: 0) {
                            ForEach(Array(recents.enumerated()), id: \.element) { i, name in
                                if i > 0 { NunaDivider() }
                                row(name, route: WorkoutCatalog.sport(named: name)?.isDistanceSport == true)
                            }
                        }
                    }
                    nunaTrendsCap("All activities")
                }
                if sports.isEmpty && !showCustom {
                    Text("No sport matches").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else if !sports.isEmpty {
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                        VStack(spacing: 0) {
                            ForEach(Array(sports.enumerated()), id: \.element.id) { i, sport in
                                if i > 0 { NunaDivider() }
                                row(sport.name, route: sport.isDistanceSport)
                            }
                        }
                    }
                    Text("The location icon marks sports that record a route.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 20).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .preferredColorScheme(NunaTheme.colorScheme)
    }
}
#endif
