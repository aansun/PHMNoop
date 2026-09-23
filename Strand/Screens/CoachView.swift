import SwiftUI
import MarkdownUI
import StrandDesign

/// Coach, the one feature in NOOP that talks to the network.
///
/// It is strictly opt-in and bring-your-own-key: the user pastes their own OpenAI
/// or Anthropic API key (stored in the macOS Keychain by `AICoachEngine`), and only
/// a compact text summary of their metrics plus their question ever leaves the Mac.
/// Nothing is sent until a key is saved and a question asked.
///
/// This screen compiles against `AICoachEngine`'s public API (the macos-core agent's
/// contract): `hasKey`, `provider` / `provider.modelOptions`, `model`, `messages`,
/// `sending`, `errorText`, `setKey(_:)`, `clearKey()`, and `send(_:)`.
struct CoachView: View {
    @EnvironmentObject var coach: AICoachEngine
    /// K8: used by "Save to Journal" — saves the coach advice as a journal entry with the text
    /// in the notes field, so it appears alongside other journal entries in Insights.
    @EnvironmentObject var repo: Repository

    /// Draft text in the composer (the question being typed).
    /// K15: the composer draft is persisted to UserDefaults so it survives an app relaunch.
    /// Restored on first appear, saved on every change. Keyed identically to the Android twin.
    private static let draftKey = "coach.composerDraft"
    @State private var draft: String = UserDefaults.standard.string(forKey: "coach.composerDraft") ?? ""
    /// Pending key text in the setup card (never persisted here, handed to `setKey`).
    @State private var keyDraft: String = ""
    /// The corrected key, typed into the editor a rejection opens. Separate from `keyDraft` so the
    /// setup card's own field is untouched, and cleared on save so a secret does not sit in view state
    /// after it has been stored. Twin of the Kotlin `keyFix`.
    @State private var keyFix: String = ""
    /// Whether the model selector is in free-text "Custom…" mode.
    @State private var customModel: Bool = false
    /// The id typed in the "Custom…" field.
    @State private var customModelDraft: String = ""
    @FocusState private var composerFocused: Bool

    /// K2: confirmation gate for the destructive "Clear conversation" toolbar action.
    @State private var showClearConfirm = false
    /// #2243: the coach settings, presented as a sheet. See `CoachSettingsView` for why a sheet
    /// rather than a push.
    @State private var showSettings = false
    /// Local thread picker. Each saved conversation stays on-device and can be reopened or deleted.
    @State private var showHistory = false

    // K4: on-device voice input for the composer (iOS only). macOS gets a no-op stub via
    // `#if os(iOS)` guards — the shared file keeps compiling for both targets.
    #if os(iOS)
    @StateObject private var voiceInput = CoachVoiceInput()
    #endif

    /// Sentinel tag for the "Custom…" entry in the model Picker.
    private let customModelTag = "__custom__"

    /// Contextual suggestion chips, derived from today's bands by `AICoachEngine.suggestions`
    /// (→ `CoachSuggestions`). Falls back to a stable generic set when there is no data. Recomputed
    /// on each body evaluation so a fresh sync immediately updates the chips.
    private var suggestions: [String] { coach.suggestions }

    private struct PromptItem: Identifiable {
        let prompt: String
        var id: String { prompt }
        var title: String
    }

    private var initialPromptItems: [PromptItem] {
        let workoutPrompts = [
            PromptItem(
                prompt: "Recommend the best workout for today using my Charge, Effort, Rest, recent workouts, and goal. Give the workout type, duration, target Heart Rate Zone or strength intensity, and one thing to avoid.",
                title: activeLanguageText("Recommend a workout")),
            PromptItem(
                prompt: "Create a practical workout plan for today. Include warm-up, main work, cooldown, duration, intensity or Heart Rate Zone, and progression. If strength training fits best, include exercises, sets, reps, and rest.",
                title: activeLanguageText("Build today's plan"))
        ]
        return workoutPrompts + suggestions.map { PromptItem(prompt: $0, title: activeLanguageText($0)) }
    }

