#if os(iOS)
import SwiftUI
import StrandDesign

/// Settings > Support > Feedback: the way to tell the makers what works and what does not. Each button opens a new GitHub issue in the browser with its outline
/// already written (`PHMNFeedback`); the message is written and sent on GitHub, not in the app.
struct NunaFeedbackView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        NunaDetailScreen("Feedback") {
            VStack(spacing: 14) {
                Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 34, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                Text("Tell us what you think").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text("What you like, what is missing and what does not work: every message is read, and it is how PHMN gets better.")
                    .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            .frame(maxWidth: .infinity).padding(.top, 18).padding(.bottom, 6)
            NunaSettingsGroup {
                Button { open(.feedback) } label: {
                    NunaListRow("Share feedback", description: "An idea, a request or a word of thanks", systemImage: "text.bubble", showsChevron: true)
                }.buttonStyle(.plain)
                NunaDivider()
                Button { open(.problem) } label: {
                    NunaListRow("Report a problem", description: "Something broke or looks wrong", systemImage: "exclamationmark.bubble", showsChevron: true)
                }.buttonStyle(.plain)
            }
            VStack(spacing: 10) {
                Text("Each button opens GitHub in your browser with a new issue started for you. You write the rest and send it there, so you need a GitHub account.")
                Text("The app adds only its version, your iOS version, the model of your iPhone and the language. Your heart rate, sleep, workouts and other health data are never added, and nothing is sent until you submit the issue on GitHub. PHMN makes no contact with GitHub until you tap a button.")
            }
            .font(.nuna(size: 12.5, weight: .semibold)).tracking(0).foregroundStyle(NunaPalette.textMuted).multilineTextAlignment(.center).textCase(nil)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 6).padding(.top, 4)
        }
    }

    private func open(_ kind: PHMNFeedback.Kind) {
        if let url = PHMNFeedback.url(kind) { openURL(url) }
    }
}
#endif
