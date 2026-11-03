#if os(iOS)
import SwiftUI
import StrandDesign

/// Anya floating over a page: a small button at the bottom corner, or, when she has a line for the page, a pill with that line and a chevron
/// (swipe it down to fold it into the button). Either opens the dark Anya sheet, which holds the line, suggestion chips and one box to ask in.
struct NunaAnyaFloating: ViewModifier {
    let context: String
    let givenLine: String?
    var metric: NunaAnyaMetric?
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @State private var open = false
    /// The line that was folded away, so the same line does not come back while the page is open.
    @State private var foldedLine: String?
    @State private var drag: CGFloat = 0

    /// `--demo-anya-pill` stands in a line when the page has none, since the demo data has no Strain to read.
    private var line: String? {
#if DEBUG
        if givenLine == nil, CommandLine.arguments.contains("--demo-anya-pill") {
            return String(localized: "You are inside the Strain your Recovery supports today: more adds load without much return.")
        }
#endif
        return givenLine
    }

    private var showsPill: Bool { line != nil && line != foldedLine }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if coachEnabled {
                    ZStack(alignment: .bottomTrailing) {
                        if showsPill, let line { pill(line) } else { button }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottomTrailing)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: showsPill)
                }
            }
            .sheet(isPresented: $open) {
                NunaAnyaSheet(context: context, cardLine: line.map { NunaAnyaCardLine(headline: $0, detail: nil, read: []) }, metric: metric, floating: true)
            }
    }

    private static let surface = LinearGradient(colors: [Color(red: 0.19, green: 0.22, blue: 0.30), Color(red: 0.12, green: 0.14, blue: 0.20)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing)

    private func ring(_ size: CGFloat) -> some View {
        ZStack {
            Circle().strokeBorder(NunaAnyaWing.gradient, lineWidth: size > 40 ? 3 : 2.5)
            AnyaMark(size: size * 0.5)
        }
        .frame(width: size, height: size)
    }

    private var button: some View {
        Button { open = true } label: {
            ring(40)
                .frame(width: 64, height: 64)
                .background(Self.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain).accessibilityLabel(Text("Ask Anya"))
        .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
    }

    private func pill(_ line: String) -> some View {
        Button { open = true } label: {
            HStack(spacing: 14) {
                ring(52)
                Text(verbatim: NunaMark.plain(line)).font(.nuna(size: 17, weight: .medium)).foregroundStyle(.white).textCase(nil)
                    .lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up").font(.system(size: 20, weight: .regular)).foregroundStyle(.white.opacity(0.7)).padding(.trailing, 6)
            }
            .padding(.leading, 14).padding(.trailing, 14).padding(.vertical, 14)
            .background(Self.surface, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .offset(y: max(drag, 0))
        .gesture(DragGesture(minimumDistance: 12)
            .onChanged { drag = $0.translation.height }
            .onEnded { v in
                if v.translation.height > 40 { foldedLine = line }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
            })
        .accessibilityHint(Text("Opens Anya"))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Anya floating over this page, with `line` as what she has to say about it (nil: only the button).
    func nunaAnyaFloating(context: String, line: String?, metric: NunaAnyaMetric? = nil) -> some View {
        modifier(NunaAnyaFloating(context: context, givenLine: line, metric: metric))
    }
}
#endif
