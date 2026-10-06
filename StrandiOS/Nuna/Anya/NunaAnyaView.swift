#if os(iOS)
import SwiftUI
import MarkdownUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import StrandDesign
import StrandAnalytics

/// Where the Anya screens lead. One enum for the tab, the sheet and Me, so each screen is reachable from all three.
enum NunaAnyaRoute: Hashable {
    case connect
    case apiKey(String)          // AIProvider.rawValue
    case custom
    case chatGPT
    case settings, memory, history, instructions, brief, voiceCoach, plan
}

extension View {
    func nunaAnyaDestinations() -> some View {
        navigationDestination(for: NunaAnyaRoute.self) { r in
            switch r {
            case .connect: NunaAnyaConnectView()
            case .apiKey(let raw): NunaAnyaKeyView(provider: AIProvider(rawValue: raw) ?? .openAI)
            case .custom: NunaAnyaCustomView()
            case .chatGPT: NunaAnyaChatGPTView()
            case .settings: NunaAnyaSettingsView()
            case .memory: NunaAnyaMemoryView()
            case .history: NunaAnyaHistoryView()
            case .instructions: NunaAnyaInstructionsView()
            case .brief: NunaAnyaBriefView()
            case .voiceCoach: NunaAnyaVoiceCoachView()
            case .plan: NunaAnyaPlanView()
            }
        }
    }
}

extension AIProvider {
    /// "Apple Intelligence · on device", "OpenAI · gpt-5.5" and so on, for the line under the Anya title.
    func nunaSubtitle(model: String) -> String {
        switch self {
        case .appleIntelligence: return String(localized: "Apple Intelligence · on device")
        case .custom: return String(localized: "Your own server") + (model.isEmpty ? "" : " · \(model)")
        default: return displayName + (model.isEmpty ? "" : " · \(model)")
        }
    }

    /// Where the question goes, for the plain-language privacy line.
    var nunaIsOnDevice: Bool { self == .appleIntelligence }
}

extension Theme {
    /// The Coach Markdown theme with the Nuna text colour and size.
    static var nuna: Theme {
        Theme.strand.text { ForegroundColor(NunaPalette.textPrimary); FontSize(15.5) }
    }
}

// MARK: - The Anya tab (Anya.dc, AnyaStart.dc)

