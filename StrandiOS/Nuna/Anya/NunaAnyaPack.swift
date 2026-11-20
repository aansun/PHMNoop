#if os(iOS)
import Foundation
import StrandAnalytics

/// The data a module's questions need that the general summary does not carry: the strap's live status for the Device module, the food and weight picture
/// for Nutrition. Without it she has nothing to answer from and says she cannot ("I am not a device"). Plain sentences, no raw readings, and only for the
/// module being asked about.
@MainActor
enum NunaAnyaPack {
    /// The answer to a question about the strap, worked out on the phone from what the app itself knows (status, charging, last sync) and what the Device screen does.
    /// A model has no strap facts to answer from and either refuses or invents a hardware step, so this module's questions are not sent to one.
    static func deviceAnswer(question: String, live: LiveState) -> String {
        let q = question.lowercased()
        let battery = live.batteryPct.map { Int($0.rounded()) }
        let status: String = {
            guard live.connected else { return String(localized: "The strap is not connected right now.") }
            guard let battery else { return String(localized: "The strap is connected.") }
            return live.isCharging ? String(localized: "The strap is connected and charging, at \(battery)%.") : String(localized: "The strap is connected, at \(battery)% and not charging.")
        }()
        if q.contains("charg") || q.contains("battery") {
            let steps = String(localized: "To charge it, put the strap on its charger. The Device screen shows Charging as soon as the level starts to rise, and the time to full once the pace is clear. The estimate of how long a charge lasts comes back after you take it off the charger.")
            return status + " " + steps
        }
        let last = live.lastSyncedAt.map { String(localized: "Its last sync was at \(NunaDeviceFormat.clock($0)).") } ?? String(localized: "It has not synced since the app opened.")
        let steps = String(localized: "If it keeps dropping: keep it within a few metres of the phone, check that Bluetooth is on and that the strap is not connected to another phone or app, then use Reconnect in Device Settings.")
        // A strap that has never synced may not be paired yet.
        let pair = live.lastSyncedAt == nil ? " " + String(localized: "If you have not paired it yet, add it first from Device Settings.") : ""
        return status + " " + last + " " + steps + pair
    }

    static func text(for module: NunaAnyaModule, repo: Repository, profile: ProfileStore, live: LiveState) async -> String? {
        switch module {
        case .device:
            var lines = ["STRAP (its live status on this phone):"]
            lines.append("  connection: " + (live.connected ? "connected" : "not connected"))
            if let b = live.batteryPct { lines.append("  battery: \(Int(b.rounded()))%" + (live.isCharging ? ", charging" : ", not charging")) }
            if live.isCharging, let h = live.chargeHoursToFull { lines.append("  time to full at the pace so far: about \(NunaDeviceFormat.fullIn(h))") }
            else if let e = live.batteryEstimate { lines.append("  estimated time left on this charge: about \(NunaDeviceFormat.remaining(e.remainingHours))") }
            if let t = live.lastSyncedAt { lines.append("  last sync: " + NunaDeviceFormat.clock(t)) } else { lines.append("  last sync: none since the app opened") }
            if let fw = live.strapFirmware { lines.append("  firmware: \(fw)") }
            if let err = live.lastSyncError { lines.append("  last sync problem: \(err)") }
            return lines.joined(separator: "\n")
        case .nutrition:
            let snap = await NunaNutritionSnapshot.build(repo: repo, profile: profile, includeLabBook: false)
            return snap.isEmpty ? nil : "NUTRITION (the person's own food and weight data):\n" + String(snap.prefix(1400))
        case .trends:
            // Four weeks, oldest first: the picture a question about the month needs and a week of days cannot give.
            let days = repo.days
            guard days.count >= 14 else { return nil }
            let scale = AICoachEngine.strainScale()
            var rows: [String] = []
            for w in (0..<4).reversed() {
                let hi = days.count - w * 7, lo = max(0, hi - 7)
                guard hi > lo else { continue }
                let block = Array(days[lo..<hi])
                func mean(_ vs: [Double]) -> Double? { vs.isEmpty ? nil : vs.reduce(0, +) / Double(vs.count) }
                var parts: [String] = []
                if let v = mean(block.compactMap(\.recovery)) { parts.append("recovery \(Int(v.rounded()))") }
                if let v = mean(block.compactMap { $0.strain.map { UnitFormatter.effortValue($0, scale: scale) } }) { parts.append(String(format: "daily strain %.1f", v)) }
                if let v = mean(block.compactMap { $0.totalSleepMin.map { $0 / 60 } }) { parts.append(String(format: "sleep %.1fh", v)) }
                if let v = mean(block.compactMap(\.avgHrv)) { parts.append("HRV \(Int(v.rounded()))ms") }
                rows.append("  \(block.first?.day ?? "") to \(block.last?.day ?? ""): " + parts.joined(separator: ", "))
            }
            return rows.isEmpty ? nil : "WEEKLY AVERAGES (oldest first):\n" + rows.joined(separator: "\n")
        default:
            return nil
        }
    }
}
#endif
