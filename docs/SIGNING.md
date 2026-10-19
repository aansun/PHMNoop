# Signing PHMN yourself

The IPA attached to each release is **unsigned**: iOS will not run it until it is signed with *your* certificate, for *your* device. The easy way is a sideloader
(AltStore or SideStore), which signs it on the phone with your Apple ID. This page is for everything else: signing it by hand on a Mac, or skipping the IPA and
building from source.

Pick the route that matches what you have:

| You have | Route | HealthKit (Apple Health) | Lasts |
|---|---|---|---|
| A free Apple ID, no sideloader | [Build from source in Xcode](#route-a-build-from-source-in-xcode) | Yes, Xcode can provision it for a device you plug in | 7 days, then rebuild |
| A paid Apple Developer account | [Re-sign the IPA by hand](#route-b-re-sign-the-ipa-by-hand) or build from source | Yes | 1 year |
| An enterprise or MDM certificate | [Re-sign the IPA by hand](#route-b-re-sign-the-ipa-by-hand) with that certificate | Depends on your profile | Per your profile |
| A free Apple ID and a sideloader | Use the sideloader, see [docs/IOS.md](IOS.md) | **No**, a sideloader cannot provision HealthKit on a free ID | 7 days, refreshed by the sideloader |

> The release IPA has no Apple Watch app. If you want the watch app and complications, build from source (Route A).

## What needs to be unique to you

An App ID belongs to one developer team, so an IPA signed for someone else's identifiers cannot be signed for yours. Before signing, the identifiers inside the IPA are changed
to a prefix you own. The release uses these, with `com.phm` as the prefix:

| Where | Value in the release |
|---|---|
| App bundle id | `com.phm.noop` |
| Widget extension bundle id | `com.phm.noop.widgets` |
| App Group (app and widget) | `group.com.phm.noop.staging` |
| Background task ids (app `Info.plist`) | `com.phm.noop.debugexport`, `.healthwriteback`, `.rescore`, `.coachbrief` |

Use any prefix you control, for example `com.yourname.phmn`.

## Route A: build from source in Xcode

Needs a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. `cp Config/BundleIdSecrets.example.xcconfig Config/BundleIdSecrets.xcconfig` and set `BUNDLE_ID_PREFIX` (your own reverse-DNS prefix) and `DEVELOPMENT_TEAM` (your Team ID,
   shown at developer.apple.com under Membership, or in Xcode › Settings › Accounts for a free account). The file is gitignored.
2. `xcodegen generate`
3. Open `Strand.xcodeproj`, pick the **NOOPiOS** scheme and your iPhone (plugged in, with Developer Mode on: Settings › Privacy & Security › Developer Mode), and press Run.
   Xcode creates the App IDs, the App Group and the provisioning profile for you.
4. The first launch may ask you to trust the developer: Settings › General › VPN & Device Management.

With a free Apple ID the app expires after 7 days; run it from Xcode again to renew it.

## Route B: re-sign the IPA by hand

Needs a Mac, a **paid** Apple Developer account (or an enterprise certificate), and the release IPA. Commands are for a terminal; `PHMN.ipa` stands for the file you downloaded.

### 1. Create the profiles (once)

At developer.apple.com › Certificates, Identifiers & Profiles, using your prefix:

1. **Identifiers › App Groups**: register `group.<prefix>.noop.staging`.
2. **Identifiers › App IDs**: register `<prefix>.noop` with the **App Groups** (select the group above) and **HealthKit** capabilities, and `<prefix>.noop.widgets` with **App Groups**.
3. **Profiles**: create an *iOS App Development* profile (or *Ad Hoc* for sharing) for each App ID, tick your certificate and your device, and download both.
4. Install your signing certificate in the login Keychain. `security find-identity -v -p codesigning` lists it; use the full name, for example `Apple Development: Your Name (TEAMID)`.

### 2. Unpack and rename

```bash
PREFIX=com.yourname.phmn
mkdir work && cd work && unzip -q ../PHMN.ipa
APP=Payload/PHMN.app
EXT=$APP/PlugIns/NOOPWidgets.appex

plutil -replace CFBundleIdentifier -string $PREFIX.noop         $APP/Info.plist
plutil -replace CFBundleIdentifier -string $PREFIX.noop.widgets $EXT/Info.plist
for f in $APP/Info.plist $EXT/Info.plist; do
  plutil -replace AppGroupIdentifier -string group.$PREFIX.noop.staging "$f"
done
plutil -replace BGTaskSchedulerPermittedIdentifiers -json \
  "[\"$PREFIX.noop.debugexport\",\"$PREFIX.noop.healthwriteback\",\"$PREFIX.noop.rescore\",\"$PREFIX.noop.coachbrief\"]" \
  $APP/Info.plist
```

The App Group and the background task ids must be changed together with the bundle id: the app reads its group from `AppGroupIdentifier` (so the widget and the app share data), and iOS
only runs background tasks whose ids are listed in `Info.plist`.

### 3. Add the profiles and read the entitlements from them

```bash
cp ~/Downloads/PHMN_app.mobileprovision     $APP/embedded.mobileprovision
cp ~/Downloads/PHMN_widget.mobileprovision  $EXT/embedded.mobileprovision

for pair in "app:PHMN_app" "widget:PHMN_widget"; do
  name=${pair%%:*}; file=${pair##*:}
  security cms -D -i ~/Downloads/$file.mobileprovision > $name.plist
  /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' $name.plist > $name.entitlements
done
```

The entitlements come straight from the profile, so they always match what Apple granted (team id, App Group, HealthKit).

### 4. Sign from the inside out, then pack

```bash
ID="Apple Development: Your Name (TEAMID)"

# 4a. Remove the old (unsigned or ad-hoc) seal
find Payload -name _CodeSignature -type d -exec rm -rf {} +

# 4b. Sign any nested frameworks first (this release has none, but a source build might)
for fw in $APP/Frameworks/*; do [ -e "$fw" ] && codesign -f -s "$ID" "$fw"; done

# 4c. The widget extension, then the app
codesign -f -s "$ID" --entitlements widget.entitlements $EXT
codesign -f -s "$ID" --entitlements app.entitlements    $APP

# 4d. Check, then zip
codesign --verify --deep --strict --verbose=2 $APP
zip -qry ../PHMN-signed.ipa Payload
```

### 5. Install

With the phone connected, trusted and in Developer Mode:

```bash
xcrun devicectl list devices
xcrun devicectl device install app --device <device id> ../PHMN-signed.ipa
```

Xcode › Window › Devices and Simulators (drag the IPA onto the device) and Apple Configurator work the same way. An *Ad Hoc* IPA can also be shared with the other devices in its profile.

### If something goes wrong

- **"The application could not be verified" or it will not open**: the profile does not contain your device, or the certificate in it is not the one you signed with.
- **`codesign` says "no identity found"**: the certificate (with its private key) is not in the login Keychain.
- **Widgets show no data**: the App Group in the widget and the app differ, or the group is missing from one profile. Both must be `group.<prefix>.noop.staging`.
- **Apple Health says it is not available**: the app's profile has no HealthKit capability. A free Apple ID cannot provision it for an IPA; use Route A.
- **A background task never runs**: an id in `BGTaskSchedulerPermittedIdentifiers` does not start with your new prefix (step 2).

## Why the release is unsigned

Anyone can read an app's bundle ids and signature, so the project ships no signature and no identifiers tied to a person. Signing is the step that ties a build to *you* and your device.
