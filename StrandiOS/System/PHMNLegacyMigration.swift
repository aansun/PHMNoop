import Foundation
import UIKit
import UserNotifications
import StrandDesign

/// One-time clean-up that points an install at PHMN, whatever it was upgraded from.
///
/// An install that began life as the original NOOP (or an earlier PHMN build) can carry state that no longer belongs: the old look, a
/// retired experience key, a cache full of old responses, notifications that were delivered under the old branding and an app-icon
/// choice that is no longer shipped. This runs once per install, before the first screen reads any of it. User data (the database,
/// settings the user picked in PHMN, Keychain) is never touched.
enum PHMNLegacyMigration {
    private static let doneKey = "phmn.legacyMigration.v1"
    /// The only alternate icon this build ships; anything else in `alternateIconName` is left over from an older build.
    private static let knownAlternateIcons: Set<String> = ["AppIcon-Butterfly"]

    static func runIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: doneKey) else { return }
        d.set(true, forKey: doneKey)

        // PHMN opens in Nuna. A new install has no value yet; an old one may still say the original look.
        d.set(ExperienceMode.nuna.rawValue, forKey: ExperienceMode.storageKey)
        // The retired placeholder that the removed Settings picker used to write.
        d.removeObject(forKey: "app.experience")

        // Regenerable leftovers: cached network responses, the Caches folder, the temporary folder.
        URLCache.shared.removeAllCachedResponses()
        let fm = FileManager.default
        for dir in [fm.urls(for: .cachesDirectory, in: .userDomainMask).first, URL(fileURLWithPath: NSTemporaryDirectory())].compactMap({ $0 }) {
            for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: item)
            }
        }

        // Notifications already in Notification Center were posted by an older build. Pending ones are left alone: the alarm and the
        // reminders own them and re-plan them themselves.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        // An alternate icon this build does not ship would leave the Home Screen on a stale picture: fall back to the primary icon.
        Task { @MainActor in
            let app = UIApplication.shared
            guard app.supportsAlternateIcons, let name = app.alternateIconName, !knownAlternateIcons.contains(name) else { return }
            try? await app.setAlternateIconName(nil)
        }
    }
}
