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
        case "today": return ["Recovery", "Strain", "Sleep"] + outdoors
        case "workouts": return ["Strain", "Distance", "Steps", "Heart rate zones"] + outdoors
        case "trends": return ["Recovery", "Strain"]
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
    /// The floating style: a dark sheet with the line, suggestion chips and one box to ask in (the one the floating Anya button opens).
    var floating = false
    /// The provider's analysis the floating pill already fetched, so the sheet opens on it.
    var seed: String?
    /// Set by the Daily Outlook card: the sheet opens on the Outlook (the read of the day, ideas and cards to commit to).
    var outlook = false
    /// Set with `outlook` in the late afternoon: the sheet opens on the Day In Review instead (the day looked back on, and tonight's bedtime to commit to).
    var review = false
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
    /// 1 helpful, -1 not helpful, 0 none: for the line on show (floating style).
    @State private var feedback = 0
    @State private var path = NavigationPath()
    /// What the sheet shows: Anya's read of the line that was tapped, or a conversation about it. Each sheet has its own conversation.
    @State private var tab = "read"
    /// The Daily Outlook on show, how far "Generate alternatives" has moved on, and what was committed today.
    @State private var outlookData: NunaOutlook?
    @State private var outlookInputs: NunaOutlookInputs?
    @State private var outlookOffset = 0
    @State private var outlookCommitted = NunaOutlookGate.committed()
    /// The Day In Review on show, and whether tonight's bedtime was committed to.
    @State private var reviewData: NunaDayReview?
    @State private var reviewCommitted = NunaReviewGate.committedBedtime() != nil

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
            Group { if floating { floatingContent } else { classicContent } }
                .toolbar(.hidden, for: .navigationBar)
                .nunaAnyaDestinations()
        }
        .presentationDetents(floating ? [.large] : [.medium, .large]).presentationDragIndicator(.visible)
        .preferredColorScheme(floating ? .dark : NunaTheme.colorScheme)
        .task(id: "\(context)|\(metric?.key ?? "")") {
            read = await NunaAnyaReader.read(context: context, metric: metric, repo: repo, profile: profile, scale: UnitPrefs.resolveEffortScale(effortScaleRaw))
            // The questions stay the screen's; the line and the signals are the card's.
            // Without a card line of its own, the page's read carries the weather and air in its detail.
            if cardLine == nil, let o = read?.outdoor { read?.detail = [read?.detail, o].compactMap { $0 }.joined(separator: " ") }
            if let c = cardLine {
                // On Nutrition the card is one line; the sheet adds the day's figures, the week and the weight trend behind it.
                var detail = c.detail
                if module == .nutrition, let r = read { detail = [c.detail, r.headline + ".", r.detail].compactMap { $0 }.joined(separator: " ") }
                read = NunaAnyaRead(headline: c.headline, detail: detail, read: module == .nutrition ? (read?.read ?? c.read) : c.read, module: read?.module ?? module, questions: read?.questions ?? [])
            }
            if explanation == nil, let seed { explanation = seed }
            if outlook { await loadOutlook() }
            loaded = true
            // The review keeps its own figures: the provider's brief is a different shape, so it only answers the follow-ups.
            if outlook, !review { await explainOutlook() }
        }
    }

    private var classicContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                top
                if tab == "read" {
                    if let read { card(read) } else if loaded { empty }
                    connectState
                } else {
                    asking
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 20).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden).scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(TapGesture().onEnded { focused = false })
        .textCase(nil)
        .background(NunaBackdrop())
    }

    // MARK: Parts

    /// Only her icon and where she is reading.
    private var top: some View {
        HStack(spacing: 12) {
            AnyaIconTile(size: 40)
            Text(metric.map { LocalizedStringKey($0.title) } ?? module.title)
                .font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Spacer(minLength: 0)
            tabSwitch
        }
    }

    /// Read and Ask, small and at the right of the header.
    private var tabSwitch: some View {
        HStack(spacing: 2) {
            ForEach([("read", LocalizedStringKey("Read")), ("ask", LocalizedStringKey("Ask"))], id: \.0) { id, title in
                let on = tab == id
                Button { withAnimation(.easeInOut(duration: 0.15)) { tab = id } } label: {
                    Text(title).font(.nuna(size: 12.5, weight: .bold)).textCase(nil)
                        .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                        .padding(.horizontal, 14).frame(height: 30)
                        .background(on ? NunaPalette.glassStrong : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
                    NunaAnyaReply(text: explanation, font: .nuna(size: 14.5, weight: .semibold)).textCase(nil)
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

    /// The conversation of this sheet: what was asked and answered about this line, the box to ask more, and the way into the Anya tab.
    private var asking: some View {
        VStack(alignment: .leading, spacing: 16) {
            connectState
            if turns.isEmpty {
                Text("Ask about this line, or anything else on this page. The answer stays in this sheet.")
                    .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            } else {
                conversation
            }
            composer
            if !turns.isEmpty {
                Button { openFull() } label: {
                    HStack(spacing: 8) {
                        Text("Continue in the Anya tab").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        Image(systemName: "arrow.right").font(.nuna(size: 13, weight: .bold))
                    }
                    .foregroundStyle(LinearGradient(colors: NunaAnyaWing.colors, startPoint: .leading, endPoint: .trailing))
                    .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    /// The question an answer replies to: the last thing the person said before it.
    private func question(before turn: ChatMessage) -> String? {
        guard let i = turns.firstIndex(where: { $0.id == turn.id }) else { return nil }
        return turns[..<i].last(where: { $0.role == .user })?.text
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(turns) { t in
                if t.role == .user {
                    HStack { Spacer(minLength: 40)
                        Text(verbatim: t.text).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 14).padding(.vertical, 9).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                } else {
                    NunaAnyaReply(text: t.text, font: .nuna(size: 14.5, weight: .semibold), question: question(before: t)).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
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
        explanation = await coach.generateContextualBrief(pageContext: context + (cardLine.map { "\n\n" + NunaMark.plain($0.headline + ($0.detail.map { ". " + $0 } ?? "")) } ?? "") + (NunaAnyaMemory.summary(module).map { "\n\n" + $0 } ?? ""))
    }

    private func openFull() {
        if let last = turns.last(where: { $0.role == .user })?.text, coach.pendingPrompt == nil, turns.count == 1 { coach.pendingPrompt = last }
        dismiss()
        router.requestedDestination = .coach
    }
}

// MARK: - Floating style

/// The dark sheet the floating Anya button and its pill open: the line in large type, what to do with it, suggestion chips, and one box to ask in.
extension NunaAnyaSheet {
    private static let ink = Color(red: 0.03, green: 0.04, blue: 0.07)
    private static let sky = Color(red: 0.10, green: 0.13, blue: 0.21)

    @ViewBuilder var floatingContent: some View {
        VStack(spacing: 0) {
            floatingHeader
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        floatingMessage
                        floatingTurns
                        connectNote
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 16)
                }
                .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                .onChange(of: turns.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: sending) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
            floatingChips
            floatingComposer
        }
        .background(LinearGradient(colors: [Self.sky, Self.ink, Self.ink], startPoint: .topLeading, endPoint: .bottom).ignoresSafeArea())
        .foregroundStyle(.white).textCase(nil)
    }

    private var floatingHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                NunaAnyaRing(size: 34)
                Text("Anya").font(.nuna(size: 15, weight: .semibold))
            }
            .padding(.leading, 6).padding(.trailing, 14).frame(height: 40)
            .background(Color.white.opacity(0.09), in: Capsule())
            Spacer(minLength: 0)
            Button { path.append(NunaAnyaRoute.memory) } label: {
                HStack(spacing: 8) {
                    Text("Memory").font(.nuna(size: 15, weight: .semibold))
                    Image(systemName: "lightbulb.max").font(.system(size: 20, weight: .regular))
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 22)
    }

    @ViewBuilder private var floatingMessage: some View {
        if outlook {
            outlookMessage
        } else if explaining {
            HStack(spacing: 8) { ProgressView().controlSize(.small).tint(.white.opacity(0.7)); Text("Anya is thinking…").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.7)) }
        } else if let explanation {
            // Her written analysis is the message; the local read stays behind it.
            NunaAnyaReply(text: explanation, font: .nuna(size: 20, weight: .regular), lineSpacing: 9, color: nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            if turns.isEmpty { feedbackRow(copying: AnyaActions.proseOnly(explanation), note: String(explanation.prefix(80))) }
        } else if let read {
            Text(NunaMark.attributed(NunaMark.compose(headline: read.headline, detail: read.detail), size: 20))
                .font(.nuna(size: 20, weight: .regular)).lineSpacing(9).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if turns.isEmpty { feedbackRow(copying: NunaMark.plain(NunaMark.compose(headline: read.headline, detail: read.detail)), note: read.headline) }
        } else if loaded {
            Text("Anya shows a line only when it has figures to cite. Wear the strap and sync, then ask again.")
                .font(.nuna(size: 18, weight: .regular)).foregroundStyle(.white.opacity(0.7)).lineSpacing(6)
        }
    }

    @ViewBuilder private var floatingTurns: some View {
        ForEach(turns) { t in
            if t.role == .user {
                HStack { Spacer(minLength: 56)
                    Text(verbatim: t.text).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaAnyaWing.ink)
                        .padding(.horizontal, 16).padding(.vertical, 10).background(NunaAnyaWing.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    NunaAnyaReply(text: t.text, font: .nuna(size: 18, weight: .regular), lineSpacing: 8, color: nil, question: question(before: t))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if t.id == turns.last?.id { feedbackRow(copying: AnyaActions.proseOnly(t.text), note: String(t.text.prefix(80))) }
                }
            }
        }
        if sending {
            HStack(spacing: 8) { ProgressView().controlSize(.small).tint(.white.opacity(0.7)); Text("Anya is thinking…").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.7)) }
        }
    }

    /// Copy, helpful and not helpful. The last two are kept in Anya's memory of this module, so what was not useful is not repeated.
    private func feedbackRow(copying text: String, note: String) -> some View {
        HStack(spacing: 22) {
            Button { UIPasteboard.general.string = text } label: { Image(systemName: "doc.on.clipboard").font(.system(size: 21, weight: .regular)) }
                .accessibilityLabel(Text("Copy"))
            Button { NunaAnyaMemory.remember(module, "Found this helpful: \(note)"); feedback = 1 } label: { Image(systemName: feedback == 1 ? "hand.thumbsup.fill" : "hand.thumbsup").font(.system(size: 21, weight: .regular)) }
                .accessibilityLabel(Text("Helpful"))
            Button { NunaAnyaMemory.remember(module, "Did not find this helpful: \(note)"); feedback = -1 } label: { Image(systemName: feedback == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown").font(.system(size: 21, weight: .regular)) }
                .accessibilityLabel(Text("Not helpful"))
        }
        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.9)).padding(.top, 2)
    }

    @ViewBuilder private var connectNote: some View {
        if !coach.isConfigured {
            Button { path.append(NunaAnyaRoute.connect) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                    Text("Connect Anya to ask questions about your data").font(.nuna(size: 15, weight: .semibold)).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                }
                .padding(16).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }.buttonStyle(.plain)
        } else if !coach.dataConsent {
            Toggle(isOn: $coach.dataConsent) { Text("Let Anya use my numbers").font(.nuna(size: 15, weight: .semibold)) }
                .tint(NunaAnyaWing.colors[1]).padding(16).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// The questions this page offers, as white pills in a row that scrolls sideways.
    @ViewBuilder private var floatingChips: some View {
        let qs = outlook ? outlookChips : (read?.questions ?? [])
        if !qs.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(qs) { q in
                        Button { chipTapped(q) } label: {
                            // The Outlook's follow-ups are smaller: a 30 pt pill with 13 pt words.
                            Text(verbatim: q.title).font(.nuna(size: outlook ? 13 : 15, weight: .medium)).foregroundStyle(Self.ink)
                                .padding(.horizontal, outlook ? 12 : 20).frame(height: outlook ? 30 : 46).background(.white, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden).padding(.bottom, 14)
        }
    }

    private func chipTapped(_ q: NunaAnyaQuestion) {
        if review { chooseReviewChip(q); return }
        if outlook, let idea = outlookData?.ideas.first(where: { q.id == outlookChipTitle($0) }) { chooseIdea(idea, prompt: q.prompt, shown: q.title); return }
        if !coach.isConfigured { path.append(NunaAnyaRoute.connect); return }
        Task { await ask(q.prompt, shown: q.title) }
    }

    private var floatingComposer: some View {
        HStack(spacing: 12) {
            Menu {
                Button { openFull() } label: { Label("Continue in the Anya tab", systemImage: "bubble.left.and.bubble.right") }
                Button { path.append(NunaAnyaRoute.memory) } label: { Label("Memory", systemImage: "lightbulb") }
                Button { path.append(NunaAnyaRoute.settings) } label: { Label("Anya settings", systemImage: "gearshape") }
            } label: {
                Image(systemName: "plus").font(.system(size: 22, weight: .regular))
                    .frame(width: 52, height: 52).background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain).accessibilityLabel(Text("More"))
            HStack(spacing: 8) {
                TextField("", text: $draft, prompt: Text("Ask Anya anything").foregroundStyle(.white.opacity(0.45)), axis: .vertical)
                    .font(.nuna(size: 18, weight: .regular)).lineLimit(1...3).focused($focused).tint(NunaAnyaWing.colors[0])
                    .disabled(!coach.isConfigured).onSubmit { submit() }
                let empty = draft.trimmingCharacters(in: .whitespaces).isEmpty
                Button { submit() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(NunaAnyaWing.ink)
                        .frame(width: 34, height: 34).background(NunaAnyaWing.gradient, in: Circle())
                }
                .buttonStyle(.plain).disabled(empty || sending || !coach.isConfigured).opacity(empty ? 0 : 1)
            }
            .padding(.leading, 20).padding(.trailing, 9).frame(minHeight: 52)
            .background(LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(NunaAnyaWing.gradient.opacity(0.8), lineWidth: 1))
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }
}

// MARK: - Daily Outlook

extension NunaAnyaSheet {
    fileprivate func loadOutlook() async {
        if review {
            UserDefaults.standard.set(Repository.localDayKey(Date()), forKey: NunaReviewGate.seenDayKey)
            reviewData = NunaDayReviewEngine.build(await NunaReviewLoader.inputs(repo: repo, profile: profile))
            return
        }
        UserDefaults.standard.set(true, forKey: NunaOutlookGate.openedKey)
        UserDefaults.standard.set(Repository.localDayKey(Date()), forKey: NunaOutlookGate.seenDayKey)
        let i = await NunaOutlookLoader.inputs(repo: repo, profile: profile)
        outlookInputs = i
        outlookData = NunaOutlookEngine.build(i, offset: outlookOffset)
    }

    /// When Anya is connected, her own words replace the local paragraph. Without a provider the local read stands.
    fileprivate func explainOutlook() async {
        guard explanation == nil, coach.isConfigured, coach.dataConsent, outlookData != nil || reviewData != nil else { return }
        explaining = true; defer { explaining = false }
        let read = reviewData.map(NunaDayReviewEngine.summary) ?? outlookData.map(NunaOutlookEngine.summary) ?? ""
        let page = "today\n\n" + read + (NunaAnyaMemory.summary(module).map { "\n\n" + $0 } ?? "")
        explanation = await coach.generateContextualBrief(pageContext: page).map { AnyaActions.proseOnly($0) }
    }

    fileprivate func outlookChipTitle(_ idea: NunaOutlookIdea) -> String { String(localized: "I'll go with \(idea.title.lowercased())") }

    fileprivate var outlookChips: [NunaAnyaQuestion] {
        if review { return reviewData?.chips ?? [] }
        return (outlookData?.ideas ?? []).map { NunaAnyaQuestion(title: outlookChipTitle($0), prompt: "I'll go with \($0.title) today. Help me plan it around my Recovery.") }
    }

    /// Commits to one of the ideas: remembered by Anya for this module, and shown as done on its card.
    fileprivate func commit(_ idea: NunaOutlookIdea) {
        NunaOutlookGate.commit(idea)
        outlookCommitted = NunaOutlookGate.committed()
        NunaAnyaMemory.remember(module, "Committed to \(idea.title) today.")
    }

    /// A chip: commits to the idea, and answers (the provider when connected, a short local reply otherwise).
    fileprivate func chooseIdea(_ idea: NunaOutlookIdea, prompt: String, shown: String) {
        commit(idea)
        if coach.isConfigured, coach.dataConsent { Task { await ask(prompt, shown: shown) }; return }
        turns.append(ChatMessage(id: UUID(), role: .user, text: shown))
        turns.append(ChatMessage(id: UUID(), role: .assistant,
                                 text: String(localized: "Noted: \(idea.title) is on for today. \(idea.line) Connect Anya if you want help shaping the session itself.")))
    }

    fileprivate func alternatives() {
        guard let i = outlookInputs else { return }
        outlookOffset += 3
        withAnimation(.easeInOut(duration: 0.2)) { outlookData = NunaOutlookEngine.build(i, offset: outlookOffset) }
    }

    /// Commits to tonight's bedtime: remembered by Anya for this module, and shown as done on its card.
    fileprivate func commitBedtime(_ idea: NunaOutlookIdea) {
        guard let time = reviewData?.bedtime?.title.split(separator: " ").last.map(String.init) else { return }
        NunaReviewGate.commitBedtime(time)
        reviewCommitted = true
        NunaAnyaMemory.remember(module, "Committed to being asleep by \(time) tonight.")
    }

    /// A review chip: Anya answers when she is connected, and a short local reply stands in when she is not.
    fileprivate func chooseReviewChip(_ q: NunaAnyaQuestion) {
        if coach.isConfigured, coach.dataConsent { Task { await ask(q.prompt, shown: q.title) }; return }
        turns.append(ChatMessage(id: UUID(), role: .user, text: q.title))
        turns.append(ChatMessage(id: UUID(), role: .assistant, text: NunaDayReviewEngine.reply(to: q.title)))
    }

    @ViewBuilder fileprivate var outlookMessage: some View {
        if review, let r = reviewData {
            NunaReviewContent(review: r, provider: explanation, committed: reviewCommitted, onCommit: { if let idea = r.bedtime { commitBedtime(idea) } })
            if explaining {
                HStack(spacing: 8) { ProgressView().controlSize(.small).tint(.white.opacity(0.7)); Text("Anya is thinking…").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.7)) }
            }
            if turns.isEmpty { feedbackRow(copying: NunaMark.plain(r.opening + "\n" + (explanation ?? r.paragraphs.joined(separator: "\n"))), note: r.opening) }
        } else if let o = outlookData {
            NunaOutlookContent(outlook: o, provider: explanation, committed: outlookCommitted, onCommit: { commit($0) }, onAlternatives: { alternatives() })
            if explaining {
                HStack(spacing: 8) { ProgressView().controlSize(.small).tint(.white.opacity(0.7)); Text("Anya is thinking…").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.7)) }
            }
            if turns.isEmpty { feedbackRow(copying: NunaMark.plain(o.greeting + "\n" + (explanation ?? o.paragraph)), note: o.greeting) }
        } else {
            HStack(spacing: 8) { ProgressView().controlSize(.small).tint(.white.opacity(0.7)); Text("Anya is thinking…").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.7)) }
        }
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
#endif
