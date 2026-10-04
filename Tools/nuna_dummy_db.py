#!/usr/bin/env python3
"""Build a synthetic 90-day PHMNOOP database for checking the Nuna design against realistic data.

The data is invented (a fictional 34-year-old with a regular training week), not anyone's records.
It writes the same tables the app reads, in the same namespaces a Bluetooth-only WHOOP user has:

  my-whoop        raw strap data (heart rate, beat-to-beat R-R, gravity), manual workouts, journal
  my-whoop-noop   the computed layer (daily metrics, sleep sessions with stages and movement, series)
  apple-health    weight and daily Apple Health totals

Usage:
  python3 Tools/nuna_dummy_db.py --template <whoop.sqlite or backup .sqlite> --out dummy.sqlite
  python3 Tools/nuna_dummy_db.py --template ... --out dummy.sqlite --noopbak dummy.noopbak

The template only supplies the schema (its rows are deleted). Dates are relative to "now" so the newest
night is last night and today is partly through; re-run it to refresh. The seed is fixed, so two runs on
the same day give the same numbers.
"""
import argparse, json, math, os, shutil, sqlite3, sys, zipfile
from datetime import datetime, timedelta, time, date

import numpy as np

DAYS = 90
RAW = "my-whoop"
COMP = "my-whoop-noop"
APPLE = "apple-health"

