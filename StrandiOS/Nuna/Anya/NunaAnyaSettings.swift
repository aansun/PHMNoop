#if os(iOS)
import SwiftUI
import StrandDesign

/// Switch for the suggestion card on each screen. On unless the wearer turns it off here.
enum NunaAnyaPrefs {
    static let cardsKey = "nuna.anya.cards"
    static var cardsEnabled: Bool { UserDefaults.standard.object(forKey: cardsKey) as? Bool ?? true }
}

// MARK: - Settings (AnyaSettings.dc)

struct NunaAnyaSettingsView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(NunaAnyaPrefs.cardsKey) private var cards = true
    @AppStorage(AICoachEngine.responseLanguageKey) private var language = "app"
    @AppStorage(AICoachEngine.responseStyleKey) private var style = "balanced"
    @AppStorage("coachBrief.enabled") private var briefOn = false
    @AppStorage(AudioCoachingPreferences.enabledKey) private var voiceOn = false
    @StateObject private var memory = CoachMemoryStore()
    @State private var confirmDeleteAll = false
    @State private var historyCount = CoachConversationHistoryStore.load().count

    var body: some View {
        NunaDetailScreen("Anya settings") {
            Text("What Anya may read, how it answers and when it writes to you.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            NunaCard(small: true) {
                NunaToggleRow("Show Anya", subtitle: "The tab, the cards and the buttons", systemImage: NunaGlyph.anya, isOn: $coachEnabled).padding(.vertical, 8)
            }
            .onChange(of: coachEnabled) { _, on in CoachBriefScheduler.applyMasterSwitch(on) }

            section("Provider") {
                NavigationLink(value: NunaAnyaRoute.connect) {
                    NunaListRow(LocalizedStringKey(coach.isConfigured ? coach.provider.displayName : "Not connected"),
                                subtitle: LocalizedStringKey(coach.isConfigured ? coach.provider.nunaSubtitle(model: coach.model) : String(localized: "Choose a provider")),
                                systemImage: "cpu", showsChevron: true)
                }.buttonStyle(.plain)
                if coach.isConfigured, coach.provider != .appleIntelligence {
                    NunaDivider()
                    NavigationLink(value: coach.provider == .custom ? NunaAnyaRoute.custom : (coach.provider == .chatGPT ? .chatGPT : .apiKey(coach.provider.rawValue))) {
                        NunaListRow("Model and key", subtitle: LocalizedStringKey(coach.model.isEmpty ? String(localized: "Default") : coach.model), systemImage: "key", showsChevron: true)
                    }.buttonStyle(.plain)
                }
            }

            section("Data access") {
                NunaToggleRow("Let Anya use my numbers", subtitle: "Summaries of computed scores", systemImage: "lock.open", isOn: $coach.dataConsent).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Share patterns and Lab Book", subtitle: "Correlations and lab markers. Off by default", systemImage: "chart.xyaxis.line", isOn: $coach.includeOnDeviceSignals).padding(.vertical, 8).disabled(!coach.dataConsent)
                if coach.provider == .gemini {
                    NunaDivider()
                    NunaToggleRow("Send chart images to Gemini", subtitle: "Only with the Gemini provider", systemImage: "photo", isOn: $coach.multimodalChartEnabled).padding(.vertical, 8).disabled(!coach.dataConsent)
                }
            }
            Text("Anya names the figures it reads in every answer. Raw heartbeat intervals, PPG and motion are never sent.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)

            VStack(alignment: .leading, spacing: 10) {
                nunaRuledHeader("How Anya answers")
                NunaCard {
                    VStack(alignment: .leading, spacing: 16) {
                        labelled("Language") { NunaSegmented([(value: "id", title: "Indonesian"), (value: "en", title: "English"), (value: "app", title: "Follow app")], selection: $language) }
                        labelled("Style") { NunaSegmented([(value: "short", title: "Short"), (value: "balanced", title: "Balanced"), (value: "detailed", title: "Detailed")], selection: $style) }
                    }
                }
                NunaCard(small: true) {
                    NavigationLink(value: NunaAnyaRoute.instructions) {
                        NunaListRow("Anya's instructions", description: "Shape how it thinks and talks", systemImage: "text.alignleft", showsChevron: true)
                    }.buttonStyle(.plain)
                }
            }

            section("Anya writes to you") {
                NavigationLink(value: NunaAnyaRoute.brief) {
                    NunaListRow("Morning brief", subtitle: LocalizedStringKey(briefOn ? String(localized: "Every day at \(Self.clock(CoachBriefScheduler.timeMinutes))") : String(localized: "Off")), systemImage: "sunrise", showsChevron: true)
                }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaAnyaRoute.voiceCoach) {
                    NunaListRow("Audio coach during sessions", subtitle: LocalizedStringKey(voiceOn ? String(localized: "On") : String(localized: "Off")), systemImage: "speaker.wave.2", showsChevron: true)
                }.buttonStyle(.plain)
                NunaDivider()
                NunaToggleRow("Suggestion cards on each screen", subtitle: "One short card per module, always with figures", systemImage: "rectangle.on.rectangle", isOn: $cards).padding(.vertical, 8)
            }

            section("Memory and history") {
                NavigationLink(value: NunaAnyaRoute.memory) {
                    NunaListRow("Memory", subtitle: LocalizedStringKey(String(localized: "\(memory.memories.filter(\.isActive).count) active")), systemImage: "brain", showsChevron: true)
                }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaAnyaRoute.history) {
                    NunaListRow("Conversation history", subtitle: LocalizedStringKey(String(localized: "\(historyCount) conversations, kept on this iPhone")), systemImage: "clock.arrow.circlepath", showsChevron: true)
                }.buttonStyle(.plain)
            }
            Button(role: .destructive) { confirmDeleteAll = true } label: {
                Text("Delete all conversations").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
            Text("Anya is not a medical tool. Its answers are personal notes, not a doctor's advice.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
        .confirmationDialog("Delete all conversations?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { coach.deleteAllConversations(); historyCount = 0 }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the current conversation and the saved ones from this iPhone.") }
        .onAppear { historyCount = CoachConversationHistoryStore.load().count }
    }

    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaTrendsCap(title)
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) { VStack(spacing: 0) { content() } }
        }
    }

    private func labelled<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            content()
        }
    }
}

