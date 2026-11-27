import Foundation

/// What a `.noopbak` carries beyond the database and `settings.json`: the rest of what a person has made or chosen in PHMN, which the app keeps in UserDefaults
/// and in a few folders instead of the database.
///
/// Why a part of its own: the `settings.json` whitelist is a contract shared byte for byte with Android and is deliberately small (profile, units, effort scale).
/// PHMN keeps far more than that outside the database: the groups the programs are sorted into, the person's own exercises and notes, Anya's memory, the
/// weekly plan and goals, the breathing log, GPS routes, the hydration log, the notes and photos of a workout review, the choices that make the screens theirs.
/// Without them a restore brings back the rows and loses everything the screens were built from.
///
/// Two optional entries, both ignored by an importer that does not know them, so a backup stays a valid `.noopbak` everywhere:
///  - `phmn-defaults.plist`: a property list of the allowed UserDefaults keys, so every value (text, numbers, `Data` blobs, lists) comes back exactly as it was.
///  - `phmn-files/<path>`: the files of the few folders listed in `fileRoots`, under their path inside Application Support.
///
/// Left out on purpose, as the `settings.json` comments say: anything tied to a device or an install (the strap's id, alarm and sync state, caches, what was
/// already announced), tokens and sign-ins (they live in the Keychain, which a backup never reads), and the step calibration, which belongs to a strap.
/// A new `nuna.` setting is covered without a change here; anything else is added to the lists below.
enum PHMNBackupExtras {
    static let defaultsEntryName = "phmn-defaults.plist"
    static let filesPrefix = "phmn-files/"

    static let maxDefaultsBytes: Int64 = 16 * 1_048_576
    static let maxFileBytes: Int64 = 25 * 1_048_576
    static let maxTotalFileBytes: Int64 = 400 * 1_048_576

    // MARK: Which UserDefaults keys

    /// Whole families: everything the Nuna screens keep, and the settings of the older ones that Nuna still reads.
    private static let allowedPrefixes: [String] = [
        "nuna.",
        "noop.hydration",            // the tracking switch, the glass size and one entry list per day
        "noop.experiment.",          // the experiment in progress, the Strava and Hevy switches, what Strava has already been given
        "noop.audioCoaching.",
        "noop.caffeine.",
        "behavior.",
        "notif.",
        "journal.",
        "today.",
        "sleep.",
        "stress.",
        "units.",
        "effort.",
        "trend.",
        "compare.",
        "workout.",
        "workouts.",
        "breathe.",
        "coach.memor",               // Anya's memory and whether she may add to it
        "coach.aboutYou",            // what the person told Anya about themselves
        "anya.evening.",             // the evening check-in and its time
        "coach.conversationHistory",
        "coachBrief.enabled",
        "coachBrief.timeMinutes",
        "ai.",                       // the provider, the model and how Anya is to answer; the key itself is in the Keychain
    ]

    /// Single keys that do not fall in a family.
    private static let allowedKeys: Set<String> = [
        "noop.workoutRoutes",        // the GPS route of each workout
        "noop.appLanguage", "noop.coachEnabled", "noop.dayCycleMode", "noop.liquidTodayEnabled", "noop.bottomBarAutoHide", "noop.liveSessionsBeta",
        "noop.shortcutSync.enabled",
        "noopAutoDetectWorkouts", "noopBanisterEffort", "noopCycleAwareness", "noopCycleAwarenessHidden", "noopHrvReadiness", "noopJournalReminder",
        "noopStressPersonalBaseline", "noopContinuousHrv", "noopContinuousHrvOvernightOnly", "noopLowRefresh", "noopPowerSaving",
        "noopPowerSavingBatteryPct", "noopPowerSavingPauseHrvDisabled", "noopMotionAwareWake", "noopExperimentalSleepV2", "noopSpo2CandidateDisplay",
        "caffeine.intakes", "hydration", "hydrationImported", "moments", "mood", "sleepMarks", "sleep_mark", "period_start",
        "fitness_age", "vo2max_est", "vo2max_manual_src", "hrv.window",
        "appIcon.name", "experience.mode", "liveActivityDesign", "liveActivity.enabled", "liveActivity.sync.enabled", "more.expandedSections",
        "syncKeepScreenOn", "workoutKeepScreenOn",
    ]

