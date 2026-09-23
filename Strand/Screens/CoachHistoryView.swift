import SwiftUI
import StrandDesign

/// Local Coach thread picker. It deliberately owns only navigation and deletion; sending and transcript
/// state stay in `AICoachEngine`, so reopening a thread uses the same chat surface as a new question.
struct CoachHistoryView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: CoachConversationHistoryItem?

    var body: some View {
        NavigationStack {
            Group {
                if coach.conversationHistory.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: NoopMetrics.space2) {
                            ForEach(coach.conversationHistory) { item in
                                historyRow(item)
                            }
                        }
                        .padding(.horizontal, NoopMetrics.screenHPadding)
                        .padding(.vertical, NoopMetrics.space3)
                    }
                }
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Coach history")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
        .confirmationDialog(
            "Delete this conversation?",
            item: $pendingDelete
        ) { item in
            Button("Delete", role: .destructive) {
                coach.deleteConversation(item)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the saved Coach conversation from this device.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: NoopMetrics.space2) {
            Image(systemName: "clock.arrow.circlepath")
                .font(StrandFont.rounded(28))
                .foregroundStyle(StrandPalette.accent)
                .accessibilityHidden(true)
            Text("No saved conversations")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            Text("Start a new chat, then use New chat to keep it here for later.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(NoopMetrics.space4)
    }

    private func historyRow(_ item: CoachConversationHistoryItem) -> some View {
        Button {
            coach.openConversation(item)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: NoopMetrics.space2) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(item.messages.count) messages · \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Text(item.provider)
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .padding(.top, 3)
            }
            .padding(NoopMetrics.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frostedCardSurface(tint: StrandPalette.chargeColor, cornerRadius: NoopMetrics.cardRadius)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = item
            } label: {
                Label("Delete conversation", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = item
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel("Open Coach conversation: \(item.title)")
        .accessibilityHint("Double tap to continue this conversation")
    }
}
