#if os(iOS)
import SwiftUI
import StrandDesign

/// The two photos of an exercise as a short loop: the start, a pause, the move to the end, a pause, and back. Tap to pause on a
/// frame; with Reduce Motion on it starts paused. The photos are the bundled ones, so nothing is downloaded.
struct NunaExerciseDemo: View {
    let exercise: NunaLibraryExercise
    var height: CGFloat = 230
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var paused = false
    @State private var pausedAt = 0.0

    /// One loop, in seconds: hold the start, move, hold the end, move back.
    private static let hold = 0.9, move = 0.7
    private static var period: Double { 2 * (hold + move) }

    /// 0 at the start position, 1 at the end, eased.
    private static func phase(at t: Double) -> Double {
        let x = t.truncatingRemainder(dividingBy: period)
        func ease(_ u: Double) -> Double { u * u * (3 - 2 * u) }
        if x < hold { return 0 }
        if x < hold + move { return ease((x - hold) / move) }
        if x < 2 * hold + move { return 1 }
        return 1 - ease((x - 2 * hold - move) / move)
    }

    var body: some View {
        let first = exercise.frames.first.flatMap(NunaExerciseLibrary.image)
        let last = exercise.frames.count > 1 ? NunaExerciseLibrary.image(exercise.frames[1]) : nil
        ZStack {
            if let first, let last, !(reduceMotion && !paused) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { tl in
                    let p = paused ? Self.phase(at: pausedAt) : Self.phase(at: tl.date.timeIntervalSinceReferenceDate)
                    ZStack {
                        frame(first)
                        frame(last).opacity(p)
                    }
                }
            } else if let first {
                frame(first)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: paused ? "play.fill" : "pause.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(.black.opacity(0.45), in: Circle()).padding(10)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !paused { pausedAt = Date().timeIntervalSinceReferenceDate }
            paused.toggle()
        }
        .onAppear { paused = reduceMotion }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: exercise.name))
        .accessibilityHint(Text("Shows the start and the end of the movement. Double tap to pause."))
    }

    private func frame(_ image: UIImage) -> some View {
        Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: height).clipped()
    }
}
#endif
