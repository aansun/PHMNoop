#!/usr/bin/env python3
"""Check that device-facing Settings preferences have a configuration decision.

The active-WHOOP preset is intentionally explicit.  This source contract makes a future Settings
addition fail loudly until it is classified as managed by the preset, manual/experimental, or
unrelated to device configuration.  It is deliberately source-based because the app target is
generated from project.yml and the preference declarations live in SwiftUI view files.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SETTING_SOURCES = (
    ROOT / "Strand/Screens/SettingsView.swift",
    ROOT / "Strand/Screens/PowerSavingView.swift",
    ROOT / "Strand/Screens/TestCentreView.swift",
)
APP_STORAGE = re.compile(r"@AppStorage\(([^)\n]+)\)")


# Preferences that the active WHOOP preset reads, compares, and can safely apply.
MANAGED = frozenset(
    {
        '"selectedWhoopModel"',
        "PuffinExperiment.keepRealtimeForDataKey",
        "PuffinExperiment.continuousHrvOvernightOnlyKey",
        "PuffinExperiment.experimentalSleepV2Key",
        "PuffinExperiment.motionAwareWakeKey",
        "UnitPrefs.effortScaleKey",
        "UnitPrefs.hrvWindowKey",
        "PuffinExperiment.banisterEffortKey",
        "PuffinExperiment.stressPersonalBaselineKey",
        "PuffinExperiment.powerSavingKey",
        "PuffinExperiment.powerSavingBatteryPctKey",
        "PuffinExperiment.pauseHrvDisabledKey",
        "PuffinExperiment.lowRefreshKey",
    }
)

# Preferences shown in the device/Test Centre surfaces but deliberately not changed by the preset.
# Several of these write persistent strap flags or expose unvalidated instrumentation.
MANUAL = frozenset(
    {
        "PuffinExperiment.defaultsKey",
        "PuffinFrameRecorder.enabledKey",
        "PuffinExperiment.deepDataKey",
        "PuffinExperiment.broadcastHrKey",
        "PuffinExperiment.ecgRawDataKey",
        "PuffinExperiment.ecgKey",
        "PuffinExperiment.spo2CandidateDisplayKey",
        "PuffinExperiment.ppgHrSubLagInterpKey",
        "PuffinExperiment.hrvReadinessKey",
    }
)

# Everything else currently stored by these general settings surfaces is not part of the active
# WHOOP hardware profile (appearance, language, journaling, update checks, and so on).
EXCLUDED = frozenset(
    {
        '"noop.coachEnabled"',
        '"noop.bottomBarAutoHide"',
        "ClockFormatPreference.defaultsKey",
        "UnitPrefs.systemKey",
        "UnitPrefs.distanceSystemKey",
        "UnitPrefs.temperatureKey",
        "UnitPrefs.skinTempDisplayKey",
        "UnitPrefs.trendChartStyleKey",
        "UnitPrefs.liveActivityKey",
        "UnitPrefs.syncLiveActivityKey",
        "DayCycleMode.storageKey",
        '"appIcon.name"',
        "AppearanceMode.storageKey",
        "AppLanguage.storageKey",
        "ChartStyle.storageKey",
        "TypographyPreset.storageKey",
        "SleepChartStyle.storageKey",
        "AccentColor.storageKey",
        "AccentColor.customHexKey",
        "SceneBackgroundPrefs.enabledKey",
        "SkyBehindCardsPrefs.enabledKey",
        "CardAppearancePrefs.opacityKey",
        "QuietMotionPrefs.enabledKey",
        "HydrationStore.enabledKey",
        "PuffinExperiment.autoDetectWorkoutsKey",
        "PuffinExperiment.journalReminderKey",
        '"workoutKeepScreenOn"',
        "ScreenIdle.strapSyncKeepAwakeKey",
        "UpdateWatch.Keys.enabled",
        "SettingsDisclosureDefaults.advancedOpenKey",
        '"noop.liquidTodayEnabled"',
        "LiveSessionPrefs.betaKey",
        "AppModel.polarDebugLoggingKey",
        "AppModel.ouraOnsetKeyingKey",
    }
)


def declared_preferences() -> set[str]:
    found: set[str] = set()
    missing_sources = [str(path) for path in SETTING_SOURCES if not path.exists()]
    if missing_sources:
        raise RuntimeError("missing settings source(s): " + ", ".join(missing_sources))
    for path in SETTING_SOURCES:
        found.update(match.group(1).strip() for match in APP_STORAGE.finditer(path.read_text()))
    return found


def audit() -> list[str]:
    declared = declared_preferences()
    decisions = MANAGED | MANUAL | EXCLUDED
    problems: list[str] = []

    for overlap_name, left, right in (
        ("MANAGED/MANUAL", MANAGED, MANUAL),
        ("MANAGED/EXCLUDED", MANAGED, EXCLUDED),
        ("MANUAL/EXCLUDED", MANUAL, EXCLUDED),
    ):
        overlap = sorted(left & right)
        if overlap:
            problems.append(f"{overlap_name} overlap: {', '.join(overlap)}")

    unknown = sorted(declared - decisions)
    if unknown:
        problems.append(
            "new or unclassified @AppStorage preference(s): " + ", ".join(unknown)
        )

    stale = sorted(decisions - declared)
    if stale:
        problems.append("manifest contains stale preference(s): " + ", ".join(stale))

    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail on an incomplete manifest")
    args = parser.parse_args()
    problems = audit()
    if problems:
        for problem in problems:
            print(f"ERROR: {problem}", file=sys.stderr)
        return 1 if args.check else 0
    print("Device configuration manifest covers all Settings, Power saving, and Test Centre preferences.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
