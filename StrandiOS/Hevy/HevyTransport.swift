#if os(iOS)
import Foundation
import StrandImport

/// The URLSession side of `HevyClient`: a GET to api.hevyapp.com with the key in the `api-key` header, and nothing else. No cookies, no
/// cache, no redirects to another host, a fixed base address and no body, so there is no way to send the key anywhere but Hevy or to
/// write anything to it.
enum HevyTransport {
    static let host = "api.hevyapp.com"

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.httpShouldSetCookies = false
        c.urlCache = nil; c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration: c, delegate: SameHostOnly(), delegateQueue: nil)
    }()

    /// Refuses a redirect to any host but Hevy's, so the key header is never replayed elsewhere.
    private final class SameHostOnly: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(request.url?.host == HevyTransport.host ? request : nil)
        }
    }

    static func live() -> HevyClient.Transport {
        { path, query, key in
            var c = URLComponents()
            c.scheme = "https"; c.host = host; c.path = path
            c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let url = c.url else { throw HevyClient.Failure.network("bad address") }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue(key, forHTTPHeaderField: "api-key")
            req.setValue("application/json", forHTTPHeaderField: "accept")
            let (data, response) = try await session.data(for: req)
            return HevyClient.Response(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        }
    }
}
#endif
