#if os(iOS)
import SwiftUI
import StrandDesign

/// Settings > Support > Feedback: the way to tell the makers what works and what does not. The message itself is written on Luciq's screen, which these two
/// buttons open; see `PHMNFeedback` for what is turned off and what a report carries.
struct NunaFeedbackView: View {
    private var available: Bool { PHMNFeedback.isConfigured }

    var body: some View {
        NunaDetailScreen("Feedback") {
            VStack(spacing: 14) {
                Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 34, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                Text("Tell us what you think").font(.nuna(size: NunaTypeSize.h2, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text("What you like, what is missing and what does not work: every message is read, and it is how PHMN gets better.")
                    .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            .frame(maxWidth: .infinity).padding(.top, 18).padding(.bottom, 6)
            NunaSettingsGroup {
                Button { PHMNFeedback.show(.feedback) } label: {
                    NunaListRow("Share feedback", description: "An idea, a request or a word of thanks", systemImage: "text.bubble", showsChevron: true)
                }.buttonStyle(.plain).disabled(!available)
                NunaDivider()
                Button { PHMNFeedback.show(.problem) } label: {
                    NunaListRow("Report a problem", description: "Something broke or looks wrong", systemImage: "exclamationmark.bubble", showsChevron: true)
                }.buttonStyle(.plain).disabled(!available)
            }
            .opacity(available ? 1 : 0.45)
            if !available {
                NunaCard(small: true) {
                    NunaListRow("Not available in this build", subtitle: "This copy of PHMN was built without a feedback channel. Report a problem on GitHub from About instead.", systemImage: "exclamationmark.circle")
                }
            }
            VStack(spacing: 10) {
                Text("A report carries what you write, your email only if you give one, a picture only if you attach one, and basic details of the app and your iPhone (such as the model and the versions) so a problem can be reproduced.")
                Text("Your heart rate, sleep, workouts and other health data are never attached, and nothing is sent as a report until you tap Send. PHMN makes no contact with the feedback service until you open this page.")
            }
            .font(.nuna(size: 12.5, weight: .semibold)).tracking(0).foregroundStyle(NunaPalette.textMuted).multilineTextAlignment(.center).textCase(nil)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 6).padding(.top, 4)
        }
        // Luciq is started here, not at launch: the app makes no contact with it until this page is opened.
        .onAppear { PHMNFeedback.start() }
    }
}
#endif
