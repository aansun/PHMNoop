#if os(iOS)
import Foundation
import StrandAnalytics

/// The URLSession side of `EnvironmentClient`: a GET over https to one of the two fixed hosts, and nothing else. No cookies, no cache,
/// no redirect to another host, no body, so a key can only reach the service it belongs to and nothing can be written to either.
enum EnvironmentTransport {
    private static let hosts: Set<String> = [EnvironmentClient.openWeatherHost, EnvironmentClient.iqAirHost]

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.httpShouldSetCookies = false
        c.urlCache = nil; c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c, delegate: SameHostOnly(), delegateQueue: nil)
    }()

    /// Refuses a redirect to any host but the two, so a key in the address is never replayed elsewhere.
    private final class SameHostOnly: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(request.url?.host.map(EnvironmentTransport.hosts.contains) == true && request.url?.scheme == "https" ? request : nil)
        }
    }

    static func live() -> EnvironmentClient.Transport {
        { host, path, query in
            guard hosts.contains(host) else { throw EnvironmentClient.Failure.noData }
            var c = URLComponents()
            c.scheme = "https"; c.host = host; c.path = path
            c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let url = c.url else { throw EnvironmentClient.Failure.noData }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "accept")
            let (data, response) = try await session.data(for: req)
            return EnvironmentClient.Response(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        }
    }
}
#endif
