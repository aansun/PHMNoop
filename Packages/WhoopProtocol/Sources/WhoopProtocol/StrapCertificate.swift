import Foundation

/// What a strap's own console says about its stored certificate.
///
/// The firmware narrates over CONSOLE_LOGS, and one of its lines is "BLE: Stored certificate is valid". PHMN does not know what the certificate is for,
/// so nothing here says more than the strap did: the verdict is read from the strap's own words, and a line about a certificate in words not known here
/// is kept as it was written and given no verdict. Pure.
public struct StrapCertificateReport: Equatable, Sendable {
    public enum Verdict: String, Codable, Equatable, Sendable {
        case valid
        case invalid
    }

    /// nil when the line mentions a certificate but says neither.
    public let verdict: Verdict?
    /// The strap's line without its boot count and clock.
    public let message: String

    public init(verdict: Verdict?, message: String) {
        self.verdict = verdict; self.message = message
    }

    /// Reads one whole console line; nil when it is not about a certificate.
    public static func read(line: String) -> StrapCertificateReport? {
        var text = line.unicodeScalars.filter { $0.value >= 0x20 }.reduce(into: "") { $0.unicodeScalars.append($1) }
        // "7, 123456789: BLE: Stored certificate is valid": the stamp is the strap's boot count and clock.
        if let stamp = text.range(of: #"^\s*\d+,\s*\d+:\s*"#, options: .regularExpression) { text.removeSubrange(stamp) }
        text = text.trimmingCharacters(in: .whitespaces)
        let lower = text.lowercased()
        guard lower.contains("certificate") else { return nil }
        // The negative wordings first: "invalid" and "not valid" both hold the word "valid".
        let bad = lower.range(of: #"certificate\b.*\b(invalid|not valid|expired|revoked)\b|\b(invalid|expired|revoked) (stored )?certificate"#, options: .regularExpression) != nil
        let good = lower.range(of: #"certificate is valid\b"#, options: .regularExpression) != nil
        return StrapCertificateReport(verdict: bad ? .invalid : (good ? .valid : nil), message: String(text.prefix(120)))
    }
}

/// Joins the console's fixed-size chunks back into lines and picks out the ones about the certificate. A line routinely splits across frames, mid-word.
public struct StrapCertificateScanner: Sendable {
    private var tail = ""
    private var lastSequence: Int?
    /// Event records take places in the console's sequence, so a few missing numbers are ordinary; more than this means text was lost, and the
    /// half line held is dropped rather than joined to whatever comes next.
    private static let allowedStep = 6
    private static let longestLine = 400

    public init() {}

    public mutating func ingest(_ chunk: String, sequence: Int? = nil) -> [StrapCertificateReport] {
        if let sequence, let last = lastSequence {
            let step = (sequence - last + 256) % 256
            if step == 0 || step > Self.allowedStep { tail = "" }
        }
        lastSequence = sequence
        tail += chunk
        // Only finished lines are read: half of "certificate is valid until ..." must not count as the whole of it.
        var lines = tail.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        tail = lines.removeLast()
        if tail.count > Self.longestLine { tail = String(tail.suffix(Self.longestLine)) }
        return lines.compactMap(StrapCertificateReport.read(line:))
    }
}

/// What one strap has reported over time, so that a change can be followed up.
public struct StrapCertificateLog: Codable, Equatable, Sendable {
    public struct Change: Codable, Equatable, Sendable {
        public let verdict: StrapCertificateReport.Verdict
        public let at: Date
    }

    /// The latest verdict the strap gave, if it ever gave one.
    public private(set) var verdict: StrapCertificateReport.Verdict?
    public private(set) var message: String?
    public private(set) var lastSeen: Date?
    /// Each time the verdict became different, the first one included, newest last.
    public private(set) var changes: [Change] = []
    /// A line about the certificate in words that give no verdict, and when it came.
    public private(set) var otherMessage: String?
    public private(set) var otherSeen: Date?

    public static let keptChanges = 20

    public init() {}

    /// The verdict before the current one, when there has been a change.
    public var previous: Change? { changes.count > 1 ? changes[changes.count - 2] : nil }
    /// Since when the current verdict has been reported.
    public var since: Date? { changes.last?.at }

    /// Adds a report; true when the verdict changed (the first verdict is not a change). The console can hand over lines the strap wrote while it was
    /// away, so a report older than the latest one concluded from is left out: it says nothing about now.
    @discardableResult
    public mutating func record(_ report: StrapCertificateReport, at date: Date) -> Bool {
        if report.verdict != nil, let seen = lastSeen, date < seen { return false }
        guard let new = report.verdict else {
            otherMessage = report.message; otherSeen = date
            return false
        }
        let changed = verdict != nil && verdict != new
        if verdict != new {
            changes.append(Change(verdict: new, at: date))
            if changes.count > Self.keptChanges { changes.removeFirst(changes.count - Self.keptChanges) }
        }
        verdict = new; message = report.message; lastSeen = date
        return changed
    }
}