    private var followUpPromptItems: [PromptItem] {
        let workout = PromptItem(
            prompt: "Create a practical workout plan for today. Include warm-up, main work, cooldown, duration, intensity or Heart Rate Zone, and progression. If strength training fits best, include exercises, sets, reps, and rest.",
            title: activeLanguageText("Build today's plan"))
        return AICoachEngine.followUpSuggestions.map {
            PromptItem(prompt: $0, title: activeLanguageText($0))
        } + [workout]
    }

    var body: some View {
        ScreenScaffold(title: "Coach",
                       // Liquid finish: the same full-bleed day-of-sky backdrop Today + the other liquid
                       // tabs carry, so Coach sits in one atmosphere. Static + non-interactive; the frosted
                       // message/setup cards below sit on the opaque canvas and stay legible.
                       topBackground: liquidScaffoldSky()) {
            if coach.isConfigured {
                connectedHeader
                transcript
                if let error = coach.errorText, !error.isEmpty {
                    errorBanner(error)
                    // A rejected key is the one failure the wearer can act on from here, and the
                    // message already tells them to: "Check the key and the provider you selected".
                    // Until this, the screen offered nowhere to check it. Rendered INSIDE the error
                    // branch, never on its own flag, so it cannot outlive the message justifying it.
                    if coach.keyRejected { keyRepairPanel }
                }
                // K7: show follow-up chips after each assistant reply (when the transcript is
                // non-empty and the last message is from the assistant and not mid-send);
                // otherwise show the initial contextual chips.
                if showFollowUpChips {
                    followUpChips
                } else {
                    suggestionChips
                }
            } else {
                setupCard
            }
        }
        // Keep the composer reachable like a conventional AI chat: the conversation scrolls behind it
        // while the input remains docked above the keyboard/tab bar instead of becoming another message
        // in the page scroll.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if coach.isConfigured {
                VStack(spacing: NoopMetrics.space2) {
                    if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let tokens = coach.estimatedTokens(forDraft: draft) {
                        tokenEstimateBar(tokens)
                    }
                    composer
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.top, NoopMetrics.space2)
                .padding(.bottom, NoopMetrics.space1)
                .background {
                    NoopPanelSurface(tint: StrandPalette.chargeColor,
                                     cornerRadius: 0,
                                     elevated: true,
                                     surfaceOpacity: 0.98)
                }
            }
        }
        // macOS only. On iOS these two live in `connectionMenu` instead, because this bar is hidden for
        // a primary tab root and VISIBLE in the pillar sheet, so leaving them here would render nothing
        // on the Coach tab and a duplicate of the menu in the sheet. One control per platform, reachable
        // in both of iOS's presentations. The `#if` sits on the CHAIN rather than inside the builder:
        // `ToolbarContentBuilder` is not relied on to accept an empty body, and the one other
        // conditional toolbar here (CoupledView) always yields an item on both platforms. (#2206)
        #if os(macOS)
        .toolbar {
            if coach.isConfigured {
                // K2: wipe the persisted + in-memory conversation. Confirmed, since it's destructive.
                ToolbarItem {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear conversation", systemImage: "trash")
                    }
                    .help("Clear the saved conversation")
                    .accessibilityLabel("Clear conversation")
                    .disabled(coach.messages.isEmpty)
                }
                ToolbarItem {
                    Button(role: .destructive) {
                        coach.disconnect()
                        keyDraft = ""
                    } label: {
                        Label("Disconnect", systemImage: "gearshape")
                    }
                    .help("Forget the saved key and disconnect")
                    .accessibilityLabel("Disconnect provider")
                }
            }
        }
        #endif
        // #2243: coach settings. `repo` rides along because the scaffold's environment is not
        // inherited by a sheet's own view tree.
        .sheet(isPresented: $showSettings) {
            CoachSettingsView()
                .environmentObject(coach)
                .environmentObject(repo)
        }
        .sheet(isPresented: $showHistory) {
            CoachHistoryView()
                .environmentObject(coach)
        }
        .confirmationDialog(
            "Clear conversation?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { coach.clearConversation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the saved conversation from this device. Coach history is your own notes, not medical advice.")
        }
        // K2 + K5 ordering matters and every step gates on an EMPTY transcript, so this is ONE `.task`
        // running sequentially (separate `.task`s can interleave at their await points on the same
        // actor): restore whatever the prior launch persisted, THEN surface a brief the scheduled
        // notification already generated (if any), THEN the interactive first-open brief — so
        // `startBriefIfNeeded` only ever runs over the network when BOTH of the above left the
        // transcript genuinely empty.
        .task {
            await coach.loadPersistedMessagesIfNeeded()
            // Gated on the transcript BEFORE consuming. `consumeStoredBrief()` clears the unconsumed
            // flag, and `surfaceScheduledBrief` then drops the text if a transcript exists, so a brief
            // that arrived on a day with a conversation already open was consumed and thrown away, gone
            // for good. Android checked first and so only ever failed to SHOW it (#2087).
            if coach.messages.isEmpty, let stored = CoachBriefScheduler.consumeStoredBrief() {
                coach.surfaceScheduledBrief(stored)
            }
            CoachBriefScheduler.activateIfEnabled { await coach.generateBrief() }
            await coach.startBriefIfNeeded()
        }
        // #1862: a question handed over by the Today launcher sheet. Cleared BEFORE sending so a view
        // rebuild mid-flight cannot send it twice, and gated on `isConfigured` so an unconfigured handoff
        // (which the launcher does not produce, but a future caller might) degrades to showing setup
        // rather than a failed request.
        .task(id: coach.pendingPrompt) {
            guard let prompt = coach.pendingPrompt, !prompt.isEmpty else { return }
            coach.pendingPrompt = nil
            guard coach.isConfigured else { return }
            await coach.send(prompt)
        }
        // K15: persist the composer draft so it survives an app relaunch.
        .onChangeCompat(of: draft) { newValue in
            UserDefaults.standard.set(newValue, forKey: Self.draftKey)
        }
        // K14: haptic feedback when a reply arrives (sending goes true → false).
        .onChangeCompat(of: coach.sending) { isSending in
            if !isSending && !coach.messages.isEmpty {
                triggerReplyHaptic()
            }
        }
        // A consent toggle AFTER the initial load re-checks the brief (the original `.task(id:)`
        // behaviour); the guard inside `startBriefIfNeeded` (messages.isEmpty) keeps this a no-op once
        // a conversation exists.
        .onChangeCompat(of: coach.dataConsent) { _ in
            Task { await coach.startBriefIfNeeded() }
        }
    }

    // MARK: - Setup (no key yet)

    private var setupCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    Text("Connect a provider")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                }

                Text("Coach uses your own API key. Pick a provider, paste a key, and choose a model. Your key is stored securely in the Keychain and never leaves \(Platform.deviceNounPhrase) except as the request you make.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Provider
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider").strandOverline()
                    Picker("Provider", selection: $coach.provider) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("Provider")
                }

                // Server URL (Custom / local LLM only)
                if coach.provider == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server URL").strandOverline()
                        TextField("http://localhost:11434/v1", text: $coach.customBaseURL)
                            .textFieldStyle(.plain)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                            .disableAutocorrection(true)
                            .accessibilityLabel("Server URL")
                        Text("Any OpenAI-compatible server: Ollama, LM Studio, llama.cpp, or your own gateway. Stays on your network; nothing leaves \(Platform.deviceNounPhrase).")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Key header").strandOverline()
                        Picker("Key header", selection: $coach.customAuthHeader) {
                            ForEach(CustomAIAuthHeader.allCases) { header in
                                Text(header.displayName).tag(header)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Key header")
                        Text("Use Bearer for most local servers; use x-api-key for gateways that require the key in that header.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Model
                modelSelector

                // === PHM OVERLAY (PHMNOOP) === Apple Intelligence is on-device and keyless: no API-key
                // field, no Save/Connect. When it's available `isConfigured` is already true so this card
                // never shows; it only appears when the device can't run it, so we explain why here.
                if coach.provider == .appleIntelligence {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.intelligence").foregroundStyle(StrandPalette.accent)
                                .accessibilityHidden(true)
                            Text(coach.appleIntelligenceUnavailableReason ?? "Apple Intelligence is ready. Ask away — nothing leaves \(Platform.deviceNounPhrase).")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("On-device AI: no API key, no account, no network. Requires an Apple-Intelligence-capable device.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    // Key
                    VStack(alignment: .leading, spacing: 6) {
                        Text(coach.provider == .custom ? "API key (optional)" : "API key").strandOverline()
                        SecureField(coach.provider == .custom
                                    ? "Only if your server requires one"
                                    : "Paste your \(coach.provider.displayName) API key", text: $keyDraft)
                            .textFieldStyle(.plain)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                            .onSubmit { coach.provider == .custom ? connectCustom() : saveKey() }
                            .accessibilityLabel("API key")
                    }

                    HStack {
                        if coach.provider == .custom {
                            NoopButton("Connect", systemImage: "link", kind: .primary, action: connectCustom)
                                .disabled(coach.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            NoopButton("Save key", systemImage: "key.fill", kind: .primary, action: saveKey)
                                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Spacer()
                    }
                }

                // Whatever the last attempt from THIS card ran into. The setup card had no error line
                // at all, so every way it can fail before a key is committed failed silently: a Refresh
                // the provider turned away, a Connect to a server that wants auth. The wearer saw a
                // button do nothing. No repair affordance beside it, unlike the chat: the key field is
                // already on screen, which is the whole point of the card.
                if let error = coach.errorText, !error.isEmpty {
                    errorBanner(error)
                }

            }
        }
    }

    /// Model selector: a Picker over `coach.availableModels` with a free-text "Custom…" path and a
    /// "Refresh models" button that fetches the provider's live list.
    private var modelSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Model").strandOverline()
                Spacer()
                Button {
                    Task { await coach.refreshModels() }
                } label: {
                    Label("Refresh models", systemImage: "arrow.clockwise")
                        .font(StrandFont.footnote)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(StrandPalette.accent)
                .disabled(!coach.hasKey)
                .help("Fetch the available models from \(coach.provider.displayName) using your saved key")
                .accessibilityLabel("Refresh models from provider")
            }

            Picker("Model", selection: modelPickerSelection) {
                ForEach(coach.availableModels, id: \.self) { m in
                    Text(m).tag(m)
                }
                Divider()
                Text("Custom…").tag(customModelTag)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel("Model")

            if customModel {
                HStack(spacing: 8) {
                    TextField("Enter a model id", text: $customModelDraft)
                        .textFieldStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                        .onSubmit(applyCustomModel)
                        .accessibilityLabel("Custom model id")

                    Button("Use", action: applyCustomModel)
                        .buttonStyle(NoopButtonStyle(.secondary))
                        .disabled(customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Use custom model")
                }
            }
        }
    }

    /// Bridges the model Picker to `coach.model`, with a "Custom…" sentinel that opens the free-text
    /// field instead of selecting a real id.
    private var modelPickerSelection: Binding<String> {
        Binding(
            get: { customModel ? customModelTag : coach.model },
            set: { newValue in
                if newValue == customModelTag {
                    customModel = true
                    if customModelDraft.isEmpty { customModelDraft = coach.model }
                } else {
                    customModel = false
                    coach.model = newValue
                }
            }
        )
    }

    private func applyCustomModel() {
        let trimmed = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setCustomModel(trimmed)
        customModel = false
    }

    // MARK: - Connected state

    private var connectedHeader: some View {
        HStack(spacing: 10) {
            providerSwitcher
            Spacer()
            if coach.sending {
                StatePill("Thinking", tone: .accent, pulsing: true)
            }
            Button {
                coach.startNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(coach.messages.isEmpty || coach.sending)
            .accessibilityLabel("New Coach conversation")
            .accessibilityHint("Save this conversation and start a blank chat")
            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Coach history")
            // #2243: the way through to what used to be stacked under this header.
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Coach settings"))
            #if os(iOS)
            connectionMenu
            #endif
        }
    }

    /// Provider selection remains available after a provider is configured. The setup card used to be
    /// the only provider picker, so selecting keyless Apple Intelligence made every other provider
    /// unreachable. A compact menu matches common AI chat headers and keeps provider switching one tap
    /// away without interrupting the current conversation.
    private var providerSwitcher: some View {
        Menu {
            ForEach(AIProvider.allCases) { candidate in
                Button {
                    coach.provider = candidate
                } label: {
                    if candidate == coach.provider {
                        Label(candidate.displayName, systemImage: "checkmark")
                    } else {
                        Text(candidate.displayName)
                    }
                }
                .disabled(coach.sending)
            }
        } label: {
            StatePill("\(coach.provider.displayName) · \(coach.model)", tone: .accent, showsDot: true)
        }
        .accessibilityLabel("Switch AI provider")
        .accessibilityHint("Choose Apple Intelligence, OpenAI, Anthropic, Gemini, or a custom provider")
    }

    #if os(iOS)
    /// #2206: the same two actions the toolbar above carries, drawn where iPhone can reach them.
    ///
    /// `RootTabView.tab(...)` wraps every primary tab root in a NavigationStack and applies
    /// `.toolbar(.hidden, for: .navigationBar)`, because each screen draws its own in-content header.
    /// So Clear conversation and Disconnect were being placed into a bar this platform never shows, and
    /// rendered nowhere. Disconnect is the ONLY route back to the setup card, which is the only place
    /// an API key can be typed: `isConfigured` gates that card away the moment a key is saved. The
    /// result was a key that could be set once and then never changed, with reinstalling the app the
    /// only way out, which on an offline-first app costs the wearer their entire history.
    ///
    /// macOS keeps the toolbar and does not get this, so its behaviour is untouched. On iOS the toolbar
    /// route is withdrawn rather than kept alongside: CoachView is presented twice on this platform, as
    /// a primary tab whose bar is hidden and as a pillar sheet whose bar is NOT (it draws a Done button
    /// and only hides the bar's background). Keeping both would render nothing on the tab and two of
    /// everything in the sheet. One control, reachable in both presentations.
    ///
    /// A menu rather than a bare button because it needs two taps to reach a destructive action,
    /// matching the protection the toolbar's separation gives, and because both actions belong to the
    /// same connection.
    ///
    /// Worth knowing before changing `disconnect()`: neither `hasKey` nor `isConfigured` is published,
    /// since `hasKey` reads the Keychain on each evaluation. The setup card reappears because
    /// `disconnect()` ALSO assigns the published `messages`, which is what re-evaluates the body. A
    /// future disconnect that stopped clearing the transcript would clear the key and leave this screen
    /// showing a chat for a connection that no longer exists. macOS has depended on the same coupling
    /// since its toolbar button existed, so this is a latent edge being written down, not a new one.
    private var connectionMenu: some View {
        Menu {
            Button {
                showClearConfirm = true
            } label: {
                Label("Clear conversation", systemImage: "trash")
            }
            .disabled(coach.messages.isEmpty)
            Button(role: .destructive) {
                coach.disconnect()
                keyDraft = ""
            } label: {
                Label("Disconnect", systemImage: "gearshape")
            }
        } label: {
            // Same affordance DevicesView uses for its per-device menu, headline size included. The
            // size is not decoration here: the report this came from was that the option could not be
            // FOUND, so a control that matches the one the wearer has already learned, at a size worth
            // aiming at, is doing part of the work.
            Image(systemName: "ellipsis.circle")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .accessibilityLabel("Connection")
    }
    #endif

    @ViewBuilder
    private var transcript: some View {
        if coach.messages.isEmpty {
            emptyTranscript
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // Lazy so off-screen bubbles aren't all resident/laid-out at once; with the
                    // `maxStoredMessages` cap the transcript is already bounded, this keeps render cost flat.
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(coach.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if coach.sending {
                            typingIndicator.id("typing")
                        }
                    }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // #697 parity: this screen builds its OWN ScrollView rather than going through
                // ScreenScaffold, so it never inherited the scaffold's horizontal-bounce suppression and
                // could still rubber-band left-right on a purely vertical scroll. Same modifier, same
                // guard. `.basedOnSize` permits horizontal bounce only when content genuinely overflows
                // the width, so nothing that is meant to scroll sideways is affected. (#1532 follow-up)
                #if os(iOS)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                #endif
                .frame(minHeight: 300, maxHeight: 560)
                .onChangeCompat(of: coach.messages.count) { _ in
                    scrollToEnd(proxy)
                }
                .onChangeCompat(of: coach.sending) { _ in
                    scrollToEnd(proxy)
                }
            }
        }
    }

    private var emptyTranscript: some View {
        VStack(spacing: NoopMetrics.space3) {
            Image(systemName: "sparkles")
                .font(StrandFont.rounded(28))
                .foregroundStyle(StrandPalette.accent)
                .accessibilityHidden(true)
            VStack(spacing: NoopMetrics.space1) {
                Text("Ask your first question")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Your coach can explain your numbers, compare trends, and turn today's recovery into a practical plan.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, NoopMetrics.space4)
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.surfaceBase)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(StrandPalette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(maxWidth: 520, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You said: \(message.text)")
        case .assistant:
            // LLM replies arrive as Markdown (bold, lists, headings, tables),             // rendered with the chat-bubble-sized Strand theme. User bubbles stay
            // verbatim `Text` so typed `*`/`#` never turn into surprise formatting.
            // The reply sits on a frosted Charge-tinted surface, a card, not a flat box.
            // K8: context menu (long-press / right-click) with Copy, Share, and Save actions.
            HStack {
                Markdown(message.text)
                    .markdownTheme(.strand)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frostedCardSurface(tint: StrandPalette.chargeColor, cornerRadius: 16)
                    .frame(maxWidth: 560, alignment: .leading)
                    // K8: Copy / Share / Save context menu on assistant replies.
                    .contextMenu {
                        Button {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                            #else
                            UIPasteboard.general.string = message.text
                            #endif
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        ShareLink(item: message.text) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            saveAdvice(message.text)
                        } label: {
                            Label("Save to Journal", systemImage: "square.and.pencil")
                        }
                    }
                Spacer(minLength: 48)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coach said: \(message.text)")
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(StrandPalette.accent)
            Text("Coach is thinking…")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frostedCardSurface(tint: StrandPalette.chargeColor, cornerRadius: 16)
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityLabel("Coach is thinking")
    }

    private func errorBanner(_ message: String) -> some View {
        StrandCard(padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(StrandPalette.statusCritical)
                    .accessibilityHidden(true)
                Text(message)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    /// The inline "your key was turned away, here is the field" repair, shown under a rejection.
    ///
    /// Saving goes through `setKey`, which replaces the stored key and leaves the transcript alone. The
    /// existing route was the Disconnect button, which also wipes the conversation and un-commits a
    /// custom provider: far more than correcting a typo asks for, and named for an outcome the wearer
    /// is trying to avoid. Twin of the Kotlin editor in `CoachChat`.
    private var keyRepairPanel: some View {
        StrandCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste the corrected key. Your conversation is kept.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField("Paste your \(coach.provider.displayName) API key", text: $keyFix)
                    .textFieldStyle(.plain)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    .onSubmit(saveRepairedKey)
                    .accessibilityLabel("Corrected API key")
                HStack {
                    NoopButton("Update key", systemImage: "key.fill", kind: .primary, action: saveRepairedKey)
                        .disabled(keyFix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
            }
        }
    }

    /// Store the corrected key and drop it from view state. `setKey` clears the error and the rejection
    /// flag, which is what closes this panel.
    private func saveRepairedKey() {
        let trimmed = keyFix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setKey(trimmed)
        keyFix = ""
    }

    private var suggestionChips: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(initialPromptItems) { item in
                promptButton(item)
            }
        }
        .padding(.vertical, 1)
    }

    /// K7: True when follow-up chips should show instead of the initial contextual chips —
    /// i.e. the transcript is non-empty, the last message is from the assistant, and a reply
    /// is not currently in flight.
    private var showFollowUpChips: Bool {
        guard let last = coach.messages.last, !coach.sending else { return false }
        return last.role == .assistant
    }

    /// K7: Follow-up suggestion chips shown after each assistant reply, so the user can dig
    /// deeper without typing. Uses the static `AICoachEngine.followUpSuggestions` list.
    private var followUpChips: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(followUpPromptItems) { item in
                promptButton(item)
            }
        }
        .padding(.vertical, 1)
    }

    private func promptButton(_ item: PromptItem) -> some View {
        Button {
            send(item.prompt)
        } label: {
            Text(item.title)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(StrandPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(LiquidPressStyle())
        .disabled(coach.sending)
        .accessibilityLabel(item.title)
    }

    /// Display copy follows the active app language while the underlying English prompt remains stable,
    /// preserving the analytics prompt contract and keeping the provider request clear.
    private func activeLanguageText(_ text: String) -> String {
        let language = AppLanguage.activeLocale.identifier.split(separator: "_", maxSplits: 1).first.map(String.init)
            ?? "en"
        guard language == "id" else { return String(localized: String.LocalizationValue(text)) }
        switch text {
        case "Recommend a workout": return "Rekomendasikan latihan"
        case "Build today's plan": return "Buat rencana hari ini"
        case "How's my charge trending?": return "Bagaimana tren Charge saya?"
        case "What should today's training look like?": return "Latihan hari ini sebaiknya seperti apa?"
        case "Analyse my sleep": return "Analisis tidur saya"
        case "Why am I run down?": return "Mengapa saya merasa lelah?"
        case "Active recovery only today — what should I do?": return "Hari ini hanya recovery aktif — apa yang sebaiknya saya lakukan?"
        case "Quality over volume today — plan my session": return "Utamakan kualitas hari ini — buatkan sesi saya"
        case "Green light — how hard can I push today?": return "Kondisi siap — seberapa keras saya boleh berlatih?"
        case "Why is my HRV trending down?": return "Mengapa tren HRV saya menurun?"
        case "I slept poorly — how do I recover today?": return "Tidur saya kurang baik — bagaimana recovery hari ini?"
        case "Have I done enough today, or push more?": return "Apakah latihan hari ini sudah cukup?"
        case "Tell me more about that": return "Jelaskan lebih lanjut"
        case "What should I do next?": return "Apa langkah saya berikutnya?"
        case "How does today compare to this week?": return "Bagaimana hari ini dibandingkan minggu ini?"
        case "Give me a specific action plan": return "Buatkan rencana tindakan yang spesifik"
        default: return text
        }
    }

    /// K12: A subtle token estimate shown below the composer when the draft is non-empty.
    /// Uses the ~4 chars/token heuristic — an estimate only, not an exact tokenizer count.
    private func tokenEstimateBar(_ tokens: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "speedometer")
                .font(.system(size: 10))
                .foregroundStyle(StrandPalette.textTertiary)
            Text("~\(tokens) tokens")
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textTertiary)
            if tokens > 8000 {
                Text("· may exceed small context windows")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(.top, 2)
    }

    /// The input bar, a frosted overlay surface holding the field + Send, so the composer reads as a
    /// distinct docked surface above the canvas rather than two floating controls.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask Coach about your data…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(composerFocused ? StrandPalette.focusRing : StrandPalette.hairline, lineWidth: 1))
                .onSubmit { send(draft) }
                .accessibilityLabel("Question")

            // K4: on-device voice input (iOS only). macOS compiles this section out entirely.
            #if os(iOS)
            micButton
            #endif

            // Docked icon-only send affordance: a crisp accent-filled square sized to the
            // composer row (not the full 48pt control height), so it routes through the same
            // token fill/label colours as the button system without overpowering the field.
            Button {
                send(draft)
            } label: {
                Group {
                    if coach.sending {
                        ProgressView().controlSize(.small).tint(StrandPalette.goldDeepText)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .frame(width: 44, height: 38)
                .foregroundStyle(StrandPalette.goldDeepText)
                .background(StrandPalette.accent,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(coach.sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(8)
        .background(NoopPanelSurface(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
    }

    // MARK: - K4: Voice input (iOS only)

    #if os(iOS)
    /// Mic button: starts/stops on-device speech recognition. Disabled when the locale lacks
    /// on-device support or permission is denied; tapping when permission is not yet determined
    /// triggers the system prompt.
    private var micButton: some View {
        Button {
            toggleVoice()
        } label: {
            Group {
                if voiceInput.isRecording {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(StrandPalette.statusCritical)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(canUseVoice ? StrandPalette.textSecondary : StrandPalette.textTertiary)
                }
            }
            .frame(width: 36, height: 38)
            .background(StrandPalette.surfaceInset,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(StrandPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!micButtonEnabled)
        .help(voiceInput.statusMessage ?? "Ask out loud")
        .accessibilityLabel(voiceInput.isRecording ? "Stop voice input" : "Voice input")
        .accessibilityHint(voiceInput.statusMessage ?? "Transcribes your question on-device")
        .task {
            // Pre-check on appear so the button reflects the right state without a tap.
            if voiceInput.authorization == .notDetermined {
                voiceInput.requestAuthorization { _ in }
            }
        }
    }

    /// Whether the mic button is tappable: not while sending, and only if voice is either
    /// already usable or permission hasn't been asked yet (first tap triggers the prompt).
    private var canUseVoice: Bool { voiceInput.canUseVoice }
    private var micButtonEnabled: Bool {
        !coach.sending && (canUseVoice || voiceInput.authorization == .notDetermined)
    }

    private func toggleVoice() {
        if voiceInput.isRecording {
            voiceInput.stopTranscribing { finalText in
                let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // Append to the draft (not replace) so a user can speak into existing text.
                    draft = draft.isEmpty ? trimmed : "\(draft) \(trimmed)"
                }
            }
        } else {
            // First tap with undetermined permission triggers the system prompt; if granted,
            // start transcribing immediately on the next tap. If already authorized, start now.
            if voiceInput.authorization == .notDetermined {
                voiceInput.requestAuthorization { state in
                    if state == .authorized {
                        voiceInput.startTranscribing { partial in
                            draft = partial
                        }
                    }
                }
            } else {
                voiceInput.startTranscribing { partial in
                    draft = partial
                }
            }
        }
    }
    #endif

    // MARK: - Actions

    private func saveKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setKey(trimmed)
        keyDraft = ""
    }

    /// Commit the Custom (local) provider: save an optional key, then connect on the entered URL.
    private func connectCustom() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            coach.setKey(trimmed)
            keyDraft = ""
        }
        coach.connectCustom()
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !coach.sending else { return }
        draft = ""
        composerFocused = false
        Task { await coach.send(trimmed) }
    }

    /// K14: Trigger a subtle haptic when the Coach reply arrives. On iOS, a light impact feedback.
    /// macOS doesn't have an equivalent simple API, so it's a no-op there.
    private func triggerReplyHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    /// K8: Save a coach reply to the journal as a note, so it appears alongside other journal
    /// entries in Insights and can be reviewed later. Uses the existing journal API with a
    /// fixed question ("Coach advice") and the reply text in the notes field.
    private func saveAdvice(_ text: String) {
        let day = Repository.localDayKey(Date())
        Task {
            await repo.saveJournalAnswer(
                day: day,
                question: "Coach advice",
                answeredYes: true,
                notes: text
            )
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(StrandMotion.fade) {
            if coach.sending {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = coach.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
