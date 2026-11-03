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
    /// The provider's analysis, when there is one.
    @Published private(set) var explanation: String?

    /// A finished analysis is kept for a while, so opening the page again does not ask the provider again.
    private static var cache: [String: (at: Date, local: String?, explanation: String?)] = [:]
    private static let keep: TimeInterval = 30 * 60

    func analyse(context: String, metric: NunaAnyaMetric?, pageLine: String?, repo: Repository, profile: ProfileStore, coach: AICoachEngine, scale: EffortScale) async {
        guard phase != .analysing else { return }
        let key = "\(context)|\(Repository.localDayKey(Date()))|\(coach.isConfigured && coach.dataConsent)"
        if let hit = Self.cache[key], Date().timeIntervalSince(hit.at) < Self.keep {
            local = hit.local; explanation = hit.explanation; phase = .done; return
        }
        phase = .analysing
        let read = await NunaAnyaReader.read(context: context, metric: metric, repo: repo, profile: profile, scale: scale)
        local = read.map { NunaMark.plain(NunaMark.compose(headline: $0.headline, detail: $0.detail)) } ?? pageLine
        if coach.isConfigured, coach.dataConsent {
            let module = NunaAnyaModule(context: context)
            let page = context + (local.map { "\n\n" + $0 } ?? "") + (NunaAnyaMemory.summary(module).map { "\n\n" + $0 } ?? "")
            explanation = await coach.generateContextualBrief(pageContext: page).map { AnyaActions.proseOnly($0) }
        }
        Self.cache[key] = (Date(), local, explanation)
        phase = .done
    }
}

/// Anya's mark in a thin neon ring: the ring's colour runs from violet at the upper left to sky blue at the lower right (sampled from the design
/// reference), with a faint glow of the same colour just inside it. The ring is about 1.4 pt thick at the 32 pt of the reference.
struct NunaAnyaRing: View {
    var size: CGFloat = 34

    /// (angle counter-clockwise from the right, colour) as measured on the reference.
    private static let samples: [(Double, Color)] = [
        (0, Color(red: 0.518, green: 0.706, blue: 0.949)), (30, Color(red: 0.529, green: 0.663, blue: 0.941)),
        (60, Color(red: 0.533, green: 0.596, blue: 0.941)), (90, Color(red: 0.525, green: 0.518, blue: 0.937)),
        (120, Color(red: 0.518, green: 0.486, blue: 0.914)), (150, Color(red: 0.533, green: 0.498, blue: 0.949)),
        (180, Color(red: 0.525, green: 0.533, blue: 0.937)), (210, Color(red: 0.561, green: 0.596, blue: 0.969)),
        (240, Color(red: 0.537, green: 0.671, blue: 0.949)), (270, Color(red: 0.525, green: 0.702, blue: 0.965)),
        (300, Color(red: 0.525, green: 0.769, blue: 1.0)), (330, Color(red: 0.494, green: 0.749, blue: 1.0)),
    ]

    private static var gradient: AngularGradient {
        // SwiftUI measures the angle clockwise from the right, so the sampled angles are mirrored.
        var stops = samples.map { Gradient.Stop(color: $0.1, location: ((360 - $0.0).truncatingRemainder(dividingBy: 360)) / 360) }
        stops.sort { $0.location < $1.location }
        if let first = stops.first { stops.append(.init(color: first.color, location: 1)) }
        return AngularGradient(gradient: Gradient(stops: stops), center: .center)
    }

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [.clear, Color(red: 0.42, green: 0.45, blue: 0.85).opacity(0.34)],
                                         center: .center, startRadius: size * 0.30, endRadius: size * 0.5))
            Circle().strokeBorder(Self.gradient, lineWidth: max(1.3, size * 0.046))
            AnyaMark(size: size * 0.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
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

    /// `line` nil means she is still analysing.
    private func pill(_ line: String?) -> some View {
        Button { open = true } label: {
            HStack(spacing: 14) {
                NunaAnyaRing(size: 34)
                Group {
                    if let line {
                        Text(verbatim: NunaMark.plain(line)).font(.nuna(size: 15.5, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small).tint(.white.opacity(0.8))
                            Text("Anya is analysing…").font(.nuna(size: 15.5, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .foregroundStyle(.white).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up").font(.system(size: 17, weight: .regular)).foregroundStyle(.white.opacity(0.7)).padding(.trailing, 4)
            }
            .padding(.leading, 15).padding(.trailing, 16).padding(.vertical, 13)
            .background(Self.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
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
