#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import Charts

/// Breathing, first screen: say what the breath is for, take Anya's pick or a ready template, and go. After the session comes the
/// report, which is kept in the history. The settings button at the top right holds the module's options.
/// The older Breathing screen as a sheet, opened on a tab ("resonance", "calm") or on its default one.
struct NunaAdvancedRoute: Identifiable {
    let id = UUID()
    let mode: String?
}

struct NunaBreathView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @AppStorage(NunaBreathPrefs.anyaKey) private var anyaOn = true
    @AppStorage(NunaBreathPrefs.lengthKey) private var lengthPref = 0

    @State private var goal: BreathGoal = .calm
    @State private var pickedGoal = false
    @State private var suggestion: NunaBreathSuggestion?
    @State private var request: NunaBreathRequest?
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var opened: NunaBreathRecord?
    @State private var route: NunaBreathRoute?
    @State private var advanced: NunaAdvancedRoute?
    @State private var showMake = false
    @State private var tab = 1
    @State private var mine = NunaCustomBreath.all()
    @State private var rrBuffer: [Int] = []
    @State private var history = NunaBreathLog.all()
    @State private var chartRange = 30
    @State private var chartPage = 0
    @State private var chartPicked: Date?
    @State private var chartTouchBeganOnPicked: Bool?

    private var liveBpm: Int? { live.worn ? model.bpm : nil }

    var body: some View {
        NunaDetailScreen("Breathing", trailing: AnyView(settingsButton), centersTitle: true) {
            NunaPageTabs([(value: 0, title: "Progress"), (value: 1, title: "Breathe")], selection: $tab)
            tabContent
        }
        .onAppear { model.startRealtimeHR(); mirrorLive(); mine = NunaCustomBreath.all() }
#if DEBUG
        // `--open-breath-detail tool:resonance | tool:calmMe | goal:calm | template:<id>` opens that page, to look at it.
        .task {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "--open-breath-detail"), i + 1 < args.count else { return }
            let parts = args[i + 1].split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            switch parts[0] {
            case "tool": if let t = NunaBreathTool(rawValue: parts[1]) { route = .tool(t) }
            case "goal": if let g = BreathGoal(rawValue: parts[1]) { route = .goal(g) }
            case "template": if let t = NunaBreathLibrary.template(id: parts[1]) { route = .template(t) }
            default: break
            }
        }
