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
    let autoDetectWorkouts: Bool
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
            continuousHrv: PuffinExperiment.keepRealtimeForDataDefault,
            continuousHrvOvernightOnly: true,
            hrvWindowRaw: HrvWindow.whole.rawValue,
            sleepStagingV2: true,
            // Off for both: it only removes wake time, and PHMN's own nights already read 93.8% sleep efficiency against
            // WHOOP's 88.1% (Nov 2026), so it would move sleep further from WHOOP, not closer.
            motionAwareWake: false,
            // The WHOOP 0-21 Day Strain axis, as in the WHOOP app (display-only; the stored value stays 0-100).
            effortScaleRaw: EffortScale.whoop.rawValue,
            banisterEffort: PuffinExperiment.banisterEffortDefault,
            autoDetectWorkouts: PuffinExperiment.autoDetectWorkoutsDefault,
            stressPersonalBaseline: false,
            // WHOOP 4.0 has materially less battery headroom than 5.0/MG, so protect its last
            // charge without slowing normal sync on the longer-lived generation.
            powerSaving: family == .whoop4,
            powerSavingBatteryPct: 20,
            pauseHrvOnLowBattery: true,
            lowRefresh: false
        )
    }

    /// Writes every value of this profile to the preferences the app reads, the same keys the Settings toggles use, so every
    /// screen that watches one of them follows. The caller then re-arms the strap stream, power saving and the scoring pass.
    func write(to d: UserDefaults = .standard) {
        d.set(modelRaw, forKey: "selectedWhoopModel")
        d.set(continuousHrv, forKey: PuffinExperiment.keepRealtimeForDataKey)
        d.set(continuousHrvOvernightOnly, forKey: PuffinExperiment.continuousHrvOvernightOnlyKey)
        d.set(hrvWindowRaw, forKey: UnitPrefs.hrvWindowKey)
        d.set(sleepStagingV2, forKey: PuffinExperiment.experimentalSleepV2Key)
        d.set(motionAwareWake, forKey: PuffinExperiment.motionAwareWakeKey)
        d.set(effortScaleRaw, forKey: UnitPrefs.effortScaleKey)
        d.set(banisterEffort, forKey: PuffinExperiment.banisterEffortKey)
        d.set(autoDetectWorkouts, forKey: PuffinExperiment.autoDetectWorkoutsKey)
        d.set(stressPersonalBaseline, forKey: PuffinExperiment.stressPersonalBaselineKey)
        d.set(powerSaving, forKey: PuffinExperiment.powerSavingKey)
        d.set(powerSavingBatteryPct, forKey: PuffinExperiment.powerSavingBatteryPctKey)
        d.set(!pauseHrvOnLowBattery, forKey: PuffinExperiment.pauseHrvDisabledKey)
        d.set(lowRefresh, forKey: PuffinExperiment.lowRefreshKey)
    }
}
