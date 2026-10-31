#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The zoomed stress chart: the last 12 hours across the whole screen, turned on its side the way a landscape view reads, with a way back at
/// the bottom left. The app is portrait-only on iPhone, so the view is rotated rather than waiting for the phone to rotate; turn the phone
/// a quarter turn and it reads upright.
struct NunaStressZoomScreen: View {
    let points: [DaytimeStress.HourPoint]
    let workouts: [WorkoutRow]
    let sleep: ClosedRange<Int>?
    let domain: ClosedRange<Int>?
    let showsNow: Bool
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                NunaStressMonitorChart(points: points, workouts: workouts, showsNow: showsNow, sleep: sleep, zoomed: true,
                                       onZoom: onClose, reads: true, domain: domain)
                    .padding(.leading, 60).padding(.trailing, 10).padding(.top, 20).padding(.bottom, 46)
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(.nuna(size: 23, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 52, height: 52).contentShape(Rectangle())
                }
                .padding(.leading, 18).padding(.bottom, 6).accessibilityLabel(Text("Back"))
            }
            .frame(width: geo.size.height, height: geo.size.width)
            .rotationEffect(.degrees(90))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
    }
}
#endif
