#if os(iOS)
import SwiftUI
import StrandDesign

/// Where a ready-made workout goes among the person's own programs.
enum NunaProgramPlacement {
    /// The group of its type (a plan of several routines gets a group of its own): what saving did before there was a choice.
    case auto
    case ungrouped
    case group(NunaProgramGroup)
}

/// The sheet that asks where a workout from Explore is saved: a group that is there, Ungrouped, or a new group made on the spot.
struct NunaAddToProgramsSheet: View {
    let onPick: (NunaProgramPlacement) -> Void
    @ObservedObject private var groups = NunaProgramGroupsModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Save to group").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).padding(.top, 22)
            Text("Pick where it goes in My Program.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                .textCase(nil).frame(maxWidth: .infinity).padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 8) {
                    row(icon: "tray", title: String(localized: "Ungrouped")) { pick(.ungrouped) }
                    ForEach(groups.groups) { g in row(icon: "folder", title: g.name) { pick(.group(g)) } }
                }
            }
            .scrollIndicators(.hidden)
            newGroupRow
        }
        .padding(.horizontal, NunaSpacing.screenH)
        .preferredColorScheme(NunaTheme.colorScheme)
        .nunaSheetChrome(detents: [.height(min(250 + CGFloat(groups.groups.count + 1) * 64, 620))])
    }

    private func pick(_ placement: NunaProgramPlacement) {
        onPick(placement)
        dismiss()
    }

    private func row(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
                Text(verbatim: title).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).frame(height: 56)
            .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A name typed here makes the group and saves into it in one step.
    private var newGroupRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.plus").font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
            TextField("", text: $newName, prompt: Text("New group").foregroundStyle(NunaPalette.textSecondary))
                .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).submitLabel(.done)
                .onSubmit(createGroup)
            Button(action: createGroup) {
                Text("Add").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.accent).frame(height: 44).padding(.horizontal, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(trimmedName.isEmpty).opacity(trimmedName.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 18).frame(height: 56)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
        .padding(.bottom, 12)
    }

    private var trimmedName: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func createGroup() {
        guard !trimmedName.isEmpty, let g = groups.add(name: trimmedName) else { return }
        pick(.group(g))
    }
}

extension NunaExploreWorkout {
    /// The workout as stored: one routine, the moves as the starter program has them.
    var asProgram: NunaStarterProgram {
        NunaStarterProgram(id: program.id, name: title, level: level, goal: program.goal, equipment: program.equipment,
                           routines: [.init(name: title, moves: routine.moves)])
    }
}
#endif