DATA_TABLES = [
    "dailyMetric", "sleepSession", "workout", "metricSeries", "hrSample", "rrInterval", "gravitySample",
    "appleDaily", "journal", "battery", "event", "stepSample", "skinTempSample", "respSample", "spo2Sample",
    "sleepStateSample", "scoreInputProvenance", "coachMessage", "liftExercise", "liftProgram",
    "liftProgramItem", "liftSession", "liftSet", "liveSession", "labMarker", "ppgWaveformSample",
    "ppgHrSample", "v18AuxSample", "rawBatch", "ouraRaw", "dayOwnership",
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", required=True, help="a whoop.sqlite (or backup .sqlite) to take the schema from")
    ap.add_argument("--out", required=True)
    ap.add_argument("--noopbak", help="also write a .noopbak (restorable from Settings) next to the database")
    ap.add_argument("--seed", type=int, default=20261004)
    a = ap.parse_args()

    rng = np.random.default_rng(a.seed)
    tz = datetime.now().astimezone().tzinfo
    now = datetime.now(tz)
    today = now.date()

    def at(d, hour):
        return datetime.combine(d, time(0), tzinfo=tz) + timedelta(hours=hour)

    def ts(dt):
        return int(dt.timestamp())

    shutil.copyfile(a.template, a.out)
    db = sqlite3.connect(a.out)
    db.execute("PRAGMA journal_mode=DELETE")
    existing = {r[0] for r in db.execute("select name from sqlite_master where type='table'")}
    for t in DATA_TABLES:
        if t in existing:
            db.execute(f"delete from {t}")
    db.execute("delete from cursors")
    db.commit()

    # ---- latent state per day -------------------------------------------------------------------
    dates = [today - timedelta(days=DAYS - 1 - i) for i in range(DAYS)]
    ready, r = [], 0.3
    for i, d in enumerate(dates):
        r = 0.55 * r + rng.normal(0.1, 0.85)
        ready.append(r)
    ILLNESS = {DAYS - 1 - 21, DAYS - 1 - 20, DAYS - 1 - 19}          # three off days about three weeks ago
    for i in ILLNESS:
        ready[i] = -2.2
    # a poor night and a very good one, so the charts have both ends
    ready[DAYS - 1 - 9] = -1.6
    ready[DAYS - 1 - 4] = 1.7

    # ---- workouts ---------------------------------------------------------------------------------
    plan = {0: ("Running", .7), 1: ("TraditionalStrengthTraining", .5), 2: ("Walking", .6), 3: ("Cycling", .4),
            4: ("Running", .6), 5: ("Hiking", .7), 6: ("Yoga", .3)}
    workouts = {}   # date -> list of dict
    for i, d in enumerate(dates):
        sport, p = plan[d.weekday()]
        if i in ILLNESS or i == DAYS - 1:
            continue
        if rng.random() > p:
            continue
        workouts.setdefault(d, []).append(make_workout(rng, sport, d, at))
    # Today: a short morning walk that has already finished
    workouts.setdefault(today, []).append(make_workout(rng, "Walking", today, at, start_hour=6.75, dur_min=38))

    # ---- sleep ------------------------------------------------------------------------------------
    nights, naps = {}, []
    sleep_rows = []
    prev_strain = 20.0
    daily = {}
    for i, d in enumerate(dates):
        rd = ready[i]
        weekend_shift = 0.9 if d.weekday() in (5, 6) else (0.35 if d.weekday() == 4 else 0.0)
        bed_h = 23.0 + weekend_shift + rng.normal(0, 0.45) + (0.3 if i in ILLNESS else 0)
        dur = 425 + 25 * (1 if d.weekday() in (5, 6) else 0) + 22 * rd + rng.normal(0, 28)
        if i in (DAYS - 1 - 9,):
            dur = 318
        if i in ILLNESS:
            dur += 35
        dur = float(np.clip(dur, 290, 560))
        bed = at(d - timedelta(days=1), bed_h)
        wake = bed + timedelta(minutes=dur + 18)
        if wake > now - timedelta(minutes=10):
            wake = None
        night = None
        if wake is not None:
            night = build_night(rng, bed, wake, rd)
            nights[d] = night

        # biometrics
        rhr = int(round(55.5 - 1.7 * rd + rng.normal(0, 0.9) + (6 if i in ILLNESS else 0)))
        hrv = 76 * math.exp(0.13 * rd + rng.normal(0, 0.05)) * (0.72 if i in ILLNESS else 1.0)
        asleep = night["asleep"] if night else None
        need = 480
        sleep_ratio = (asleep / need) if asleep else 0.9
        rec = 100 / (1 + math.exp(-(0.9 * rd + 2.6 * (sleep_ratio - 0.9) + 0.25)))
        rec = float(np.clip(rec + rng.normal(0, 3), 3, 99)) if night else None
        wk = workouts.get(d, [])
        wk_strain = sum(w["strain"] for w in wk)
        base_strain = 6 + 4 * rng.random() + (0 if d.weekday() < 5 else 3)
        strain = float(np.clip(base_strain + 0.9 * wk_strain, 3, 85))
        frac = 1.0
        if d == today:
            frac = float(np.clip((now.hour + now.minute / 60 - 6) / 16, 0.05, 1))
            strain = base_strain * frac + 0.9 * wk_strain
        steps = int(5200 + rng.random() * 3600 + (1500 if d.weekday() >= 5 else 0)
                    + sum(w.get("steps") or 0 for w in wk))
        if d == today:
            steps = int(steps * frac * 0.8)
        kcal = steps * 0.04 + sum(w["kcal"] for w in wk) * 0.8 + 140 * frac
        skin_dev = rng.normal(0, 0.22) + (0.9 if i in ILLNESS else 0)
        resp = 14.1 - 0.25 * rd + rng.normal(0, 0.25) + (1.3 if i in ILLNESS else 0)
        spo2 = float(np.clip(96.6 + rng.normal(0, 0.6), 93, 99))
        stress = float(np.clip(1.45 - 0.5 * rd + rng.normal(0, 0.25), 0.4, 2.8))
        daily[d] = dict(rhr=rhr, hrv=hrv, rec=rec, strain=strain, steps=steps, kcal=kcal, skin_dev=skin_dev,
                        resp=resp, spo2=spo2, stress=stress, night=night, need=need,
                        skin_abs=33.55 + 0.25 * math.sin(i / 9) + skin_dev, ready=rd, base_strain=base_strain)
        prev_strain = strain

        # naps: about twice a week, early afternoon, plus yesterday so the Naps screen has one for sure
        if (rng.random() < 0.28 or i == DAYS - 2) and i != DAYS - 1 and i not in ILLNESS:
            ns = at(d, 13.0 + rng.random() * 0.8)
            nd = float(rng.integers(18, 46))
            naps.append(build_nap(rng, ns, nd))

    # ---- computed-layer rows ----------------------------------------------------------------------
    # The same daily rows go in twice. The app re-scores the last ~21 days from raw heart rate whenever it
    # opens and overwrites the computed layer; this synthetic raw data is too simple to reproduce the
    # scores, so the imported layer (which wins and is never re-scored) carries the intended values.
    for d, v in daily.items():
        n = v["night"]
        for dev in (COMP, RAW):
          db.execute(
            "insert into dailyMetric (deviceId,day,totalSleepMin,efficiency,deepMin,remMin,lightMin,disturbances,restingHr,"
            "avgHrv,recovery,strain,exerciseCount,spo2Pct,skinTempDevC,respRateBpm,steps,activeKcalEst,avgSdnn,skinTempC)"
            " values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (dev, d.isoformat(), n and n["asleep"], n and n["eff"], n and n["deep"], n and n["rem"], n and n["light"],
             n and n["wakes"], v["rhr"], v["hrv"], v["rec"], round(v["strain"], 2), len(workouts.get(d, [])),
             round(v["spo2"], 1), round(v["skin_dev"], 2), round(v["resp"], 1), v["steps"], round(v["kcal"], 1),
             v["hrv"] * 1.12, round(v["skin_abs"], 2)))
    for d, n in nights.items():
      for dev in (COMP, RAW):
        db.execute(
            "insert into sleepSession (deviceId,startTs,endTs,efficiency,restingHr,avgHrv,stagesJSON,userEdited,motionJSON)"
            " values (?,?,?,?,?,?,?,0,?)",
            (dev, n["start"], n["end"], n["eff"], daily[d]["rhr"], daily[d]["hrv"],
             json.dumps(n["segments"], separators=(",", ":"), sort_keys=True),
             json.dumps([round(x, 4) for x in n["motion"]], separators=(",", ":"))))
    for nap in naps:
      for dev in (COMP, RAW):
        db.execute(
            "insert into sleepSession (deviceId,startTs,endTs,efficiency,restingHr,avgHrv,stagesJSON,userEdited,motionJSON)"
            " values (?,?,?,?,?,?,?,0,?)",
            (dev, nap["start"], nap["end"], nap["eff"], None, None,
             json.dumps(nap["segments"], separators=(",", ":"), sort_keys=True),
             json.dumps([round(x, 4) for x in nap["motion"]], separators=(",", ":"))))

    for d, ws in workouts.items():
        for w in ws:
            db.execute(
                "insert into workout (deviceId,startTs,endTs,sport,source,durationS,energyKcal,avgHr,maxHr,strain,distanceM,"
                "zonesJSON,notes,steps) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (RAW, w["start"], w["end"], w["sport"], "manual", w["dur"] * 60.0, w["kcal"], w["avg"], w["max"],
                 round(w["strain"], 2), w["dist"], None, None, w["steps"]))

    # lifting sessions behind the strength workouts: a few exercises, working sets with weight and reps
    lift_plan = [
        ("Back squat", "quads", ["glutes", "hamstrings"], 100.0),
        ("Bench press", "chest", ["frontDelts", "triceps"], 80.0),
        ("Barbell row", "lats", ["upperBack", "biceps"], 70.0),
        ("Overhead press", "frontDelts", ["triceps"], 47.5),
        ("Romanian deadlift", "hamstrings", ["glutes", "lowerBack"], 90.0),
    ]
    lift_n = 0
    for d, ws in sorted(workouts.items()):
        for w in ws:
            if w["sport"] != "TraditionalStrengthTraining":
                continue
            lift_n += 1
            sid = f"dummy-lift-{w['start']}"
            db.execute("insert into liftSession (id,deviceId,startTs,endTs,sport,programId,programName,sessionRpe,note)"
                       " values (?,?,?,?,?,?,?,?,?)", (sid, RAW, w["start"], w["end"], w["sport"], None, None, 7.0 + (lift_n % 3) * 0.5, None))
            picks = lift_plan[(lift_n % 2)::2] if lift_n % 2 == 0 else lift_plan[:3]
            order = 0
            for name, prim, sec, base in picks:
                load = base * (1 + 0.012 * lift_n)
                for k in range(4):
                    reps = [8, 8, 6, 6][k]
                    db.execute("insert into liftSet (id,deviceId,sessionId,ord,exercise,primaryMuscle,secondaryMuscles,setIndex,weightKg,reps,rpe,isWarmup,startTs,endTs,restSec,note)"
                               " values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                               (f"{sid}-{order}", RAW, sid, order, name, prim, ",".join(sec), k + 1, round(load * (0.8 if k == 0 else 1.0) / 2.5) * 2.5, reps,
                                7.0 + k * 0.5, 0, None, None, 120, None))
                    order += 1
    # series the screens read from metricSeries (the rest come from the daily columns)
    ms = []
    nonnull = [d for d in dates if daily[d]["night"]]
    last_rec = None
    for idx, d in enumerate(nonnull):
        v, n = daily[d], daily[d]["night"]
        eff = n["eff"]
        restorative = (n["deep"] + n["rem"]) / max(n["asleep"], 1)
        # consistency: how tightly bedtimes cluster over the 7 nights up to here
        win = nonnull[max(0, idx - 6): idx + 1]
        bed_hours = [((datetime.fromtimestamp(daily[x]["night"]["start"], tz).hour * 60
                       + datetime.fromtimestamp(daily[x]["night"]["start"], tz).minute) / 60) % 24 for x in win]
        bed_hours = [h + 24 if h < 12 else h for h in bed_hours]
        sd = float(np.std(bed_hours)) if len(bed_hours) > 2 else 0.5
        consistency = float(np.clip(100 * (1 - sd / 2.0), 35, 99))
        rest = 100 * (0.55 * min(1, n["asleep"] / v["need"]) + 0.2 * eff + 0.15 * min(1, restorative / 0.42)
                      + 0.10 * consistency / 100)
        rest = float(np.clip(rest + 4, 30, 99))
        debt = max(0.0, v["need"] - n["asleep"])
        day = d.isoformat()
        for key, val in (("sleep_performance", rest), ("sleep_consistency", consistency),
                         ("hours_vs_needed_pct", 100 * n["asleep"] / v["need"]), ("sleep_need_min", v["need"]),
                         ("sleep_debt_min", debt), ("restorative_pct", 100 * restorative),
                         ("restorative_min", n["deep"] + n["rem"]), ("sleep_efficiency", 100 * eff)):
            ms.append((COMP, day, key, float(val)))
    for d in dates:
        ms.append((COMP, d.isoformat(), "stress", round(daily[d]["stress"], 2)))
    sat = [d for d in dates if d.weekday() == 5] + [today]
    fa = 33.0
    for k, d in enumerate(sat):
        fa -= 0.18 + 0.05 * rng.random()
        ms.append((COMP, d.isoformat(), "fitness_age", round(fa, 1)))
        ms.append((COMP, d.isoformat(), "body_age", round(fa + 1.5, 1)))
        ms.append((COMP, d.isoformat(), "vo2max_est", round(44.5 + k * 0.18 + rng.normal(0, 0.2), 1)))
        ms.append((COMP, d.isoformat(), "vitality", round(66 + k * 0.6 + rng.normal(0, 1.5), 0)))
    # weight (Apple Health): a slow downward drift, a reading every few days
    w = 79.4
    for i, d in enumerate(dates):
        w += rng.normal(-0.03, 0.12)
        if i % 3 == 0:
            ms.append((APPLE, d.isoformat(), "weight", round(w, 1)))
            db.execute("insert into appleDaily (deviceId,day,steps,activeKcal,basalKcal,vo2max,avgHr,maxHr,walkingHr,weightKg)"
                       " values (?,?,?,?,?,?,?,?,?,?)",
                       (APPLE, d.isoformat(), None, None, None, None, None, None, None, round(w, 1)))
    ms = ms + [(RAW, d, k, v) for (dev, d, k, v) in ms if dev == COMP]
    db.executemany("insert or replace into metricSeries (deviceId,day,key,value) values (?,?,?,?)", ms)

    # journal
    qs = ["Consumed caffeine?", "Ate food close to bedtime?", "Hydrated sufficiently?", "Feeling sick or ill?",
          "Travelled in a car or train?", "Ate an evening snack?"]
    for i, d in enumerate(dates):
        for q in qs:
            p = {"Consumed caffeine?": .6, "Ate food close to bedtime?": .25, "Hydrated sufficiently?": .7,
                 "Feeling sick or ill?": .02, "Travelled in a car or train?": .3, "Ate an evening snack?": .35}[q]
            yes = int(rng.random() < p)
            if q == "Feeling sick or ill?" and i in ILLNESS:
                yes = 1
            db.execute("insert into journal (deviceId,day,question,answeredYes,notes,numericValue) values (?,?,?,?,?,?)",
                       (RAW, d.isoformat(), q, yes, None, None))
    db.commit()

    # ---- raw strap data ---------------------------------------------------------------------------
    print("heart rate ...", flush=True)
    hr_total = rr_total = gr_total = 0
    for i, d in enumerate(dates):
        v = daily[d]
        start = at(d, 0)
        end = min(at(d + timedelta(days=1), 0), now)
        t0, t1 = ts(start), ts(end)
        grid = np.arange(t0, t1, 10)
        if len(grid) == 0:
            continue
        hr, rmssd, active = hr_day(rng, grid, d, v, nights.get(d), nights.get(d + timedelta(days=1)),
                                   workouts.get(d, []), at)
        db.executemany("insert or ignore into hrSample (deviceId,ts,bpm,synced) values (?,?,?,0)",
                       ((RAW, int(t), int(b)) for t, b in zip(grid, hr)))
        hr_total += len(grid)
        age = (today - d).days
        if age <= 20:     # gravity feeds the sleep detector and the motion gate on the stress curve
            dyn = np.where(active > 0, 0.25 + 1.1 * rng.random(len(grid)), 0.012 + 0.02 * rng.random(len(grid)))
            db.executemany("insert or ignore into gravitySample (deviceId,ts,x,y,z,synced,dynAccel) values (?,?,?,?,?,0,?)",
                           ((RAW, int(t), float(-0.3 + 0.05 * rng.normal()), float(0.95 + 0.02 * rng.normal()),
                             float(0.1 + 0.05 * rng.normal()), float(dv)) for t, dv in zip(grid, dyn)))
            gr_total += len(grid)
        windows = []
        if age <= 6:
            windows.append((t0, t1))
        elif age <= 29:
            n = nights.get(d)
            if n:
                windows.append((n["start"], n["end"]))
        for (w0, w1) in windows:
            rr_total += write_rr(db, rng, grid, hr, rmssd, w0, w1)
        if i % 15 == 14:
            db.commit()
            print(f"  day {i + 1}/{DAYS}", flush=True)
    db.commit()

    # a battery trace so the strap card has something to show
    soc, t = 96.0, ts(now - timedelta(days=7))
    rows = []
    while t < ts(now):
        soc -= 0.021 * 30 / 60 * 1.0 + 0.0
        if soc < 14:
            soc = 100.0
        rows.append((RAW, t, round(soc, 1), None, 0, 0))
        t += 1800
    db.executemany("insert or ignore into battery (deviceId,ts,soc,mv,synced,charging) values (?,?,?,?,?,?)", rows)
    db.commit()
    db.execute("vacuum")
    db.close()

    print(f"hr {hr_total:,}  rr {rr_total:,}  gravity {gr_total:,}  nights {len(nights)}  naps {len(naps)}  "
          f"workouts {sum(len(x) for x in workouts.values())}")
    print(f"wrote {a.out} ({os.path.getsize(a.out) / 1e6:.0f} MB)")

    if a.noopbak:
        settings = {"effort.scale": "hundred", "profile.age": 34, "profile.heightCm": 175, "profile.waistCm": 84,
                    "profile.weightKg": 78.0, "profile.sex": "male", "today.hostedCards": "[]"}
        manifest = {"appBuild": "409", "appVersion": "11.8.0", "exportedAt": int(now.timestamp() * 1000),
                    "platform": "apple", "schemaVersion": 18}
        with zipfile.ZipFile(a.noopbak, "w", zipfile.ZIP_DEFLATED) as z:
            z.write(a.out, "noop-backup.sqlite")
            z.writestr("settings.json", json.dumps(settings, separators=(",", ":")))
            z.writestr("manifest.json", json.dumps(manifest, separators=(",", ":")))
        print(f"wrote {a.noopbak} ({os.path.getsize(a.noopbak) / 1e6:.0f} MB)")


