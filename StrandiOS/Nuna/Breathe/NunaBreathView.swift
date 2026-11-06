#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import Charts

/// Breathing, first screen: say what the breath is for, take Anya's pick or a ready template, and go. After the session comes the
/// report, which is kept in the history. The settings button at the top right holds the module's options.
struct NunaBreathView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @AppStorage(NunaBreathPrefs.anyaKey) private var anyaOn = true
    @AppStorage(NunaBreathPrefs.lengthKey) private var lengthPref = 0
    @AppStorage("noop.coachEnabled") private var coachEnabled = true

    @State private var goal: BreathGoal = .calm
    @State private var pickedGoal = false
    @State private var suggestion: NunaBreathSuggestion?
    @State private var request: NunaBreathRequest?
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showAnya = false
    @State private var showAdvanced = false
    @State private var showMake = false
    @State private var tab = 1
    @State private var mine = NunaCustomBreath.all()
    @State private var rrBuffer: [Int] = []
    @State private var history = NunaBreathLog.all()

    private var liveBpm: Int? { live.worn ? model.bpm : nil }

    var body: some View {
        NunaDetailScreen("Breathing", trailing: AnyView(settingsButton), centersTitle: true) {
            NunaPageTabs([(value: 0, title: "Progress"), (value: 1, title: "Breathe"), (value: 2, title: "Explore")], selection: $tab)
            tabContent
        }
        .onAppear { model.startRealtimeHR(); mirrorLive(); mine = NunaCustomBreath.all() }
        .onDisappear { model.stopRealtimeHR() }
        .onRRPackets(live) { ingest($0) }
        .onChange(of: model.bpm) { _, _ in mirrorLive() }
        .onChange(of: live.worn) { _, _ in mirrorLive() }
        .task(id: refreshKey) { await refreshSuggestion() }
        .fullScreenCover(item: $request, onDismiss: { history = NunaBreathLog.all(); mine = NunaCustomBreath.all() }) { req in
            NunaBreathFlow(first: req) { request = nil }
        }
        .sheet(isPresented: $showSettings, onDismiss: { history = NunaBreathLog.all() }) {
            NunaBreathSettingsView { showSettings = false; showAdvanced = true } onClose: { showSettings = false }.nunaSheetChrome(detents: [.large])
        }
        .sheet(isPresented: $showHistory) { NunaBreathHistoryView { showHistory = false }.nunaSheetChrome(detents: [.large]) }
        .sheet(isPresented: $showAnya) { NunaAnyaSheet(context: "Breathing") }
        .sheet(isPresented: $showMake, onDismiss: { mine = NunaCustomBreath.all() }) {
            ScrollView {
                NunaBreathAskAnya(inputs: suggestion?.inputs)
                    .padding(.horizontal, NunaSpacing.screenH).padding(.top, 28).padding(.bottom, 32)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            .background(NunaBackdrop())
            .preferredColorScheme(NunaTheme.colorScheme)
            .nunaSheetChrome(detents: [.large])
        }
        .sheet(isPresented: $showAdvanced) {
            NavigationStack { BreathingView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showAdvanced = false } } } }
                .preferredColorScheme(NunaTheme.colorScheme)
        }
    }

    /// The three tabs, as on the Strength Trainer: Progress (what you have done), Breathe (start one, make your own), Explore (every goal and ready exercise).
    @ViewBuilder private var tabContent: some View {
        switch tab {
        case 0: progressTab
        case 1: breatheTab
        default: exploreTab
        }
    }

    // MARK: Breathe

    private var breatheTab: some View {
        VStack(spacing: NunaSpacing.section) {
            topActions
            NunaDivider()
            myExercises
            if anyaOn { anyaCard }
        }
    }

    private var quickStartTemplate: BreathTemplate? {
        anyaOn ? suggestion?.advice.template : BreathTemplates.templates(for: goal).first
    }

    /// One white button, as Quick start on the Strength Trainer: Anya's pick (or the first ready exercise when she is off) and go.
    private var topActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start a Session").font(.nuna(size: 20, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Text(anyaOn ? "Take a guided breath. Anya picks one that fits how you are right now." : "Take a guided breath at your own pace.")
                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            Button { if let t = quickStartTemplate { start(t) } } label: {
                Text("Quick start").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                    .background(NunaPalette.textPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain).disabled(quickStartTemplate == nil).opacity(quickStartTemplate == nil ? 0.4 : 1)
            liveStrip
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Heart rate and HRV right now, small, under the button; without the strap it says so.
    private var liveStrip: some View {
        HStack(spacing: 18) {
            Circle().fill(live.worn && liveBpm != nil ? NunaPalette.charge : NunaPalette.textMuted).frame(width: 8, height: 8)
            if let bpm = liveBpm {
                metric("Heart rate", "\(bpm)", "bpm")
                metric("HRV", NunaBreathLive.shared.rmssd.map { String(format: "%.0f", $0) } ?? "–", "ms")
                Spacer(minLength: 0)
            } else {
                Text("Wear the strap for live guidance. You can still breathe without it.").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 4)
    }

    private func metric(_ label: LocalizedStringKey, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                Text(verbatim: unit).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
        }
    }

    /// The exercises that are yours: make one with Anya, find your own pace by hand, and the ones you kept.
    private var myExercises: some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "My Exercises") { EmptyView() }
            NunaBreathGenerateCard(title: "Generate with Anya", text: "Say what you need and Anya will make a breathing exercise for you.") { showMake = true }
            Button { showAdvanced = true } label: {
                Text("Resonance and Calm me").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 54)
                    .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }.buttonStyle(.plain)
            NunaDivider().padding(.vertical, 6)
            if mine.isEmpty {
                Text("No exercises yet. Ask Anya to make one and it is kept here.")
                    .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            } else {
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                    VStack(spacing: 0) {
                        ForEach(Array(mine.enumerated()), id: \.element.id) { i, e in
                            if i > 0 { NunaDivider() }
                            savedRow(e)
                        }
                    }
                }
            }
        }
    }

    private func savedRow(_ e: NunaSavedBreath) -> some View {
        let g = BreathGoal(rawValue: e.goal) ?? .calm
        return HStack(spacing: 12) {
            Button { request = NunaCustomBreath.request(for: e) } label: {
                HStack(spacing: 12) {
                    NunaActivityGlyph(name: g.activity, size: 26).foregroundStyle(g.tint).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: e.title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).textCase(nil)
                        Text(verbatim: "\(e.minutes) min · " + NunaCustomBreath.summary(e.stages)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(2).textCase(nil)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "play.circle.fill").font(.nuna(size: 28, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { NunaCustomBreath.delete(id: e.id); mine = NunaCustomBreath.all() } label: {
                Image(systemName: "trash").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).frame(width: 36, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(Text("Delete"))
        }.padding(.vertical, 10)
    }

    private var anyaCard: some View {
        NunaAnyaNote {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anya suggests").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Text(verbatim: suggestion?.headline ?? String(localized: "Reading your numbers…")).font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                if let d = suggestion?.detail {
                    Text(verbatim: d).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                if let read = suggestion?.read, !read.isEmpty {
                    HStack(spacing: 6) {
                        Text("Read:").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        ForEach(read, id: \.self) { Text(LocalizedStringKey($0)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                    }
                }
                HStack(spacing: 10) {
                    Button { if let s = suggestion { start(s.advice.template) } } label: {
                        HStack(spacing: 6) { Image(systemName: "play.fill").font(.nuna(size: 13, weight: .bold)); Text("Start this") }
                            .font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 18).frame(height: 44)
                            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain).disabled(suggestion == nil).opacity(suggestion == nil ? 0.4 : 1)
                    if coachEnabled {
                        Button { showAnya = true } label: {
                            Text("Ask Anya").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 18).frame(height: 44)
                                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Explore

    private var exploreTab: some View {
        VStack(spacing: NunaSpacing.section) {
            goalPicker
            templates
        }
    }

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            NunaTitleRow(title: "What is it for?") { EmptyView() }
            ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BreathGoal.allCases, id: \.self) { g in
                        let on = g == goal
                        Button { goal = g; pickedGoal = true } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                NunaActivityGlyph(name: g.activity, size: 26).foregroundStyle(on ? NunaPalette.onAccent : g.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.title).font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(g.blurb).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(on ? NunaPalette.onAccent.opacity(0.7) : NunaPalette.textSecondary).lineLimit(2).multilineTextAlignment(.leading).textCase(nil)
                                }
                            }
                            .padding(12).frame(width: 150, height: 120, alignment: .topLeading)
                            .background(on ? NunaPalette.accent : NunaPalette.card, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous).strokeBorder(on ? Color.clear : NunaPalette.hairlineSoft, lineWidth: 1))
                        }.buttonStyle(.plain).id(g)
                    }
                }
            }
            .padding(.horizontal, -NunaSpacing.screenH).contentMargins(.horizontal, NunaSpacing.screenH, for: .scrollContent)
            .onChange(of: goal) { _, g in withAnimation { proxy.scrollTo(g, anchor: .center) } }
            }
        }
    }

    private var templates: some View {
        VStack(alignment: .leading, spacing: 10) {
            NunaTitleRow(title: "Ready to start") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                VStack(spacing: 0) {
                    ForEach(Array(BreathTemplates.templates(for: goal).enumerated()), id: \.element.id) { i, t in
                        if i > 0 { NunaDivider() }
                        Button { start(t) } label: { templateRow(t) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func templateRow(_ t: BreathTemplate) -> some View {
        let mins = lengthPref > 0 ? lengthPref : t.minutes
        let picked = suggestion?.advice.template.id == t.id
        return HStack(spacing: 12) {
            NunaActivityGlyph(name: t.goal.activity, size: 28).foregroundStyle(t.goal.tint).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: t.title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    if picked && anyaOn { NunaChip("Anya's pick", color: NunaPalette.charge) }
                }
                Text(verbatim: "\(mins) min · \(t.blurb)").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(2)
                if let c = BreathProtocolCatalog.protocolById(t.protocolId)?.caution {
                    Text(verbatim: String(localized: String.LocalizationValue(c))).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.warning).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
            Spacer(minLength: 6)
            Image(systemName: "play.circle.fill").font(.nuna(size: 28, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
        }
        .padding(.vertical, 10).contentShape(Rectangle())
    }

    // MARK: Progress

    private static let chartDays = 14

    /// Minutes breathed on each of the last days, today last.
    private var dayMinutes: [(date: Date, minutes: Double)] {
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        return (0..<Self.chartDays).reversed().map { back in
            let day = cal.date(byAdding: .day, value: -back, to: today) ?? today
            let secs = history.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.seconds }
            return (day, Double(secs) / 60)
        }
    }

    private var progressTab: some View {
        let days = dayMinutes
        let since = Calendar.current.date(byAdding: .day, value: -(Self.chartDays - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let recent = history.filter { $0.date >= since }
        let total = Int((days.reduce(0) { $0 + $1.minutes }).rounded())
        let week = history.filter { $0.startTs >= Int(Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970) }
        let moves = week.compactMap(\.rmssdChangePct)
        return VStack(spacing: NunaSpacing.section) {
            if history.isEmpty {
                NunaCard(small: true) { Text("Finish a session and its report is kept here.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Last 14 days").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "\(total)").font(.nuna(size: 44, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                        Text(verbatim: "min").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        Spacer(minLength: 0)
                        Text(verbatim: String(localized: "\(recent.count) sessions")).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    minutesChart(days)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    statTile("Sessions", "\(week.count)", "7 days")
                    statTile("Time", "\(week.reduce(0) { $0 + $1.seconds } / 60)", "min")
                    statTile("HRV move", moves.isEmpty ? "–" : String(format: "%+.0f", moves.reduce(0, +) / Double(moves.count)), "%")
                }
            }
            sessions
        }
    }

    private func minutesChart(_ days: [(date: Date, minutes: Double)]) -> some View {
        Chart(days, id: \.date) { d in
            BarMark(x: .value("Day", d.date, unit: .day), y: .value("Minutes", d.minutes), width: .ratio(0.62))
                .foregroundStyle(NunaPalette.rest).cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day(), centered: true).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(NunaPalette.hairlineSoft)
                AxisValueLabel().font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
        .frame(height: 170)
    }

    private func statTile(_ label: LocalizedStringKey, _ value: String, _ unit: String) -> some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                    Text(verbatim: unit).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            NunaTitleRow(title: "Your sessions") {
                if !history.isEmpty { Button { showHistory = true } label: { Text("All").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }.buttonStyle(.plain) }
            }
            if !history.isEmpty {
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                    VStack(spacing: 0) {
                        ForEach(Array(history.prefix(5).enumerated()), id: \.element.id) { i, r in
                            if i > 0 { NunaDivider() }
                            Button { showHistory = true } label: { sessionRow(r) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func sessionRow(_ r: NunaBreathRecord) -> some View {
        let g = BreathGoal(rawValue: r.goal) ?? .calm
        let name = r.templateId.flatMap { BreathTemplates.template(id: $0)?.title } ?? r.protocolId
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return HStack(spacing: 12) {
            NunaIconTile(g.icon, tint: g.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: "\(f.string(from: r.date)) · \(r.durationText)").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 6)
            if let p = r.rmssdChangePct { NunaChip(verbatim: String(format: "%+.0f%% HRV", locale: AppLanguage.activeLocale, p), color: p >= 5 ? NunaPalette.charge : nil) }
        }
        .padding(.vertical, 10).contentShape(Rectangle())
    }

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            NunaBareIcon("slider.horizontal.3")
        }.buttonStyle(.plain).accessibilityLabel(Text("Breathing settings"))
    }

    // MARK: Logic

    /// Re-read Anya's pick when something that matters moved: the hour, the heart rate by tens, or the strap going on or off.
    private var refreshKey: String {
        "\(Calendar.current.component(.hour, from: Date()))-\((liveBpm ?? 0) / 10)-\(live.worn)-\(history.count)"
    }

    private func refreshSuggestion() async {
        guard anyaOn else { return }
        let s = await NunaBreathAdviceMaker.make(repo: repo, profile: profile)
        suggestion = s
        if !pickedGoal { goal = s.advice.goal }
    }

    private func mirrorLive() {
        let l = NunaBreathLive.shared
        l.bpm = model.bpm; l.worn = live.worn && model.bpm != nil
    }

    private func ingest(_ rr: [Int]) {
        rrBuffer.append(contentsOf: rr)
        if rrBuffer.count > 30 { rrBuffer.removeFirst(rrBuffer.count - 30) }
        guard rrBuffer.count >= 8 else { return }
        var sumSq = 0.0
        for i in 1..<rrBuffer.count { let d = Double(rrBuffer[i] - rrBuffer[i - 1]); sumSq += d * d }
        NunaBreathLive.shared.rmssd = (sumSq / Double(rrBuffer.count - 1)).squareRoot()
    }

    private func start(_ t: BreathTemplate) {
        request = NunaBreathRequest(goal: t.goal, templateId: t.id, protocolId: t.protocolId, seconds: (lengthPref > 0 ? lengthPref : t.minutes) * 60)
    }
}

/// The session and, when it ends, its report; "Breathe again" starts the same request afresh.
struct NunaBreathFlow: View {
    let first: NunaBreathRequest
    let onClose: () -> Void
    @State private var request: NunaBreathRequest
    @State private var record: NunaBreathRecord?

    init(first: NunaBreathRequest, onClose: @escaping () -> Void) {
        self.first = first; self.onClose = onClose
        _request = State(initialValue: first)
    }

    var body: some View {
        if let record {
            NunaBreathReportView(record: record, onDone: onClose) {
                self.record = nil
                var again = request; again = NunaBreathRequest(goal: again.goal, templateId: again.templateId, protocolId: again.protocolId, seconds: again.seconds)
                request = again
            }
        } else {
            NunaBreathSessionView(request: request) { r in
                if let r { record = r } else { onClose() }
            }
            .id(request.id)
        }
    }
}
/// The card that makes an exercise with Anya, the same as "Generate with Anya" on the Strength Trainer: a violet-to-teal outline, what it does, and the way in.
struct NunaBreathGenerateCard: View {
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.nuna(size: 16.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Text(text).font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true).textCase(nil)
                HStack(spacing: 8) {
                    Text("Get started").font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    Image(systemName: "arrow.right").font(.nuna(size: 15, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.49, green: 0.46, blue: 0.94)).padding(.top, 2)
            }
            .padding(.horizontal, 18).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.17, green: 0.15, blue: 0.33).opacity(0.9), Color(red: 0.11, green: 0.2, blue: 0.26).opacity(0.9)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color(red: 0.47, green: 0.4, blue: 0.9), Color(red: 0.25, green: 0.6, blue: 0.72)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}
#endif