// MARK: - Instructions (AnyaInstructions.dc)

struct NunaAnyaInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = UserDefaults.standard.string(forKey: AICoachEngine.extraInstructionsKey) ?? ""
    private let limit = AICoachEngine.maxExtraInstructionsLength

    var body: some View {
        NunaDetailScreen("Anya's instructions", trailing: AnyView(saveButton)) {
            Text("Change how Anya thinks and talks. It applies from your next message, on top of Anya's built-in safety rules.")
                .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            NunaCard {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $text).scrollContentBackground(.hidden).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(minHeight: 170).onChange(of: text) { _, new in if new.count > limit { text = String(new.prefix(limit)) } }
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty { Text("For example: answer casually, always name the numbers you use, and give one next step.").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                        }
                    HStack {
                        Text(verbatim: String(localized: "\(text.count) of \(limit) characters")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        Spacer()
                        Button("Clear") { text = "" }.font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).disabled(text.isEmpty)
                    }
                }
            }
            nunaTrendsCap("Examples")
            example(String(localized: "Running coach"), String(localized: "Focus on pace, zones and recovery"),
                    String(localized: "You are my running coach. Focus on pace, heart-rate zones and recovery between runs, and name the numbers you use."))
            example(String(localized: "Sleep adviser"), String(localized: "Focus on routine and bedtime"),
                    String(localized: "Act as a sleep adviser. Focus on my routine and bedtime, and put sleep before adding training load."))
            Text("Safety rules, the data you allow and your memories always apply. These instructions cannot turn them off.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var saveButton: some View {
        Button {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { UserDefaults.standard.removeObject(forKey: AICoachEngine.extraInstructionsKey) } else { UserDefaults.standard.set(t, forKey: AICoachEngine.extraInstructionsKey) }
            dismiss()
        } label: {
            Text("Save").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 20).frame(height: 44).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func example(_ title: String, _ subtitle: String, _ body: String) -> some View {
        Button { text = String(body.prefix(limit)) } label: {
            NunaCard(small: true) { NunaListRow(LocalizedStringKey(title), description: LocalizedStringKey(subtitle), systemImage: "text.badge.plus", showsChevron: true) }
        }.buttonStyle(.plain)
    }
}

