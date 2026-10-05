#if os(iOS)
import SwiftUI
import StrandDesign

/// Appearance (Appearance.dc): Experience, Language and Units, a live preview, theme, density and the app icon. Colour, font
/// and text size are fixed to the design guides and are not offered here. Haptics, Live Activity and the morning brief live with the feature they belong to
/// (strap automations, History sync, Anya) and are not repeated here; the arrangement of Today is under Optional features.
struct NunaAppearanceView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ExperienceMode.storageKey) private var experienceRaw = ExperienceMode.standard.rawValue
    @AppStorage(NunaTheme.storageKey) private var themeRaw = NunaTheme.Mode.dark.rawValue
    @AppStorage(NunaThemePrefs.densityKey) private var densityRaw = NunaThemePrefs.Density.standard.rawValue
    @AppStorage("appIcon.name") private var iconName = ""
    @AppStorage(UnitPrefs.systemKey) private var unitSystem = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distance = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScale = EffortScale.hundred.rawValue
    @State private var iconError: String?

    private var experience: ExperienceMode { ExperienceMode(rawValue: experienceRaw) ?? .standard }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                NunaHeader("Appearance", onBack: { dismiss() })
                Text("Choose light or dark, spacing and the app icon. Colour and type follow the app's design guide.")
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                experienceCard
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        NavigationLink(value: NunaMeRoute.language) {
                            NunaListRow("Language", subtitle: LocalizedStringKey(languageName), systemImage: "globe", showsChevron: true)
                        }.buttonStyle(.plain)
                        NunaDivider()
                        NavigationLink(value: NunaMeRoute.units) { NunaListRow("Units", subtitle: LocalizedStringKey(unitsSummary), systemImage: "ruler.fill", showsChevron: true) }.buttonStyle(.plain)
                    }
                }
                preview
                themeSection
                densityCard
                #if os(iOS)
                iconCard
                #endif
                nunaFootnote("Haptics are under Strap automations, the Live Activity under History sync and the morning brief under Anya.")
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 14).padding(.bottom, 24)
        }
        .nunaScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .alert("Couldn't change the app icon", isPresented: Binding(get: { iconError != nil }, set: { if !$0 { iconError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: iconError ?? "") }
    }

    // MARK: Pieces

    private var experienceCard: some View {
        NavigationLink { ExperienceView() } label: {
            NunaCard {
                HStack(spacing: 14) {
                    Image(systemName: "sparkle").font(.system(size: 18, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                        .frame(width: 44, height: 44).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        NunaSectionHeader("Experience")
                        Text(verbatim: experience.displayName).font(.nuna(size: NunaTypeSize.h2 - 2, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Switch to Default to return to the original NOOP look").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }.buttonStyle(.plain)
    }

    private var languageName: String {
        let code = AppLanguage.activeLocale.identifier.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init) ?? "en"
        return (Locale(identifier: code).localizedString(forLanguageCode: code) ?? code).capitalized
    }

    private var unitsSummary: String {
        let body = (UnitSystem(rawValue: unitSystem) ?? .metric) == .imperial ? String(localized: "Imperial") : String(localized: "Metric")
        let dist = UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystem) ?? .metric, override: distance) == .imperial ? "mi" : "km"
        return body + " · " + dist + " · " + (UnitPrefs.resolveEffortScale(effortScale) == .whoop ? String(localized: "Effort 0 to 21") : String(localized: "Effort 0 to 100"))
    }

    private var preview: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Preview")
                HStack(spacing: 16) {
                    NunaRingGauge(fraction: 0.78, color: NunaPalette.charge, size: 84, lineWidth: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("78").font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            Text("%").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ready for a moderate load").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                        Text("Start workout").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 18).frame(height: 38).background(NunaPalette.accent, in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaTrendsCap("Theme")
            HStack(spacing: 12) {
                ForEach(NunaTheme.Mode.allCases) { m in
                    Button { themeRaw = m.rawValue } label: {
                        VStack(spacing: 10) {
                            themeThumb(m).frame(height: 78)
                            Text(themeTitle(m)).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        }
                        .padding(10).frame(maxWidth: .infinity)
                        .background(NunaPalette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(themeRaw == m.rawValue ? NunaPalette.accent : NunaPalette.hairlineSoft, lineWidth: themeRaw == m.rawValue ? 2 : 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var densityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaTrendsCap("Density")
            NunaSegmented([(value: NunaThemePrefs.Density.roomy.rawValue, title: "Roomy"), (value: NunaThemePrefs.Density.standard.rawValue, title: "Standard"), (value: NunaThemePrefs.Density.compact.rawValue, title: "Compact")], selection: $densityRaw)
        }
    }

    private var iconCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("App icon")
                HStack(spacing: 12) {
                    iconChoice("", "Default", AnyView(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient(colors: [Color(hex: "#16EC06").opacity(0.9), Color(hex: "#0A0D10")], startPoint: .topLeading, endPoint: .bottomTrailing))))
                    iconChoice("AppIcon-Navy", "Navy", AnyView(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient(colors: [Color(hex: "#1B2D52"), Color(hex: "#0B1224")], startPoint: .top, endPoint: .bottom))))
                    iconChoice("AppIcon-PHM", "PHMNOOP", AnyView(ZStack { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "#0A0D10")); Text("⌥").font(.system(size: 28, weight: .heavy)).foregroundStyle(.white) }))
                }
            }
        }
    }

    private func iconChoice(_ name: String, _ title: LocalizedStringKey, _ art: AnyView) -> some View {
        Button { setIcon(name) } label: {
            VStack(spacing: 8) {
                art.frame(width: 62, height: 62).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(iconName == name ? NunaPalette.accent : NunaPalette.hairline, lineWidth: iconName == name ? 2.5 : 1))
                Text(title).font(.nuna(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }

    private func setIcon(_ name: String) {
        iconName = name
        let target = name.isEmpty ? nil : name
        Task { @MainActor in
            guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != target else { return }
            do { try await UIApplication.shared.setAlternateIconName(target) }
            catch { iconName = UIApplication.shared.alternateIconName ?? ""; iconError = error.localizedDescription }
        }
    }

    // MARK: Helpers

    private func themeThumb(_ m: NunaTheme.Mode) -> some View {
        let dark = m == .dark, light = m == .light
        return ZStack {
            if m == .auto { HStack(spacing: 0) { Color(hex: "#F2F4F6"); Color(hex: "#000000") } }
            else { Color(hex: light ? "#F2F4F6" : "#000000") }
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 5).fill(Color(hex: dark ? "#121214" : "#FFFFFF")).frame(height: 26).opacity(m == .auto ? 0.85 : 1)
                HStack(spacing: 6) { Capsule().fill(Color(hex: dark ? "#FFFFFF" : "#0A0D10")).frame(width: 28, height: 8); Capsule().fill(Color(hex: "#00FF66")).frame(width: 14, height: 8) }
            }.padding(9)
        }.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func themeTitle(_ m: NunaTheme.Mode) -> LocalizedStringKey { switch m { case .auto: return "Automatic"; case .light: return "Light"; case .dark: return "Dark" } }
}
#endif
