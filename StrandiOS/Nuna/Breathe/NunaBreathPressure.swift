#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// Blood pressure around a breathing session, for someone who already records it: a reading before the start and one after the end, and the change
// between them. Nobody without a reading is asked to take one.

/// Above Start: the reading that will count as "before", or the way to add one.
struct NunaBPBeforeRow: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var readings: [NunaBPReading] = []
    @State private var adding = false

    private var recent: NunaBPReading? {
        let now = Int(Date().timeIntervalSince1970)
        return readings.last { $0.takenAt <= now && now - $0.takenAt <= PressureLinks.breathWindow }
    }

    var body: some View {
        // A stack, not a Group: the readings are loaded by the task below, and an empty Group would never run it.
        VStack(spacing: 0) {
            if !readings.isEmpty {
                if let r = recent {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.nuna(size: 13, weight: .bold))
                        Text(verbatim: String(localized: "Before: \(r.text) mmHg")).font(.nuna(size: 12.5, weight: .semibold)).textCase(nil)
                    }
                    .foregroundStyle(NunaPalette.textSecondary).frame(minHeight: 28)
                } else {
                    Button { adding = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: NunaIcons.bloodPressure).font(.nuna(size: 13, weight: .semibold))
                            Text("Measure blood pressure first (optional)").font(.nuna(size: 12.5, weight: .semibold)).textCase(nil).underline()
                        }
                        .foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") { readings = await NunaBP.load(repo) }
        .sheet(isPresented: $adding) { NunaBPAddSheet { drafts in await NunaLabStore.save(drafts, repo: repo) } }
    }
}

/// On a session's report: its two readings and the change. Just after a session it also offers the "after" reading; an older session shows the card
/// only when both were taken.
struct NunaBPBreathCard: View {
    let startTs: Int
    let seconds: Int

    @EnvironmentObject private var repo: Repository
    @ObservedObject private var changes = NunaDataChanges.shared
    @State private var readings: [NunaBPReading] = []
    @State private var adding = false

    private var session: PressureLinks.Session { .init(start: startTs, end: startTs + seconds) }
    /// Whether a reading taken now would still count as "after".
    private var justEnded: Bool { Int(Date().timeIntervalSince1970) - session.end <= PressureLinks.breathWindow }

    var body: some View {
        let linked = readings.map(\.linked)
        let before = PressureLinks.before(linked, session), after = PressureLinks.after(linked, session)
        let shown = !readings.isEmpty && (justEnded || (before != nil && after != nil))
        // A stack, not a Group, so the task runs while there is nothing to show yet.
        VStack(spacing: 0) {
            if shown {
                NunaCard(small: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: NunaIcons.bloodPressure).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            Text("Blood pressure").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        }
                        HStack(alignment: .top, spacing: 14) {
                            figure("Before", before)
                            figure("After", after)
                        }
                        if let before, let after {
                            let s = Int((after.systolic - before.systolic).rounded()), d = Int((after.diastolic - before.diastolic).rounded())
                            note(String(localized: "Change: \(Self.signed(s)) / \(Self.signed(d)) mmHg. Sitting still lowers a reading too."))
                        } else if before == nil {
                            note(String(localized: "Next time, measure before you start to see the change."))
                        }
                        if after == nil, justEnded {
                            Button { adding = true } label: {
                                Text("Add the after reading").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                    .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 46)
                                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        // With nothing to show it also gives back the gap its place in the page would leave.
        .padding(.bottom, shown ? 0 : -NunaSpacing.section)
        .task(id: "\(repo.refreshSeq)-\(changes.seq)") { readings = await NunaBP.load(repo) }
        .sheet(isPresented: $adding) { NunaBPAddSheet { drafts in await NunaLabStore.save(drafts, repo: repo) } }
    }

    private static func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : (v < 0 ? "−\(-v)" : "0") }

    private func figure(_ title: LocalizedStringKey, _ r: PressureLinks.Reading?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            nunaTrendsCap(title)
            Text(verbatim: r.map { NunaBP.text($0.systolic, $0.diastolic) } ?? "–").font(.nuna(size: 24, weight: .bold, design: NunaType.design))
                .foregroundStyle(r.map { NunaBPCategory.of($0.systolic, $0.diastolic).color } ?? NunaPalette.textMuted).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
    }
}
#endif
