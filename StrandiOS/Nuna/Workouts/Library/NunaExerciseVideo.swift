#if os(iOS)
import SwiftUI
import WebKit
import StrandDesign

struct NunaVideoTarget: Identifiable { let name: String; var id: String { name } }

/// How an exercise is done, as a video, for the exercises the library has no demo for (the person's own names). It opens YouTube's search for
/// the movement inside the app. Nothing is requested until this sheet opens, and the only thing sent is the exercise name; the library's
/// own demos never go online.
struct NunaExerciseVideoSheet: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var loading = true

    @State private var source = NunaDemoSource.video

    /// The words searched: the name and what the person wants to see.
    static func url(for name: String, source: NunaDemoSource = .video) -> URL? { source.url(for: name) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { NunaBareIcon("xmark") }.buttonStyle(.plain).accessibilityLabel(Text("Close"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).textCase(nil)
                    Text(source == .video ? "How it is done · YouTube" : "How it is done · GIF").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Spacer(minLength: 8)
                if let url = Self.url(for: name, source: source) {
                    Button { openURL(url) } label: { NunaBareIcon("arrow.up.right.square") }.buttonStyle(.plain).accessibilityLabel(Text("Open in the browser"))
                }
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 6)
            NunaDemoSourcePicker(source: $source).padding(.horizontal, 16).padding(.bottom, 8)
            ZStack {
                if let url = Self.url(for: name, source: source) { NunaWebView(url: url, loading: $loading).id(source).onChange(of: source) { _ in loading = true } } else { Text("This video could not be opened.").foregroundStyle(NunaPalette.textSecondary) }
                if loading { ProgressView().tint(NunaPalette.textSecondary) }
            }
            Text(source == .video ? "Opens YouTube. Only the exercise name is sent." : "Opens GIPHY. Only the exercise name is sent.").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

/// Where a how-to comes from for an exercise with no photo demo: a video (YouTube) or a GIF (GIPHY). Both are a search for the exercise's name,
/// opened only when the person asks, and the name is all that is sent.
enum NunaDemoSource: Hashable {
    case video, gif

    func url(for name: String) -> URL? {
        switch self {
        case .video:
            var c = URLComponents(string: "https://m.youtube.com/results")
            c?.queryItems = [URLQueryItem(name: "search_query", value: name + " exercise how to")]
            return c?.url
        case .gif:
            let slug = (name + " exercise").lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
            return URL(string: "https://giphy.com/search/" + slug)
        }
    }
}

/// Video or GIF, as two chips.
struct NunaDemoSourcePicker: View {
    @Binding var source: NunaDemoSource
    var body: some View {
        HStack(spacing: 8) {
            chip("Video", "play.rectangle.fill", .video)
            chip("GIF", "photo.on.rectangle", .gif)
            Spacer(minLength: 0)
        }
    }
    private func chip(_ title: LocalizedStringKey, _ icon: String, _ value: NunaDemoSource) -> some View {
        let on = source == value
        return Button { source = value } label: {
            HStack(spacing: 6) { Image(systemName: icon).font(.nuna(size: 12, weight: .bold)); Text(title).font(.nuna(size: 13.5, weight: .bold)) }
                .foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 34)
                .background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }
}

/// Stands in for the photo demo of a library exercise that has none: a tile that, once tapped, turns into the embedded video or GIF.
struct NunaMissingDemoPanel: View {
    let name: String
    var height: CGFloat = 230
    @State private var source: NunaDemoSource?
    @State private var loading = true

    var body: some View {
        VStack(spacing: 8) {
            if let source {
                NunaDemoSourcePicker(source: Binding(get: { source }, set: { self.source = $0; loading = true }))
                ZStack {
                    if let url = source.url(for: name) { NunaWebView(url: url, loading: $loading).id(source) }
                    if loading { ProgressView().tint(NunaPalette.textSecondary) }
                }
                .frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(source == .video ? "Opens YouTube. Only the exercise name is sent." : "Opens GIPHY. Only the exercise name is sent.")
                    .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 30, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                    Text("No animation for this exercise yet").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    HStack(spacing: 10) {
                        Button { loading = true; source = .video } label: {
                            Label("Watch a video", systemImage: "play.rectangle.fill").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                                .padding(.horizontal, 16).frame(height: 40).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain)
                        Button { loading = true; source = .gif } label: {
                            Label("See a GIF", systemImage: "photo.on.rectangle").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                .padding(.horizontal, 16).frame(height: 40).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: height).background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

struct NunaWebView: UIViewRepresentable {
    let url: URL
    @Binding var loading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(loading: $loading) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // A search for a one-off look: no cookies or history are kept between openings.
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var loading: Bool
        init(loading: Binding<Bool>) { _loading = loading }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loading = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loading = false }
    }
}
#endif
