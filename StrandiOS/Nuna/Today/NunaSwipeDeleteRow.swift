#if os(iOS)
import SwiftUI
import StrandDesign

/// A row that slides to the left under a finger and shows a round red delete button where it was; a tap on the button removes it. Sliding
/// back, or tapping the row, puts it back. Used by the editors where the system's rectangular swipe action does not fit the look.
struct NunaSwipeDeleteRow<Content: View>: View {
    var enabled = true
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    /// How far the row moves to uncover the button: the button, and the gap between it and the row.
    private static var reveal: CGFloat { 68 }
    @State private var base: CGFloat = 0
    @State private var live: CGFloat = 0
    /// Whether the touch in progress is a sideways one (decided once, on its first movement), so a vertical scroll never moves the row.
    @State private var sideways: Bool?

    private var x: CGFloat { min(max(base + live, -Self.reveal - 14), 0) }
    private var progress: CGFloat { min(max(-x / Self.reveal, 0), 1) }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: delete) {
                Image(systemName: "trash").font(.system(size: 20, weight: .regular)).foregroundStyle(.white)
                    .frame(width: 49, height: 49).background(NunaPalette.alert, in: Circle())
            }
            .buttonStyle(.plain)
            .scaleEffect(0.6 + 0.4 * progress).opacity(Double(progress))
            .allowsHitTesting(progress > 0.9)
            .accessibilityLabel(Text("Delete"))
            content()
                .contentShape(Rectangle())
                .offset(x: x)
                .simultaneousGesture(TapGesture().onEnded { if base != 0 { close() } })
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in
                    guard enabled else { return }
                    if sideways == nil { sideways = abs(v.translation.width) > abs(v.translation.height) * 1.2 }
                    if sideways == true { live = v.translation.width }
                }
                .onEnded { v in
                    defer { sideways = nil }
                    guard enabled, sideways == true else { live = 0; return }
                    let end = base + v.translation.width
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        base = end < -Self.reveal / 2 ? -Self.reveal : 0
                        live = 0
                    }
                }
        )
        .onChange(of: enabled) { _, on in if !on { close() } }
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { base = 0; live = 0 }
    }

    private func delete() {
        withAnimation(.easeInOut(duration: 0.2)) { onDelete() }
    }
}
#endif