struct NunaAnyaView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @StateObject private var memory = CoachMemoryStore()
    @StateObject private var voice = CoachVoiceInput()
    @State private var keyboardUp = false
    @State private var draft = UserDefaults.standard.string(forKey: "coach.composerDraft") ?? ""
    @FocusState private var focused: Bool
    @State private var reading: NunaAnyaRead?
    @State private var showAttach = false
    @State private var showPhoto = false
    @State private var showDocument = false
    @State private var photoItem: PhotosPickerItem?
    @State private var attachment: Attachment?
    @State private var attachmentError: String?
    @State private var showVoice = false

    enum Attachment {
        case image(name: String, base64: String)
        case document(name: String, text: String)
        var name: String { switch self { case .image(let n, _), .document(let n, _): return n } }
        var symbol: String { switch self { case .image: return "photo"; case .document: return "doc.text" } }
    }

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if coach.isConfigured {
                if coach.messages.isEmpty { start } else { transcript }
                if let error = coach.errorText, !error.isEmpty { errorBanner(error) }
                composer
            } else {
                ScrollView { connectPrompt.padding(.horizontal, NunaSpacing.screenH).padding(.top, 12).padding(.bottom, 120) }.scrollIndicators(.hidden)
            }
        }
        .textCase(nil)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .task {
            await coach.loadPersistedMessagesIfNeeded()
            if coach.messages.isEmpty, let stored = CoachBriefScheduler.consumeStoredBrief() { coach.surfaceScheduledBrief(stored) }
            CoachBriefScheduler.activateIfEnabled { await coach.generateBrief() }
        }
        .task(id: repo.refreshSeq) { reading = await NunaAnyaReader.read(context: "today", repo: repo, profile: profile, scale: scale) }
        .task(id: coach.pendingPrompt) {
            guard let prompt = coach.pendingPrompt, !prompt.isEmpty else { return }
            coach.pendingPrompt = nil
            guard coach.isConfigured else { return }
            await coach.send(prompt)
        }
        .onChange(of: draft) { _, new in UserDefaults.standard.set(new, forKey: "coach.composerDraft") }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .onChange(of: coach.sending) { _, sending in
            if !sending, !coach.messages.isEmpty { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
        .confirmationDialog("Add to Anya", isPresented: $showAttach, titleVisibility: .visible) {
            Button("Photo") { showPhoto = true }
            Button("Document") { showDocument = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhoto, selection: $photoItem, matching: .images)
        .fileImporter(isPresented: $showDocument, allowedContentTypes: [.pdf, .plainText, .commaSeparatedText, .json, .rtf, .html], allowsMultipleSelection: false) { importDocument($0) }
        .onChange(of: photoItem) { _, item in if let item { loadPhoto(item) } }
        .alert("Couldn't attach file", isPresented: Binding(get: { attachmentError != nil }, set: { if !$0 { attachmentError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: attachmentError ?? "") }
        .sheet(isPresented: $showVoice) { NunaAnyaVoiceSheet(voice: voice) { text in
            showVoice = false
            if !text.isEmpty { send(text) }
        } }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Anya").font(.nuna(size: 30, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    if coach.isConfigured {
                        HStack(spacing: 6) {
                            Image(systemName: coach.provider.nunaIsOnDevice ? "iphone" : "cloud").font(.nuna(size: 11, weight: .bold))
                            Text(verbatim: coach.provider.nunaIsOnDevice ? String(localized: "On this iPhone") : String(localized: "Connected")).lineLimit(1)
                        }
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
                Spacer(minLength: 8)
                if coach.sending { NunaChip("Thinking") }
                if coach.isConfigured {
                    round("square.and.pencil", "New conversation", enabled: !coach.messages.isEmpty && !coach.sending) { coach.startNewConversation() }
                    NavigationLink(value: NunaAnyaRoute.history) { roundLabel("clock.arrow.circlepath") }.buttonStyle(.plain).accessibilityLabel(Text("History"))
                }
                NavigationLink(value: NunaAnyaRoute.settings) { roundLabel("slider.horizontal.3") }.buttonStyle(.plain).accessibilityLabel(Text("Anya settings"))
            }
            if coach.isConfigured { readsRow }
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 10).padding(.bottom, 6)
    }

    private func round(_ symbol: String, _ label: LocalizedStringKey, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { roundLabel(symbol).opacity(enabled ? 1 : 0.4) }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel(Text(label))
    }

    private func roundLabel(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            .frame(width: 42, height: 42).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous)).overlay(RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
    }

    /// "Anya reads: Charge · Sleep · Workouts 7 days", and the memory chip. Honest: only what the settings allow.
    private var readsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if coach.dataConsent {
                    Text("Anya reads").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    ForEach(readNames, id: \.self) { n in chip(n) }
                    if coach.includeOnDeviceSignals { chip(String(localized: "Patterns and Lab Book")) }
                    NavigationLink(value: NunaAnyaRoute.settings) {
                        Text("Adjust").font(.nuna(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 6)
                    }.buttonStyle(.plain)
                } else {
                    NavigationLink(value: NunaAnyaRoute.settings) {
                        HStack(spacing: 6) { Image(systemName: "lock").font(.nuna(size: 11, weight: .bold)); Text("Anya only sees your question. Allow data access") }
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 12).frame(height: 32).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
                let active = memory.memories.filter(\.isActive).count
                if active > 0 {
                    NavigationLink(value: NunaAnyaRoute.memory) {
                        HStack(spacing: 5) { Image(systemName: "brain").font(.nuna(size: 11, weight: .bold)); Text(verbatim: String(localized: "Memory active · \(active)")) }
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 12).frame(height: 32).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var readNames: [String] {
        [String(localized: "Charge"), String(localized: "Sleep"), String(localized: "Workouts 7 days")]
    }

    private func chip(_ t: String) -> some View {
        Text(verbatim: t).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
            .padding(.horizontal, 12).frame(height: 32).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
    }

    // MARK: Not connected

    private var connectPrompt: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard(highlight: true) {
                VStack(alignment: .leading, spacing: 14) {
                    AnyaIconTile(size: 44)
                    Text("Connect Anya").font(.nuna(size: 22, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text("Anya uses the AI provider you choose. Your key stays in the Keychain on this iPhone, and nothing is sent until you allow it and ask a question.")
                        .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    NavigationLink(value: NunaAnyaRoute.connect) {
                        Text("Choose a provider").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
            if let reading {
                NunaCard(small: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your day, without a provider").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: reading.headline).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        if let d = reading.detail { Text(verbatim: d).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            NavigationLink(value: NunaAnyaRoute.plan) {
                NunaCard(small: true) { NunaListRow("Today's plan", subtitle: "Built on this iPhone from your Charge, no provider needed", systemImage: "list.bullet.rectangle", showsChevron: true) }
            }.buttonStyle(.plain)
        }
    }

    // MARK: Start (AnyaStart.dc)

    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                VStack(alignment: .leading, spacing: 10) {
                    AnyaIconTile(size: 44)
                    Text("I'm here with you").font(.nuna(size: 26, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text("Anya reads your baseline, load and sleep together, then picks the next small step.")
                        .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                if let reading {
                    NunaCard(highlight: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            nunaTrendsCap("Recommendation for today")
                            Text(verbatim: reading.headline).font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                            if let d = reading.detail { Text(verbatim: d).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil) }
                            NavigationLink(value: NunaAnyaRoute.plan) {
                                Text("Build today's plan").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                                    .padding(.horizontal, 22).frame(height: 44).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                NunaTitleRow(title: "Try asking") { EmptyView() }
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        ForEach(Array(starters.enumerated()), id: \.offset) { i, q in
                            if i > 0 { NunaDivider() }
                            Button { send(q.prompt) } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: q.title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                        Text(verbatim: q.subtitle).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                                }.padding(.vertical, 14).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(coach.sending)
                        }
                    }
                }
                NavigationLink(value: NunaAnyaRoute.memory) {
                    NunaCard(small: true) { NunaListRow("Give Anya a memory", subtitle: "Your goals, events and preferences", systemImage: "brain", showsChevron: true) }
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
    }

    private struct Starter { let title: String; let subtitle: String; let prompt: String }
    private var starters: [Starter] {
        [Starter(title: String(localized: "Recommend a workout"), subtitle: String(localized: "From Charge, Effort, Rest and your goal"),
                 prompt: "Recommend the best workout for today using my Charge, Effort, Rest, recent workouts, and goal. Give the workout type, duration, target Heart Rate Zone or strength intensity, and one thing to avoid."),
         Starter(title: String(localized: "Why is my sleep short?"), subtitle: String(localized: "Compare the last 7 nights"),
                 prompt: "Why might my sleep be short lately? Compare my last 7 nights and point to the pattern."),
         Starter(title: String(localized: "Why did HRV drop?"), subtitle: String(localized: "Look for triggers in the journal and workouts"),
                 prompt: "Why might my HRV have dropped? Look at my journal, workouts and sleep for triggers."),
         Starter(title: String(localized: "What should I eat today?"), subtitle: String(localized: "From calories out and training"),
                 prompt: "Suggest what to eat today given my activity and training load.")]
    }

    // MARK: Conversation

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(coach.messages) { message in bubble(message).id(message.id) }
                    if coach.sending {
                        HStack(spacing: 8) { ProgressView().controlSize(.small).tint(NunaPalette.textSecondary); Text("Anya is thinking…").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }.id("typing")
                    } else if let last = coach.messages.last, last.role == .assistant {
                        followUps.id("follow")
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 8)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            .onChange(of: coach.messages.count) { _, _ in scroll(proxy) }
            .onChange(of: coach.sending) { _, _ in scroll(proxy) }
            .onAppear { scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if coach.sending { proxy.scrollTo("typing", anchor: .bottom) } else if let last = coach.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    @ViewBuilder private func bubble(_ m: ChatMessage) -> some View {
        switch m.role {
        case .user:
            HStack {
                Spacer(minLength: 56)
                Text(verbatim: m.text).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.onAccent).textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 11).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                    NunaAnyaReply(text: m.text)
                }
                HStack(spacing: 8) {
                    if coach.dataConsent {
                        Text("Read:").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        ForEach(readNames, id: \.self) { n in Text(verbatim: n).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                    } else {
                        Text("Based only on your question").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                    }
                    Spacer(minLength: 0)
                    Button { UIPasteboard.general.string = AnyaActions.proseOnly(m.text) } label: { Image(systemName: "doc.on.doc").font(.nuna(size: 13, weight: .semibold)) }.buttonStyle(.plain).accessibilityLabel(Text("Copy"))
                    ShareLink(item: AnyaActions.proseOnly(m.text)) { Image(systemName: "square.and.arrow.up").font(.nuna(size: 13, weight: .semibold)) }
                    Button { saveAdvice(AnyaActions.proseOnly(m.text)) } label: { Image(systemName: "bookmark").font(.nuna(size: 13, weight: .semibold)) }.buttonStyle(.plain).accessibilityLabel(Text("Save to Journal"))
                }
                .foregroundStyle(NunaPalette.textSecondary).padding(.horizontal, 4)
            }
        }
    }

    private var followUps: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                followChip(String(localized: "What should I do next?"), "What should I do next?")
                followChip(String(localized: "Tell me more"), "Tell me more about that")
                NavigationLink(value: NunaAnyaRoute.plan) { chipLabel(String(localized: "Build today's plan")) }.buttonStyle(.plain)
            }
        }
    }
    private func followChip(_ title: String, _ prompt: String) -> some View {
        Button { send(prompt) } label: { chipLabel(title) }.buttonStyle(.plain)
    }
    private func chipLabel(_ t: String) -> some View {
        Text(verbatim: t).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            .padding(.horizontal, 14).frame(height: 38).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous)).overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
    }

    private func errorBanner(_ text: String) -> some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: text).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil)
                if coach.keyRejected {
                    NavigationLink(value: coach.provider == .custom ? NunaAnyaRoute.custom : (coach.provider == .chatGPT ? .chatGPT : .apiKey(coach.provider.rawValue))) {
                        Text("Update the key").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    }.buttonStyle(.plain)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 6)
    }

    // MARK: Composer

    private var hasContent: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil }

    private var composer: some View {
        VStack(spacing: 8) {
            if let a = attachment {
                HStack(spacing: 10) {
                    Image(systemName: a.symbol).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: a.name).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                    Spacer()
                    Button { attachment = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(NunaPalette.textMuted) }.buttonStyle(.plain).accessibilityLabel(Text("Remove attachment"))
                }
                .padding(.horizontal, 14).frame(height: 40).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                Text("The file is read on this iPhone and only its text is sent with your question.").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
            HStack(spacing: 10) {
                Button { showAttach = true } label: {
                    Image(systemName: "plus").font(.nuna(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 48, height: 48).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous)).overlay(RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel(Text("Add attachment"))
                HStack(spacing: 6) {
                    TextField("", text: $draft, prompt: Text("Ask Anya about your data").foregroundStyle(NunaPalette.textMuted), axis: .vertical)
                        .font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1...4)
                        .focused($focused).padding(.leading, 16).padding(.vertical, 12).onSubmit { send(draft) }
                    if coach.sending {
                        ProgressView().controlSize(.small).tint(NunaPalette.textSecondary).frame(width: 40, height: 40)
                    } else if !hasContent {
                        Button { showVoice = true } label: {
                            Image(systemName: "mic.fill").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 40, height: 40)
                        }.buttonStyle(.plain).accessibilityLabel(Text("Ask out loud"))
                    } else {
                        Button { send(draft) } label: {
                            Image(systemName: "arrow.up").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(width: 38, height: 38).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                        }.buttonStyle(.plain).accessibilityLabel(Text("Send")).padding(.trailing, 5)
                    }
                }
                .frame(minHeight: 48).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous)).overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
            }
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8)
        // The floating tab bar sits over the bottom of this tab, so the box is lifted clear of it; with the keyboard up it rides above the keyboard.
        .padding(.bottom, keyboardUp ? 8 : 104)
        .background(NunaPalette.canvas)
    }

    // MARK: Actions

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || attachment != nil), !coach.sending else { return }
        var prompt = trimmed
        switch attachment {
        case .image:
            if prompt.isEmpty { prompt = "Please review the attached image and tell me what is relevant to my recovery today." }
            if case .image(_, let b64) = attachment { coach.pendingChartImage = b64 }
        case .document(let name, let body):
            let question = prompt.isEmpty ? "Please review the attached document and explain the points most relevant to my recovery today." : prompt
            prompt = "\(question)\n\n[Attached document: \(name)]\n\(body)\n[/Attached document]"
            coach.pendingChartImage = nil
        case nil: coach.pendingChartImage = nil
        }
        attachment = nil; photoItem = nil; draft = ""; focused = false
        Task { await coach.send(prompt) }
    }

    private func saveAdvice(_ text: String) {
        let day = Repository.localDayKey(Date())
        Task { await repo.saveJournalAnswer(day: day, question: "Coach advice", answeredYes: true, notes: text) }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                  let resized = image.preparingThumbnail(of: CGSize(width: 1600, height: 1600)), let png = resized.pngData() else {
                attachmentError = String(localized: "The selected photo could not be read."); photoItem = nil; return
            }
            attachment = .image(name: String(localized: "Photo"), base64: png.base64EncodedString()); photoItem = nil
        }
    }

    private func importDocument(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let secured = url.startAccessingSecurityScopedResource(); defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let text: String
            switch url.pathExtension.lowercased() {
            case "pdf":
                guard let doc = PDFDocument(data: data), let s = doc.string else { throw CocoaError(.fileReadCorruptFile) }
                text = s
            case "rtf": text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
            case "html", "htm": text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil).string
            default:
                guard let s = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
                text = s
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            attachment = .document(name: url.lastPathComponent, text: String(trimmed.prefix(24_000)))
        } catch {
            attachmentError = String(localized: "This document could not be read. Choose a PDF or a text-based document.")
        }
    }
}

