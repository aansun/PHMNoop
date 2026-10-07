#!/usr/bin/env python3
"""Builds the bundled exercise library from a checkout of yuhonas/free-exercise-db (The Unlicense, public domain).

    git clone --depth 1 https://github.com/yuhonas/free-exercise-db.git /tmp/free-exercise-db
    python3 Tools/build-exercise-library.py /tmp/free-exercise-db

Writes StrandiOS/Resources/ExerciseLibrary/library.json and, for every exercise, its start and end photo shrunk to 480 px wide
(JPEG, quality 50) as <id>_0.jpg and <id>_1.jpg. An exercise with a single photo gets only <id>_0.jpg. Everything is rebuilt
from scratch, so a run leaves exactly what the data set holds.
"""
import json, pathlib, re, shutil, subprocess, sys

WIDTH, QUALITY = 480, 50

# Names a person may log an exercise under, by the library's own name. Matching is on whole names with case and punctuation aside
# (see NunaExerciseLibrary.normalized), so only names that really differ from the library's are listed.
ALIASES = {
    "Barbell Bench Press - Medium Grip": ["bench press", "barbell bench press", "flat bench press", "bench"],
    "Barbell Squat": ["squat", "back squat", "barbell back squat"],
    "Front Barbell Squat": ["front squat"],
    "Barbell Deadlift": ["deadlift", "conventional deadlift"],
    "Romanian Deadlift": ["romanian deadlift", "rdl", "romanian deadlift dumbbell", "dumbbell romanian deadlift"],
    "Pullups": ["pull up", "pull ups", "pullup", "chin up over bar"],
    "Chin-Up": ["chin up", "chinup"],
    "Band Assisted Pull-Up": ["assisted pull up", "assisted pullup", "assisted pull-up"],
    "Standing Military Press": ["overhead press", "military press", "standing overhead press", "ohp", "shoulder press barbell"],
    "Dumbbell Shoulder Press": ["dumbbell shoulder press", "seated dumbbell shoulder press", "dumbbell overhead press"],
    "Dumbbell Bicep Curl": ["bicep curl", "biceps curl", "dumbbell curl", "dumbbell biceps curl"],
    "Bent Over Barbell Row": ["barbell row", "bent over row", "bent-over row"],
    "Plank": ["plank"],
    "Dead Bug": ["dead bug"],
    "Dumbbell Bench Press": ["dumbbell bench press", "db bench press"],
    "Incline Dumbbell Press": ["incline dumbbell press", "incline db press"],
    "Farmer's Walk": ["farmer carry", "farmers carry", "farmer's carry", "farmer walk", "farmer's walk"],
    "Goblet Squat": ["goblet squat"],
    "Barbell Hip Thrust": ["hip thrust", "barbell hip thrust"],
    "Wide-Grip Lat Pulldown": ["lat pulldown", "lat pull down", "wide grip lat pulldown"],
    "Seated Leg Curl": ["leg curl", "seated leg curl", "hamstring curl"],
    "Leg Press": ["leg press"],
    "Seated Cable Rows": ["seated cable row", "cable row", "seated row"],
    "Split Squats": ["split squat", "bulgarian split squat"],
    "Calf Press On The Leg Press Machine": ["leg press calf raise"],
    "Standing Calf Raises": ["calf raise", "standing calf raise"],
    "Triceps Pushdown": ["triceps pushdown", "tricep pushdown", "cable pushdown"],
    "Barbell Curl": ["barbell curl", "bicep curl barbell"],
    "Pushups": ["push up", "push ups", "pushup", "push-up"],
    "Dips - Chest Version": ["chest dip", "dip"],
    "Dips - Triceps Version": ["tricep dip", "triceps dip"],
    "Face Pull": ["face pull", "cable face pull"],
    "Side Lateral Raise": ["lateral raise", "dumbbell lateral raise", "side raise"],
    "Hanging Leg Raise": ["hanging leg raise", "leg raise"],
    "Crunches": ["crunch"],
    "Cable Crunch": ["cable crunch"],
}

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "StrandiOS" / "Resources" / "ExerciseLibrary"


def main(src: pathlib.Path) -> None:
    db = json.loads((src / "dist" / "exercises.json").read_text())
    by_name = {x["name"].lower(): x["id"] for x in db}
    wanted = {}
    for name, names in ALIASES.items():
        ex_id = by_name.get(name.lower())
        if ex_id is None:
            sys.exit(f"alias target not in the data set: {name}")
        wanted[ex_id] = names

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    out = []
    for x in sorted(db, key=lambda e: e["name"].lower()):
        frames = []
        for i, rel in enumerate(x["images"][:2]):
            dst = OUT / f"{x['id']}_{i}.jpg"
            subprocess.run(["sips", "-Z", str(WIDTH), "-s", "format", "jpeg", "-s", "formatOptions", str(QUALITY),
                            str(src / "exercises" / rel), "--out", str(dst)], check=True, capture_output=True)
            frames.append(dst.name)
        out.append({k: x.get(k) for k in ("id", "name", "level", "mechanic", "force", "equipment", "category",
                                         "primaryMuscles", "secondaryMuscles", "instructions")}
                   | {"frames": frames, "aliases": wanted.get(x["id"], [])})
    (OUT / "library.json").write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    size = sum(p.stat().st_size for p in OUT.iterdir())
    print(len(out), "exercises,", sum(1 for e in out if e["frames"]), "with photos,", size // (1024 * 1024), "MB")


if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1]))
