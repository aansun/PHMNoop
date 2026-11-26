#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore

// MARK: - Consent (HealthRhythmConsent)

/// The consent screen shown the first time Rhythm is turned on, and again if the wording version changes.
/// The wording and version are the existing `RhythmConsent` record, so both experiences share one consent.
struct NunaRhythmConsentView: View {
    let onAccept: () -> Void
    let onCancel: () -> Void
    @State private var understood = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(Text("Close"))
                    Spacer()
                    NunaChip("Experimental")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "waveform.path.ecg").font(.nuna(size: 26, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 56, height: 56).background(NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                    Text("Before you turn on Rhythm").font(.nuna(size: NunaTypeSize.h1 - 4, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text("An experimental picture of your beat-to-beat timing. Please read these first.")
                        .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(RhythmConsent.points.enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .top, spacing: 14) {
                            Text(verbatim: "\(i + 1)").font(.nuna(size: 14, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: p.0).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: p.1).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                            }
                        }
                    }
                }
                Text("This is a wellness visualization, not a screening test. It does not tell you to see a clinician and it names no condition. This is not legal or medical advice.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                NunaCard {
                    HStack(alignment: .top, spacing: 14) {
                        Toggle("", isOn: $understood).labelsHidden().tint(NunaPalette.charge)
                        Text("I understand this is an experimental wellness feature, not a medical device or a diagnosis.")
                            .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(action: onAccept) {
                    Text("Turn on Rhythm").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(NunaPalette.accent.opacity(understood ? 1 : 0.35), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(!understood)
                Button(action: onCancel) {
                    Text("Not now").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaBackdrop())
    }
}

// MARK: - Poincaré plot

/// Successive-beat scatter: a tight line along the diagonal is a steady beat, a rounder cloud is more variable. The window the figures are about is drawn
/// bright, with its ellipse; the rest of the night sits behind it, dim, so the shape and the numbers are visibly about the same beats.
struct NunaPoincarePlot: View {
    let points: [RhythmScreener.PoincarePoint]
    var others: [RhythmScreener.PoincarePoint] = []
    let sd1: Double?
    let sd2: Double?
    private let lo = 300.0, hi = 1500.0

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height), inset: CGFloat = 12, plot = s - inset * 2
            func map(_ v: Double) -> CGFloat { inset + CGFloat((min(max(v, lo), hi) - lo) / (hi - lo)) * plot }
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerRadius: 10), with: .color(NunaPalette.field))
            var grid = Path()
            for i in 1...3 {
                let p = inset + plot * CGFloat(i) / 4
                grid.move(to: CGPoint(x: inset, y: p)); grid.addLine(to: CGPoint(x: s - inset, y: p))
                grid.move(to: CGPoint(x: p, y: inset)); grid.addLine(to: CGPoint(x: p, y: s - inset))
            }
            ctx.stroke(grid, with: .color(NunaPalette.ink.opacity(0.07)), lineWidth: 1)
            var diag = Path()
            diag.move(to: CGPoint(x: inset, y: s - inset)); diag.addLine(to: CGPoint(x: s - inset, y: inset))
            ctx.stroke(diag, with: .color(NunaPalette.ink.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
            // A whole night holds thousands of pairs; an evenly spaced sample keeps the cloud readable.
            func dots(_ list: [RhythmScreener.PoincarePoint], limit: Int, color: Color) {
                let step = max(1, list.count / limit)
                for (i, p) in list.enumerated() where i % step == 0 {
                    let x = map(p.x), y = s - map(p.y)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)), with: .color(color))
                }
            }
            dots(others, limit: 260, color: NunaPalette.ink.opacity(0.22))
            guard !points.isEmpty else { return }
            if let sd1, let sd2 {
                let mx = points.map(\.x).reduce(0, +) / Double(points.count), my = points.map(\.y).reduce(0, +) / Double(points.count)
                let k = plot / CGFloat(hi - lo) * 2.5
                let c = CGPoint(x: map(mx), y: s - map(my))
                var e = Path(ellipseIn: CGRect(x: -CGFloat(sd2) * k, y: -CGFloat(sd1) * k, width: CGFloat(sd2) * k * 2, height: CGFloat(sd1) * k * 2))
                e = e.applying(CGAffineTransform(rotationAngle: -.pi / 4)).applying(CGAffineTransform(translationX: c.x, y: c.y))
                var inside = ctx
                inside.clip(to: Path(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerRadius: 10))
                inside.fill(e, with: .color(NunaPalette.rest.opacity(0.12)))
                inside.stroke(e, with: .color(NunaPalette.restText), lineWidth: 1.5)
            }
            dots(points, limit: 320, color: NunaPalette.restLight.opacity(0.85))
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            Text("This beat (ms) →").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).padding(12)
        }
        .overlay(alignment: .topLeading) {
            Text("↑ Next beat").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).padding(12)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The screen