    /// Parts of an allowed family that are state, not a choice: a flag that an alert was shown, the day something was last announced, a draft, a place.
    private static let deniedFragments: [String] = [
        "Alerted", "LastDay", "LastNotified", "DayKey", "Unconsumed", "storedText", "composerDraft", "lastLocation", "environment.",
        "ai.keyProvider", "ai.customConnected", "demo.", ".seenDay", ".opened",
    ]

    static func isBackedUp(_ key: String) -> Bool {
        if deniedFragments.contains(where: { key.contains($0) }) { return false }
        return allowedKeys.contains(key) || allowedPrefixes.contains(where: { key.hasPrefix($0) })
    }

    // MARK: Which files

    /// Under Application Support: the notes and photos of workout reviews, and the days the stress figures were worked out from.
    private static let fileRoots: [String] = ["WorkoutReviews", "stress-waking-days.json"]

    private static func supportDirectory(_ override: URL?) -> URL? {
        override ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// The path inside Application Support that an entry name stands for, or nil when it is not one of the roots or tries to leave it.
    static func relativePath(forEntry entryPath: String) -> String? {
        guard entryPath.hasPrefix(filesPrefix) else { return nil }
        let rel = String(entryPath.dropFirst(filesPrefix.count))
        let parts = rel.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.contains("\\") }) else { return nil }
        guard fileRoots.contains(parts[0]) else { return nil }
        return rel
    }

    // MARK: Export

    struct Snapshot {
        var defaultsPlist: Data?
        var files: [(entry: String, url: URL)] = []
        var isEmpty: Bool { defaultsPlist == nil && files.isEmpty }
    }

    /// What to add to a backup now. Safe off the main actor.
    static func collect(defaults: UserDefaults = .standard, supportDirectory override: URL? = nil) -> Snapshot {
        var snap = Snapshot()
        var picked: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where isBackedUp(key) && PropertyListSerialization.propertyList(value, isValidFor: .binary) {
            picked[key] = value
        }
        if !picked.isEmpty, let data = try? PropertyListSerialization.data(fromPropertyList: picked, format: .binary, options: 0),
           Int64(data.count) <= maxDefaultsBytes {
            snap.defaultsPlist = data
        }
        guard let base = supportDirectory(override) else { return snap }
        let fm = FileManager.default
        var total: Int64 = 0
        for root in fileRoots {
            let url = base.appendingPathComponent(root)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            let candidates: [URL]
            if isDir.boolValue {
                candidates = (fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])?.compactMap { $0 as? URL }) ?? []
            } else {
                candidates = [url]
            }
            for file in candidates {
                let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true, let size = values?.fileSize.map(Int64.init), size <= maxFileBytes, total + size <= maxTotalFileBytes else { continue }
                let rel = String(file.path.dropFirst(base.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard relativePath(forEntry: filesPrefix + rel) != nil else { continue }
                snap.files.append((entry: filesPrefix + rel, url: file))
                total += size
            }
        }
        return snap
    }

    // MARK: Restore

    struct Summary: Equatable {
        var keys = 0
        var files = 0
    }

    /// Puts back what a restore extracted into `extractedDir`: the allowed keys of `phmn-defaults.plist` and the files under `phmn-files/`. Call it only after the
    /// database swap has succeeded. It never fails a restore: whatever cannot be read is left out.
    @discardableResult
    static func apply(extractedDir: URL, defaults: UserDefaults = .standard, supportDirectory override: URL? = nil) -> Summary {
        var summary = Summary()
        let fm = FileManager.default
        let plist = extractedDir.appendingPathComponent(defaultsEntryName)
        if let data = try? Data(contentsOf: plist),
           let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] {
            for (key, value) in dict where isBackedUp(key) && PropertyListSerialization.propertyList(value, isValidFor: .binary) {
                defaults.set(value, forKey: key)
                summary.keys += 1
            }
        }
        let filesDir = extractedDir.appendingPathComponent("phmn-files", isDirectory: true)
        guard let base = supportDirectory(override), fm.fileExists(atPath: filesDir.path),
              let walker = fm.enumerator(at: filesDir, includingPropertiesForKeys: [.isRegularFileKey]) else { return summary }
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let rel = String(file.path.dropFirst(filesDir.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard relativePath(forEntry: filesPrefix + rel) != nil else { continue }
            let dest = base.appendingPathComponent(rel)
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: file, to: dest)
                summary.files += 1
            } catch { continue }
        }
        return summary
    }
}
