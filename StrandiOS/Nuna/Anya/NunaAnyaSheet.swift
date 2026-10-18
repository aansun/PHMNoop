#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The sheet every Anya card and header button opens (AnyaSheet*.dc). The top is always the local read: a line that cites
/// its figures, computed on this iPhone. A provider adds a short explanation only after it is connected and data access is
/// allowed; follow-up questions are answered inside the sheet, and "Open full conversation" hands over to the Anya tab.
/// Something the card could do, offered in the sheet instead (start a session, breathe, open the journal).
struct NunaAnyaCardAction: Identifiable {
    let title: LocalizedStringKey
    let perform: () -> Void
    var id: String { "\(title)" }
}

/// The line of the card that opened the sheet, so the sheet talks about what was tapped.
struct NunaAnyaCardLine: Equatable {
    var headline: String
    var detail: String?
    var read: [String]
    var actions: [NunaAnyaCardAction] = []

    static func == (a: NunaAnyaCardLine, b: NunaAnyaCardLine) -> Bool {
        a.headline == b.headline && a.detail == b.detail && a.read == b.read && a.actions.map(\.id) == b.actions.map(\.id)
    }

    /// The signals a card on this screen was drawn from.
    static func signals(_ context: String) -> [String] {
        // The weather and air are one more thing Anya sees once they are on.
        let outdoors = EnvironmentExperiment.isEnabled && EnvironmentKeyStore.hasAny ? ["Weather and air"] : []
        switch context {
        case "today": return ["Charge", "Effort", "Sleep"] + outdoors
        case "workouts": return ["Effort", "Distance", "Steps", "Heart rate zones"] + outdoors
        case "trends": return ["Charge", "Effort"]
        default: return []
        }
    }
}

struct NunaAnyaSheet: View {
    let context: String
    /// Set when a card with its own line opened the sheet.
    var cardLine: NunaAnyaCardLine?
    /// Set by a single-metric screen, so the read and the questions are about that metric.
    var metric: NunaAnyaMetric?
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var read: NunaAnyaRead?
    @State private var loaded = false
    @State private var explanation: String?
    @State private var explaining = false
    @State private var path = NavigationPath()

    /// Provider replies use light markdown (bold, lists); show it formatted and keep line breaks.
    static func markdown(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }

    private var module: NunaAnyaModule { NunaAnyaModule(context: context) }

    /// What the provider is told about this page: the local read and the notes Anya kept in this module (and only this one).
    private var notice: String? {
        [read.map { NunaMark.plain($0.headline + ($0.detail.map { ". " + $0 } ?? "")) }, NunaAnyaMemory.summary(module)].compactMap { $0 }.joined(separator: "\n\n").nilIfEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    top
                    if let read { card(read) } else if loaded { empty }
                    connectState
                    // Follow-up questions live in the Anya tab, not here.
                    Button { openFull() } label: {
                        Text("Open full conversation").font(.nuna(size: 15, weight: .heavy)).foregroundStyle(NunaAnyaWing.ink)
                            .frame(maxWidth: .infinity).frame(height: 50).background(NunaAnyaWing.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 20).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .textCase(nil)
            .background(NunaPalette.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .nunaAnyaDestinations()
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .preferredColorScheme(NunaTheme.colorScheme)
        .task(id: "\(context)|\(metric?.key ?? "")") {
            read = await NunaAnyaReader.read(context: context, metric: metric, repo: repo, profile: profile, scale: UnitPrefs.resolveEffortScale(effortScaleRaw))
            // The questions stay the screen's; the line and the signals are the card's.
            if let c = cardLine { read = NunaAnyaRead(headline: c.headline, detail: c.detail, read: c.read, module: read?.module ?? module, questions: read?.questions ?? []) }
            loaded = true
        }
    }

    // MARK: Parts

    /// Only her icon and where she is reading.
    private var top: some View {
        HStack(spacing: 12) {
            AnyaIconTile(size: 40)
            Text(metric.map { LocalizedStringKey($0.title) } ?? module.title)
                .font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private func card(_ r: NunaAnyaRead) -> some View {
        NunaAnyaPlain(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
            VStack(alignment: .leading, spacing: 12) {
                // The headline and what follows it read as one paragraph; what is good news or bad news is in a colour.
                Text(NunaMark.attributed(NunaMark.compose(headline: r.headline, detail: r.detail)))
                    .font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true).textCase(nil)
                if let acts = cardLine?.actions, !acts.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(acts) { a in
                            Button {
                                dismiss()
                                // Let the sheet go before the screen behind it moves on.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { a.perform() }
                            } label: {
                                Text(a.title).font(.nuna(size: 14, weight: .heavy)).foregroundStyle(NunaAnyaWing.ink).padding(.horizontal, 20).frame(height: 42)
                                    .background(NunaAnyaWing.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if explaining {
                    HStack(spacing: 8) { ProgressView().controlSize(.small).tint(NunaPalette.textSecondary); Text("Anya is thinking…").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                } else if let explanation {
                    NunaDivider()
                    Text(Self.markdown(AnyaActions.proseOnly(explanation))).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                if coach.isConfigured, coach.dataConsent, explanation == nil, !explaining {
                    Button { Task { await explain() } } label: {
                        // Text and an arrow in the wing gradient, like "Learn more with Anya": no fill.
                        HStack(spacing: 8) {
                            Text("Explain").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            Image(systemName: "arrow.right").font(.nuna(size: 13, weight: .bold))
                        }
                        .foregroundStyle(LinearGradient(colors: NunaAnyaWing.colors, startPoint: .leading, endPoint: .trailing))
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var empty: some View {
        NunaAnyaPlain(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing to read yet").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text("Anya shows a line only when it has figures to cite. Wear the strap and sync, then ask again.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shown when asking needs something the wearer has not done yet. Never sends anything.
    @ViewBuilder private var connectState: some View {
        if !coach.isConfigured {
            NavigationLink(value: NunaAnyaRoute.connect) {
                NunaListRow("Connect Anya", description: "Get advice from your own data", systemImage: "link", showsChevron: true)
            }.buttonStyle(.plain)
        } else if !coach.dataConsent {
            NunaToggleRow("Let Anya use my numbers", subtitle: "Without this, Anya sees only your question", systemImage: "lock.open", isOn: $coach.dataConsent)
        }
    }

    // MARK: Actions

    private func explain() async {
        explaining = true; defer { explaining = false }
        explanation = await coach.generateContextualBrief(pageContext: context + (cardLine.map { "\n\n" + NunaMark.plain($0.headline + ($0.detail.map { ". " + $0 } ?? "")) } ?? "") + (NunaAnyaMemory.summary(module).map { "\n\n" + $0 } ?? ""))
    }

    private func openFull() {
        dismiss()
        router.requestedDestination = .coach
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
#endif
