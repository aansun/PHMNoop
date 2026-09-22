import Foundation
import WhoopProtocol

/// The safe, user-facing settings bundle for a WHOOP family. This deliberately excludes firmware
/// experiments and persistent strap writes: applying a preset should improve the normal data path,
/// never silently change an experimental device flag.
struct WhoopDeviceConfiguration: Equatable {
    let family: DeviceFamily
    let modelRaw: String
    let continuousHrv: Bool
    let continuousHrvOvernightOnly: Bool
    let hrvWindowRaw: String
    let sleepStagingV2: Bool
    let motionAwareWake: Bool
    let effortScaleRaw: String
    let banisterEffort: Bool
    let stressPersonalBaseline: Bool
    let powerSaving: Bool
    let powerSavingBatteryPct: Int
    let pauseHrvOnLowBattery: Bool
    let lowRefresh: Bool

    static func recommended(for family: DeviceFamily) -> WhoopDeviceConfiguration {
        WhoopDeviceConfiguration(
            family: family,
            modelRaw: family == .whoop4 ? WhoopModel.whoop4.rawValue : WhoopModel.whoop5mg.rawValue,
            // Overnight capture is the best data/battery balance for both generations. It keeps the
            // dense R-R stream available for sleep/recovery without making daytime battery cost mandatory.
            continuousHrv: true,
            continuousHrvOvernightOnly: true,
            hrvWindowRaw: HrvWindow.whole.rawValue,
            sleepStagingV2: true,
            // WHOOP 5/MG has richer motion records; the engine still self-gates when a night is sparse.
            motionAwareWake: family == .whoop5,
            // Keep NOOP's native axis as the honest default; the WHOOP 0-21 scale is display-only.
            effortScaleRaw: EffortScale.hundred.rawValue,
            banisterEffort: false,
            stressPersonalBaseline: false,
            // WHOOP 4.0 has materially less battery headroom than 5.0/MG, so protect its last
            // charge without slowing normal sync on the longer-lived generation.
            powerSaving: family == .whoop4,
            powerSavingBatteryPct: 20,
            pauseHrvOnLowBattery: true,
            lowRefresh: false
        )
    }
}
