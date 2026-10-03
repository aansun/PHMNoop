import SwiftUI
import StrandDesign

/// Compact, standalone About page for the iOS More → App flow.
///
/// Settings remains the place for preferences; this page only explains the product and keeps the
/// requested reference links together. The page is intentionally WHOOP-focused and does not advertise
/// alternate wearable sources.
struct AboutView: View {
    private var version: String { UpdateWatch.installedVersion }
    private var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "—"
    }

    var body: some View {
        ScreenScaffold(title: "About", subtitle: "PHMN for WHOOP, computed on your device.",
                       topBackground: liquidScaffoldSky()) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                NoopCard(tint: StrandPalette.accent) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text("PHMN").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                        Text("v\(version) · build \(build)")
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textTertiary)
                        Text("Offline-first companion for WHOOP 4.0 and 5.0/MG straps. Your data stays on this device.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                aboutLink("How PHMN works", "How sleep, local storage, and device sync fit together.", "questionmark.circle") {
                    HowNoopWorksView(onClose: {})
                }
                aboutLink("How your scores work", "How Charge, Effort, and Rest are calculated.", "chart.bar.doc.horizontal") {
                    ScoringGuideView(onClose: {})
                }
                aboutLink("Diagnostics", "Device and build information for troubleshooting.", "stethoscope") {
                    TestCentreView()
                }
                aboutLink("About Apple Watch data", "What Apple Watch can contribute to NOOP.", "applewatch") {
                    AppleWatchAboutView(onStartSetup: {})
                }

                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text("PROJECT HOME").strandOverline()
                        Link(destination: URL(string: "https://github.com/aansun/PHMNoop")!) {
                            Label("Project home & source", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(StrandFont.body.weight(.semibold))
                                .foregroundStyle(StrandPalette.accent)
                        }
                        Text("Open-source, independent, and designed to keep health data local.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }

                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text("BUILT ON").strandOverline()
                        Text("Built on the NOOP baseline and community WHOOP protocol work.")
                    }
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private func aboutLink<Destination: View>(_ title: LocalizedStringKey,
                                               _ subtitle: LocalizedStringKey,
                                               _ icon: String,
                                               @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(StrandFont.body.weight(.semibold))
                    Text(subtitle).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.horizontal, NoopMetrics.cardPadding)
            .padding(.vertical, 14)
            .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("About") {
    AboutView()
}
#endif
