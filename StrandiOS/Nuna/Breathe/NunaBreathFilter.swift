#if os(iOS)
import SwiftUI
import StrandDesign

/// What Explore is narrowed to: some purposes, some levels, and a word to search for. Nothing chosen is "All", so the default shows every technique.
/// Within one list (purposes, or levels) a technique needs to match any of the ticked boxes; across the two lists and the search it needs to match all.
struct NunaBreathFilter: Equatable {
    var groups: Set<NunaBreathGroup> = []
    var levels: Set<NunaBreathLevel> = []
    var query = ""

    /// Ticked boxes, not the search word: this is what the filter button counts.
    var count: Int { groups.count + levels.count }
    var isActive: Bool { count > 0 }

    func apply(to all: [NunaBreathItem]) -> [NunaBreathItem] {
        let inGroups: Set<String>? = groups.isEmpty ? nil : Set(groups.flatMap(\.items).map(\.id))
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { item in
            if let inGroups, !inGroups.contains(item.id) { return false }
            if !levels.isEmpty, !levels.contains(item.level) { return false }
            if !word.isEmpty, !(item.title.localizedCaseInsensitiveContains(word) || item.blurb.localizedCaseInsensitiveContains(word)) { return false }
            return true
        }
    }
}

/// The search box over the list, and the button that opens the filters. The button carries the number of ticked boxes.
struct NunaBreathSearchBar: View {
    @Binding var query: String
    let filterCount: Int
    let onFilters: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary)
                TextField("", text: $query, prompt: Text("Search for a technique…").foregroundStyle(NunaPalette.textMuted))
                    .font(.nunaWords(size: 16)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    .focused($focused).submitLabel(.search).autocorrectionDisabled().textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textMuted)
                    }.buttonStyle(.plain).accessibilityLabel(Text("Clear"))
                }
            }
            .padding(.horizontal, 16).frame(height: 54)
            .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
            .contentShape(Rectangle()).onTapGesture { focused = true }

            Button(action: onFilters) {
                NunaGlyph(NunaIcons.filter, pointSize: 20).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 54, height: 54)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if filterCount > 0 {
                            Text(verbatim: "\(filterCount)").font(.nuna(size: 11, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.onAccent)
                                .frame(minWidth: 18, minHeight: 18).background(NunaPalette.accent, in: Capsule()).offset(x: 5, y: -5)
                        }
                    }
            }
            .buttonStyle(.plain).accessibilityLabel(Text("Filters"))
        }
    }
}

/// One technique as a row of the list: a picture, its name with its level and length, and the info mark. A touch opens its page.
struct NunaBreathListRow: View {
    let icon: String
    let title: String
    let level: String
    let minutes: String
    var badge: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                LinearGradient(colors: [NunaPalette.glassStrong, NunaPalette.cardSurface], startPoint: .top, endPoint: .bottom)
                NunaActivityGlyph(name: icon, size: 34).foregroundStyle(NunaPalette.textPrimary)
            }
            .frame(width: 84, height: 72).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: title).font(.nunaWords(size: 16, semibold: true)).tracking(0).foregroundStyle(NunaPalette.textPrimary)
                    .lineLimit(2).multilineTextAlignment(.leading).textCase(nil)
                HStack(spacing: 6) {
                    if let badge {
                        Text(verbatim: badge).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.charge)
                    }
                    Text(verbatim: "\(level) · \(minutes)").font(.nunaWords(size: 13)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
            Spacer(minLength: 8)
            NunaGlyph("info.circle", pointSize: 22, weight: .regular).foregroundStyle(NunaPalette.textSecondary)
        }
        .padding(8).padding(.trailing, 8)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The filters: a list of boxes to tick for each of two tabs, as on WHOOP's exercise picker. They take effect as they are ticked; the button at the
/// foot says how many techniques that leaves and closes the sheet.
struct NunaBreathFilterSheet: View {
    @Binding var filter: NunaBreathFilter
    let resultCount: Int
    let onClose: () -> Void
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Filters").font(.nuna(size: 18, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                HStack {
                    Spacer()
                    if filter.isActive {
                        Button { filter.groups = []; filter.levels = [] } label: {
                            Text("Clear all").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                .padding(.horizontal, 8).frame(height: 40).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 22)
            NunaPageTabs([(value: 0, title: "Purpose"), (value: 1, title: "Level")], selection: $tab)
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if tab == 0 {
                        ForEach(NunaBreathGroup.allCases) { g in
                            row(g.title, on: filter.groups.contains(g)) { toggle(&filter.groups, g) }
                        }
                    } else {
                        ForEach(NunaBreathLevel.allCases, id: \.self) { l in
                            row(l.title, on: filter.levels.contains(l)) { toggle(&filter.levels, l) }
                        }
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 24).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            Button(action: onClose) {
                Text(verbatim: String(localized: "Show \(resultCount)")).font(.nuna(size: NunaTypeSize.h3, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56)
                    .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }
            .buttonStyle(.plain).padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 12)
        }
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func row(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? NunaPalette.accent : NunaPalette.textPrimary, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? NunaPalette.accent : Color.clear))
                    .frame(width: 34, height: 34)
                    .overlay { if on { Image(systemName: "checkmark").font(.nuna(size: 16, weight: .heavy)).foregroundStyle(NunaPalette.onAccent) } }
                Text(verbatim: title).font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
#endif