// MARK: - Voice (AnyaVoice.dc)

/// Listening sheet: the words appear as they are recognised, on this iPhone, and nothing is sent until Send.
struct NunaAnyaVoiceSheet: View {
    @ObservedObject var voice: CoachVoiceInput
    let onFinish: (String) -> Void
    @State private var text = ""
    @State private var started = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            ZStack {
                Circle().fill(NunaPalette.glassStrong).frame(width: 96, height: 96)
                Image(systemName: voice.isRecording ? "waveform" : "mic.fill").font(.nuna(size: 34, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                    .symbolEffect(.variableColor.iterative, isActive: voice.isRecording)
            }
            Text(voice.isRecording ? "Listening" : "Paused").font(.nuna(size: 22, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            ScrollView {
                Text(verbatim: text.isEmpty ? (voice.statusMessage ?? String(localized: "Say what you want to ask")) : text)
                    .font(.nuna(size: 20, weight: .semibold)).foregroundStyle(text.isEmpty ? NunaPalette.textMuted : NunaPalette.textPrimary)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }.frame(maxHeight: 200)
            Text("Recognised on this iPhone. Your voice is not sent anywhere.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).multilineTextAlignment(.center)
            Spacer()
            HStack(spacing: 12) {
                Button { voice.stopTranscribing { _ in }; onFinish("") } label: {
                    Text("Cancel").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 54).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
                Button { voice.stopTranscribing { final in onFinish(final.isEmpty ? text : final) } } label: {
                    Text("Send").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(text.isEmpty).opacity(text.isEmpty ? 0.4 : 1)
            }
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 20)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .presentationDetents([.medium, .large]).preferredColorScheme(NunaTheme.colorScheme)
        .task {
            guard !started else { return }
            started = true
            if voice.authorization == .notDetermined {
                voice.requestAuthorization { state in if state == .authorized { voice.startTranscribing { text = $0 } } }
            } else {
                voice.startTranscribing { text = $0 }
            }
        }
        .onDisappear { if voice.isRecording { voice.stopTranscribing { _ in } } }
    }
}
#endif
