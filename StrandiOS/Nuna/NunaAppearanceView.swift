#if os(iOS)
import SwiftUI
import StrandDesign

/// Nuna "Tampilan": Experience first, then the existing theme / language / unit settings.
struct NunaAppearanceView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ExperienceMode.storageKey) private var experienceRaw = ExperienceMode.standard.rawValue

    private var experience: ExperienceMode { ExperienceMode(rawValue: experienceRaw) ?? .standard }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                NunaHeader("Appearance", onBack: { dismiss() })
                Text("Choose how the whole app looks. Your data and settings do not change.")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(NunaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                NavigationLink { ExperienceView() } label: {
                    NunaCard {
                        HStack(spacing: 14) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(NunaPalette.onAccent)
                                .frame(width: 44, height: 44)
                                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                NunaSectionHeader("Experience")
                                Text(verbatim: experience.displayName)
                                    .font(.system(size: NunaTypeSize.h2 - 2, weight: .heavy))
                                    .foregroundStyle(NunaPalette.textPrimary)
                                Text("Switch to Default to return to the original NOOP look")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(NunaPalette.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(NunaPalette.textMuted)
                        }
                    }
                }
                .buttonStyle(.plain)

                NunaCard(small: true) {
                    VStack(spacing: 0) {
                        NavigationLink(value: NunaMeRoute.theme) {
                            NunaListRow("Theme, accent and typography", subtitle: LocalizedStringKey(themeSummary), systemImage: "paintpalette.fill", showsChevron: true)
                        }.buttonStyle(.plain)
                        NunaDivider()
                        Button { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } label: {
                            NunaListRow("Language", subtitle: LocalizedStringKey(AppLanguage.activeLocale.localizedString(forIdentifier: AppLanguage.activeLocale.identifier)?.capitalized ?? "") , systemImage: "globe", showsChevron: true) {
                                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                            }
                        }.buttonStyle(.plain)
                        NunaDivider()
                        NavigationLink(value: NunaMeRoute.units) {
                            NunaListRow("Units", subtitle: LocalizedStringKey(unitsSummary), systemImage: "ruler.fill", showsChevron: true)
                        }.buttonStyle(.plain)
                    }
                }
                Text("Language is set in iOS Settings > NOOP > Language, so it follows the system and every app together.")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .nunaScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    @AppStorage(NunaTheme.storageKey) private var themeRaw = NunaTheme.Mode.dark.rawValue
    @AppStorage(NunaThemePrefs.accentKey) private var accentRaw = NunaThemePrefs.Accent.ink.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystem = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScale = EffortScale.hundred.rawValue

    private var themeSummary: String {
        let t: String = { switch NunaTheme.Mode(rawValue: themeRaw) ?? .dark { case .auto: return String(localized: "Automatic"); case .light: return String(localized: "Light"); case .dark: return String(localized: "Dark") } }()
        return t + " · " + Self.accentName(NunaThemePrefs.Accent(rawValue: accentRaw) ?? .ink)
    }
    private var unitsSummary: String {
        ((UnitSystem(rawValue: unitSystem) ?? .metric) == .imperial ? String(localized: "Imperial") : String(localized: "Metric")) + " · " + (UnitPrefs.resolveEffortScale(effortScale) == .whoop ? "0–21" : "0–100")
    }
    static func accentName(_ a: NunaThemePrefs.Accent) -> String {
        switch a { case .ink: return String(localized: "White"); case .green: return String(localized: "Green"); case .blue: return String(localized: "Blue"); case .steel: return String(localized: "Steel"); case .yellow: return String(localized: "Yellow") }
    }
}

// MARK: - Theme, accent and typography (Appearance.dc)

struct NunaThemeView: View {
    @AppStorage(NunaTheme.storageKey) private var themeRaw = NunaTheme.Mode.dark.rawValue
    @AppStorage(NunaThemePrefs.accentKey) private var accentRaw = NunaThemePrefs.Accent.ink.rawValue
    @AppStorage(NunaThemePrefs.typographyKey) private var typoRaw = NunaThemePrefs.Typography.bold.rawValue
    @EnvironmentObject private var repo: Repository

    private var accent: NunaThemePrefs.Accent { NunaThemePrefs.Accent(rawValue: accentRaw) ?? .ink }