# ---------------------------------------------------------------------------------------------------
def make_workout(rng, sport, d, at, start_hour=None, dur_min=None):
    morning = rng.random() < 0.6
    sh = start_hour if start_hour is not None else (6.2 + rng.random() * 1.2 if morning else 17.3 + rng.random() * 1.0)
    spec = {
        "Running": (28, 55, 150, 174, 9.8, 11),
        "TraditionalStrengthTraining": (40, 65, 118, 150, 0, 6.5),
        "Walking": (30, 60, 106, 124, 4.9, 4.7),
        "Cycling": (45, 80, 138, 166, 22.0, 9.5),
        "Hiking": (75, 130, 118, 148, 4.4, 6.0),
        "Yoga": (25, 45, 86, 104, 0, 2.5),
    }[sport]
    dur = dur_min if dur_min is not None else float(rng.integers(spec[0], spec[1]))
    avg = int(spec[2] + rng.normal(0, 4))
    mx = int(spec[3] + rng.normal(0, 4))
    speed = spec[4] * (1 + rng.normal(0, 0.05))
    dist = dur / 60 * speed * 1000 if speed else None
    strain = dur / 60 * max(avg - 100, 4) * 0.62
    kcal = dur * spec[5] * (0.9 + 0.2 * rng.random())
    steps = int(dist / 0.78) if sport in ("Running", "Walking", "Hiking") and dist else None
    start = at(d, sh)
    return dict(sport=sport, start=int(start.timestamp()), end=int((start + timedelta(minutes=dur)).timestamp()),
                dur=dur, avg=avg, max=mx, strain=strain, kcal=kcal, dist=dist, steps=steps)