// MARK: - Memory (AnyaMemory.dc)

struct NunaAnyaMemoryView: View {
    @StateObject private var store = CoachMemoryStore()
    @AppStorage(CoachMemoryStore.autoCaptureKey) private var autoCapture = true
    @State private var draft = ""
    @State private var editing: CoachMemory?
    @State private var confirmDeleteAll = false

    var body: some View {
        let all = store.memories
        let active = all.filter(\.isActive), paused = all.filter { !$0.isActive }
        NunaDetailScreen("Memory") {
            // How much Anya remembers and where it came from, as plain figures on the page.
            HStack(spacing: 0) {
                figure("Active", "\(active.count)")
                figureDivider
                figure("From chats", "\(all.filter(\.fromConversation).count)")
                figureDivider
                figure("Added by you", "\(all.filter { !$0.fromConversation }.count)")
            }
            .padding(.vertical, 6)
            NunaToggleRow("Save from conversations", systemImage: "brain", isOn: $autoCapture)
            NunaFormField("Add a memory") {
                HStack {
                    TextField("", text: $draft, prompt: Text("For example: I don't eat dairy").foregroundStyle(NunaPalette.textMuted)).submitLabel(.done).onSubmit(add)
                    Button(action: add) { Image(systemName: "plus.circle.fill").font(.nuna(size: 24)).foregroundStyle(NunaPalette.textPrimary) }.buttonStyle(.plain)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityLabel(Text("Add memory"))
                }
            }
            if all.isEmpty {
                Text("Nothing yet. Tell Anya things like “remember I race on 5 December”, or add one above.")
                    .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
            }
            if !active.isEmpty { section("Active", active) }
            if !paused.isEmpty { section("Paused", paused) }
            if !all.isEmpty {
                Button { confirmDeleteAll = true } label: {
                    Text("Delete all memory").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.alertText).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain)
            }
            nunaFootnote("Memory is used with every AI provider and is stored only on this iPhone.")
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $editing) { m in NunaMemoryEditSheet(memory: m) { store.update($0) } }
        .alert(deleteTitle, isPresented: $confirmDeleteAll) {
            if paused.isEmpty {
                Button("OK", role: .cancel) {}
            } else {
                Button(paused.count == 1 ? "Delete 1 memory" : "Delete \(paused.count) memories", role: .destructive) { store.deleteInactive() }
                Button("Cancel", role: .cancel) {}
            }
        } message: { Text(deleteMessage) }
    }

    // MARK: Warning before deleting

    private var deleteTitle: LocalizedStringKey {
        let n = store.memories.filter { !$0.isActive }.count
        switch n {
        case 0: return "Nothing to delete"
        case 1: return "Delete 1 paused memory?"
        default: return "Delete \(n) paused memories?"
        }
    }

    private var deleteMessage: LocalizedStringKey {
        let paused = store.memories.filter { !$0.isActive }.count, active = store.memories.filter(\.isActive).count
        if paused == 0 { return "Only paused memories can be deleted. Pause a memory first to delete it." }
        switch active {
        case 0: return "Only paused memories are deleted. This cannot be undone."
        case 1: return "Only paused memories are deleted. The 1 active memory stays, and Anya keeps using it. This cannot be undone."
        default: return "Only paused memories are deleted. The \(active) active memories stay, and Anya keeps using them. This cannot be undone."
        }
    }

    // MARK: Pieces

    private var figureDivider: some View { Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 30) }

    private func figure(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 5) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(verbatim: value).font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }.frame(maxWidth: .infinity)
    }

    private func section(_ title: LocalizedStringKey, _ items: [CoachMemory]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaRuledHeader(title, count: items.count)
            // The lists of active and paused memories are cards; the rest of the page is on the background.
            NunaCard(small: true, padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 10)) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                        if i > 0 { NunaDivider() }
                        row(m)
                    }
                }
            }
        }
    }

    private func row(_ m: CoachMemory) -> some View {
        HStack(spacing: 12) {
            Button { editing = m } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: m.title).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(m.isActive ? NunaPalette.textPrimary : NunaPalette.textMuted)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    if !m.detail.isEmpty && m.detail != m.title {
                        Text(verbatim: m.detail).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(2)
                            .multilineTextAlignment(.leading).textCase(nil)
                    }
                    Text(verbatim: m.category.displayName + " · " + (m.fromConversation ? String(localized: "From a chat") : String(localized: "Added by you")))
                        .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { m.isActive }, set: { store.setActive(m, $0) })).labelsHidden().tint(NunaPalette.charge)
            Menu {
                Button { editing = m } label: { Label("Edit", systemImage: "pencil") }
                Button { store.setActive(m, !m.isActive) } label: { Label(m.isActive ? "Pause" : "Activate", systemImage: m.isActive ? "pause.circle" : "play.circle") }
                Button(role: .destructive) { store.delete(m) } label: { Label("Delete", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).frame(width: 34, height: 44) }
        }
        .padding(.vertical, 12)
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let found = CoachMemoryExtractor.extract(from: t) { store.add(title: found.title, detail: found.detail, category: found.category) }
        else { store.add(title: t, detail: "", category: .note) }
        draft = ""
    }
}

