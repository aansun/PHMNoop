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

    /// The words searched: the name and what the person wants to see.
    static func url(for name: String) -> URL? {
        var c = URLComponents(string: "https://m.youtube.com/results")
        c?.queryItems = [URLQueryItem(name: "search_query", value: name + " exercise how to")]
        return c?.url
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { NunaBareIcon("xmark") }.buttonStyle(.plain).accessibilityLabel(Text("Close"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).textCase(nil)
                    Text("How it is done · YouTube").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Spacer(minLength: 8)
                if let url = Self.url(for: name) {
                    Button { openURL(url) } label: { NunaBareIcon("arrow.up.right.square") }.buttonStyle(.plain).accessibilityLabel(Text("Open in the browser"))
                }
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 6)
            ZStack {
                if let url = Self.url(for: name) { NunaWebView(url: url, loading: $loading) } else { Text("This video could not be opened.").foregroundStyle(NunaPalette.textSecondary) }
                if loading { ProgressView().tint(NunaPalette.textSecondary) }
            }
            Text("Opens YouTube. Only the exercise name is sent.").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

private struct NunaWebView: UIViewRepresentable {
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
