#!/usr/bin/env python3
"""Builds StrandiOS/Resources/Legal/open-source-licenses.json, the list behind About > Open source licenses.

Each entry carries the licence text exactly as the package ships it, read from the Swift Package Manager checkout, with the
version the checkout is at. The packages are the ones project.yml links into the iOS app (directly or through another package).
Re-run it after a package version changes:

    xcodebuild -resolvePackageDependencies -project Strand.xcodeproj -scheme NOOPiOS -derivedDataPath /tmp/phmn-dd
    python3 Tools/build-open-source-licenses.py /tmp/phmn-dd/SourcePackages/checkouts

What is not a Swift package (the exercise library, the typefaces, openGym, NOOP itself) is listed in NunaAbout.swift.
"""
import json, subprocess, sys
from pathlib import Path

checkouts = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/phmn-dd/SourcePackages/checkouts")
out = Path(__file__).resolve().parent.parent / "StrandiOS/Resources/Legal/open-source-licenses.json"

# folder in the checkout -> (shown name, author, licence, project url, what PHMN uses it for, licence file)
PACKAGES = {
    "GRDB.swift": ("GRDB.swift", "Gwendal Roué", "MIT", "https://github.com/groue/GRDB.swift", "The on-device database.", "LICENSE"),
    "MuscleMap": ("MuscleMap", "Melih Colpan", "MIT", "https://github.com/melihcolpan/MuscleMap", "The body map in the Gym screens, with its heat colouring.", "LICENSE"),
    "swift-markdown-ui": ("MarkdownUI", "Guillermo Gonzalez", "MIT", "https://github.com/gonzalezreal/swift-markdown-ui", "The formatting of Anya's replies and of the documents in About.", "LICENSE"),
    "NetworkImage": ("NetworkImage", "Guille Gonzalez", "MIT", "https://github.com/gonzalezreal/NetworkImage", "Image loading inside MarkdownUI.", "LICENSE"),
    "swift-cmark": ("swift-cmark (cmark-gfm)", "John MacFarlane and contributors", "BSD 2-Clause and others, see the text", "https://github.com/swiftlang/swift-cmark", "The Markdown parser inside MarkdownUI.", "COPYING"),
    "ZIPFoundation": ("ZIPFoundation", "Thomas Zoechling", "MIT", "https://github.com/weichsel/ZIPFoundation", "Reading and writing the zip files of imports and backups.", "LICENSE"),
}

entries = []
for folder, (name, author, licence, url, used, licfile) in PACKAGES.items():
    d = checkouts / folder
    version = subprocess.run(["git", "-C", str(d), "describe", "--tags"], capture_output=True, text=True).stdout.strip() or \
              subprocess.run(["git", "-C", str(d), "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    text = (d / licfile).read_text(encoding="utf-8").strip()
    entries.append({"id": folder.lower(), "name": name, "author": author, "license": licence, "version": version, "url": url, "used": used, "text": text})

out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(sorted(entries, key=lambda e: e["name"].lower()), ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(f"wrote {len(entries)} entries to {out}")
