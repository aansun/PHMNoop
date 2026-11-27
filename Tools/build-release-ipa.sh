#!/usr/bin/env bash
#
# Builds the unsigned IPA of a release so that nothing of the Mac it was built on goes out with it.
#
#   Tools/build-release-ipa.sh            # writes ~/Downloads/PHMN-v<version>-ios-unsigned.ipa
#
# A build made inside a home folder writes that folder's path, and so the account name, into the binaries (the debug symbol table and every
# `#file` of the packages). This one:
#   1. clones the committed tree to a folder with a neutral name and builds there, so local, untracked files cannot slip in either;
#   2. removes the debug symbols from every binary;
#   3. searches the finished package for home-folder paths, the account, computer and git e-mail of this Mac, and the extra patterns in
#      ~/.config/phmn-release/private-patterns.txt (one per line; that file stays on the Mac). One hit and no IPA is written.
# Nothing personal is written into this script: what to look for is read from the Mac when it runs.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="/private/tmp/phmn-release"
PRIVATE="$HOME/.config/phmn-release/private-patterns.txt"
# The prefix the published app has always had. The local BundleIdSecrets file also names a development team, which is not taken along.
PREFIX="${PHMN_RELEASE_BUNDLE_PREFIX:-com.phm}"

[ -z "$(git -C "$ROOT" status --porcelain)" ] || { echo "commit first: the release is built from the committed tree" >&2; exit 1; }
VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' "$ROOT/project.yml" | head -1)
BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' "$ROOT/project.yml" | head -1)
OUT="$HOME/Downloads/PHMN-v$VERSION-ios-unsigned.ipa"
rm -f "$OUT"

rm -rf "$WORK"
mkdir -p "$WORK"
git clone --quiet --no-hardlinks "$ROOT" "$WORK/src"
printf 'BUNDLE_ID_PREFIX = %s\n' "$PREFIX" > "$WORK/src/Config/BundleIdSecrets.xcconfig"

(cd "$WORK/src" && xcodegen generate >/dev/null)
echo "building $VERSION ($BUILD) in $WORK ..."
if ! (cd "$WORK/src" && xcodebuild -project Strand.xcodeproj -scheme NOOPiOS -configuration Release -destination 'generic/platform=iOS' \
        -derivedDataPath "$WORK/dd" CODE_SIGNING_ALLOWED=NO build > "$WORK/build.log" 2>&1); then
  grep -E 'error:|BUILD FAILED' "$WORK/build.log" | sort -u | head -20 >&2
  exit 1
fi

mkdir -p "$WORK/pkg/Payload"
APP="$WORK/pkg/Payload/PHMN.app"
cp -R "$WORK/dd/Build/Products/Release-iphoneos/PHMN.app" "$APP"
rm -rf "$APP/Watch"

# Debug symbols hold the paths of the object files. Strip before signing: stripping breaks a signature.
find "$APP" -type f -print0 | while IFS= read -r -d '' f; do
  case "$(file -b "$f")" in Mach-O*) xcrun strip -S "$f" 2>/dev/null ;; esac
done
"$ROOT/Tools/prepare-ios-sideload-app.sh" "$APP"

# -X leaves out the owner numbers and extra times the archive would otherwise carry for each file.
(cd "$WORK/pkg" && zip -qryX "$WORK/release.ipa" Payload)

# The check is made on what is in the IPA, unpacked again, not on the folder it was made from.
mkdir -p "$WORK/check"
(cd "$WORK/check" && unzip -q "$WORK/release.ipa")
python3 -I - "$WORK/check" "$PRIVATE" <<'PY'
import os, socket, subprocess, sys

root, private = sys.argv[1], sys.argv[2]

def ask(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout.strip()
    except Exception:
        return ""

patterns = {"/Users/", "/var/folders/", os.environ.get("HOME", ""), ask("id", "-un"), ask("id", "-F"), socket.gethostname(),
            ask("scutil", "--get", "ComputerName"), ask("scutil", "--get", "LocalHostName"), ask("git", "config", "--global", "user.email"),
            ask("git", "config", "user.email")}
if os.path.exists(private):
    patterns |= {line.strip() for line in open(private) if not line.startswith("#")}
else:
    print("note: no private pattern file; only the Mac's own names are checked", file=sys.stderr)
# Very short strings would match by chance.
patterns = sorted(p for p in patterns if len(p) >= 5)

hits, count = {}, 0
for folder, _, files in os.walk(root):
    for name in files:
        path = os.path.join(folder, name)
        if os.path.islink(path):
            continue
        data = open(path, "rb").read().lower()
        count += 1
        shown = os.path.relpath(path, root)
        if any(p.lower() in shown.lower() for p in patterns):
            hits.setdefault("(file name)", set()).add(shown)
        for p in patterns:
            if p.lower().encode() in data or p.lower().encode("utf-16-le") in data:
                hits.setdefault(p, set()).add(shown)
        if name == "embedded.mobileprovision":
            hits.setdefault("(provisioning profile)", set()).add(shown)

if hits:
    print("PRIVATE DATA FOUND, no IPA written:", file=sys.stderr)
    for p, files in hits.items():
        print(f"  {p!r}: {', '.join(sorted(files)[:5])}", file=sys.stderr)
    sys.exit(1)
print(f"privacy check: {count} files, {len(patterns)} patterns, nothing found")
PY

mv "$WORK/release.ipa" "$OUT"
echo "✓ $OUT ($(stat -f %z "$OUT") bytes, version $VERSION build $BUILD)"
