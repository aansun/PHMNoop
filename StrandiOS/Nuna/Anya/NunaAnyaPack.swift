#if os(iOS)
import Foundation
import StrandAnalytics

/// The data a module's questions need that the general summary does not carry: the strap's live status for the Device module, the food and weight picture
/// for Nutrition. Without it she has nothing to answer from and says she cannot ("I am not a device"). Plain sentences, no raw readings, and only for the
/// module being asked about.
@MainActor
enum NunaAnyaPack {
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
