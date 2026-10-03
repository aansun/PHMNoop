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
                                .background(NunaPalette.textPrimary, in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
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
                        link("Theme, accent and typography", "Dark, light, accent colour, type preset", "paintpalette.fill", NunaPalette.effortText)
                        NunaDivider()
                        link("Language", "Indonesian, English and more", "globe", nil)
                        NunaDivider()
                        link("Units", "Metric or imperial, Effort scale", "ruler.fill", nil)
                    }
                }
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .nunaScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func link(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ icon: String, _ tint: Color?) -> some View {
        NavigationLink { SettingsView() } label: {
            NunaListRow(title, subtitle: subtitle, systemImage: icon, tint: tint, showsChevron: true)
        }
        .buttonStyle(.plain)
    }
}
#endif