/// Change a memory's words and kind. The memory keeps its id, its date and whether it is active.
private struct NunaMemoryEditSheet: View {
    let memory: CoachMemory
    let onSave: (CoachMemory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var detail: String
    @State private var category: CoachMemoryCategory

    init(memory: CoachMemory, onSave: @escaping (CoachMemory) -> Void) {
        self.memory = memory; self.onSave = onSave
        _title = State(initialValue: memory.title); _detail = State(initialValue: memory.detail); _category = State(initialValue: memory.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit memory").font(.nuna(size: 18, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).padding(.top, 24)
            NunaFormField("Memory") { TextField("", text: $title, axis: .vertical).lineLimit(1...3) }
            NunaFormField("Detail") { TextField("", text: $detail, axis: .vertical).lineLimit(1...5) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(CoachMemoryCategory.allCases) { c in
                        Button { category = c } label: {
                            Label(c.displayName, systemImage: c.symbol).font(.nuna(size: 13.5, weight: .bold)).labelStyle(.titleAndIcon)
                                .foregroundStyle(category == c ? NunaPalette.textPrimary : NunaPalette.textMuted).frame(minHeight: 44)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button {
                var m = memory
                m.title = title.trimmingCharacters(in: .whitespacesAndNewlines); m.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines); m.category = category
                onSave(m); dismiss()
            } label: { Text("Save") }
                .buttonStyle(.nuna(.primary, fullWidth: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NunaSpacing.screenH)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .nunaSheetChrome(detents: [.height(470), .large])
    }
}

// MARK: - History (AnyaHistory.dc)

struct NunaAnyaHistoryView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var editing = false

    var body: some View {
        let items = coach.conversationHistory.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(query) } }
        NunaDetailScreen("History", trailing: AnyView(editButton)) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(NunaPalette.textMuted)
                TextField("", text: $query, prompt: Text("Search conversations").foregroundStyle(NunaPalette.textMuted)).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            }
            .padding(.horizontal, 16).frame(height: 48).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous)).overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
            if items.isEmpty {
                NunaCard(small: true) { Text(coach.conversationHistory.isEmpty ? "Finished conversations are kept here, on this iPhone." : "No conversation matches.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading) }
            }
            ForEach(groups(items), id: \.title) { g in
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: g.title).font(.nuna(size: 17, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                        VStack(spacing: 0) {
                            ForEach(Array(g.items.enumerated()), id: \.element.id) { i, item in
                                if i > 0 { NunaDivider() }
                                HStack(spacing: 10) {
                                    Button { coach.openConversation(item); dismiss() } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(verbatim: item.title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).multilineTextAlignment(.leading)
                                                Spacer(minLength: 6)
                                                Text(verbatim: Self.time(item.updatedAt)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                            }
                                            if let a = item.messages.last(where: { $0.role == "assistant" }) {
                                                Text(verbatim: a.text.replacingOccurrences(of: "\n", with: " ")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1)
                                            }
                                        }.padding(.vertical, 13).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    if editing {
                                        Button { withAnimation { coach.deleteConversation(item) } } label: {
                                            Image(systemName: "trash").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.alertText).frame(width: 36, height: 36)
                                        }.buttonStyle(.plain).accessibilityLabel(Text("Delete"))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Text("Saved on this iPhone. Tap Edit to delete a conversation.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var editButton: some View {
        Button { withAnimation { editing.toggle() } } label: {
            NunaBareIcon(editing ? "checkmark" : "pencil", tint: editing ? NunaPalette.charge : NunaPalette.textPrimary)
        }.buttonStyle(.plain).accessibilityLabel(Text(editing ? "Done" : "Edit"))
    }

    private struct Group { let title: String; let items: [CoachConversationHistoryItem] }

    private func groups(_ items: [CoachConversationHistoryItem]) -> [Group] {
        let cal = Calendar.current
        var today: [CoachConversationHistoryItem] = [], week: [CoachConversationHistoryItem] = [], older: [CoachConversationHistoryItem] = []
        for i in items {
            if cal.isDateInToday(i.updatedAt) { today.append(i) }
            else if i.updatedAt > Date().addingTimeInterval(-7 * 86_400) { week.append(i) } else { older.append(i) }
        }
        return [Group(title: String(localized: "Today"), items: today), Group(title: String(localized: "This week"), items: week), Group(title: String(localized: "Earlier"), items: older)].filter { !$0.items.isEmpty }
    }

    private static func time(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(d) ? "HH:mm" : "d MMM"); return f.string(from: d)
    }
}

// MARK: - Morning brief (AnyaBrief.dc)

struct NunaAnyaBriefView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var enabled = CoachBriefScheduler.isEnabled
    @State private var minutes = CoachBriefScheduler.timeMinutes
    @State private var generating = false
    @State private var status: String?
    @State private var preview = CoachBriefScheduler.storedBrief
    @State private var sample: NunaAnyaRead?

    var body: some View {
        NunaDetailScreen("Morning brief") {
            Text("Anya writes a short brief on this iPhone each morning and shows it as a notification.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            notificationPreview
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    NunaToggleRow("Morning brief", subtitle: "Made on this iPhone every morning", systemImage: "sunrise", isOn: Binding(get: { enabled }, set: { setEnabled($0) })).padding(.vertical, 8)
                    if enabled {
                        NunaDivider()
                        HStack {
                            Text("Time").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute).labelsHidden().colorScheme(.dark)
                        }.padding(.vertical, 12)
                    }
                }
            }
            Button { Task { await generate() } } label: {
                Text(generating ? "Writing…" : "Write one now").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(generating || !coach.isConfigured || !coach.dataConsent).opacity(coach.isConfigured && coach.dataConsent ? 1 : 0.4)
            if !coach.isConfigured || !coach.dataConsent {
                NavigationLink(value: coach.isConfigured ? NunaAnyaRoute.settings : .connect) {
                    Text(coach.isConfigured ? "Allow Anya to use my numbers first" : "Connect Anya first").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                }.buttonStyle(.plain)
            }
            if let status { Text(verbatim: status).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            Text("Uses the connected provider. iOS may delay the notification by a few minutes.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
        }
        .task {
            sample = await NunaAnyaReader.read(context: "today", repo: repo, profile: profile, scale: UnitPrefs.resolveEffortScale(effortScaleRaw))
        }
    }

    /// What the notification looks like: the last real brief when there is one, otherwise the line Anya would lead with.
    private var notificationPreview: some View {
        HStack(alignment: .top, spacing: 12) {
            AnyaIconTile()
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text("Anya").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary); Spacer(); Text("now").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                Text(verbatim: preview.map { CoachBriefScheduler.oneLineSummary(from: $0) } ?? sample?.headline ?? String(localized: "Your brief appears here"))
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var timeBinding: Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? Date() }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            minutes = (c.hour ?? 7) * 60 + (c.minute ?? 0)
            CoachBriefScheduler.setTimeMinutes(minutes, generateBrief: { await coach.generateBrief() })
        })
    }

    private func setEnabled(_ on: Bool) {
        enabled = on
        CoachBriefScheduler.setEnabled(on, generateBrief: { await coach.generateBrief() }) { outcome in
            if outcome == .denied { enabled = false; status = String(localized: "Notifications are off for this app. Turn them on in iOS Settings first.") }
        }
    }

    private func generate() async {
        generating = true; status = nil; defer { generating = false }
        if let text = await CoachBriefScheduler.generateNow(generateBrief: { await coach.generateBrief() }) { preview = text; coach.appendGeneratedBrief(text) }
        else { status = String(localized: "Couldn't write a brief now. Check the provider and data access.") }
    }
}

// MARK: - Voice coach (AnyaVoiceCoach.dc)

/// Spoken cues during a session, mapped onto the audio coach that already exists: heart-rate zone alerts, distance
/// milestones, optional smart cues and the speech speed. Everything stays on this iPhone; the voice is the system voice.
struct NunaAnyaVoiceCoachView: View {
    @EnvironmentObject private var audio: AudioCoachingCoordinator
    @AppStorage(AudioCoachingPreferences.enabledKey) private var enabled = false
    @AppStorage(AudioCoachingPreferences.lifecycleKey) private var lifecycle = true
    @AppStorage(AudioCoachingPreferences.heartRateKey) private var heartRate = true
    @AppStorage(AudioCoachingPreferences.distanceKey) private var distance = true
    @AppStorage(AudioCoachingPreferences.coachingKey) private var coaching = false
    @AppStorage(AudioCoachingPreferences.checkInKey) private var checkIn = false
    @AppStorage(AudioCoachingPreferences.aiWordingKey) private var aiWording = false
    @AppStorage(AudioCoachingPreferences.distanceMilestoneKilometersKey) private var every = 1
    @AppStorage(AudioCoachingPreferences.targetZoneKey) private var targetZone = 3
    @AppStorage(AudioCoachingPreferences.frequencyKey) private var frequency = AudioPromptFrequency.normal.rawValue
    @AppStorage(AudioCoachingPreferences.speechRateKey) private var speechRate = AudioSpeechRate.normal.rawValue
    @AppStorage(AudioCoachingPreferences.chimeKey) private var chime = true

    /// The same test the standard screen has, kept visible whether or not the coach is on: it plays a sample cue with the current settings
    /// and says what happened, so a silent workout can be told apart from a setting that is off or an audio session that did not start.
    private var testCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap("Test audio")
                Text("Plays a sample with your current distance interval, details and voice speed.").font(.nuna(size: 13.5, weight: .semibold))
                    .foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                Button { audio.testAudio() } label: {
                    HStack(spacing: 8) { Image(systemName: "play.fill").font(.nuna(size: 13, weight: .bold)); Text("Test current settings").font(.nuna(size: 15, weight: .bold)) }
                        .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 46)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
                if let error = audio.lastAudioError {
                    Label { Text(verbatim: error).textCase(nil) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).fixedSize(horizontal: false, vertical: true)
                }
                if !audio.audioDetails.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(audio.audioDetails.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                    }
                }
                if let decision = audio.lastDecision {
                    Text(verbatim: decision).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                if let prompt = audio.lastPromptText {
                    Text(verbatim: String(localized: "Last prompt: \(prompt)")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                if !enabled {
                    Text("The audio coach is off. Turn it on below to hear cues during a workout; the test plays either way.").font(.nuna(size: 12.5, weight: .semibold))
                        .foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        NunaDetailScreen("Audio coach") {
            NunaCard(highlight: enabled) {
                NunaToggleRow("Anya's audio coach", subtitle: "Short spoken cues during a session, through earphones", systemImage: "speaker.wave.2", isOn: $enabled).padding(.vertical, 8)
            }
            testCard
            if enabled {
                VStack(alignment: .leading, spacing: 10) {
                    nunaRuledHeader("When Anya speaks")
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                        VStack(spacing: 0) {
                            NunaToggleRow("Start, pause and finish", subtitle: "Confirms each change and when you reach your target", systemImage: "play.circle", isOn: $lifecycle).padding(.vertical, 8)
                            NunaDivider()
                            NunaToggleRow("Out of the target zone", subtitle: "When your heart rate leaves the zone", systemImage: "heart", isOn: $heartRate).padding(.vertical, 8)
                            NunaDivider()
                            NunaToggleRow("Every kilometre", subtitle: "Distance, time and heart rate", systemImage: "figure.run", isOn: $distance).padding(.vertical, 8)
                            NunaDivider()
                            NunaToggleRow("Every minute", subtitle: "Time and heart-rate zone", systemImage: "timer", isOn: $checkIn).padding(.vertical, 8)
                            NunaDivider()
                            NunaToggleRow("Smart cues", subtitle: "Experimental: a short cue when a trend is reliable", systemImage: "sparkles", isOn: $coaching).padding(.vertical, 8)
                        }
                    }
                }
                if heartRate || coaching {
                    VStack(alignment: .leading, spacing: 10) {
                        nunaRuledHeader("How often")
                        NunaCard { NunaSegmented([(value: AudioPromptFrequency.low.rawValue, title: "Rarely"), (value: AudioPromptFrequency.normal.rawValue, title: "Balanced"), (value: AudioPromptFrequency.high.rawValue, title: "Often")], selection: $frequency) }
                    }
                }
                if heartRate {
                    NunaCard(small: true) {
                        HStack {
                            Text("Target zone").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            Picker("", selection: $targetZone) { Text("Off").tag(0); ForEach(1...5, id: \.self) { Text(verbatim: String(localized: "Zone \($0)")).tag($0) } }.pickerStyle(.menu).tint(NunaPalette.textPrimary)
                        }
                    }
                }
                if distance {
                    NunaCard(small: true) {
                        HStack {
                            Text("Announce every").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            Picker("", selection: $every) { ForEach(1...10, id: \.self) { Text(verbatim: String(localized: "\($0) km")).tag($0) } }.pickerStyle(.menu).tint(NunaPalette.textPrimary)
                        }
                    }
                }
                if coaching {
                    NunaCard(small: true) { NunaToggleRow("Let the AI word the cues", subtitle: "Uses the connected provider; a local fallback stays", systemImage: "text.bubble", isOn: $aiWording) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    nunaRuledHeader("Voice")
                    NunaCard { NunaSegmented(AudioSpeechRate.allCases.map { (value: $0.rawValue, title: LocalizedStringKey($0.title)) }, selection: $speechRate) }
                }
                NunaCard(small: true) { NunaToggleRow("Tone before each cue", subtitle: "A short beep, so a cue is noticed over music or wind", systemImage: "bell", isOn: $chime) }
            }
            Text("Spoken on this iPhone with the system voice. Music is lowered briefly and returns to normal. Silent strap vibrations are set under strap automations.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
    }
}
#endif
