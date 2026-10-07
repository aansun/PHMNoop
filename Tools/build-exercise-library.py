#!/usr/bin/env python3
"""Builds the bundled exercise library from a checkout of yuhonas/free-exercise-db (The Unlicense, public domain).

    git clone --depth 1 https://github.com/yuhonas/free-exercise-db.git /tmp/free-exercise-db
    python3 Tools/build-exercise-library.py /tmp/free-exercise-db

Writes StrandiOS/Resources/ExerciseLibrary/library.json and one pair of photos per exercise (start and end position, shrunk to
520 px wide) as <id>_0.jpg and <id>_1.jpg. The list of ids below is the sample; widen it to apply the library to every exercise.
"""
import json, pathlib, subprocess, sys

SAMPLE = [
    "Barbell_Bench_Press_-_Medium_Grip", "Barbell_Squat", "Barbell_Deadlift", "Pullups",
    "Standing_Military_Press", "Dumbbell_Bicep_Curl", "Bent_Over_Barbell_Row", "Plank",
]
# Other names a person may log the exercise under. Matching is on whole names, case and punctuation aside.
ALIASES = {
    "Barbell_Bench_Press_-_Medium_Grip": ["bench press", "barbell bench press", "flat bench press", "bench"],
    "Barbell_Squat": ["squat", "back squat", "barbell squat", "barbell back squat"],
    "Barbell_Deadlift": ["deadlift", "barbell deadlift", "conventional deadlift"],
    "Pullups": ["pull up", "pull ups", "pullup", "pullups"],
    "Standing_Military_Press": ["overhead press", "military press", "shoulder press", "standing overhead press", "ohp"],
    "Dumbbell_Bicep_Curl": ["bicep curl", "biceps curl", "dumbbell curl", "dumbbell biceps curl"],
    "Bent_Over_Barbell_Row": ["barbell row", "bent over row", "bent over barbell row"],
    "Plank": ["plank"],
}
WIDTH = 520
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "StrandiOS" / "Resources" / "ExerciseLibrary"

def main(src: pathlib.Path) -> None:
    db = {x["id"]: x for x in json.loads((src / "dist" / "exercises.json").read_text())}
    OUT.mkdir(parents=True, exist_ok=True)
    out = []
    for ex_id in SAMPLE:
        x = db[ex_id]
        frames = []
        for i, rel in enumerate(x["images"][:2]):
            dst = OUT / f"{ex_id}_{i}.jpg"
            subprocess.run(["sips", "-Z", str(WIDTH), "-s", "format", "jpeg", "-s", "formatOptions", "70",
                            str(src / "exercises" / rel), "--out", str(dst)], check=True, capture_output=True)
            frames.append(dst.name)
        out.append({k: x.get(k) for k in ("id", "name", "level", "mechanic", "force", "equipment", "category",
                                         "primaryMuscles", "secondaryMuscles", "instructions")} | {"frames": frames, "aliases": ALIASES.get(ex_id, [])})
    (OUT / "library.json").write_text(json.dumps(out, indent=1, ensure_ascii=False))
    print(len(out), "exercises,", sum(p.stat().st_size for p in OUT.glob("*.jpg")) // 1024, "KB of photos")

if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1]))
