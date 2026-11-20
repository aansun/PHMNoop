#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// What Anya works out as soon as the page opens: her local read of it and, when she is connected and may use the numbers, a short written
/// analysis from the provider. The pill shows "analysing" until it is done, then the result; the sheet starts from the same text.
@MainActor
final class NunaAnyaFloatingModel: ObservableObject {
    enum Phase { case idle, analysing, done }
    @Published private(set) var phase = Phase.idle
    /// The local read of the page, as one run of sentences.
    @Published private(set) var local: String?
    /// The provider's analysis, when there is one (or, without one, what the phone worked out): the sheet's text, with titled parts.
    @Published private(set) var explanation: String?
    /// The one sentence the pill shows from that analysis: what the reading is and whether it is good, fair or needs attention.
    @Published private(set) var headline: String?

    /// A finished analysis is kept for a while, so opening the page again does not ask the provider again.
    private static var cache: [String: (at: Date, local: String?, explanation: String?, headline: String?)] = [:]
    private static let keep: TimeInterval = 30 * 60

    func analyse(context: String, metric: NunaAnyaMetric?, pageLine: String?, repo: Repository, profile: ProfileStore, coach: AICoachEngine, scale: EffortScale) async {
        guard phase != .analysing else { return }
        let key = "\(context)|\(Repository.localDayKey(Date()))|\(coach.isConfigured && coach.dataConsent)"
        if let hit = Self.cache[key], Date().timeIntervalSince(hit.at) < Self.keep {
            local = hit.local; explanation = hit.explanation; headline = hit.headline; phase = .done; return
        }
        phase = .analysing
#if DEBUG
        // `--demo-anya-slow` keeps her "analyzing" for a while, so that state can be looked at.
        if CommandLine.arguments.contains("--demo-anya-slow") { try? await Task.sleep(nanoseconds: 60_000_000_000) }
#endif
        let read = await NunaAnyaReader.read(context: context, metric: metric, repo: repo, profile: profile, scale: scale)
        local = read.map { NunaMark.plain(NunaMark.compose(headline: $0.headline, detail: $0.detail)) } ?? pageLine
        let verdict = read?.verdict
        if coach.isConfigured, coach.dataConsent {
            let module = NunaAnyaModule(context: context)
            // The page, the phone's own verdict on it (so she explains a judgement instead of making one up) and what she noted before.
            let page = context + (local.map { "\n\n" + $0 } ?? "") + (verdict.map { "\n\n" + $0.providerLine } ?? "") + (NunaAnyaMemory.summary(module).map { "\n\n" + $0 } ?? "")
            if let raw = await coach.generatePageInsight(topic: verdict?.topic ?? NunaAnyaTopic.of(metricKey: metric?.key ?? "", title: metric?.title ?? context), pageContext: page) {
                let shown = NunaAnyaInsightText.fromProvider(raw, verdict: verdict)
                explanation = shown.text; headline = shown.headline
            }
        }
        // No provider, or it did not answer: the sheet still gets the verdict, the reading and the next step, worked out on this phone.
        // The pill keeps the page's own line (it is richer than the verdict's one sentence).
        if explanation == nil, let verdict {
            explanation = NunaAnyaInsightText.fromVerdict(verdict, reading: read?.detail.map { NunaMark.plain($0) }).text
        }
        Self.cache[key] = (Date(), local, explanation, headline)
        phase = .done
    }
}

/// Anya's mark in a thin neon ring: the PHMN butterfly in white, the ring running from violet at the upper left to sky blue at the lower right
/// (sampled from the design reference), with a faint glow of the same colour just inside it. See `PHMNAnyaMark`.
struct NunaAnyaRing: View {
    var size: CGFloat = 34

    var body: some View {
        PHMNAnyaMark(size: size)
    }
}

/// "Analyzing…" in grey with a light that sweeps across the letters, as on the reference.
private struct NunaAnyaShimmerText: View {
    let text: String
    @State private var phase: CGFloat = -0.4
    var body: some View {
        Text(verbatim: text).font(.nuna(size: 15.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.52))
            .overlay {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.45)
                        .offset(x: phase * g.size.width)
                }
                .mask(Text(verbatim: text).font(.nuna(size: 15.5, weight: .semibold)))
            }
            .onAppear { withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { phase = 1.0 } }
    }
}

