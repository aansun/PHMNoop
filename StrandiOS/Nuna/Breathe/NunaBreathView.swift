#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

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
    @State private var rrBuffer: [Int] = []
    @State private var history = NunaBreathLog.all()

    private var liveBpm: Int? { live.worn ? model.bpm : nil }

    var body: some View {
        NunaDetailScreen("Breathing", trailing: AnyView(settingsButton)) {
            liveCard
            if anyaOn { anyaCard }
            goalPicker
            templates
            sessions
            advancedRow
        }
        .onAppear { model.startRealtimeHR(); mirrorLive() }
        .onDisappear { model.stopRealtimeHR() }
        .onRRPackets(live) { ingest($0) }
        .onChange(of: model.bpm) { _, _ in mirrorLive() }
        .onChange(of: live.worn) { _, _ in mirrorLive() }
        .task(id: refreshKey) { await refreshSuggestion() }
        .fullScreenCover(item: $request, onDismiss: { history = NunaBreathLog.all() }) { req in
            NunaBreathFlow(first: req) { request = nil }
        }
        .sheet(isPresented: $showSettings, onDismiss: { history = NunaBreathLog.all() }) {
            NunaBreathSettingsView { showSettings = false; showAdvanced = true } onClose: { showSettings = false }.nunaSheetChrome(detents: [.large])
        }
        .sheet(isPresented: $showHistory) { NunaBreathHistoryView { showHistory = false }.nunaSheetChrome(detents: [.large]) }
        .sheet(isPresented: $showAnya) { NunaAnyaSheet(context: "Breathing") }
        .sheet(isPresented: $showAdvanced) {
            NavigationStack { BreathingView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showAdvanced = false } } } }
                .preferredColorScheme(NunaTheme.colorScheme)
        }
    }

    // MARK: Parts

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "slider.horizontal.3").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 44, height: 44)
                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
        }.buttonStyle(.plain).accessibilityLabel(Text("Breathing settings"))
    }

    private var liveCard: some View {
        NunaCard(small: true) {
            HStack(spacing: 14) {
                Circle().fill(live.worn && liveBpm != nil ? NunaPalette.charge : NunaPalette.textMuted).frame(width: 8, height: 8)
                if let bpm = liveBpm {
                    metric("Heart rate", "\(bpm)", "bpm")
                    metric("HRV", NunaBreathLive.shared.rmssd.map { String(format: "%.0f", $0) } ?? "–", "ms")
                    Spacer(minLength: 0)
                    Text("Live").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                } else {
                    Text("Wear the strap for live guidance. You can still breathe without it.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    Spacer(minLength: 0)
                }
            }
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

    private var anyaCard: some View {
        NunaCard(highlight: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    AnyaIconTile()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Anya suggests").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: suggestion?.headline ?? String(localized: "Reading your numbers…")).font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                    Spacer(minLength: 0)
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
                                Image(systemName: g.icon).font(.nuna(size: 20, weight: .semibold)).foregroundStyle(on ? NunaPalette.onAccent : g.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.title).font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(g.blurb).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(on ? NunaPalette.onAccent.opacity(0.7) : NunaPalette.textSecondary).lineLimit(2).multilineTextAlignment(.leading)
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
            NunaIconTile(t.goal.icon, tint: t.goal.tint)
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

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            NunaTitleRow(title: "Your sessions") {
                if !history.isEmpty { Button { showHistory = true } label: { Text("All").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }.buttonStyle(.plain) }
            }
            if history.isEmpty {
                NunaCard(small: true) { Text("Finish a session and its report is kept here.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            } else {
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                    VStack(spacing: 0) {
                        ForEach(Array(history.prefix(3).enumerated()), id: \.element.id) { i, r in
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

    private var advancedRow: some View {
        Button { showAdvanced = true } label: {
            NunaCard(small: true) { NunaListRow("Resonance and Calm me", subtitle: "Find your own pace, or let the strap lead you down", systemImage: "waveform.path", showsChevron: true) }
        }.buttonStyle(.plain)
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
#endif
