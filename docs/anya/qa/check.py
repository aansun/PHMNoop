#!/usr/bin/env python3
"""Automatic checks on a QA run (docs/anya/QA.md): the mechanical part of the checklist.

    python3 check.py qa-poor.json [more.json ...]

For every page insight and module answer it reports: figures that are not in the data she was given (grounding), banned wording (a dash read aloud, a label or
phrase the model copies from its instructions, a "not measured"), answers over the word cap of the surface, and a missing next step. The judgement checks (does
the step fit the verdict, is it on the surface) stay with a human or a second reviewer.
"""
import json, re, sys

BANNED = [r"\bdash\b", r"best supports", r"NOT MEASURED", r"\bREAD:", r"\bEXPLAIN:", r"\bADVISE:", r"\bHEADLINE:", r"this surface", r"I am not a device", r"like a (tree|wave|lullaby|whisper)"]
CAP = {"pages": 90, "chat": 130, "brief": 130}
NUM = re.compile(r"(?<![\w.])-?\d+(?:[.,]\d+)?")

def numbers(text):
    out = set()
    for m in NUM.findall(text):
        v = m.replace(",", ".")
        out.add(v)
        try:
            f = float(v); out.add(str(int(round(f)))); out.add("%.1f" % f)
            if f == int(f): out.add(str(int(f)))
        except ValueError: pass
    return out

def words(t): return len(re.findall(r"\w+", t))

def check(d):
    known = numbers(d.get("compactContext", ""))
    rows = []
    def audit(kind, name, text, extra="", cap=None):
        text = text or ""
        known_here = known | numbers(extra)
        unknown = sorted({n for n in numbers(text) if n not in known_here and not re.fullmatch(r"-?\d{1,2}", n)})  # one and two digit integers are too often counts
        issues = []
        if unknown: issues.append("figures not in the data: " + ", ".join(unknown[:8]))
        for pat in BANNED:
            m = re.search(pat, text, re.I)
            if m: issues.append("banned: '%s'" % m.group(0))
        if cap and words(text) > cap: issues.append("%d words, cap %d" % (words(text), cap))
        rows.append((kind, name, issues))
    for p in d.get("pages", []):
        body = re.sub(r"\*\*[^*]+\*\*", "", p.get("text", ""))
        audit("page", p["page"], body, p.get("local", ""), CAP["pages"] + 40)
    for c in d.get("chat", []):
        audit("chat", c["module"] + ": " + c["question"][:50], c.get("answer", ""), c.get("known", ""), CAP["chat"] + 30)
    mb = d.get("morningBrief")
    if mb: audit("brief", "morning brief", mb.get("output", ""), "", CAP["brief"] + 40)
    return rows

if __name__ == "__main__":
    for path in sys.argv[1:]:
        d = json.load(open(path))
        rows = check(d)
        bad = [r for r in rows if r[2]]
        print("\n== %s (%s): %d items, %d with issues" % (path, d.get("scenario"), len(rows), len(bad)))
        for kind, name, issues in bad:
            print("  [%s] %s\n      - %s" % (kind, name, "\n      - ".join(issues)))
