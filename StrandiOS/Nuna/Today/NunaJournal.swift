#if os(iOS)
import SwiftUI
import StrandDesign

/// Journal (TodayJournal.dc). The same journal as the Default Insights screen: the merged behaviour catalog (imported questions
/// plus your own), yes or no with the tap-again-to-clear rule, numeric items, custom items, rename, regroup and hide, and the
/// day's mood. Answers are written as they are tapped, under the app's own journal source, so an import can never overwrite them.
struct NunaJournalView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @Environment(\.dismiss) private var dismiss
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
    /// The day's note, the Smart log sheet, what it just filled in, and a counter that redraws the follow-up answers after they change.
    @State private var note = ""
    @State private var showSmart = false
    @State private var smartResult: String?
    @State private var extrasTick = 0
    /// True once the page has scrolled under the bar.
    @State private var scrolled = false

    private static let offsets: [Int] = Array((0...6).reversed())

    private var dayDate: Date { Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date() }
    private var dayKey: String { Repository.localDayKey(dayDate) }
    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // The page's own colour: a deep violet at the top that fades into the canvas by the lower half of the screen.
                LinearGradient(stops: [.init(color: Color(red: 62 / 255, green: 43 / 255, blue: 118 / 255), location: 0),
                                       .init(color: Color(red: 51 / 255, green: 38 / 255, blue: 99 / 255), location: 0.15),
                                       .init(color: Color(red: 22 / 255, green: 24 / 255, blue: 40 / 255), location: 0.5),
                                       .init(color: NunaPalette.canvas, location: 0.7)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        dayNav
                        daySelector.padding(.top, 7)
                        heading
                        smartCard
                        moodLink
                        behaviors
                        notesSection
                        if editing { addCard }
                        nunaFootnote("Answers are about the night and day leading into this morning, the same attribution a WHOOP export uses, so logged and imported days line up.")
                    }
                    .padding(.horizontal, NunaSpacing.screenH).padding(.top, geo.safeAreaInsets.top + 45).padding(.bottom, 150)
                    .background(NunaScrollOffsetReader { y in
                        let on = y > 40
                        if on != scrolled { withAnimation(.easeInOut(duration: 0.15)) { scrolled = on } }
                    })
                    // A warm light at the top of the page, part of the page: it scrolls away with it, leaving the violet.
                    .background(alignment: .top) {
                        LinearGradient(stops: [.init(color: Color(red: 207 / 255, green: 178 / 255, blue: 142 / 255), location: 0),
                                               .init(color: Color(red: 159 / 255, green: 152 / 255, blue: 138 / 255), location: 0.25),
                                               .init(color: Color(red: 106 / 255, green: 113 / 255, blue: 113 / 255), location: 0.5),
                                               .init(color: Color(red: 56 / 255, green: 66 / 255, blue: 74 / 255), location: 0.75),
                                               .init(color: Color(red: 15 / 255, green: 19 / 255, blue: 23 / 255).opacity(0), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 540).frame(maxWidth: .infinity)
                    }
                }
                .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).ignoresSafeArea(edges: .top)
                // The bar: the X, the name of the page and the pencil on the page's own violet, which only shows once the page has scrolled under it,
                // so what scrolls up goes out of sight behind it instead of running through the buttons.
                header
                    .offset(y: -11)
                    .frame(maxWidth: .infinity)
                    .background(alignment: .bottom) {
                        // Reaches up under the status bar, however tall that is.
                        Color(red: 62 / 255, green: 43 / 255, blue: 118 / 255).opacity(scrolled ? 1 : 0)
                            .padding(.top, -200).ignoresSafeArea(edges: .top)
                    }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { if !editing { saveBar } }
        .task(id: "\(repo.refreshSeq)-\(dayOffset)") { await load(); note = NunaJournalExtras.note(day: dayKey) }
        .sheet(isPresented: $showSmart) { NunaJournalSmartSheet { text in applySmart(text) } }
        .onAppear {
            if let d = router.pendingJournalDayOffset { dayOffset = d; router.pendingJournalDayOffset = nil }
        }
        .alert("Rename item", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Display name", text: $renameDraft)
            Button("Save") { if let r = renaming { catalog.rename(r.canonical, to: renameDraft) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: { Text("History stays under the original question so WHOOP imports still line up.") }
    }

    /// The cross to leave, the name of the page in the middle and the pencil that edits the list.
    private var header: some View {
        ZStack {
            Text("Journal").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.nuna(size: 19, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Close"))
                Spacer()
                editButton
            }
        }
        .padding(.horizontal, NunaSpacing.screenH - 6).padding(.top, 8).padding(.bottom, 2)
    }

    /// Every answer is written the moment it is tapped, so this only closes the journal; it is there so finishing reads as a step.
    private var saveBar: some View {
        Button { dismiss() } label: {
            Text("Done").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1.2)).textCase(.uppercase)
                .foregroundStyle(Color(red: 0.05, green: 0.06, blue: 0.08))
                .frame(maxWidth: .infinity).frame(height: 47)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 23).padding(.top, 24).padding(.bottom, 10)
        .background(LinearGradient(colors: [NunaPalette.canvas.opacity(0), NunaPalette.canvas.opacity(0.96), NunaPalette.canvas], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)).ignoresSafeArea())
    }

    /// A pencil, like the reference: it switches the list into edit mode and back.
    private var editButton: some View {
        Button { withAnimation { editing.toggle() } } label: {
            NunaBareIcon(editing ? "checkmark" : "pencil", tint: editing ? NunaPalette.charge : NunaPalette.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(editing ? "Done" : "Edit"))
    }

    // MARK: Day and mood

    /// Previous day, the day's name, next day: the way the reference steps through the week. There is no day after today.
    private var dayNav: some View {
        HStack(spacing: 18) {
            Button { withAnimation(.snappy) { dayOffset = min(6, dayOffset + 1) } } label: {
                Image(systemName: "chevron.left").font(.nuna(size: 17, weight: .black)).frame(width: 44, height: 44).contentShape(Rectangle())
            }.disabled(dayOffset >= 6).opacity(dayOffset >= 6 ? 0.3 : 1)
            Text(verbatim: Self.navLabel(dayOffset)).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textPrimary).frame(minWidth: 150)
            Button { withAnimation(.snappy) { dayOffset = max(0, dayOffset - 1) } } label: {
                Image(systemName: "chevron.right").font(.nuna(size: 17, weight: .black)).frame(width: 44, height: 44).contentShape(Rectangle())
            }.disabled(dayOffset <= 0).opacity(dayOffset <= 0 ? 0.3 : 1)
        }
        .foregroundStyle(NunaPalette.textPrimary).buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    /// The week as a row of days: a check for a day with answers, an empty circle for one without, a ring around the chosen day.
    private var daySelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Self.offsets, id: \.self) { off in dayColumn(off) }
                }.padding(.horizontal, 1).padding(.vertical, 3)
            }
            .onAppear { DispatchQueue.main.async { proxy.scrollTo(dayOffset, anchor: .center) } }
            .onChange(of: dayOffset) { _, new in withAnimation(.snappy) { proxy.scrollTo(new, anchor: .center) } }
        }
    }

    /// A day, 41 pt wide and 72 high as on the reference: its name, its number and, at the bottom, a check or an empty circle.
    private func dayColumn(_ off: Int) -> some View {
        let on = dayOffset == off
        let logged = loggedDays.contains(Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -off, to: Date()) ?? Date()))
        return Button { withAnimation(.snappy) { dayOffset = off } } label: {
            ZStack {
                Text(verbatim: Self.weekday(off)).font(.nuna(size: 13, weight: .semibold))
                    .foregroundStyle(NunaPalette.textPrimary.opacity(on ? 1 : 0.88)).textCase(nil).position(x: 20.75, y: 14)
                Text(verbatim: Self.dayNumber(off)).font(.nunaBoldFigure(size: 16)).foregroundStyle(NunaPalette.textPrimary).position(x: 20.75, y: 36)
                if logged {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundStyle(.black)
                        .frame(width: 16, height: 16).background(Color(red: 0.0, green: 0.86, blue: 0.54), in: Circle()).position(x: 20.75, y: 55.5)
                } else {
                    Circle().fill(NunaPalette.textPrimary.opacity(0.22)).frame(width: 16, height: 16).position(x: 20.75, y: 55.5)
                }
            }
            .frame(width: 41.5, height: 72)
            .background(NunaPalette.textPrimary.opacity(on ? 0.2 : 0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? NunaPalette.textPrimary : .clear, lineWidth: 1.8))
        }
        .buttonStyle(.plain).id(off)
        .accessibilityLabel(Text(verbatim: Self.title(Calendar.current.date(byAdding: .day, value: -off, to: Date()) ?? Date())))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var heading: some View {
        let date = Self.shortDate(dayDate)
        let text = dayOffset == 0
            ? String(format: String(localized: "What's happening today, %@?"), date)
            : String(format: String(localized: "What's happening on %@?"), date)
        return Text(verbatim: text).font(.nuna(size: 26, weight: .medium)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            .lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14).padding(.bottom, 4)
    }

    /// Mood has its own screen, so the journal only points to it, with what was logged for the day.
    private var moodLink: some View {
        NavigationLink(value: NunaTodayRoute.mood) {
            NunaCard(small: true) {
                NunaListRow("Mood", subtitle: mood.map { LocalizedStringKey(MoodStore.label(for: $0)) } ?? "Log how you feel", systemImage: "face.smiling", showsChevron: true) {
                    if let mood { Text(verbatim: "\(mood)/5").font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary) }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Smart log

    /// "Smart log": write the day in your own words and the behaviours it answers are filled in.
    private var smartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 20)).foregroundStyle(Color(red: 0.50, green: 0.55, blue: 0.98))
                Text("Smart log with Anya").font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            }
            Button { showSmart = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard").font(.system(size: 17))
                    Text("Text").font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.3).textCase(.uppercase)
                }
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 39)
                .background(Color(red: 0.25, green: 0.26, blue: 0.36), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            }.buttonStyle(.plain)
            if let smartResult {
                Text(verbatim: smartResult).font(.nuna(size: 13.5, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 16)
        .background(LinearGradient(colors: [Color(red: 0.17, green: 0.18, blue: 0.30), Color(red: 0.13, green: 0.18, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color(red: 0.34, green: 0.32, blue: 0.66).opacity(0.8), lineWidth: 1.2))
        .padding(.top, 4)
    }

    private func applySmart(_ text: String) {
        let all = catalog.resolvedItems(imported: imported, includeHidden: false)
        let found = NunaJournalSmartLog.answers(from: text, items: all)
        // The words stay with the day, as its note.
        let kept = note.isEmpty ? text : note + "\n" + text
        note = kept; NunaJournalExtras.setNote(kept, day: dayKey)
        guard !found.isEmpty else { smartResult = String(localized: "Nothing in that matched a behavior. It was kept as a note."); return }
        for (q, yes) in found { answers[q] = yes }
        Task {
            for (q, yes) in found { await repo.saveJournalAnswer(day: dayKey, question: q, answeredYes: yes) }
            await load()
        }
        smartResult = String(localized: "Logged \(found.count) from what you wrote. Check them below.")
    }

    // MARK: Behaviours

    /// A single list under "Behaviors", the way the reference has it; the groups come back while the list is being edited.
    @ViewBuilder private var behaviors: some View {
        if editing {
            ForEach(JournalGroup.displayOrder, id: \.self) { group($0) }
        } else {
            let all = JournalGroup.displayOrder.flatMap { items(in: $0) }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text("Behaviors").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.3).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Rectangle().fill(NunaPalette.hairline).frame(height: 1)
                }
                .padding(.top, 14)
                ForEach(all, id: \.canonical) { item in itemRow(item) }
            }
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.3).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            TextField("", text: $note, prompt: Text("Add a note…").foregroundStyle(NunaPalette.textMuted), axis: .vertical)
                .font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2...8)
                .onChange(of: note) { _, v in NunaJournalExtras.setNote(v, day: dayKey) }
                .padding(.horizontal, 16).padding(.vertical, 16).frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
        .padding(.top, 22)
    }

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
                    HStack(spacing: 12) {
                        Text(LocalizedStringKey(g.title)).font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingHead(0.6)).textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                        Rectangle().fill(NunaPalette.hairline).frame(height: 1)
                        Image(systemName: closed ? "chevron.right" : "chevron.down").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    .padding(.top, 10).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if !closed {
                    ForEach(list, id: \.canonical) { item in itemRow(item) }
                    if list.isEmpty { Text("Nothing here yet").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).padding(.vertical, 14) }
                }
            }
        }
    }

    private func toggle(_ g: JournalGroup) {
        var set = collapsed
        if set.contains(g.rawValue) { set.remove(g.rawValue) } else { set.insert(g.rawValue) }
        collapsedRaw = set.sorted().joined(separator: ",")
    }

    /// A behaviour as a translucent card 62 pt high: its question, and the two buttons. Answered yes, a behaviour with follow-ups opens them below.
    private func itemRow(_ item: JournalCatalogItem) -> some View {
        let q = item.canonical
        let follow = (!editing && !item.kind.isNumeric && answers[q] == true) ? NunaJournalExtras.spec(q) : nil
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(verbatim: item.display).font(.nuna(size: 17, weight: .regular)).foregroundStyle(item.hidden ? NunaPalette.textMuted : NunaPalette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).textCase(nil)
                if editing { editControls(item) }
                else if item.kind.isNumeric { numberControl(item) }
                else { yesNo(q) }
            }
            .padding(.leading, 16).padding(.trailing, 15).padding(.vertical, 15).frame(minHeight: 62)
            if let follow {
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.horizontal, 16)
                followUps(q, follow)
            }
        }
        .background(Color.white.opacity(0.095), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    /// How much, and when it last happened: a count with minus and plus, and a time on a slider that has nothing chosen until it moves.
    private func followUps(_ q: String, _ spec: NunaJournalExtras.Spec) -> some View {
        let _ = extrasTick
        let count = NunaJournalExtras.value(day: dayKey, q, "count")
        let time = Binding<Double?>(get: { NunaJournalExtras.value(day: dayKey, q, "time") },
                                     set: { NunaJournalExtras.set($0, day: dayKey, q, "time"); extrasTick += 1 })
        return VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Text(verbatim: spec.count).font(.nuna(size: 15.5, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    stepButton("minus") { NunaJournalExtras.set(max(1, (count ?? 2) - 1), day: dayKey, q, "count"); extrasTick += 1 }
                    Text(verbatim: count.map { String(Int($0)) } ?? "–").font(.nunaBoldFigure(size: 16)).foregroundStyle(count == nil ? NunaPalette.textPrimary : Color.black)
                        .frame(width: 31, height: 31).background(count == nil ? Color.white.opacity(0.10) : Color(red: 0.41, green: 0.68, blue: 0.90), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    stepButton("plus") { NunaJournalExtras.set((count ?? 0) + 1, day: dayKey, q, "count"); extrasTick += 1 }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(verbatim: spec.time).font(.nuna(size: 15.5, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    Spacer(minLength: 8)
                    Text(verbatim: time.wrappedValue.map(NunaJournalExtras.clock) ?? "--").font(.nunaBoldFigure(size: 15))
                        .foregroundStyle(time.wrappedValue == nil ? NunaPalette.textPrimary : Color(red: 0.41, green: 0.68, blue: 0.90))
                }
                NunaJournalTimeSlider(value: time)
            }
        }
        .padding(.leading, 31).padding(.trailing, 15).padding(.top, 16).padding(.bottom, 18)
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 31, height: 31).background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(.plain)
    }

    /// A cross and a check, side by side, 31 pt each: the chosen "no" is white with a black cross, the chosen "yes" is blue with a black check, and
    /// the one not chosen is a faint square. Tapping the chosen one again clears the answer.
    private func yesNo(_ q: String) -> some View {
        HStack(spacing: 8) {
            answerButton("xmark", on: answers[q] == false, fill: .white, label: "No") { set(q, false) }
            answerButton("checkmark", on: answers[q] == true, fill: Color(red: 0.41, green: 0.68, blue: 0.90), label: "Yes") { set(q, true) }
        }
    }

    private func answerButton(_ symbol: String, on: Bool, fill: Color, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 13, weight: symbol == "xmark" ? .black : .heavy)).foregroundStyle(on ? Color.black : NunaPalette.textPrimary)
                .frame(width: 31, height: 31)
                .background(on ? fill : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(4).contentShape(Rectangle()).padding(-4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func numberControl(_ item: JournalCatalogItem) -> some View {
        let q = item.canonical
        let cur = numbers[q]
        return HStack(spacing: 8) {
            step("minus") { save(q, max(0, (cur ?? 0) - 1)) }
            Text(verbatim: cur.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.1f", locale: AppLanguage.activeLocale, $0) } ?? "–")
                .font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(cur == nil ? NunaPalette.textPrimary : Color.black)
                .frame(minWidth: 31, minHeight: 31).padding(.horizontal, 4)
                .background(cur == nil ? Color.white.opacity(0.10) : Color(red: 0.41, green: 0.68, blue: 0.90), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            step("plus") { save(q, (cur ?? 0) + 1) }
            if let unit = item.kind.unitLabel, !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
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
                .frame(width: 31, height: 31).background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func editControls(_ item: JournalCatalogItem) -> some View {
        HStack(spacing: 8) {
            if item.hidden {
                Button { catalog.restore(item.canonical) } label: {
                    Text("Restore").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 34).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            } else {
                NunaMenu {
                    NunaMenuItem("Rename…", icon: "pencil") { renameDraft = item.displayName ?? item.canonical; renaming = item }
                    NunaMenuSub("Group", icon: "folder") {
                        ForEach(JournalGroup.displayOrder, id: \.self) { g in NunaMenuItem(verbatim: g.title, selected: g == item.group) { catalog.setGroup(item.canonical, to: g) } }
                    }
                    if item.kind.isNumeric { NunaMenuItem("Change to Yes/No", icon: "checkmark.circle") { catalog.setKind(item.canonical, to: .bool) } }
                    else { NunaMenuItem("Change to Number", icon: "number") { catalog.setKind(item.canonical, to: .numeric(unitLabel: nil)) } }
                } label: {
                    NunaBareIcon("gearshape", target: 36)
                }
                Button { catalog.remove(item.canonical) } label: {
                    Image(systemName: "minus").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                        .frame(width: 36, height: 36)
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
                        NunaMenu {
                            ForEach(JournalGroup.displayOrder, id: \.self) { g in NunaMenuItem(verbatim: g.title, selected: g == customGroup) { customGroup = g } }
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
        if let first = Self.offsets.first.flatMap({ cal.date(byAdding: .day, value: -$0, to: Date()) }),
           let last = Self.offsets.last.flatMap({ cal.date(byAdding: .day, value: -$0, to: Date()) }) {
            loggedDays = await repo.nativeJournalDays(from: Repository.localDayKey(first), to: Repository.localDayKey(last))
        }
    }

    // MARK: Formatting

    private static func title(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: d)
    }
    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("dMMMM")
        return f.string(from: d)
    }
    private static func navLabel(_ off: Int) -> String {
        if off == 0 { return String(localized: "Today") }
        if off == 1 { return String(localized: "Yesterday") }
        let d = Calendar.current.date(byAdding: .day, value: -off, to: Date()) ?? Date()
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEdMMM")
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
