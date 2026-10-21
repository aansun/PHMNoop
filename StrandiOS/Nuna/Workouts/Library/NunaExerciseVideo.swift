#if os(iOS)
import SwiftUI
import WebKit
import StrandDesign

struct NunaVideoTarget: Identifiable { let name: String; var id: String { name } }

/// How an exercise is done, as a video, for an exercise the library has no animation for (a name the person typed). Only the player is shown. Nothing is
/// requested until the player appears, and the only thing sent to YouTube is the exercise name; the library's own animations never go online.
struct NunaExerciseVideoSheet: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { NunaBareIcon("xmark") }.buttonStyle(.plain).accessibilityLabel(Text("Close"))
                Text(verbatim: name).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).textCase(nil)
                Spacer(minLength: 8)
                if let url = NunaVideoResolver.searchURL(for: name) {
                    Button { openURL(url) } label: { NunaBareIcon("arrow.up.right.square") }.buttonStyle(.plain).accessibilityLabel(Text("Open in the browser"))
                }
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 10)
            NunaVideoPlayer(name: name).padding(.horizontal, 16)
            Text("Opens YouTube. Only the exercise name is sent.").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
            Spacer(minLength: 0)
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

/// Finds the first YouTube video for an exercise. Only the name goes out, as a search; the page that comes back is read for the id of the first result.
enum NunaVideoResolver {
    private static var cache: [String: String] = [:]

    static func searchURL(for name: String) -> URL? {
        var c = URLComponents(string: "https://m.youtube.com/results")
        c?.queryItems = [URLQueryItem(name: "search_query", value: name + " exercise how to")]
        return c?.url
    }

    static func videoID(for name: String) async -> String? {
        if let hit = cache[name] { return hit }
        var c = URLComponents(string: "https://www.youtube.com/results")
        c?.queryItems = [URLQueryItem(name: "search_query", value: name + " exercise how to"), URLQueryItem(name: "hl", value: "en")]
        guard let url = c?.url else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        req.setValue("CONSENT=YES+1", forHTTPHeaderField: "Cookie")
        let session = URLSession(configuration: .ephemeral)
        guard let (data, _) = try? await session.data(for: req), let html = String(data: data, encoding: .utf8) else { return nil }
        // The page writes its quotes as \x22 on the mobile site and as " on the desktop one. The results come in order; a video its owner does not allow
        // to be embedded shows "unavailable", so the first one YouTube says can be embedded is the one used.
        let pattern = try? NSRegularExpression(pattern: #"videoId(?:\\x22|")\s*:\s*(?:\\x22|")([A-Za-z0-9_-]{11})"#)
        let ns = html as NSString
        var candidates: [String] = []
        for m in pattern?.matches(in: html, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let id = ns.substring(with: m.range(at: 1))
            if !candidates.contains(id) { candidates.append(id) }
            if candidates.count == 8 { break }
        }
        var found: String?
        for id in candidates where await embeddable(id, session: session) { found = id; break }
        guard let id = found else { return nil }
        cache[name] = id
        return id
    }
}

extension NunaVideoResolver {
    /// YouTube's oEmbed answers 200 for a video that may be embedded and 401 or 403 for one that may not.
    static func embeddable(_ id: String, session: URLSession) async -> Bool {
        guard let url = URL(string: "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(id)") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await session.data(for: req), let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}

/// Only the player: no page around it. While the video is found there is a spinner; if it cannot be found, the way to open the search instead.
struct NunaVideoPlayer: View {
    let name: String
    @Environment(\.openURL) private var openURL
    @State private var id: String?
    @State private var failed = false
    @State private var loading = true

    var body: some View {
        ZStack {
            if let id {
                NunaYouTubePlayer(videoID: id, loading: $loading)
                if loading { ProgressView().tint(.white) }
            } else if failed {
                VStack(spacing: 12) {
                    Image(systemName: "play.slash").font(.system(size: 28, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                    Text("The video could not be loaded.").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    HStack(spacing: 10) {
                        Button { failed = false; Task { await load() } } label: {
                            Text("Try again").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 16).frame(height: 40)
                                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain)
                        if let url = NunaVideoResolver.searchURL(for: name) {
                            Button { openURL(url) } label: {
                                Text("Open YouTube").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 16).frame(height: 40)
                                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity).aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(failed ? NunaPalette.tile : Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: name) { await load() }
    }

    private func load() async {
        id = nil; failed = false; loading = true
        if let found = await NunaVideoResolver.videoID(for: name) { id = found } else { failed = true }
    }
}

/// YouTube's own embedded player and nothing else.
struct NunaYouTubePlayer: UIViewRepresentable {
    let videoID: String
    @Binding var loading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(loading: $loading) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // One look at a video: no cookies or history are kept between openings.
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head>
        <body><iframe src="https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1&origin=https://noop.local" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe></body></html>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://noop.local"))
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
