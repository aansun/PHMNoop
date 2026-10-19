#if os(iOS)
import Foundation
import WhoopProtocol

/// The newest PHMN releases, read from the project's public GitHub releases, so What's new shows a version the moment it is published
/// without a new build. The bundled `PHMNChangelog` stays as the offline baseline; a release in the feed that the bundle does not
/// carry is added on top. Same switch and same public endpoint as the daily update check (Settings › Check for updates): nothing
/// about the wearer is sent, and with the switch off no request is made.
@MainActor
final class PHMNChangelogFeed: ObservableObject {
    static let shared = PHMNChangelogFeed()

    @Published private(set) var releases: [PHMNChangelog.Release]

    private static let endpoint = URL(string: "https://api.github.com/repos/aansun/PHMNoop/releases?per_page=12")!
    private static let cacheKey = "phmn.changelog.feed"
    private static let checkedKey = "phmn.changelog.feed.checkedAt"
    /// An hour is plenty: releases come days apart, and What's new can be opened many times.
    private static let minInterval: TimeInterval = 3600

    private struct Stored: Codable {
        let version: String, title: String, date: String, items: [String]
    }

    private init() {
        releases = Self.loadCache()
    }

    /// Reads the feed unless it was read within the hour. Silent on any failure: the cache (or the bundle) stays on screen.
    func refresh(force: Bool = false) async {
        guard UpdateWatch.isEnabled else { return }
        let d = UserDefaults.standard
        let last = d.double(forKey: Self.checkedKey)
        let now = Date().timeIntervalSince1970
        if !force, last > 0, now >= last, now - last < Self.minInterval { return }
        d.set(now, forKey: Self.checkedKey)
        var req = URLRequest(url: Self.endpoint, timeoutInterval: 12)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let parsed = list.compactMap(Self.release(from:))
        guard !parsed.isEmpty else { return }
        releases = parsed
        let stored = parsed.map { Stored(version: $0.version, title: $0.title, date: $0.date, items: $0.items) }
        if let data = try? JSONEncoder().encode(stored) { d.set(data, forKey: Self.cacheKey) }
    }

    private static func loadCache() -> [PHMNChangelog.Release] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let stored = try? JSONDecoder().decode([Stored].self, from: data) else { return [] }
        return stored.map { .init(version: $0.version, title: $0.title, date: $0.date, items: $0.items) }
    }

    /// One GitHub release as a changelog entry, nil for a draft, a pre-release or a body without bullets.
    private static func release(from json: [String: Any]) -> PHMNChangelog.Release? {
        guard json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String,
              let body = json["body"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard let parsed = parse(body: body) else { return nil }
        return .init(version: version, title: parsed.title, date: monthYear(json["published_at"] as? String), items: parsed.items)
    }

    /// The release body is "## PHMN x", a one-line summary, "### What's new" and its bullets, then other sections (Install, notes).
    /// The summary is the title and the bullets under What's new are the items.
    static func parse(body: String) -> (title: String, items: [String])? {
        var title: String?
        var items: [String] = []
        var inNew = false
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("###") {
                inNew = line.lowercased().contains("what's new") || line.lowercased().contains("whats new")
                continue
            }
            if line.hasPrefix("#") || line.isEmpty { continue }
            if inNew {
                if line.hasPrefix("- ") || line.hasPrefix("* ") { items.append(String(line.dropFirst(2))) }
                else if !items.isEmpty { items[items.count - 1] += " " + line }
            } else if title == nil {
                title = line
            }
        }
        guard !items.isEmpty else { return nil }
        return (title ?? "", items)
    }

    private static func monthYear(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f.string(from: date).capitalized(with: AppLanguage.activeLocale)
    }
}

extension PHMNChangelog {
    /// The bundled releases with the feed's newer ones on top, newest first; a version in both keeps the feed's wording.
    @MainActor static func merged(with feed: [Release]) -> [Release] {
        var byVersion: [String: Release] = [:]
        for r in releases { byVersion[r.version] = r }
        for r in feed { byVersion[r.version] = r }
        return byVersion.values.sorted { VersionCheck.isNewer($0.version, than: $1.version) }
    }
}
#endif
