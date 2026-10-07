#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// Shows the gym session full screen over whatever is on top, without closing it.
///
/// The session used to be a SwiftUI cover on the app root, and a cover cannot open over a sheet. Gym lives in sheets (Quick actions,
/// Workouts from Today), so a start from there first had to close its sheet, wait, and only then open the session: the screen went
/// away and came back late. UIKit can present from the top-most controller, so the session opens at once over the Gym page, and
/// minimising it returns to that page.
@MainActor
final class NunaLiftSessionPresenter {
    private weak var host: SessionHost?
    private var generation = 0

    /// A hosting controller that reports when it has left the screen.
    private final class SessionHost: UIHostingController<AnyView> {
        var onGone: (() -> Void)?
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isBeingDismissed || view.window == nil { onGone?() }
        }
    }

    func present(repo: Repository, model: AppModel, session: LiftSessionController, router: NavRouter) {
        guard host == nil else { return }
        generation += 1
        attempt(generation: generation, tries: 0, repo: repo, model: model, session: session, router: router)
    }

    func dismiss() {
        generation += 1
        // Asked of the controller below, so the session goes with anything open above it (the finish sheet); asked of the session itself it
        // would close only that sheet.
        host?.presentingViewController?.dismiss(animated: true)
        host = nil
    }

    private func attempt(generation: Int, tries: Int, repo: Repository, model: AppModel, session: LiftSessionController, router: NavRouter) {
        guard generation == self.generation, session.isPresented, session.engine != nil else { return }
        guard let top = Self.topController() else { return retry(generation, tries, repo, model, session, router) }
        // A sheet that is still closing (the exercise picker that has just handed over its choice) cannot present anything yet.
        if top.isBeingDismissed || top.isBeingPresented || top.transitionCoordinator != nil {
            return retry(generation, tries, repo, model, session, router)
        }
        let root = NunaLiftSessionView()
            .environmentObject(repo).environmentObject(session).environmentObject(model)
            .environmentObject(model.ble).environmentObject(model.live).environmentObject(model.profile)
            .environmentObject(model.behavior).environmentObject(model.intelligence).environmentObject(model.coach)
            .environmentObject(router)
            .environment(\.locale, AppLanguage.activeLocale)
        let vc = SessionHost(rootView: AnyView(root))
        vc.modalPresentationStyle = .fullScreen
        // The adaptive palette resolves from the controller's style; a hosted controller does not inherit the shell's choice by itself.
        vc.overrideUserInterfaceStyle = NunaTheme.colorScheme.map { $0 == .dark ? .dark : .light } ?? .unspecified
        vc.onGone = { [weak self, weak session] in
            self?.host = nil
            if session?.isPresented == true { session?.isPresented = false }
        }
        host = vc
        top.present(vc, animated: true)
    }

    private func retry(_ generation: Int, _ tries: Int, _ repo: Repository, _ model: AppModel, _ session: LiftSessionController, _ router: NavRouter) {
        guard tries < 40 else { session.isPresented = false; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.attempt(generation: generation, tries: tries + 1, repo: repo, model: model, session: session, router: router)
        }
    }

    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return nil }
        while let next = top.presentedViewController { top = next }
        return top
    }
}
#endif