    var body: some View {
        NunaDetailScreen("Theme and type") {
            Text("Set how the app looks. The change shows straight away in the preview.").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            preview
            VStack(alignment: .leading, spacing: 10) {
                nunaTrendsCap("Theme")
                HStack(spacing: 12) {
                    ForEach(NunaTheme.Mode.allCases) { m in
                        Button { themeRaw = m.rawValue } label: {
                            VStack(spacing: 10) {
                                themeThumb(m).frame(height: 78)
                                Text(title(m)).font(.system(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            }
                            .padding(10).frame(maxWidth: .infinity)
                            .background(NunaPalette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(themeRaw == m.rawValue ? NunaPalette.accent : NunaPalette.hairlineSoft, lineWidth: themeRaw == m.rawValue ? 2 : 1))
                        }.buttonStyle(.plain)
                    }
                }
            }
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { nunaTrendsCap("Accent colour"); Spacer(); Text(verbatim: NunaAppearanceView.accentName(accent)).font(.system(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                    HStack(spacing: 0) {
                        ForEach(NunaThemePrefs.Accent.allCases) { a in
                            Button { accentRaw = a.rawValue } label: {
                                Circle().fill(a.swatch).frame(width: 44, height: 44)
                                    .overlay(Circle().strokeBorder(NunaPalette.hairline, lineWidth: 1))
                                    .overlay { if accentRaw == a.rawValue { Image(systemName: "checkmark").font(.system(size: 15, weight: .black)).foregroundStyle(a == .ink ? .black : .black) } }
                                    .padding(3).overlay(Circle().strokeBorder(accentRaw == a.rawValue ? NunaPalette.textPrimary : .clear, lineWidth: 2))
                            }.buttonStyle(.plain).accessibilityLabel(Text(verbatim: NunaAppearanceView.accentName(a)))
                            if a != NunaThemePrefs.Accent.allCases.last { Spacer(minLength: 0) }
                        }
                    }
                    Text("The accent only colours buttons and selections. Data colours stay the same: green for Charge, blue for Effort, steel for Rest.").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            NunaSettingsGroup("Typography") {
                ForEach(Array(NunaThemePrefs.Typography.allCases.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { NunaDivider() }
                    Button { typoRaw = t.rawValue } label: {
                        HStack(spacing: 14) {
                            Text("Aa").font(.system(size: 20, weight: .heavy, design: t.design)).fontWidth(t == .geometric ? .expanded : nil)
                                .foregroundStyle(NunaPalette.textPrimary).frame(width: 46, height: 46).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(name(t)).font(.system(size: 16.5, weight: .bold, design: t.design)).fontWidth(t == .geometric ? .expanded : nil).foregroundStyle(NunaPalette.textPrimary)
                                Text(blurb(t)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: typoRaw == t.rawValue ? "checkmark.circle.fill" : "circle").font(.system(size: 21)).foregroundStyle(typoRaw == t.rawValue ? NunaPalette.accent : NunaPalette.textMuted)
                        }.padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            nunaFootnote("Automatic follows the iPhone. The type styles use the iPhone's own system faces, so numbers and labels stay crisp at every size.")
        }
    }

    /// A small slice of the app drawn with the choices, so every control has a visible effect.
    private var preview: some View {
        NunaCard {
            HStack(spacing: 16) {
                NunaRingGauge(fraction: 0.78, color: NunaPalette.charge, size: 84, lineWidth: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("78").font(.system(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text("%").font(.system(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Charge").font(.system(size: 11.5, weight: .heavy)).tracking(1).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Text("Ready for a moderate load").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text("Start workout").font(.system(size: 14, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 18).frame(height: 38).background(NunaPalette.accent, in: Capsule())
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func themeThumb(_ m: NunaTheme.Mode) -> some View {
        let dark = m == .dark, light = m == .light
        return ZStack {
            if m == .auto {
                HStack(spacing: 0) { Rectangle().fill(Color(hex: "#F2F4F6")); Rectangle().fill(Color(hex: "#0A0D10")) }
            } else { Rectangle().fill(Color(hex: light ? "#F2F4F6" : "#0A0D10")) }
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 5).fill(Color(hex: dark ? "#14181D" : "#FFFFFF")).frame(height: 26).opacity(m == .auto ? 0.85 : 1)
                HStack(spacing: 6) { Capsule().fill(Color(hex: dark ? "#FFFFFF" : "#0A0D10")).frame(width: 28, height: 8); Capsule().fill(Color(hex: "#16EC06")).frame(width: 14, height: 8) }
            }.padding(9)
        }.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func title(_ m: NunaTheme.Mode) -> LocalizedStringKey { switch m { case .auto: return "Automatic"; case .light: return "Light"; case .dark: return "Dark" } }
    private func name(_ t: NunaThemePrefs.Typography) -> LocalizedStringKey { switch t { case .bold: return "Bold"; case .geometric: return "Geometric"; case .system: return "System" } }
    private func blurb(_ t: NunaThemePrefs.Typography) -> LocalizedStringKey {
        switch t { case .bold: return "Rounded and compact. The original Nuna look."; case .geometric: return "Wider letters and numbers."; case .system: return "The plain iPhone font. Most neutral." }
    }
}
#endif