/// A light that runs round the pill's edge while she works: a short comet of blue that circles the whole outline, with a soft glow behind it.
private struct NunaAnyaProgressLight: View {
    let shape: RoundedRectangle
    /// Seconds for one lap.
    private let lap = 2.2

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((t.truncatingRemainder(dividingBy: lap)) / lap * 360)
            let comet = AngularGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.62),
                .init(color: Color(red: 0.36, green: 0.42, blue: 0.9).opacity(0.55), location: 0.86),
                .init(color: Color(red: 0.7, green: 0.76, blue: 1.0), location: 0.995),
                .init(color: .clear, location: 1.0),
            ], center: .center, angle: angle)
            ZStack {
                shape.strokeBorder(comet, lineWidth: 5).blur(radius: 5).opacity(0.9)
                shape.strokeBorder(comet, lineWidth: 2.5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Anya floating over a page: a small button at the bottom corner, or, when she has a line for the page, a pill with that line and a chevron
/// (swipe it down to fold it into the button). Either opens the dark Anya sheet, which holds the line, suggestion chips and one box to ask in.
struct NunaAnyaFloating: ViewModifier {
    let context: String
    let givenLine: String?
    var metric: NunaAnyaMetric?
    /// Whether she analyses the page as it opens (today only); otherwise she is just the button.
    var analyses = true
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var coach: AICoachEngine
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @StateObject private var model = NunaAnyaFloatingModel()
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @State private var open = false
    /// The line that was folded away, so the same line does not come back while the page is open.
    @State private var folded = false
    @State private var drag: CGFloat = 0

    /// What the pill says once the analysis is in: the provider's, else Anya's own read of the page, else what the page itself gave.
    private var line: String? {
#if DEBUG
        if givenLine == nil, CommandLine.arguments.contains("--demo-anya-pill") {
            return String(localized: "You are inside the Strain your Recovery supports today: more adds load without much return.")
        }
#endif
        if let h = model.headline { return h }
        if let e = model.explanation { return e }
        return givenLine ?? model.local
    }

    private var analysing: Bool { analyses && model.phase != .done }
    private var showsPill: Bool { !folded && (analysing || line != nil) }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if coachEnabled {
                    ZStack(alignment: .bottomTrailing) {
                        if showsPill { pill(analysing ? nil : line) } else { button }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottomTrailing)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: showsPill)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: analysing)
                }
            }
            .task { if analyses { await model.analyse(context: context, metric: metric, pageLine: givenLine, repo: repo, profile: profile, coach: coach, scale: UnitPrefs.resolveEffortScale(effortScaleRaw)) } }
            .sheet(isPresented: $open) {
                NunaAnyaSheet(context: context, cardLine: (givenLine ?? model.local).map { NunaAnyaCardLine(headline: $0, detail: nil, read: []) },
                              metric: metric, floating: true, seed: model.explanation)
            }
    }

    private static let surface = LinearGradient(colors: [Color(red: 0.22, green: 0.215, blue: 0.29), Color(red: 0.19, green: 0.205, blue: 0.24), Color(red: 0.165, green: 0.19, blue: 0.22)],
                                                startPoint: .leading, endPoint: .trailing)

    private var button: some View {
        Button { open = true } label: {
            NunaAnyaRing(size: 34)
                .frame(width: 64, height: 64)
                .background(Self.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain).accessibilityLabel(Text("Ask Anya"))
        .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
    }

    /// `line` nil means she is still analysing: a small pill with "Analyzing…" at the right, which opens out to the full line once it is there.
    private func pill(_ line: String?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return Button { open = true } label: {
            HStack(spacing: 14) {
                NunaAnyaRing(size: 34)
                if let line {
                    Text(verbatim: NunaMark.plain(line)).font(.nuna(size: 15.5, weight: .medium)).foregroundStyle(.white).textCase(nil)
                        .lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up").font(.system(size: 17, weight: .regular)).foregroundStyle(.white.opacity(0.7)).padding(.trailing, 4)
                } else {
                    NunaAnyaShimmerText(text: String(localized: "Analyzing…")).textCase(nil).padding(.trailing, 8)
                }
            }
            .padding(.leading, 15).padding(.trailing, 16).padding(.vertical, 13)
            .frame(maxWidth: line == nil ? nil : .infinity)
            .background(Self.surface, in: shape)
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [Color(red: 0.55, green: 0.5, blue: 0.85).opacity(0.5), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .overlay { if line == nil { NunaAnyaProgressLight(shape: shape) } }
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .offset(y: max(drag, 0))
        .gesture(DragGesture(minimumDistance: 12)
            .onChanged { drag = $0.translation.height }
            .onEnded { v in
                if v.translation.height > 40 { folded = true }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
            })
        .accessibilityLabel(line.map { Text(verbatim: NunaMark.plain($0)) } ?? Text("Analyzing…"))
        .accessibilityHint(Text("Opens Anya"))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Anya floating over this page, with `line` as what she has to say about it (nil: only the button).
    func nunaAnyaFloating(context: String, line: String?, metric: NunaAnyaMetric? = nil, analyses: Bool = true) -> some View {
        modifier(NunaAnyaFloating(context: context, givenLine: line, metric: metric, analyses: analyses))
    }
}
#endif
