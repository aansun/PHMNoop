#if os(iOS)
import SwiftUI
import StrandDesign

/// The "+" sheet: every Today action in one place (Phase 1).
struct NunaQuickSheet: View {
    let hydrationEnabled: Bool
    let coachEnabled: Bool

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: NavRouter
    @State private var presented: Panel?

    private enum Panel: String, Identifiable { case breathing, water; var id: String { rawValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick actions")
                .font(.system(size: NunaTypeSize.h2, weight: .bold, design: .rounded))
                .foregroundStyle(NunaPalette.textPrimary)
                .padding(.top, 20)
            NunaCard(small: true) {
                VStack(spacing: 0) {
                    row("Start workout", "Pick a sport and begin", "play.fill", NunaPalette.charge) { go(.activeWorkout) }
                    NunaDivider()
                    row("Add activity", "Log a session you already did", "plus.circle.fill", NunaPalette.effortText) { go(.workouts) }
                    NunaDivider()
                    row("Journal", "Log how you feel", "book.closed.fill", nil) { go(.journal) }
                    NunaDivider()
                    row("Breathing", "Guided breathing with haptics", "wind", NunaPalette.restText) { presented = .breathing }
                    if hydrationEnabled {
                        NunaDivider()
                        row("Water", "Log a drink", "drop.fill", NunaPalette.effortText) { presented = .water }
                    }
                    if coachEnabled {
                        NunaDivider()
                        row("Ask Anya", "Ask about your day", "sparkles", nil) { go(.coach) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NunaSpacing.screenH)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(item: $presented) { panel in
            NavigationStack {
                Group {
                    switch panel {
                    case .breathing: BreathingView()
                    case .water: HydrationView()
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { presented = nil } } }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func go(_ dest: NavRouter.Destination) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { router.requestedDestination = dest }
    }

    private func row(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ icon: String, _ tint: Color?,
                     _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NunaListRow(title, subtitle: subtitle, systemImage: icon, tint: tint, showsChevron: true)
        }
        .buttonStyle(.plain)
    }
}
#endif