/// Laid out like the Body clock page: the title in the middle, the night's picture first, one panel of figures about the window drawn bright, the reading
/// windows, cards that explain, the settings, and Anya as the floating pill with a line worked out from these figures.
struct NunaRhythmView: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @AppStorage(RhythmConsent.acceptedVersionKey) private var acceptedVersion = ""
    @AppStorage(RhythmConsent.enabledKey) private var enabled = false

    struct Span: Identifiable {
        let id = UUID(); let start: Int; let end: Int; let beats: Int; let label: RhythmRegularity
    }

    @State private var night: RhythmScreener.NightRhythmSummary?
    @State private var windows: [RhythmScreener.WindowResult] = []
    /// When each of `windows` ran, in the same order.
    @State private var times: [(start: Int, end: Int)] = []
    @State private var spans: [Span] = []
    @State private var emptyReason: RhythmEmptyState = .gatheringData
    @State private var loaded = false
    @State private var showConsent = false
    @State private var exportURL: URL?

    private var consentGiven: Bool { enabled && RhythmConsent.isAccepted(acceptedVersion) }
    private var readable: [RhythmScreener.WindowResult] { windows.filter { $0.label != .unreadable } }
    /// The one window the figures and the bright dots are about: the first that varied most, else the first with extra beats, else the first read.
    private var featuredIndex: Int? {
        windows.firstIndex(where: { $0.label == .varied }) ?? windows.firstIndex(where: { $0.label == .occasionalEctopy })
            ?? windows.firstIndex(where: { $0.label != .unreadable })
    }
    private var featured: RhythmScreener.WindowResult? { featuredIndex.map { windows[$0] } }
    private var overall: RhythmRegularity { night?.overall ?? featured?.label ?? .unreadable }

    var body: some View {
        Group {
            if !consentGiven {
                NunaRhythmConsentView(onAccept: { acceptedVersion = RhythmConsent.currentVersion; enabled = true }, onCancel: { dismiss() })
            } else {
                NunaDetailScreen("Rhythm", centersTitle: true) { content }
                    // Her line comes from the figures on this page; nothing is sent anywhere unless she is asked.
                    .nunaAnyaFloating(context: "rhythm", line: anyaLine, detail: anyaDetail, analyses: false)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(consentGiven)|\(repo.refreshSeq)") {
            guard consentGiven else { return }
            await load()
        }
        .sheet(isPresented: $showConsent) {
            NunaRhythmConsentView(onAccept: { acceptedVersion = RhythmConsent.currentVersion; showConsent = false }, onCancel: { showConsent = false })
                .preferredColorScheme(NunaTheme.colorScheme)
        }
    }

    @ViewBuilder private var content: some View {
        if !loaded {
            ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
        } else if let featured, let index = featuredIndex {
            hero(featured, index: index)
            panel(featured, index: index)
            spansList
            if let exportURL {
                ShareLink(item: exportURL) {
                    NunaCard(small: true) { NunaListRow("Share", description: "A neutral CSV of the numbers, never a verdict", systemImage: "square.and.arrow.up", showsChevron: true) }
                }.buttonStyle(.plain)
            }
        } else {
            emptyCard
        }
        NunaRhythmReadingInfo(window: featured)
        NunaRhythmMeasureInfo()
        settings
    }

    // MARK: Anya

    private var anyaLine: String? {
        guard loaded else { return nil }
        guard !readable.isEmpty else {
            if emptyReason == .deviceBanksBeats || emptyReason == .deviceNoMotion { return nil }
            return String(localized: "No quiet window was clear enough to read last night.")
        }
        switch overall {
        case .steady: return String(localized: "Your beat timing looked even through last night's quiet windows.")
        case .occasionalEctopy: return String(localized: "Mostly even last night, with some variation here and there.")
        case .varied: return String(localized: "Your beat timing was more spread out in several windows last night.")
        case .unreadable: return String(localized: "No quiet window was clear enough to read last night.")
        }
    }

    private var anyaDetail: String? {
        guard let night, let f = featured, let i = featuredIndex else {
            return loaded ? String(localized: "Rhythm only reads while you are still and resting. A snug strap and a calm night give it more to work with.") : nil
        }
        let counts = String(localized: "Quiet windows read: \(night.readableWindows). Steady: \(night.steadyWindows). Some variation: \(night.occasionalWindows). More varied: \(night.variedWindows).")
        let window = String(localized: "In the window \(range(i)), beat-to-beat variation was \(pct(f.normRmssd)) and extra or skipped beats \(pct(f.ectopicFraction)).")
        let causes = String(localized: "Breathing, movement, an imperfect optical reading or an early beat can all change the timing. This is a picture, not a diagnosis.")
        return [counts, window, causes].joined(separator: " ")
    }

    // MARK: Hero

    private func hero(_ f: RhythmScreener.WindowResult, index: Int) -> some View {
        let others = windows.indices.filter { $0 != index && windows[$0].label != .unreadable }.flatMap { windows[$0].poincare }
        // No card behind it: like the dial on Body clock, the picture sits straight on the page.
        return VStack(spacing: 14) {
            HStack {
                nunaTrendsCap("Last night")
                Spacer()
                NunaChip("Experimental")
            }
            Text(label(overall)).font(.nuna(size: 28, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            NunaPoincarePlot(points: f.poincare, others: others, sd1: f.sd1, sd2: f.sd2)
                .frame(maxWidth: 300)
            HStack(spacing: 14) {
                key(NunaPalette.restLight, windowName(f.label))
                if !others.isEmpty { key(NunaPalette.ink.opacity(0.3), "Rest of the night") }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func key(_ color: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: Panel

    /// Plain figures, no good / poor bars: the page describes the timing and does not grade it.
    private func panel(_ f: RhythmScreener.WindowResult, index: Int) -> some View {
        NunaSignalPanel {
            VStack(spacing: 0) {
                HStack {
                    nunaTrendsCap(windowName(f.label))
                    Spacer(minLength: 8)
                    Text(verbatim: range(index)).font(.nuna(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.restText)
                }
                .padding(.top, 14)
                NunaFigureRow(title: "Variation", icon: "waveform.path.ecg", value: pct(f.normRmssd))
                NunaDivider()
                NunaFigureRow(title: "Extra or skipped", icon: "heart", value: pct(f.ectopicFraction))
                NunaDivider()
                NunaFigureRow(title: "Shape", icon: "oval", value: shape(f.sd1sd2))
                NunaDivider()
                NunaFigureRow(title: "Beats read", icon: "number", value: "\(f.nBeats)")
                NunaDivider()
                NunaFigureRow(title: "Read quality", icon: "checkmark.seal", value: quality(f.confidence))
            }
        }
    }

    // MARK: Reading windows

    @ViewBuilder private var spansList: some View {
        if !spans.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                NunaTitleRow(title: "Reading windows") { EmptyView() }
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        ForEach(Array(spans.enumerated()), id: \.element.id) { i, s in
                            if i > 0 { NunaDivider() }
                            HStack(spacing: 14) {
                                NunaIcon(name: "moon", size: 18, weight: .regular).foregroundStyle(NunaPalette.textSecondary).frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: clock(s.start) + " – " + clock(s.end)).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                    Text(verbatim: String(localized: "\((s.end - s.start) / 60) min · \(s.beats) beats read"))
                                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                }
                                Spacer(minLength: 6)
                                Text(label(s.label)).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                    .foregroundStyle(s.label == .steady ? NunaPalette.textSecondary : NunaPalette.restText)
                                    .multilineTextAlignment(.trailing)
                            }
                            .padding(.vertical, 14)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    // MARK: Settings

    private var settings: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                NunaListRow("Rhythm on", subtitle: "Computed on this phone") {
                    Toggle("", isOn: Binding(get: { enabled }, set: { on in enabled = on; if !on { dismiss() } })).labelsHidden().tint(NunaPalette.charge)
                }
                NunaDivider()
                Button { showConsent = true } label: {
                    NunaListRow("Read the consent again", subtitle: LocalizedStringKey(String(localized: "Accepted version \(acceptedVersion)")), systemImage: "doc.text", showsChevron: true)
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: Empty and unsupported

    private var emptyCard: some View {
        let unsupported = emptyReason == .deviceBanksBeats || emptyReason == .deviceNoMotion
        return NunaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    NunaIconTile(unsupported ? "applewatch" : "waveform.path.ecg", tint: NunaPalette.restText)
                    Spacer()
                    NunaChip("Experimental")
                }
                Text(unsupported ? "This device can't support a rhythm reading" : "No clear reading yet")
                    .font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text(emptyMessage).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyMessage: LocalizedStringKey {
        switch emptyReason {
        case .deviceBanksBeats: return "Rhythm needs beat-to-beat timing measured one beat at a time. Your device stores its heartbeats in batches, so the exact spacing between them isn't recoverable. Nothing is wrong with your night."
        case .deviceNoMotion: return "Rhythm reads only during still, resting windows, and this device doesn't record the stillness signal it needs to find them. Nothing is wrong with your night."
        default: return "Rhythm only looks during quiet, still, resting windows, so it needs a calm night's worth of steady beats. Once there's a clean window, the scatter and its description show here."
        }
    }

    // MARK: Words

    private func label(_ l: RhythmRegularity) -> LocalizedStringKey {
        switch l {
        case .steady: return "Steady"
        case .occasionalEctopy: return "Some variation"
        case .varied: return "More varied"
        case .unreadable: return "No clear reading"
        }
    }

    private func windowName(_ l: RhythmRegularity) -> LocalizedStringKey {
        switch l {
        case .varied: return "Most varied window"
        case .occasionalEctopy: return "Window with extra beats"
        default: return "One quiet window"
        }
    }

    /// The cloud's shape in a word, cut where the engine itself calls it rounding out.
    private func shape(_ ratio: Double?) -> String {
        guard let ratio else { return "–" }
        return ratio >= RhythmScreener.tauRatio ? String(localized: "Rounder") : String(localized: "Elongated")
    }

    private func quality(_ c: RhythmConfidence) -> String {
        switch c {
        case .solid: return String(localized: "Solid")
        case .building: return String(localized: "Building")
        case .calibrating: return String(localized: "Calibrating")
        }
    }

    private func pct(_ v: Double?) -> String { v.map { String(format: "%.0f%%", locale: AppLanguage.activeLocale, $0 * 100) } ?? "–" }

    private func range(_ i: Int) -> String { times.indices.contains(i) ? clock(times[i].start) + " – " + clock(times[i].end) : "–" }

    private func clock(_ ts: Int) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("jj:mm")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    // MARK: Load (same windowing and gates as the Default Rhythm host)

#if DEBUG
    /// `--demo-rhythm`: a night of made-up beat timing, so the page can be looked at without a strap. Six resting windows: mostly steady, one with a few extra
    /// beats and one that varies more. Nothing is read from or written to the store.
    private func loadDemo() {
        var rng = SystemRandomNumberGenerator()
        func window(beats: Int, baseMs: Double, rsa: Double, noise: Double, ectopicEvery: Int = 0, scatter: Double = 0) -> [Double] {
            var out: [Double] = []
            for i in 0..<beats {
                var v = baseMs + rsa * sin(Double(i) / 4.2) + Double.random(in: -noise...noise, using: &rng) + Double.random(in: -scatter...scatter, using: &rng)
                if ectopicEvery > 0, i > 0, i % ectopicEvery == 0 { v *= 0.62 }       // an early beat, then the pause that follows it
                if ectopicEvery > 0, i > 1, (i - 1) % ectopicEvery == 0 { v *= 1.38 }
                out.append(v)
            }
            return out
        }
        let shapes: [[Double]] = [
            window(beats: 300, baseMs: 1040, rsa: 38, noise: 9),
            window(beats: 296, baseMs: 1010, rsa: 42, noise: 10),
            window(beats: 310, baseMs: 1060, rsa: 35, noise: 8, ectopicEvery: 17),
            window(beats: 305, baseMs: 1030, rsa: 40, noise: 9),
            window(beats: 288, baseMs: 990, rsa: 30, noise: 40, scatter: 190),
            window(beats: 300, baseMs: 1050, rsa: 44, noise: 9),
        ]
        let lo = Int(Date().timeIntervalSince1970) - 8 * 3600
        var results: [RhythmScreener.WindowResult] = []
        var starts: [(Int, Int)] = []
        for (i, rr) in shapes.enumerated() {
            let mean = rr.reduce(0, +) / Double(rr.count)
            results.append(RhythmScreener.screenWindow(RhythmScreener.WindowInput(rrMs: rr, ts: [], motionStill: true, meanHR: 60_000 / mean)))
            let start = lo + i * 5 * 60 + (i >= 3 ? 40 * 60 : 0)
            starts.append((start, start + 300))
        }
        windows = results
        times = starts.map { (start: $0.0, end: $0.1) }
        night = RhythmScreener.summarizeNight(results)
        func rank(_ l: RhythmRegularity) -> Int { l == .varied ? 3 : (l == .occasionalEctopy ? 2 : 1) }
        var out: [Span] = []
        for (i, r) in results.enumerated() where r.label != .unreadable {
            let (s, e) = starts[i]
            if let last = out.last, last.end == s {
                out[out.count - 1] = Span(start: last.start, end: e, beats: last.beats + r.nBeats, label: rank(r.label) > rank(last.label) ? r.label : last.label)
            } else {
                out.append(Span(start: s, end: e, beats: r.nBeats, label: r.label))
            }
        }
        spans = out
    }
#endif

    private func load() async {
        defer { loaded = true }
#if DEBUG
        if CommandLine.arguments.contains("--demo-rhythm") { loadDemo(); return }
#endif
        guard let lastSleep = (await repo.allSleepSessions(days: 14)).last else { return }
        let lo = lastSleep.effectiveStartTs, hi = lastSleep.endTs
        guard hi > lo else { return }
        let rr = await repo.rrIntervals(from: lo, to: hi, limit: 200_000)
        guard !rr.isEmpty else { return }
        let grav = await repo.gravitySamplesUnion(from: lo, to: hi, limit: 200_000)
        var results: [RhythmScreener.WindowResult] = []
        var starts: [(Int, Int)] = []
        var t = lo
        while t < hi {
            let end = min(t + 300, hi)
            let wRR = rr.filter { $0.ts >= t && $0.ts < end }
            if wRR.count >= RhythmScreener.windowMinBeats {
                let g = grav.filter { $0.ts >= t && $0.ts < end }
                results.append(RhythmScreener.screenWindow(RhythmScreener.WindowInput(rr: wRR, motionStill: Self.isStill(g))))
                starts.append((t, end))
            }
            t = end
        }
        windows = results
        times = starts.map { (start: $0.0, end: $0.1) }
        night = RhythmScreener.summarizeNight(results)
        emptyReason = RhythmScreener.classifyEmptyState(
            windows: results, hadMotionSignal: !grav.isEmpty,
            beatsAreBanked: RhythmScreener.nightBeatsAreBanked(rrMs: rr.map { Double($0.rrMs) }, tsSec: rr.map { $0.ts }))
        // Join neighbouring readable windows into spans; a span takes its least steady label.
        func rank(_ l: RhythmRegularity) -> Int { l == .varied ? 3 : (l == .occasionalEctopy ? 2 : 1) }
        var out: [Span] = []
        for (i, r) in results.enumerated() where r.label != .unreadable {
            let (s, e) = starts[i]
            if let last = out.last, last.end == s {
                out[out.count - 1] = Span(start: last.start, end: e, beats: last.beats + r.nBeats, label: rank(r.label) > rank(last.label) ? r.label : last.label)
            } else {
                out.append(Span(start: s, end: e, beats: r.nBeats, label: r.label))
            }
        }
        spans = out
        if let night, !results.isEmpty {
            let csv = RhythmExport.csv(summary: night, windows: results)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("phmn-rhythm.csv")
            exportURL = (try? csv.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
        }
    }

    private static func isStill(_ grav: [GravitySample]) -> Bool {
        guard grav.count >= 4 else { return false }
        let mags = grav.map { ($0.x * $0.x + $0.y * $0.y + $0.z * $0.z).squareRoot() }
        let mean = mags.reduce(0, +) / Double(mags.count)
        guard mean > 0 else { return false }
        let variance = mags.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(mags.count)
        return (variance.squareRoot() / mean) < 0.03
    }
}
#endif
