#if os(iOS)
import SwiftUI
import StrandDesign

/// Pulling Today down: the strap is asked to sync, and a banner under the day says what happened, for about three seconds.
///
/// "Caught up" means the strap's history was fetched (or there was nothing new) and the time is when that last finished. When the strap is not
/// connected nothing is asked of it, and the banner says so with the time of the last sync there was.
@MainActor
final class NunaPullSync: ObservableObject {
    enum Phase: Equatable {
        case syncing
        case caughtUp(Date?)
        case offline(Date?)
    }

    @Published private(set) var phase: Phase?
    weak var app: AppModel?
    private var hideTask: Task<Void, Never>?

    /// How long a result stays up. A debug build launched with `--hold-sync-banner` keeps it for 30 s, to look at it.
    static var visibleSeconds: UInt64 {
        #if DEBUG
        if CommandLine.arguments.contains("--hold-sync-banner") { return 30 }
        #endif
        return 3
    }
    /// The longest a sync is waited for before the banner reports what it has.
    private static let giveUpSeconds: Double = 20

    private func set(_ p: Phase?) { withAnimation(.easeInOut(duration: 0.25)) { phase = p } }

    private var lastSync: Date? { app?.live.lastSyncedAt.map { Date(timeIntervalSince1970: $0) } }

    /// The refresh action: returns once the banner shows its result.
    func run() async {
        hideTask?.cancel()
        guard let app else { return }
        #if DEBUG
        // `--demo-sync`: with no strap on hand, pretend a sync went through, to look at the banner.
        if CommandLine.arguments.contains("--demo-sync") {
            set(.syncing)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            set(.caughtUp(Date()))
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.visibleSeconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.set(nil)
            }
            return
        }
        #endif
        if app.live.connected, app.live.bonded {
            set(.syncing)
            app.ble.syncNow()
            // The offload starts a moment after the request; wait for it to begin, then for it to end.
            try? await Task.sleep(nanoseconds: 800_000_000)
            let began = Date()
            while app.live.backfilling, Date().timeIntervalSince(began) < Self.giveUpSeconds, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            set(.caughtUp(lastSync))
        } else {
            set(.offline(lastSync))
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.visibleSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.set(nil)
        }
    }
}

/// Hands the app model to the sync without Today observing it (the model changes every second while the strap streams).
struct NunaPullSyncBinder: View {
    @EnvironmentObject private var app: AppModel
    let sync: NunaPullSync
    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear { sync.app = app }
        #if DEBUG
        // `--demo-sync` also runs one sync at launch, so the banner can be looked at without a pull.
            .task {
                guard CommandLine.arguments.contains("--demo-sync") else { return }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await sync.run()
            }
        #endif
    }
}

/// "Strap not in use" under the day for as long as a paired strap is not connected: it stays until the strap is back, unlike the sync banner,
/// which is a result that goes after a few seconds. Nothing to put away: it goes by itself when the strap connects.
struct NunaStrapIdleBanner: View {
    static let height: CGFloat = 64

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "applewatch.slash").font(.system(size: 20, weight: .light)).foregroundStyle(Color.white.opacity(0.7)).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("Strap not in use").font(.nuna(size: 13, weight: .heavy)).tracking(1.5).textCase(.uppercase).foregroundStyle(Color.white).lineLimit(1).minimumScaleFactor(0.7)
                Text("Put it on to keep recording").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.7)).textCase(nil).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(height: Self.height)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Mirrors "a paired strap has been off for a few seconds" into the screen. The wait keeps a reconnect that takes a moment (the app opening, the
/// strap changing link) from flashing the banner. Today itself does not observe the live state, which ticks with every heartbeat.
struct NunaStrapIdleWatcher: View {
    @Binding var idle: Bool
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var app: AppModel
    @State private var pending: Task<Void, Never>?
    /// A strap has been connected since the app started. Until then the first connection is still being made, which takes longer than a reconnect.
    private static var connectedSinceLaunch = false

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { update() }
            .onChange(of: live.connected) { _, _ in update() }
            .onDisappear { pending?.cancel() }
    }

    private var hasStrap: Bool { app.deviceRegistry?.devices.contains { $0.status == .active } ?? false }

    private func update() {
        pending?.cancel()
        if live.connected {
            Self.connectedSinceLaunch = true
            if idle { withAnimation(.easeInOut(duration: 0.25)) { idle = false } }
            return
        }
        let wait: UInt64 = Self.connectedSinceLaunch ? 6 : 20
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
            guard !Task.isCancelled, !live.connected, hasStrap else { return }
            withAnimation(.easeInOut(duration: 0.25)) { idle = true }
        }
    }
}

/// The strip under the day: a cloud and what it says on the left, when and a check on the right, on a black ground.
struct NunaSyncBanner: View {
    let phase: NunaPullSync.Phase
    static let height: CGFloat = 56

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(Color.white.opacity(0.55)).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.nuna(size: 13, weight: .heavy)).tracking(1.5).textCase(.uppercase).foregroundStyle(Color.white).lineLimit(1).minimumScaleFactor(0.7)
                // A strap that is not on the wrist has nothing to sync: say what to do, not only that it is away.
                if case .offline = phase {
                    Text("Put it on to sync").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6)).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 16).frame(height: Self.height)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch phase { case .syncing: return "arrow.triangle.2.circlepath.icloud"; case .caughtUp: return "cloud"; case .offline: return "icloud.slash" }
    }

    private var title: LocalizedStringKey {
        switch phase { case .syncing: return "Syncing…"; case .caughtUp: return "Data caught up"; case .offline: return "Strap not in use" }
    }

    @ViewBuilder private var trailing: some View {
        switch phase {
        case .syncing:
            ProgressView().tint(Color.white.opacity(0.7))
        case .caughtUp(let date):
            HStack(spacing: 14) {
                if let date { stamp("Synced to", date, NunaSyncBanner.green) }
                Image(systemName: "checkmark").font(.system(size: 20, weight: .semibold)).foregroundStyle(NunaSyncBanner.green)
            }
        case .offline(let date):
            if let date { stamp("Last sync", date, Color.white.opacity(0.6)) }
        }
    }

    private static let green = Color(red: 0.36, green: 0.86, blue: 0.56)

    private func stamp(_ caption: LocalizedStringKey, _ date: Date, _ tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(caption).font(.nuna(size: 13, weight: .heavy)).tracking(1.5).textCase(.uppercase).foregroundStyle(Color.white)
            Text(verbatim: Self.time(date)).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(tint).textCase(nil)
        }
    }

    private static func time(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: d)
    }
}
#endif