def _segments(rng, t0, total_min, rd, nap=False):
    """Stage segments covering [t0, t0 + total_min] as {start,end,stage} in epoch seconds."""
    segs, t, end = [], float(t0), float(t0) + total_min * 60
    def add(stage, minutes):
        nonlocal t
        if t >= end:
            return
        e = min(end, t + minutes * 60)
        segs.append({"start": int(t), "end": int(e), "stage": stage})
        t = e
    if nap:
        add("wake", 2 + rng.random() * 3)
        add("light", 8 + rng.random() * 6)
        add("deep", 6 + rng.random() * 10)
        while t < end:
            add("light", 6 + rng.random() * 8)
            if rng.random() < .5:
                add("rem", 3 + rng.random() * 5)
        return segs
    add("wake", 6 + rng.random() * 10)
    cycle = 0
    while t < end:
        add("light", 12 + rng.random() * 14)
        add("deep", max(0, 34 - 7.5 * cycle + rng.normal(0, 7) + 3 * rd))
        add("light", 10 + rng.random() * 12)
        if rng.random() < 0.55:
            add("wake", 1.5 + rng.random() * 4)
            add("light", 5 + rng.random() * 8)
        add("rem", 9 + 6 * cycle + rng.normal(0, 4))
        if rng.random() < 0.32:
            add("wake", 2 + rng.random() * 6)
        cycle += 1
    return [s for s in segs if s["end"] > s["start"]]


