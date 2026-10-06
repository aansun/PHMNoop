#if os(iOS)
import SwiftUI
import StrandDesign

/// Experience picker: Default (the original NOOP look) or Nuna (docs/nuna). Reachable from both shells
/// so a user can always go back: Nuna → Me → Appearance → Experience, and Default → Settings → Experience.
struct ExperienceView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ExperienceMode.storageKey) private var experienceRaw = ExperienceMode.nuna.rawValue
    @State private var pending: ExperienceMode?

    private var current: ExperienceMode { ExperienceMode(rawValue: experienceRaw) ?? .nuna }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                NunaHeader("Experience", onBack: { dismiss() })
                Text("Pick the look of the whole app. Your data, scores and settings stay the same.")
                    .font(.nuna(size: 13.5, weight: .semibold))
                    .foregroundStyle(NunaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)

                option(.standard,
                       tag: "Original NOOP look",
                       blurb: "Back to the original NOOP look.",
                       bullets: ["Today with sky and liquid", "Today, Insights, Health and More tabs", "Every NOOP feature as before"])
                option(.nuna,
                       tag: "New design",
                       blurb: "The new PHMN design: simple, clear and customisable.",
                       bullets: ["Three-ring score card and customisable Today cards",
                                 "Anya in every module and a quick actions button",
                                 "Today, Health, Trends, Anya and Me tabs"])

                NunaCard(small: true) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle").foregroundStyle(NunaPalette.textMuted).padding(.top, 2)
                        Text("Switching reloads the app shell briefly. Widgets, Live Activities and Anya keep working with the same data.")
                            .font(.nuna(size: 12.5, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .nunaScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $pending) { mode in
            ExperienceConfirmSheet(target: mode) {
                experienceRaw = mode.rawValue
                pending = nil
            } onCancel: { pending = nil }
            .nunaSheetChrome(detents: [.height(470)])
        }
    }

    private func option(_ mode: ExperienceMode, tag: LocalizedStringKey, blurb: LocalizedStringKey, bullets: [LocalizedStringKey]) -> some View {
        let selected = current == mode
        return Button {
            if !selected { pending = mode }
        } label: {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Text(verbatim: mode.displayName)
                            .font(.nuna(size: NunaTypeSize.h2, weight: .heavy))
                            .foregroundStyle(NunaPalette.textPrimary)
                        NunaChip(tag)
                        Spacer(minLength: 0)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.nuna(size: 24))
                            .foregroundStyle(selected ? NunaPalette.charge : NunaPalette.ink.opacity(0.3))
                    }
                    HStack(alignment: .top, spacing: 16) {
                        ExperiencePreview(mode: mode)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(blurb)
                                .font(.nuna(size: 13, weight: .semibold))
                                .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            ForEach(bullets.indices, id: \.self) { i in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(NunaPalette.textMuted).frame(width: 5, height: 5).padding(.top, 7)
                                    Text(bullets[i]).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                                }
                            }
                        }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous)
                .strokeBorder(selected ? NunaPalette.charge : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Little static phone drawings for the picker (no live data).
private struct ExperiencePreview: View {
    let mode: ExperienceMode
    var body: some View {
        Group {
            if mode == .nuna { nuna } else { standard }
        }
        .frame(width: 116, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NunaPalette.ink.opacity(0.16), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var nuna: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today").font(.nuna(size: 11, weight: .heavy)).foregroundStyle(NunaPalette.ink)
            HStack(spacing: 6) {
                ring(NunaPalette.charge, 0.78); ring(NunaPalette.effort, 0.59); ring(NunaPalette.rest, 0.86)
            }
            .padding(8).frame(maxWidth: .infinity)
            .background(NunaPalette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NunaPalette.ink.opacity(0.1)).frame(height: 26)
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NunaPalette.ink.opacity(0.06)).frame(height: 26)
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.ink.opacity(0.08)).frame(height: 24)
        }
        .padding(10)
        .background(NunaPalette.canvas)
    }

    private func ring(_ color: Color, _ f: Double) -> some View {
        ZStack {
            Circle().stroke(NunaPalette.ink.opacity(0.1), lineWidth: 4)
            Circle().trim(from: 0, to: f).stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .frame(width: 28, height: 28)
    }

    private var standard: some View {
        VStack(spacing: 8) {
            Text("Today").font(.nuna(size: 10, weight: .heavy)).foregroundStyle(Color(hex: "#9FB4D8")).frame(maxWidth: .infinity, alignment: .leading)
            Circle().fill(Color(hex: "#2E7BE8")).frame(width: 52, height: 52).padding(.top, 6)
            Text("Recovery 78").font(.nuna(size: 10, weight: .heavy)).foregroundStyle(NunaPalette.ink)
            HStack(spacing: 8) {
                ForEach([Color(hex: "#3AA0FF"), Color(hex: "#5C6BFF"), Color(hex: "#38C6C0")], id: \.self) { Circle().fill($0).frame(width: 24, height: 24) }
            }
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NunaPalette.ink.opacity(0.08)).frame(height: 24)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(LinearGradient(colors: [Color(hex: "#1B2D52"), Color(hex: "#0B1224")], startPoint: .top, endPoint: .bottom))
    }
}

private struct ExperienceConfirmSheet: View {
    let target: ExperienceMode
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                NunaIconTile("slider.horizontal.3", tint: NunaPalette.effortText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target == .standard ? "Switch to the Default look?" : "Switch to Nuna?")
                        .font(.nuna(size: 20, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    Text(target == .standard ? "The original NOOP look" : "The new PHMN design")
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                bullet("Your data, scores and settings stay the same")
                bullet("Widgets and Live Activities are unchanged")
                bullet(target == .standard ? "You can switch back to Nuna any time" : "You can switch back to Default any time")
            }
            if target == .standard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NunaPalette.textSecondary)
                    Text("Features that exist only in Nuna, like customisable Today cards and Anya in every module, do not appear in Default.")
                        .font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.warning)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                .padding(12)
                .background(NunaPalette.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Spacer(minLength: 0)
            Button(action: onConfirm) { Text("Switch and reload") }
                .buttonStyle(.nuna(.primary, height: 54, fullWidth: true))
            Button(action: onCancel) { Text(target == .standard ? "Stay on Nuna" : "Stay on Default") }
                .buttonStyle(.nuna(.ghost, height: 50, fullWidth: true))
        }
        .padding(20)
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark").font(.nuna(size: 13, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).padding(.top, 3)
            Text(text).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
        }
    }
}
#endif
