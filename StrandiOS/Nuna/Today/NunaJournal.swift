#if os(iOS)
import SwiftUI
import StrandDesign

/// Journal (TodayJournal.dc). The same journal as the Default Insights screen: the merged behaviour catalog (imported questions
/// plus your own), yes or no with the tap-again-to-clear rule, numeric items, custom items, rename, regroup and hide, and the
/// day's mood. Answers are written as they are tapped, under the app's own journal source, so an import can never overwrite them.
struct NunaJournalView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @StateObject private var catalog = JournalCatalogStore()

    /// 0 = today, 1 = yesterday ... 6, -1 = tomorrow (logging ahead).
    @State private var dayOffset = 0
    @State private var answers: [String: Bool] = [:]
    @State private var numbers: [String: Double] = [:]
    @State private var imported: [String] = []
    @State private var mood: Int?
    /// Days in the strip that have at least one answer.
    @State private var loggedDays: Set<String> = []
    @State private var editing = false
    @State private var customDraft = ""
    @State private var customNumeric = false
    @State private var customGroup: JournalGroup = .other
    @State private var renaming: JournalCatalogItem?
    @State private var renameDraft = ""
    @AppStorage("journal.collapsedGroups") private var collapsedRaw = ""

    private static let offsets: [Int] = Array((-1...6).reversed())

    private var dayDate: Date { Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date() }
    private var dayKey: String { Repository.localDayKey(dayDate) }
    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        NunaDetailScreen("Journal", trailing: AnyView(editButton)) {
            dayStrip
            moodCard
            ForEach(JournalGroup.displayOrder, id: \.self) { group($0) }
            addCard
            nunaFootnote(dayOffset == -1
                ? "Logging ahead for tomorrow: today's activities inform tomorrow's recovery. Tomorrow's answers line up with tomorrow's morning."
                : "Answers are about the night and day leading into this morning, the same attribution a WHOOP export uses, so logged and imported days line up.")
        }
        .task(id: "\(repo.refreshSeq)-\(dayOffset)") { await load() }
        .onAppear {
            if let d = router.pendingJournalDayOffset { dayOffset = d; router.pendingJournalDayOffset = nil }
        }
        .alert("Rename item", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Display name", text: $renameDraft)
            Button("Save") { if let r = renaming { catalog.rename(r.canonical, to: renameDraft) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: { Text("History stays under the original question so WHOOP imports still line up.") }
    }

    private var editButton: some View {
        Button { withAnimation { editing.toggle() } } label: {
            Text(editing ? "Done" : "Edit").font(.nuna(size: 14, weight: .bold)).foregroundStyle(editing ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .padding(.horizontal, 16).frame(height: 40)
                .background(editing ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: Day and mood

    /// The date as a heading with the week as a row of capsules: the chosen day is filled, a dot under a day says it has answers.
    private var dayStrip: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text(verbatim: Self.title(dayDate)).font(.nuna(size: 22, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if dayOffset != 0 {
                    Button { withAnimation(.snappy) { dayOffset = 0 } } label: {
                        Text("Today").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 14).frame(height: 32)
                            .background(NunaPalette.glassStrong, in: Capsule())
                            .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.offsets, id: \.self) { off in
                            dayCapsule(off)
                        }
                    }.padding(.horizontal, 1)
                }
                .onAppear { DispatchQueue.main.async { proxy.scrollTo(dayOffset, anchor: .center) } }
            }
        }
    }

    private func dayCapsule(_ off: Int) -> some View {
        let on = dayOffset == off
        let isToday = off == 0
        let logged = loggedDays.contains(Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -off, to: Date()) ?? Date()))
        return Button { withAnimation(.snappy) { dayOffset = off } } label: {
            VStack(spacing: 6) {
                Text(verbatim: Self.weekday(off)).font(.nuna(size: 11, weight: .heavy)).tracking(0.6).textCase(.uppercase)
                    .foregroundStyle(on ? NunaPalette.onAccent.opacity(0.7) : NunaPalette.textSecondary)
                Text(verbatim: Self.dayNumber(off)).font(.nuna(size: 19, weight: .bold, design: NunaType.design))
                    .foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
                Circle().fill(logged ? (on ? NunaPalette.onAccent : NunaPalette.charge) : .clear).frame(width: 5, height: 5)
            }
            .frame(width: 48, height: 80)
            .background(on ? NunaPalette.accent : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? .clear : (isToday ? NunaPalette.textSecondary : NunaPalette.hairline), lineWidth: isToday && !on ? 1.5 : 1))
        }
        .buttonStyle(.plain).id(off)
    }

    /// One colour per step of the 1 to 5 scale, from rough to great.
    private static let moodTints: [Color] = [NunaPalette.alert, NunaPalette.warning, NunaPalette.effort, NunaPalette.charge, NunaPalette.rest]

    private var moodCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        nunaTrendsCap("Mood")
                        if let mood {
                            Text(verbatim: MoodStore.label(for: mood)).font(.nuna(size: 24, weight: .heavy)).foregroundStyle(Self.moodTints[min(max(mood, 1), 5) - 1])
                        } else {
                            Text("How are you feeling right now?").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                    }
                    Spacer()
                    if let mood {
                        Text(verbatim: "\(mood)/5").font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(Array(MoodStore.scale), id: \.self) { v in
                        let on = mood == v
                        let tint = Self.moodTints[v - 1]
                        Button {
                            withAnimation(.snappy) { mood = v }
                            Task { await repo.saveMood(day: dayKey, value: v) }
                        } label: {
                            Text(verbatim: "\(v)").font(.nuna(size: 19, weight: .bold, design: NunaType.design))
                                .foregroundStyle(on ? Color.black : tint)
                                .frame(width: 52, height: 52)
                                .background(on ? tint : tint.opacity(0.14), in: Circle())
                                .overlay(Circle().strokeBorder(tint.opacity(on ? 0 : 0.35), lineWidth: 1))
                                .scaleEffect(on ? 1.12 : 1)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: "\(MoodStore.label(for: v)), \(v) / 5"))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                HStack {
                    Text(verbatim: MoodStore.label(for: 1))
                    Spacer()
                    Text(verbatim: MoodStore.label(for: 5))
                }
                .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
    }

    // MARK: Behaviours

    private func items(in g: JournalGroup) -> [JournalCatalogItem] {
        catalog.resolvedItems(imported: imported, includeHidden: editing)
            .filter { $0.group == g }.sorted { ($0.sortIndex, $0.display) < ($1.sortIndex, $1.display) }
    }

    @ViewBuilder private func group(_ g: JournalGroup) -> some View {
        let list = items(in: g)
        if !list.isEmpty || editing {
            let closed = collapsed.contains(g.rawValue)
            VStack(alignment: .leading, spacing: 10) {
                Button { toggle(g) } label: {
                    HStack(spacing: 8) {
                        nunaTrendsCap(LocalizedStringKey(g.title))
                        Text(verbatim: "\(list.count)").font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        Spacer()
                        Image(systemName: closed ? "chevron.right" : "chevron.down").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                if !closed {
                    NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.canonical) { i, item in
                                if i > 0 { NunaDivider() }
                                itemRow(item)
                            }
                            if list.isEmpty { Text("Nothing here yet").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).padding(.vertical, 14) }
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ g: JournalGroup) {
        var set = collapsed
        if set.contains(g.rawValue) { set.remove(g.rawValue) } else { set.insert(g.rawValue) }
        collapsedRaw = set.sorted().joined(separator: ",")
    }

    private func itemRow(_ item: JournalCatalogItem) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: item.display).font(.nuna(size: 16, weight: .bold)).foregroundStyle(item.hidden ? NunaPalette.textMuted : NunaPalette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            if editing { editControls(item) }
            else if item.kind.isNumeric { numberControl(item) }
            else { yesNo(item.canonical) }
        }
        .padding(.vertical, 12)
    }

    private func yesNo(_ q: String) -> some View {
        HStack(spacing: 6) {
            pill("Yes", on: answers[q] == true) { set(q, true) }
            pill("No", on: answers[q] == false) { set(q, false) }
        }
    }

    private func pill(_ title: LocalizedStringKey, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .padding(.horizontal, 16).frame(height: 36).background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func numberControl(_ item: JournalCatalogItem) -> some View {
        let q = item.canonical
        let cur = numbers[q]
        return HStack(spacing: 8) {
            step("minus") { save(q, max(0, (cur ?? 0) - 1)) }
            Text(verbatim: cur.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.1f", locale: AppLanguage.activeLocale, $0) } ?? "–")
                .font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(minWidth: 34)
            if let unit = item.kind.unitLabel, !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            step("plus") { save(q, (cur ?? 0) + 1) }
            if cur != nil {
                Button { Task { await repo.clearJournalAnswer(day: dayKey, question: q); await load() } } label: {
                    Image(systemName: "xmark.circle.fill").font(.nuna(size: 16)).foregroundStyle(NunaPalette.textMuted)
                }.buttonStyle(.plain).accessibilityLabel(Text("Clear"))
            }
        }
    }

    private func step(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 34, height: 34).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func editControls(_ item: JournalCatalogItem) -> some View {
        HStack(spacing: 8) {
            if item.hidden {
                Button { catalog.restore(item.canonical) } label: {
                    Text("Restore").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 34).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            } else {
                Menu {
                    Button("Rename…") { renameDraft = item.displayName ?? item.canonical; renaming = item }
                    Menu("Group") {
                        ForEach(JournalGroup.displayOrder, id: \.self) { g in Button(g.title) { catalog.setGroup(item.canonical, to: g) } }
                    }
                    if item.kind.isNumeric { Button("Change to Yes/No") { catalog.setKind(item.canonical, to: .bool) } }
                    else { Button("Change to Number") { catalog.setKind(item.canonical, to: .numeric(unitLabel: nil)) } }
                } label: {
                    Image(systemName: "slider.horizontal.3").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 36, height: 36).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                }
                Button { catalog.remove(item.canonical) } label: {
                    Image(systemName: "minus").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                        .frame(width: 36, height: 36).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                }.buttonStyle(.plain).accessibilityLabel(Text(item.custom ? "Delete this custom item" : "Hide this item"))
            }
        }
    }

    // MARK: Add your own

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaTrendsCap("Add your own")
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("", text: $customDraft, prompt: Text("Add a custom item…").foregroundStyle(NunaPalette.textMuted))
                        .font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .padding(.horizontal, 16).frame(height: 48)
                        .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
                    NunaSegmented<Bool>([(value: false, title: "Yes/No"), (value: true, title: "Number")], selection: $customNumeric)
                    HStack {
                        Menu {
                            ForEach(JournalGroup.displayOrder, id: \.self) { g in Button(g.title) { customGroup = g } }
                        } label: {
                            HStack(spacing: 6) { Text(verbatim: customGroup.title); Image(systemName: "chevron.up.chevron.down").font(.nuna(size: 11, weight: .bold)) }
                                .font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 16).frame(height: 42).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }
                        Spacer()
                        let ok = !customDraft.trimmingCharacters(in: .whitespaces).isEmpty
                        Button {
                            catalog.addCustom(customDraft.trimmingCharacters(in: .whitespaces), kind: customNumeric ? .numeric(unitLabel: nil) : .bool, group: customGroup)
                            customDraft = ""
                        } label: {
                            Text("Add").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 24).frame(height: 42)
                                .background(NunaPalette.accent.opacity(ok ? 1 : 0.35), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain).disabled(!ok)
                    }
                }
            }
        }
    }

    // MARK: Data

    private func set(_ q: String, _ value: Bool) {
        let same = answers[q] == value
        if same { answers[q] = nil } else { answers[q] = value }
        Task {
            // Tapping the filled chip again clears the answer; only the app's own rows can ever be removed this way.
            if same { await repo.clearJournalAnswer(day: dayKey, question: q) } else { await repo.saveJournalAnswer(day: dayKey, question: q, answeredYes: value) }
            await load()
        }
    }

    private func save(_ q: String, _ value: Double) {
        numbers[q] = value
        Task { await repo.saveJournalNumeric(day: dayKey, question: q, value: value); await load() }
    }

    private func load() async {
        let key = dayKey
        let importedRows = await repo.importedJournalEntries()
        imported = (NSOrderedSet(array: importedRows.map(\.question)).array as? [String]) ?? []
        answers = await repo.nativeJournalAnswers(day: key)
        numbers = await repo.nativeJournalNumeric(day: key)
        mood = await repo.mood(day: key)
        let cal = Calendar.current
        if let first = Self.offsets.last.flatMap({ cal.date(byAdding: .day, value: -$0, to: Date()) }),
           let last = Self.offsets.first.flatMap({ cal.date(byAdding: .day, value: -$0, to: Date()) }) {
            loggedDays = await repo.nativeJournalDays(from: Repository.localDayKey(first), to: Repository.localDayKey(last))
        }
    }

    // MARK: Formatting

    private static func title(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: d)
    }
    private static func weekday(_ off: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -off, to: Date()) ?? Date()
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d)
    }
    private static func dayNumber(_ off: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -off, to: Date()) ?? Date()
        return String(Calendar.current.component(.day, from: d))
    }
}
#endif
