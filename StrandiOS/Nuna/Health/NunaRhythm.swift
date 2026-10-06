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
                            .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
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
                                .frame(width: 30, height: 30).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
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
        .background(NunaPalette.canvas.ignoresSafeArea())
    }
}

// MARK: - Poincaré plot

/// Successive-beat scatter: a tight line along the diagonal is a steady beat, a rounder cloud is more variable.
struct NunaPoincarePlot: View {
    let points: [RhythmScreener.PoincarePoint]
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
            guard !points.isEmpty else { return }
            let mx = points.map(\.x).reduce(0, +) / Double(points.count), my = points.map(\.y).reduce(0, +) / Double(points.count)
            if let sd1, let sd2 {
                let k = plot / CGFloat(hi - lo) * 2.5
                let c = CGPoint(x: map(mx), y: s - map(my))
                var e = Path(ellipseIn: CGRect(x: -CGFloat(sd2) * k, y: -CGFloat(sd1) * k, width: CGFloat(sd2) * k * 2, height: CGFloat(sd1) * k * 2))
                e = e.applying(CGAffineTransform(rotationAngle: -.pi / 4)).applying(CGAffineTransform(translationX: c.x, y: c.y))
                ctx.fill(e, with: .color(NunaPalette.rest.opacity(0.14)))
                ctx.stroke(e, with: .color(NunaPalette.restText), lineWidth: 1.5)
            }
            // A whole night holds thousands of pairs; an evenly spaced sample keeps the cloud readable.
            let step = max(1, points.count / 320)
            for p in points.enumerated().filter({ $0.offset % step == 0 }).map(\.element) {
                let x = map(p.x), y = s - map(p.y)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)), with: .color(NunaPalette.restLight.opacity(0.7)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottomLeading) {
            Text("RR now (ms) →").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).padding(12)
        }
        .overlay(alignment: .topLeading) {
            Text("↑ next RR").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).padding(12)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The screen

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
    @State private var spans: [Span] = []
    @State private var emptyReason: RhythmEmptyState = .gatheringData
    @State private var loaded = false
    @State private var showConsent = false
    @State private var exportURL: URL?

    private var consentGiven: Bool { enabled && RhythmConsent.isAccepted(acceptedVersion) }
    private var readable: [RhythmScreener.WindowResult] { windows.filter { $0.label != .unreadable } }
    private var allPoints: [RhythmScreener.PoincarePoint] { windows.flatMap { $0.poincare } }
    private var headline: RhythmScreener.WindowResult? {
        readable.first(where: { $0.label == .varied }) ?? readable.first(where: { $0.label == .occasionalEctopy }) ?? readable.first
    }

    var body: some View {
        Group {
            if !consentGiven {
                NunaRhythmConsentView(onAccept: { acceptedVersion = RhythmConsent.currentVersion; enabled = true }, onCancel: { dismiss() })
            } else {
                NunaDetailScreen("Rhythm") { content }
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
        HStack {
            Text("A picture of your beat-to-beat timing, not a verdict.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Spacer(minLength: 8)
            NunaChip("Experimental")
        }
        if !loaded {
            ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 160)
        } else if allPoints.isEmpty {
            emptyCard
        } else {
            summaryCard
            plotCard
            spansList
            numbers
            if let exportURL {
                ShareLink(item: exportURL) {
                    NunaCard(small: true) { NunaListRow("Share", subtitle: "A neutral CSV of the numbers, never a verdict", systemImage: "square.and.arrow.up", showsChevron: true) }
                }.buttonStyle(.plain)
            }
        }
        NunaCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("How this is measured").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Text("During quiet, still, resting windows, NOOP looks at the timing between your heartbeats (R-R intervals) and draws their Poincaré scatter. From the cloud it computes its short and long axes (SD1, SD2) and a few plain regularity numbers. Movement and noisy windows are skipped, not shown. These are transparent, published descriptive statistics: a picture of your timing, never a clinical measurement.")
                    .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
        disclaimer
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                NunaListRow("Rhythm on", subtitle: "Computed on this phone, never leaves your iPhone") {
                    Toggle("", isOn: Binding(get: { enabled }, set: { on in enabled = on; if !on { dismiss() } })).labelsHidden().tint(NunaPalette.charge)
                }
                NunaDivider()
                Button { showConsent = true } label: {
                    NunaListRow("Read the consent again", subtitle: LocalizedStringKey(String(localized: "Accepted version \(acceptedVersion)")), systemImage: "doc.text", showsChevron: true)
                }.buttonStyle(.plain)
            }
        }
    }

    private var disclaimer: some View {
        NunaCard(small: true) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle").foregroundStyle(NunaPalette.textMuted)
                Text("Experimental wellness visualization: not a diagnosis, not an ECG, and not a medical device. It cannot detect any heart condition. Beat-to-beat variation has many ordinary, benign causes. If you feel unwell or are worried, contact a qualified professional; in an emergency, your local emergency service. Everything is computed on your device.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
    }

    // MARK: Empty and unsupported

    private var emptyCard: some View {
        let unsupported = emptyReason == .deviceBanksBeats || emptyReason == .deviceNoMotion
        return VStack(spacing: 16) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: unsupported ? "applewatch" : "waveform.path.ecg").font(.nuna(size: 26, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 56, height: 56).background(NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                    Text(unsupported ? "This device can't support a rhythm reading" : "No clear reading yet")
                        .font(.nuna(size: 22, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text(emptyMessage).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var emptyMessage: LocalizedStringKey {
        switch emptyReason {
        case .deviceBanksBeats: return "Rhythm needs beat-to-beat timing measured one beat at a time. Your device stores its heartbeats in batches, so the exact spacing between them isn't recoverable. Nothing is wrong with your night."
        case .deviceNoMotion: return "Rhythm reads only during still, resting windows, and this device doesn't record the stillness signal it needs to find them. Nothing is wrong with your night."
        default: return "Rhythm only looks during quiet, still, resting windows, so it needs a calm night's worth of steady beats. Once there's a clean window, the scatter and its description show here."
        }
    }

    // MARK: Result cards

    private func label(_ l: RhythmRegularity) -> LocalizedStringKey {
        switch l {
        case .steady: return "Steady"
        case .occasionalEctopy: return "Some variation"
        case .varied: return "More varied"
        case .unreadable: return "No clear reading"
        }
    }

    private var summaryCard: some View {
        let overall = night?.overall ?? headline?.label ?? .unreadable
        let confidence: LocalizedStringKey = {
            switch headline?.confidence ?? .calibrating {
            case .solid: return "Solid"
            case .building: return readable.count <= 1 ? "Building (1 window)" : "Building"
            case .calibrating: return "Calibrating"
            }
        }()
        let detail: LocalizedStringKey = {
            switch overall {
            case .steady: return "Across the quiet windows we could read, your beat-to-beat timing held a tight, even shape."
            case .occasionalEctopy: return "Mostly steady, with a few isolated extra or skipped beats. Very common and usually nothing."
            case .varied: return "The scatter looked rounder and more spread out than a tight, steady beat. This has many ordinary causes and is not a diagnosis."
            case .unreadable: return "There wasn't a calm, still window clean enough to describe. Try again after a settled night."
            }
        }()
        return NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Last night").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    NunaChip(confidence, systemImage: "checkmark", color: NunaPalette.restText)
                }
                NunaChip(label(overall), systemImage: overall == .steady ? "checkmark" : "waveform.path.ecg", color: NunaPalette.restText)
                Text(detail).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                if let h = headline {
                    VStack(spacing: 12) {
                        bar("Beat-to-beat variation", h.normRmssd, NunaPalette.restLight)
                        bar("Extra or skipped beats", h.ectopicFraction, NunaPalette.rest)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func bar(_ title: LocalizedStringKey, _ v: Double?, _ color: Color) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Spacer()
                Text(verbatim: pct(v)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            NunaProgressBar(fraction: min(max(v ?? 0, 0), 1), color: color)
        }
    }

    private var plotCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Beat-to-beat scatter").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                NunaPoincarePlot(points: allPoints, sd1: headline?.sd1, sd2: headline?.sd2)
                Text("Each dot pairs one heartbeat interval with the next. A tight line along the diagonal means a steady beat; a rounder, more spread-out cloud means the timing varied more.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
        }
    }

    @ViewBuilder private var spansList: some View {
        if !spans.isEmpty {
            NunaTitleRow(title: "Reading windows") { EmptyView() }
            ForEach(spans) { s in
                NunaCard(small: true) {
                    NunaListRow(LocalizedStringKey(clock(s.start) + " – " + clock(s.end)),
                                subtitle: LocalizedStringKey(String(localized: "\((s.end - s.start) / 60) min · \(s.beats) beats read")), systemImage: "moon") {
                        NunaChip(label(s.label), systemImage: s.label == .steady ? "checkmark" : nil, color: NunaPalette.restText)
                    }
                }
            }
        }
    }

    private var numbers: some View {
        let h = headline
        let total = readable.reduce(0) { $0 + $1.nBeats }
        return VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "The numbers") { EmptyView() }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tile("Short axis", h?.sd1.map { String(format: "%.0f", $0) } ?? "–", "SD1 · ms")
                tile("Long axis", h?.sd2.map { String(format: "%.0f", $0) } ?? "–", "SD2 · ms")
                tile("Cloud shape", h?.sd1sd2.map { String(format: "%.2f", locale: AppLanguage.activeLocale, $0) } ?? "–", "SD1:SD2 ratio")
                tile("Beat-to-beat variation", pct(h?.normRmssd), "variation index")
                tile("Extra / skipped", pct(h?.ectopicFraction), "of beats")
                tile("Beats read", "\(total)", "clean intervals")
            }
        }
    }

    private func tile(_ label: LocalizedStringKey, _ value: String, _ caption: LocalizedStringKey) -> some View {
        NunaStatTile(label: label, value: value, caption: caption)
    }

    private func pct(_ v: Double?) -> String { v.map { String(format: "%.0f%%", $0 * 100) } ?? "–" }

    private func clock(_ ts: Int) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("jj:mm")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    // MARK: Load (same windowing and gates as the Default Rhythm host)

    private func load() async {
        defer { loaded = true }
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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("noop-rhythm.csv")
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