def _motion(rng, segs, t0, t1, lively=False):
    n = int((t1 - t0) // 30)
    v = np.abs(rng.normal(0.02, 0.025, n)) + 0.015
    if lively:
        v = v * 2
    stage_at = np.full(n, "light", dtype=object)
    for s in segs:
        a, b = int((s["start"] - t0) // 30), int((s["end"] - t0) // 30)
        stage_at[a:b] = s["stage"]
        if 0 <= a < n:
            v[a] += rng.uniform(0.3, 3.0) if rng.random() < 0.5 else 0
    wake = stage_at == "wake"
    v[wake] = np.exp(rng.normal(-0.4, 1.0, wake.sum()))
    burst = rng.random(n) < 0.04
    v[burst] = rng.uniform(0.35, 2.6, burst.sum())
    if n > 40:
        for k in rng.choice(n, size=int(rng.integers(3, 8)), replace=False):
            v[k] = rng.uniform(6.5, 14)
    return v.tolist()


def build_night(rng, bed, wake, rd):
    t0, t1 = int(bed.timestamp()), int(wake.timestamp())
    segs = _segments(rng, t0, (t1 - t0) / 60, rd)
    m = {"wake": 0.0, "light": 0.0, "deep": 0.0, "rem": 0.0}
    wakes = 0
    for s in segs:
        m[s["stage"]] += (s["end"] - s["start"]) / 60
        wakes += s["stage"] == "wake" and s["start"] > t0 + 20 * 60
    asleep = m["light"] + m["deep"] + m["rem"]
    return dict(start=t0, end=t1, segments=segs, deep=round(m["deep"], 1), rem=round(m["rem"], 1),
                light=round(m["light"], 1), asleep=round(asleep, 1), eff=asleep / max(asleep + m["wake"], 1),
                wakes=int(wakes), motion=_motion(rng, segs, t0, t1))


def build_nap(rng, start, dur_min):
    t0 = int(start.timestamp())
    segs = _segments(rng, t0, dur_min, 0, nap=True)
    t1 = segs[-1]["end"]
    asleep = sum((s["end"] - s["start"]) / 60 for s in segs if s["stage"] != "wake")
    return dict(start=t0, end=t1, segments=segs, eff=asleep / max((t1 - t0) / 60, 1), motion=_motion(rng, segs, t0, t1))


def hr_day(rng, grid, d, v, night_today, night_next, wk, at):
    """Heart rate every 10 s for one calendar day, plus an R-R variability target and an 'active' mask."""
    n = len(grid)
    h = ((grid - grid[0]) / 3600.0)
    base = v["rhr"] + 13 + 8.5 * np.cos(2 * np.pi * (h - 16.2) / 24)
    noise = np.zeros(n)
    x = 0.0
    eps = rng.normal(0, 1.6, n)
    for k in range(n):
        x = 0.93 * x + eps[k]
        noise[k] = x
    hr = base + noise * 0.9
    rmssd = np.full(n, v["hrv"] * 0.46)
    active = np.zeros(n)
    stage_off = {"wake": 9.0, "light": 0.0, "deep": -3.5, "rem": 2.5}
    stage_rm = {"wake": 0.55, "light": 1.0, "deep": 1.18, "rem": 0.85}

    def apply_night(nt):
        if not nt:
            return
        for s in nt["segments"]:
            a = np.searchsorted(grid, s["start"]); b = np.searchsorted(grid, s["end"])
            if b > a:
                tgt = v["rhr"] - 1 + stage_off[s["stage"]]
                hr[a:b] = tgt + noise[a:b] * 0.35
                rmssd[a:b] = v["hrv"] * stage_rm[s["stage"]]
        # morning ramp after waking
        a = np.searchsorted(grid, nt["end"])
        ramp = np.arange(min(180, n - a))
        if len(ramp):
            hr[a:a + len(ramp)] += 14 * np.exp(-ramp / 70)
    apply_night(night_today)
    apply_night(night_next)

    def bump(t_start, minutes, amount, rm_factor, act, shape="smooth"):
        a = np.searchsorted(grid, t_start); b = np.searchsorted(grid, t_start + minutes * 60)
        if b <= a:
            return
        L = b - a
        env = np.minimum(1, np.minimum(np.arange(L) + 1, L - np.arange(L)) / max(6, L // 5))
        hr[a:b] += amount * env
        rmssd[a:b] *= (1 - (1 - rm_factor) * env)
        if act:
            active[a:b] = 1

    awake_from = grid[0] + 7.4 * 3600
    for _ in range(int(rng.integers(4, 8))):                      # walks about
        s = awake_from + rng.random() * 12.5 * 3600
        bump(s, rng.integers(5, 20), rng.uniform(16, 36), 0.4, True)
    for _ in range(int(rng.integers(1, 4))):                       # stress episodes
        s = awake_from + 1.5 * 3600 + rng.random() * 8 * 3600
        bump(s, rng.integers(20, 55), rng.uniform(7, 17), 0.45, False)
    if v["ready"] < -1.0 or rng.random() < 0.12:
        bump(grid[0] + 10.3 * 3600, 35, 17, 0.4, False)            # a long tense stretch mid-morning
    for w in wk:
        a = np.searchsorted(grid, w["start"]); b = np.searchsorted(grid, w["end"])
        if b > a:
            L = b - a
            tgt = w["avg"] + 3 * np.sin(np.arange(L) / 18.0) + rng.normal(0, 4, L)
            ramp = np.minimum(1, np.arange(L) / 40.0)
            hr[a:b] = base[a:b] * (1 - ramp) + tgt * ramp
            rmssd[a:b] = v["hrv"] * 0.14
            active[a:b] = 1
            # recovery tail after the session
            tail = np.arange(min(120, n - b))
            if len(tail):
                hr[b:b + len(tail)] += (w["avg"] - base[b]) * 0.45 * np.exp(-tail / 25)
    if v["ready"] < -2:                                            # an off day runs warmer all day
        hr += 3
    hr = np.clip(np.round(hr), 38, 196)
    return hr, rmssd, active


def write_rr(db, rng, grid, hr, rmssd, w0, w1):
    a = np.searchsorted(grid, w0); b = np.searchsorted(grid, w1)
    if b - a < 6:
        return 0
    tg = grid[a:b].astype(float)
    t = float(w0)
    rows = []
    last_sec, seq = None, 0
    while t < w1:
        hr_t = float(np.interp(t, tg, hr[a:b]))
        rm_t = float(np.interp(t, tg, rmssd[a:b]))
        base = 60000.0 / max(hr_t, 38)
        sigma = max(rm_t / 1.4142, 2.0)
        rr = int(np.clip(base + rng.normal(0, sigma), 380, 1600))
        sec = int(t)
        seq = seq + 1 if sec == last_sec else 0
        last_sec = sec
        rows.append((RAW, sec, rr, seq, 0, 0, 5, None))
        t += rr / 1000.0
    db.executemany("insert or ignore into rrInterval (deviceId,ts,rrMs,seq,synced,ord,srcChannel,tsSuspect)"
                   " values (?,?,?,?,?,?,?,?)", rows)
    return len(rows)


if __name__ == "__main__":
    main()
