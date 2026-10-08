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
        switch context {
        case "today": return ["Charge", "Effort", "Sleep"]
        case "workouts": return ["Effort", "Heart rate zones"]
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
    @State private var turns: [ChatMessage] = []
    @State private var draft = ""
    @State private var sending = false
    @FocusState private var focused: Bool
    @State private var path = NavigationPath()

    /// Provider replies use light markdown (bold, lists); show it formatted and keep line breaks.
    static func markdown(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }

    private var module: NunaAnyaModule { NunaAnyaModule(context: context) }

    /// What the provider is told about this page: the local read and the notes Anya kept in this module (and only this one).
    private var notice: String? {
        [read.map { $0.headline + ($0.detail.map { ". " + $0 } ?? "") }, NunaAnyaMemory.summary(module)].compactMap { $0 }.joined(separator: "\n\n").nilIfEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    top
                    if let read { card(read) } else if loaded { empty }
                    connectState
                    if !turns.isEmpty { conversation }
                    if let read { questions(read) }
                    composer
                    Button { openFull() } label: {
                        Text("Open full conversation").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 50).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 20).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded { focused = false })
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

    private var top: some View {
        HStack(spacing: 10) {
            AnyaIconTile(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Anya").font(.nuna(size: 22, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Text("Anya sees").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer()
            Text(metric.map { LocalizedStringKey($0.title) } ?? module.title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
        }
    }

    private func card(_ r: NunaAnyaRead) -> some View {
        NunaAnyaPlain(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: r.headline).font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                if let d = r.detail { Text(verbatim: d).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil) }
                if let acts = cardLine?.actions, !acts.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(acts) { a in
                            Button {
                                dismiss()
                                // Let the sheet go before the screen behind it moves on.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { a.perform() }
                            } label: {
                                Text(a.title).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 18).frame(height: 40)
                                    .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
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
                if !r.read.isEmpty {
                    HStack(spacing: 6) {
                        Text("Read:").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        ForEach(r.read, id: \.self) { Text(LocalizedStringKey($0)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                    }
                }
                if coach.isConfigured, coach.dataConsent, explanation == nil, !explaining {
                    Button { Task { await explain() } } label: {
                        Text("Explain")
                            .font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 18).frame(height: 40)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
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

    private func questions(_ r: NunaAnyaRead) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(r.questions.enumerated()), id: \.element.id) { i, q in
                if i > 0 { NunaDivider() }
                Button {
                    if q.kind == .plan { path.append(NunaAnyaRoute.plan) } else { Task { await ask(q.prompt, shown: q.title) } }
                } label: {
                    HStack {
                        Text(verbatim: q.title).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        Image(systemName: q.kind == .plan ? "chevron.right" : "arrow.up.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    .frame(height: 52).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(sending || (q.kind == .ask && !(coach.isConfigured)))
                    .opacity(q.kind == .ask && !coach.isConfigured ? 0.45 : 1)
            }
        }
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(turns) { t in
                if t.role == .user {
                    HStack { Spacer(minLength: 40)
                        Text(verbatim: t.text).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 14).padding(.vertical, 9).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                } else {
                    Text(Self.markdown(AnyaActions.proseOnly(t.text))).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if sending { HStack(spacing: 8) { ProgressView().controlSize(.small).tint(NunaPalette.textSecondary); Text("Anya is thinking…").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) } }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("", text: $draft, prompt: Text(coach.isConfigured ? "Ask a follow-up" : "Connect Anya to ask").foregroundStyle(NunaPalette.textMuted), axis: .vertical)
                .font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1...3).focused($focused)
                .padding(.leading, 16).padding(.vertical, 12).disabled(!coach.isConfigured).onSubmit { submit() }
            Button { submit() } label: {
                Image(systemName: "arrow.up").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(width: 38, height: 38).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
            }.buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending || !coach.isConfigured)
                .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1).padding(.trailing, 5)
        }
        .frame(minHeight: 48).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous)).overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
    }

    // MARK: Actions

    private func submit() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        draft = ""; focused = false
        Task { await ask(q, shown: q) }
    }

    /// Answers inside the sheet. Needs a provider and data access; otherwise it hands the question to the full conversation
    /// where the same gates are explained, so nothing is sent from here without them.
    private func ask(_ prompt: String, shown: String) async {
        guard coach.isConfigured else { return }
        guard coach.dataConsent else { coach.pendingPrompt = prompt; openFull(); return }
        turns.append(ChatMessage(id: UUID(), role: .user, text: shown))
        sending = true; defer { sending = false }
        let reply = await coach.answerContextualMessage(pageContext: context, notice: notice, history: Array(turns.dropLast()), question: prompt)
        turns.append(ChatMessage(id: UUID(), role: .assistant, text: reply ?? String(localized: "I couldn't answer right now. Check the provider in Anya settings.")))
        if let reply { NunaAnyaMemory.remember(module, "Asked: \(shown) Answer: \(reply.prefix(220))") }
    }

    private func explain() async {
        explaining = true; defer { explaining = false }
        explanation = await coach.generateContextualBrief(pageContext: context + (cardLine.map { "\n\n" + $0.headline + ($0.detail.map { ". " + $0 } ?? "") } ?? "") + (NunaAnyaMemory.summary(module).map { "\n\n" + $0 } ?? ""))
    }

    private func openFull() {
        if let last = turns.last(where: { $0.role == .user })?.text, coach.pendingPrompt == nil, turns.count == 1 { coach.pendingPrompt = last }
        dismiss()
        router.requestedDestination = .coach
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
#endif