#endif
        .onDisappear { model.stopRealtimeHR() }
        .onRRPackets(live) { ingest($0) }
        .onChange(of: model.bpm) { _, _ in mirrorLive() }
        .onChange(of: live.worn) { _, _ in mirrorLive() }
        .task(id: refreshKey) { await refreshSuggestion() }
        .fullScreenCover(item: $request, onDismiss: { history = NunaBreathLog.all(); mine = NunaCustomBreath.all() }) { req in
            NunaBreathFlow(first: req) { request = nil }
        }
        .sheet(isPresented: $showSettings, onDismiss: { history = NunaBreathLog.all() }) {
            NunaBreathSettingsView { showSettings = false; advanced = NunaAdvancedRoute(mode: nil) } onClose: { showSettings = false }.nunaSheetChrome(detents: [.large])
        }
        .sheet(item: $route) { r in detailSheet(r) }
        .sheet(item: $opened) { r in
            NunaBreathReportView(record: r, readOnly: true, onDone: { opened = nil }).nunaSheetChrome(detents: [.large])
        }
        .sheet(isPresented: $showHistory) { NunaBreathHistoryView { showHistory = false }.nunaSheetChrome(detents: [.large]) }
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
        .sheet(item: $advanced) { route in
            NavigationStack { BreathingView(initialMode: route.mode, onSessionEnd: { start, secs, kind in NunaBreathRecovery.logExternal(repo: repo, startTs: start, seconds: secs, kind: kind); history = NunaBreathLog.all() }).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { advanced = nil } } } }
                .preferredColorScheme(NunaTheme.colorScheme)
        }
    }

    /// Two tabs: Progress (what you have done) and Breathe (start one, pick one by goal, make your own).
    @ViewBuilder private var tabContent: some View {
        switch tab {
        case 0: progressTab
        default: breatheTab
        }
    }

    // MARK: Breathe

    private var breatheTab: some View {
        VStack(spacing: NunaSpacing.section) {
            topActions
            NunaDivider()
            explore
            NunaDivider()
            myExercises
        }
    }

    private var quickStartTemplate: BreathTemplate? {
        anyaOn ? suggestion?.advice.template : NunaBreathLibrary.templates(for: goal).first
    }

    /// One white button, as Quick start on the Strength Trainer: Anya's pick (or the first ready exercise when she is off) and go.
    private var topActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start a Session").font(.nuna(size: 20, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            if anyaOn {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: suggestion?.headline ?? String(localized: "Reading your numbers…")).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    if let d = suggestion?.detail {
                        Text(verbatim: d).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }.fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Take a guided breath at your own pace.")
                    .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
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

    /// Heart rate and HRV right now, small, under the button; without the strap there is nothing to show, so it takes no room.
    @ViewBuilder private var liveStrip: some View {
        if let bpm = liveBpm, live.worn {
            HStack(spacing: 18) {
                Circle().fill(NunaPalette.charge).frame(width: 8, height: 8)
                metric("Heart rate", "\(bpm)", "bpm")
                metric("HRV", NunaBreathLive.shared.rmssd.map { String(format: "%.0f", $0) } ?? "–", "ms")
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
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

    // MARK: Explore

    /// Every goal and its ready exercises, and the two hands-on tools (Resonance and Calm me) as the last row.
    private var explore: some View {
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
                        Button { goal = g; pickedGoal = true; route = .goal(g) } label: {
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

    /// Each ready exercise is its own card; a touch opens what it is, what it does for you and how long it takes, with Start at the bottom.
    private var templates: some View {
        VStack(alignment: .leading, spacing: 10) {
            NunaTitleRow(title: "Ready to start") { EmptyView() }
            ForEach(NunaBreathLibrary.templates(for: goal)) { t in
                let picked = suggestion?.advice.template.id == t.id && anyaOn
                Button { route = .template(t) } label: {
                    NunaBreathPickRow(glyph: t.goal.activity, tint: t.goal.tint, title: t.title, line: t.blurb,
                                      figure: "\(lengthPref > 0 ? lengthPref : t.minutes)", chip: picked ? "Anya's pick" : nil)
                }.buttonStyle(.plain)
            }
            ForEach([NunaBreathTool.resonance, .calmMe]) { tool in
                Button { route = .tool(tool) } label: {
                    NunaBreathPickRow(glyph: tool.glyph, tint: tool.tint, title: tool.title, line: tool.subtitle)
                }.buttonStyle(.plain)
            }
        }
    }

    /// The page a card opens. Start closes it first, then the session takes the screen.
    @ViewBuilder private func detailSheet(_ r: NunaBreathRoute) -> some View {
        switch r {
        case .goal(let g):
            NunaBreathGoalDetail(goal: g, recommended: recommended(for: g), lengthPref: lengthPref,
                                 onStart: { startFromDetail($0) }, onOpen: { route = .template($0) }, onClose: { route = nil })
                .nunaSheetChrome(detents: [.large])
        case .tool(let tool):
            NunaBreathToolDetail(tool: tool, onStart: { openTool(tool) }, onClose: { route = nil })
                .nunaSheetChrome(detents: [.large])
        case .template(let t):
            NunaBreathTemplateDetail(template: t, minutes: lengthPref > 0 ? lengthPref : t.minutes,
                                     onStart: { startFromDetail(t) }, onClose: { route = nil })
                .nunaSheetChrome(detents: [.large])
        }
    }

    /// Anya's pick when it belongs to the goal, otherwise the goal's first exercise.
    private func recommended(for g: BreathGoal) -> BreathTemplate {
        if anyaOn, let t = suggestion?.advice.template, t.goal == g { return t }
        return NunaBreathLibrary.templates(for: g).first ?? BreathTemplates.all[0]
    }

    /// Resonance and Calm me run on the older screen, opened on the tab the page was for.
    private func openTool(_ tool: NunaBreathTool) {
        route = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { advanced = NunaAdvancedRoute(mode: tool.mode) }
    }

    private func startFromDetail(_ t: BreathTemplate) {
        route = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { start(t) }
    }

    // MARK: Progress

    /// Minutes breathed on each calendar day that has a session, split by kind (guided, Resonance, Calm me).
    private var minutesByDay: [Date: [NunaBreathKind: Double]] {
        let cal = Calendar.current
        var out: [Date: [NunaBreathKind: Double]] = [:]
        for r in history { out[cal.startOfDay(for: r.date), default: [:]][r.kind, default: 0] += Double(r.seconds) / 60 }
        return out
    }

    private var chartWindow: NunaTrendWindow { NunaTrendWindow(range: chartRange, page: chartPage, endingDaysAgo: 0) }

    private var progressTab: some View {
        VStack(spacing: NunaSpacing.section) {
            if history.isEmpty {
                NunaCard(small: true) { Text("Finish a session and its report is kept here.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            } else {
                minutesSection
            }
            sessions
        }
    }

    /// Minutes breathed per day, laid out like the Strength Trainer's volume chart: an average on the left, the M / 6M switch and
    /// the date stepper on the right, bars you can touch to read one day.
    private var minutesSection: some View {
        let w = chartWindow, cal = Calendar.current
        let byDay = minutesByDay
        let days: [(date: Date, minutes: Double)] = (0..<chartRange).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: w.start), let m = byDay[cal.startOfDay(for: d)]?.values.reduce(0, +), m > 0 else { return nil }
            return (w.noon(d), m)
        }
        let average: Double? = days.isEmpty ? nil : days.map(\.minutes).reduce(0, +) / Double(days.count)
        // A fixed scale, 0 to 15 minutes in steps of 5; a day with more than that fills the bar and its real figure shows when touched.
        let top = 15.0
        let ticks = [0.0, 5, 10, 15]
        // One stacked bar per day, a slice for each kind, cut off at the top of the scale.
        var slices: [(date: Date, kind: NunaBreathKind, minutes: Double)] = []
        for i in 0..<chartRange {
            guard let d = cal.date(byAdding: .day, value: i, to: w.start), let parts = byDay[cal.startOfDay(for: d)] else { continue }
            var room = top
            for k in NunaBreathKind.allCases {
                guard let m = parts[k], m > 0, room > 0 else { continue }
                slices.append((w.noon(d), k, min(m, room))); room -= min(m, room)
            }
        }
        let kindsShown = NunaBreathKind.allCases.filter { k in slices.contains { $0.kind == k } }
        let oldest = byDay.keys.min()
        let pickedMin: Double? = chartPicked.flatMap { p in days.first { cal.isDate($0.date, inSameDayAs: p) }?.minutes }
        let shown = pickedMin ?? average
        let pickedTitle: String = {
            guard let p = chartPicked else { return "" }
            let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE, MMM d")
            return f.string(from: p)
        }()
        func nearest(_ x: CGFloat, _ proxy: ChartProxy, _ frame: CGRect) -> Date? {
            guard let touched: Date = proxy.value(atX: x - frame.minX) else { return nil }
            return days.min { abs($0.date.timeIntervalSince(touched)) < abs($1.date.timeIntervalSince(touched)) }?.date
        }
        func lit(_ d: Date) -> Bool { chartPicked == nil || cal.isDate(d, inSameDayAs: chartPicked!) }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Time breathed").font(.nuna(size: 20, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: pickedMin == nil ? String(localized: "Avg. daily minutes") : pickedTitle).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(pickedMin == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: shown.map { String(format: "%.0f", $0.rounded()) } ?? "–").font(.nuna(size: 32, weight: .semibold, design: NunaType.design))
                            .foregroundStyle(pickedMin == nil ? NunaPalette.textPrimary : NunaPalette.rest)
                        if shown != nil { Text(verbatim: String(localized: "min")).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(pickedMin == nil ? NunaPalette.textPrimary : NunaPalette.rest).textCase(nil) }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 14) {
                    NunaRangeSwitch(choices: [(30, "M"), (180, "6M")], range: $chartRange) { chartPage = 0; chartPicked = nil }
                    NunaDateStepper(label: w.label, canGoBack: oldest.map { w.start > cal.startOfDay(for: $0) } ?? false, canGoForward: chartPage > 0,
                                    back: { chartPage += 1; chartPicked = nil }, forward: { chartPage = max(0, chartPage - 1); chartPicked = nil })
                }
            }
            Chart {
                ForEach(Array(slices.enumerated()), id: \.offset) { _, d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("min", d.minutes), width: .fixed(chartRange == 30 ? 8 : 3))
                        .foregroundStyle(by: .value("Kind", d.kind.name)).cornerRadius(1.5).opacity(lit(d.date) ? 1 : 0.3)
                }
                if let p = chartPicked, days.contains(where: { cal.isDate($0.date, inSameDayAs: p) }) {
                    RuleMark(x: .value("Picked", w.noon(p))).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            .chartForegroundStyleScale(domain: NunaBreathKind.allCases.map(\.name), range: NunaBreathKind.allCases.map(\.color))
            .chartLegend(.hidden)
            .chartYScale(domain: 0...top)
            .chartXScale(domain: w.domain)
            .chartYAxis {
                AxisMarks(position: .leading, values: ticks) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.white.opacity(0.09))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: String(format: "%.0f", d)).font(.nuna(size: 11.5, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textMuted) } }
                }
            }
            .chartXAxis(.hidden)
            .chartPlotStyle { $0.padding(.bottom, 46) }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let frame = proxy.plotFrame.map({ geo[$0] }) {
                        ZStack {
                            ForEach(w.axisDates, id: \.self) { d in
                                if let x = proxy.position(forX: d) { w.axisLabel(d).position(x: frame.minX + x, y: frame.maxY + 25).allowsHitTesting(false) }
                            }
                            Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { g in
                                        let hit = nearest(g.location.x, proxy, frame)
                                        if chartTouchBeganOnPicked == nil { chartTouchBeganOnPicked = chartPicked != nil && hit.map { cal.isDate($0, inSameDayAs: chartPicked!) } == true }
                                        if let hit { chartPicked = hit }
                                    }
                                    .onEnded { g in
                                        if chartTouchBeganOnPicked == true, abs(g.translation.width) < 6 { chartPicked = nil }
                                        chartTouchBeganOnPicked = nil
                                    })
                        }
                    }
                }
            }
            .frame(height: 260)
            .accessibilityLabel(Text("Time breathed"))
            if kindsShown.count > 1 {
                HStack(spacing: 16) {
                    ForEach(kindsShown, id: \.self) { k in
                        HStack(spacing: 6) {
                            Circle().fill(k.color).frame(width: 8, height: 8)
                            Text(verbatim: k.name).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            NunaTitleRow(title: "Your sessions") {
                if !history.isEmpty { Button { showHistory = true } label: { Text("All").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }.buttonStyle(.plain) }
            }
            ForEach(history.prefix(5)) { r in
                Button { opened = r } label: { sessionRow(r) }.buttonStyle(.plain)
            }
        }
    }

    /// One session as its own card, like a Personal Record on the Strength Trainer: a tile for the goal, the name and when, the minutes
    /// at the right. A touch opens its report.
    private func sessionRow(_ r: NunaBreathRecord) -> some View {
        let g = BreathGoal(rawValue: r.goal) ?? .calm
        let name = r.displayTitle
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        let when = f.string(from: r.date)
        let hrv = r.rmssdChangePct.map { String(format: "%+.0f%% HRV", locale: AppLanguage.activeLocale, $0) }
        let long = r.seconds >= 60
        return NunaCard(small: true, padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 14)) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(g.tint.opacity(0.16)).frame(width: 72, height: 54)
                    .overlay(NunaActivityGlyph(name: g.activity, size: 28).foregroundStyle(g.tint))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: name).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading).textCase(nil)
                    Text(verbatim: when).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).textCase(nil)
                    if let hrv {
                        Text(verbatim: hrv).font(.nuna(size: 11.5, weight: .bold)).foregroundStyle((r.rmssdChangePct ?? 0) >= 5 ? NunaPalette.charge : NunaPalette.textSecondary).lineLimit(1).textCase(nil)
                    }
                }
                Spacer(minLength: 8)
                Text(verbatim: "\(long ? r.seconds / 60 : r.seconds)").font(.nuna(size: 26, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6).frame(width: 52, alignment: .trailing)
                Text(verbatim: long ? String(localized: "min") : String(localized: "s")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize()
                Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            }
        }
        .contentShape(Rectangle())
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
