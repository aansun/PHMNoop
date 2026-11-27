#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopProtocol

/// Device Settings: what the strap itself says about its stored certificate, since when, and whether that has changed. PHMN does not know what the
/// certificate is for: the card repeats the strap and draws no conclusion of its own.
struct NunaStrapCertificateCard: View {
    let deviceId: String
    @EnvironmentObject private var live: LiveState

    /// What the demo launch shows; never stored, so a demo cannot be mistaken later for something a strap said.
    @State private var demoLog: StrapCertificateLog?

    /// A debug build launched with `--demo-strapcert` shows the card although no strap has been heard from.
    static var demo: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("--demo-strapcert")
        #else
        return false
        #endif
    }

    var body: some View {
        let log = demoLog ?? live.strapCertificate(for: deviceId)
        NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: icon(log?.verdict)).font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 42, height: 42).background(NunaPalette.glassStrong, in: Circle())
                    Text("Strap certificate").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textPrimary).lineLimit(2)
                    Spacer(minLength: 8)
                    Text(word(log?.verdict)).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(tint(log?.verdict)).lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 10).frame(height: 28).background(NunaPalette.tint(tint(log?.verdict)), in: Capsule())
                }
                if let log, let seen = log.lastSeen {
                    VStack(alignment: .leading, spacing: 4) {
                        line(String(localized: "Last reported \(moment(seen))"), strong: true)
                        if let previous = log.previous, let since = log.since {
                            line(String(localized: "Changed from \(plain(previous.verdict)) on \(moment(since))"), strong: true)
                        } else if let since = log.since {
                            line(String(localized: "Reported since \(moment(since))"))
                        }
                        if let message = log.message { line(message) }
                        if let other = log.otherMessage, let at = log.otherSeen, at > seen { line(String(localized: "Another line from the strap: \(other)")) }
                    }
                } else if let other = log?.otherMessage {
                    line(String(localized: "Another line from the strap: \(other)"))
                } else {
                    line(String(localized: "The strap has not said anything about it yet. PHMN reads it from the strap's log while connected."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        #if DEBUG
        // `--demo-strapcert valid|invalid`: with no strap on hand, the card as it reads when the strap reports that, after a day of reporting valid.
        .onAppear {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "--demo-strapcert"), i + 1 < args.count, ["valid", "invalid"].contains(args[i + 1]) else { return }
            var demo = StrapCertificateLog()
            for (word, ago) in [("valid", 86_400.0), (args[i + 1], 0)] {
                if let report = StrapCertificateReport.read(line: "BLE: Stored certificate is " + word) { demo.record(report, at: Date().addingTimeInterval(-ago)) }
            }
            demoLog = demo
        }
        #endif
    }

    private func line(_ text: String, strong: Bool = false) -> some View {
        Text(verbatim: text).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(strong ? NunaPalette.textPrimary : NunaPalette.textSecondary)
            .textCase(nil).fixedSize(horizontal: false, vertical: true)
    }

    private func word(_ v: StrapCertificateReport.Verdict?) -> LocalizedStringKey {
        switch v { case .valid: return "Valid"; case .invalid: return "Not valid"; case nil: return "No report yet" }
    }
    private func plain(_ v: StrapCertificateReport.Verdict) -> String { v == .valid ? String(localized: "Valid") : String(localized: "Not valid") }
    private func tint(_ v: StrapCertificateReport.Verdict?) -> Color {
        switch v { case .valid: return NunaPalette.charge; case .invalid: return NunaPalette.alert; case nil: return NunaPalette.textSecondary }
    }
    private func icon(_ v: StrapCertificateReport.Verdict?) -> String {
        switch v { case .valid: return "checkmark.seal"; case .invalid: return "xmark.seal"; case nil: return "seal" }
    }
    private func moment(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return f.string(from: date)
    }
}
#endif
