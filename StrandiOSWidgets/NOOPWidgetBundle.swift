import WidgetKit
import SwiftUI

/// The widget extension entry point. Bundles the Nuna widgets (Score, Vital sign, Anya, Steps), the Rings and Ring 2 widgets,
/// the heart-rate trace widget (#1957), the stress curve widget (#2040), the live-HR Live Activity, the Lift Log session
/// Live Activity, and the strap-sync Live Activity.
@main
struct NOOPWidgetBundle: WidgetBundle {
    var body: some Widget {
        NunaScoreWidget()
        NunaVitalWidget()
        NunaAnyaWidget()
        NunaStepsWidget()
        PHMNRingsWidget()
        NOOPRing2Widget()
        NOOPLiveActivity()
        HeartRateWidget()
        StressWidget()
        LiftLiveActivity()
        SyncLiveActivity()
    }
}
