#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// How the start of the app stands, for the opening screen to wait on.
@MainActor
enum NunaLaunch {
    /// Today has read its figures.
    static var todayReady = false
    /// The opening screen has been put away. It belongs to the start of the app, not to every rebuild of the shell.
    static var done = false
}

/// The opening screen: the PHMN wordmark on black, ringed by a turning arc while the app reads its data. It takes over from the system's launch screen,
/// which shows the same wordmark in the same place, and gives way to Today once Today has its figures.
struct NunaLaunchCover: View {
    let repo: Repository
    let onDone: () -> Void

    /// Long enough to be seen as a screen of its own and not as a flash.
    private static let shortest = 0.9
    /// What Today is given once the database is read, should it not be the page the app opened on.
    private static let afterRead = 5.0
    /// The app is never held back longer than this.
    private static let longest = 15.0
    /// How many ticks in a row must come on time before the screen gives way. A fade begun while the app is still busy stops half way, with the page
    /// showing through the wordmark.
    private static let calmTicks = 5

    /// The figures are in: the screen fades, and then says it is done.
    @State private var leaving = false

    var body: some View {
        NunaLaunchArt(leaving: leaving) {
            NunaLaunch.done = true
            onDone()
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "PHMN"))
        .task {
            let start = Date()
            var readAt: Date?
            var last = start
            var calm = 0
            while !Task.isCancelled {
                let now = Date()
                let up = now.timeIntervalSince(start)
                calm = now.timeIntervalSince(last) < 0.1 ? calm + 1 : 0
                last = now
                if repo.loaded, readAt == nil { readAt = now }
                let overRead = readAt.map { now.timeIntervalSince($0) >= Self.afterRead } ?? false
                let due = up >= Self.shortest && (NunaLaunch.todayReady || overRead) && calm >= Self.calmTicks
                if due || up >= Self.longest { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard !Task.isCancelled else { return }
            leaving = true
        }
    }
}

/// What the opening screen draws. It is a UIKit view so that the turning of the ring and the fade at the end are both run by Core Animation, and stay
/// even while the app is busy starting.
private struct NunaLaunchArt: UIViewRepresentable {
    let leaving: Bool
    let onGone: () -> Void

    func makeUIView(context: Context) -> NunaLaunchArtView { NunaLaunchArtView() }
    func updateUIView(_ view: NunaLaunchArtView, context: Context) {
        if leaving { view.fadeAway(then: onGone) }
    }
}

private final class NunaLaunchArtView: UIView {
    /// The very picture of the system's launch screen, so nothing moves as the one takes over from the other.
    private let wordmark = UIImageView(image: UIImage(named: "LaunchWordmark"))
    private let track = CAShapeLayer()
    private let sweep = CAGradientLayer()
    private let arc = CAShapeLayer()
    private var going = false
    private static let ring: CGFloat = 176
    private static let width: CGFloat = 2.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(NunaPalette.launchGround)
        let ink = UIColor(NunaPalette.launchInk)
        track.fillColor = UIColor.clear.cgColor
        track.strokeColor = ink.withAlphaComponent(0.1).cgColor
        track.lineWidth = Self.width
        // A tail that grows out of nothing and ends bright, once round the circle.
        sweep.type = .conic
        sweep.startPoint = CGPoint(x: 0.5, y: 0.5)
        sweep.endPoint = CGPoint(x: 0.5, y: 0)
        sweep.colors = [ink.withAlphaComponent(0).cgColor, ink.withAlphaComponent(0).cgColor, ink.cgColor]
        sweep.locations = [0, 0.3, 1]
        arc.fillColor = UIColor.clear.cgColor
        arc.strokeColor = ink.cgColor
        arc.lineWidth = Self.width
        arc.lineCap = .round
        sweep.mask = arc
        layer.addSublayer(track)
        layer.addSublayer(sweep)
        addSubview(wordmark)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        wordmark.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let box = CGRect(x: bounds.midX - Self.ring / 2, y: bounds.midY - Self.ring / 2, width: Self.ring, height: Self.ring)
        let centre = CGPoint(x: Self.ring / 2, y: Self.ring / 2)
        let radius = Self.ring / 2 - Self.width
        track.frame = box
        track.path = UIBezierPath(arcCenter: centre, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath
        sweep.bounds = CGRect(origin: .zero, size: box.size)
        sweep.position = CGPoint(x: box.midX, y: box.midY)
        // Stops just short of the top, where the bright end of the tail is, so that end is round and not cut by the start of the gradient.
        arc.path = UIBezierPath(arcCenter: centre, radius: radius, startAngle: -.pi / 2 + 0.03, endAngle: 1.5 * .pi - 0.03, clockwise: true).cgPath
        turn()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        turn()
    }

    /// Fades the screen out, once, and reports when it has gone.
    func fadeAway(then done: @escaping () -> Void) {
        guard !going else { return }
        going = true
        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseOut, animations: { self.alpha = 0 }, completion: { _ in done() })
    }

    /// Core Animation drops an animation when its view leaves the window, so it is added again whenever the view is back.
    private func turn() {
        guard window != nil, sweep.animation(forKey: "turn") == nil else { return }
        let spin: CABasicAnimation
        if UIAccessibility.isReduceMotionEnabled {
            spin = CABasicAnimation(keyPath: "opacity")
            spin.fromValue = 1
            spin.toValue = 0.35
            spin.autoreverses = true
            spin.duration = 0.9
        } else {
            spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * Double.pi
            spin.duration = 1.2
        }
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        sweep.add(spin, forKey: "turn")
    }
}
#endif
