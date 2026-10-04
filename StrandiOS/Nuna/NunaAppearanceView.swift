#if os(iOS)
import SwiftUI
import StrandDesign

/// Appearance (Appearance.dc): Experience, Language and Units, a live preview, theme, accent, typography, text size,
/// density and the app icon. Haptics, Live Activity and the morning brief live with the feature they belong to
/// (strap automations, History sync, Anya) and are not repeated here; the arrangement of Today is under Optional features.
struct NunaAppearanceView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ExperienceMode.storageKey) private var experienceRaw = ExperienceMode.standard.rawValue
    @AppStorage(NunaTheme.storageKey) private var themeRaw = NunaTheme.Mode.dark.rawValue
    @AppStorage(NunaThemePrefs.accentKey) private var accentRaw = NunaThemePrefs.Accent.ink.rawValue
    @AppStorage(NunaThemePrefs.typographyKey) private var typoRaw = NunaThemePrefs.Typography.bold.rawValue
    @AppStorage(NunaThemePrefs.textSizeKey) private var sizeRaw = NunaThemePrefs.TextSize.standard.rawValue
    @AppStorage(NunaThemePrefs.densityKey) private var densityRaw = NunaThemePrefs.Density.standard.rawValue
    @AppStorage("appIcon.name") private var iconName = ""
    @AppStorage(UnitPrefs.systemKey) private var unitSystem = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distance = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScale = EffortScale.hundred.rawValue
    @State private var iconError: String?

    private var experience: ExperienceMode { ExperienceMode(rawValue: experienceRaw) ?? .standard }
    private var accent: NunaThemePrefs.Accent { NunaThemePrefs.Accent(rawValue: accentRaw) ?? .ink }
    private var size: NunaThemePrefs.TextSize { NunaThemePrefs.TextSize(rawValue: sizeRaw) ?? .standard }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                NunaHeader("Appearance", onBack: { dismiss() })
                Text("Set the look to suit you. Changes show straight away in the preview.")
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                experienceCard
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        Button { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } label: {
                            NunaListRow("Language", subtitle: LocalizedStringKey(languageName), systemImage: "globe", showsChevron: true) {
                                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                            }
                        }.buttonStyle(.plain)
                        NunaDivider()
                        NavigationLink(value: NunaMeRoute.units) { NunaListRow("Units", subtitle: LocalizedStringKey(unitsSummary), systemImage: "ruler.fill", showsChevron: true) }.buttonStyle(.plain)
                    }
                }
                preview
                themeSection
                accentCard
                typographyCard
                sizeCard
                densityCard
                #if os(iOS)
                iconCard
                #endif
                nunaFootnote("Language is changed in iOS Settings > NOOP > Language, so it follows the system. Haptics are under Strap automations, the Live Activity under History sync and the morning brief under Anya.")
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
                        Text(verbatim: String(localized: "Accent \(NunaAppearanceView.accentName(accent).lowercased())")).font(.nuna(size: 11.5, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
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

    private var accentCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack { nunaTrendsCap("Accent colour"); Spacer(); Text(verbatim: NunaAppearanceView.accentName(accent)).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                HStack(spacing: 0) {
                    ForEach(NunaThemePrefs.Accent.allCases) { a in
                        Button { accentRaw = a.rawValue } label: {
                            Circle().fill(a.swatch).frame(width: 44, height: 44)
                                .overlay(Circle().strokeBorder(NunaPalette.hairline, lineWidth: 1))
                                .overlay { if accentRaw == a.rawValue { Image(systemName: "checkmark").font(.system(size: 15, weight: .black)).foregroundStyle(.black) } }
                                .padding(3).overlay(Circle().strokeBorder(accentRaw == a.rawValue ? NunaPalette.textPrimary : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel(Text(verbatim: NunaAppearanceView.accentName(a)))
                        if a != NunaThemePrefs.Accent.allCases.last { Spacer(minLength: 0) }
                    }
                }
                Text("The accent only colours buttons and selections. Data colours stay the same: green for Charge, blue for Effort, steel for Rest.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var typographyCard: some View {
        NunaSettingsGroup("Typography") {
            ForEach(Array(NunaThemePrefs.Typography.allCases.enumerated()), id: \.element.id) { i, t in
                if i > 0 { NunaDivider() }
                Button { typoRaw = t.rawValue } label: {
                    HStack(spacing: 14) {
                        Text("Aa").font(.system(size: 20, weight: .heavy, design: t.design)).fontWidth(t == .geometric ? .expanded : nil)
                            .foregroundStyle(typoRaw == t.rawValue ? NunaPalette.charge : NunaPalette.textPrimary).frame(width: 46, height: 46)
                            .background(typoRaw == t.rawValue ? NunaPalette.charge.opacity(0.16) : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(typoName(t)).font(.system(size: 16.5, weight: .bold, design: t.design)).fontWidth(t == .geometric ? .expanded : nil).foregroundStyle(NunaPalette.textPrimary)
                            Text(typoBlurb(t)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer()
                        if typoRaw == t.rawValue { Image(systemName: "checkmark.circle.fill").font(.system(size: 21)).foregroundStyle(NunaPalette.accent) }
                    }.padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private var sizeCard: some View {
        let all = NunaThemePrefs.TextSize.allCases
        let idx = Double(all.firstIndex(of: size) ?? 1)
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack { nunaTrendsCap("Text size"); Spacer(); NunaChip(sizeName(size)) }
                HStack(spacing: 14) {
                    Text("A").font(.system(size: 14, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary)
                    Slider(value: Binding(get: { idx }, set: { sizeRaw = all[min(max(Int($0.rounded()), 0), all.count - 1)].rawValue }), in: 0...Double(all.count - 1), step: 1)
                        .tint(NunaPalette.accent)
                    Text("A").font(.system(size: 24, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                }
                Text("Sample text at the size you pick.").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
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
            if m == .auto { HStack(spacing: 0) { Color(hex: "#F2F4F6"); Color(hex: "#0A0D10") } }
            else { Color(hex: light ? "#F2F4F6" : "#0A0D10") }
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 5).fill(Color(hex: dark ? "#14181D" : "#FFFFFF")).frame(height: 26).opacity(m == .auto ? 0.85 : 1)
                HStack(spacing: 6) { Capsule().fill(Color(hex: dark ? "#FFFFFF" : "#0A0D10")).frame(width: 28, height: 8); Capsule().fill(Color(hex: "#16EC06")).frame(width: 14, height: 8) }
            }.padding(9)
        }.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func themeTitle(_ m: NunaTheme.Mode) -> LocalizedStringKey { switch m { case .auto: return "Automatic"; case .light: return "Light"; case .dark: return "Dark" } }
    private func typoName(_ t: NunaThemePrefs.Typography) -> LocalizedStringKey { switch t { case .bold: return "Bold"; case .geometric: return "Geometric"; case .system: return "System" } }
    private func typoBlurb(_ t: NunaThemePrefs.Typography) -> LocalizedStringKey {
        switch t { case .bold: return "Rounded and compact. The original Nuna look."; case .geometric: return "Wider letters and numbers."; case .system: return "The plain iPhone font. Most neutral." }
    }
    private func sizeName(_ s: NunaThemePrefs.TextSize) -> LocalizedStringKey { switch s { case .small: return "Small"; case .standard: return "Standard"; case .large: return "Large"; case .xlarge: return "Extra large" } }

    static func accentName(_ a: NunaThemePrefs.Accent) -> String {
        switch a { case .ink: return String(localized: "White"); case .green: return String(localized: "Green"); case .blue: return String(localized: "Blue"); case .steel: return String(localized: "Steel"); case .yellow: return String(localized: "Yellow") }
    }
}
#endif
