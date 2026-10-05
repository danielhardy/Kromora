#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
caller_directory="$PWD"

if (( $# > 1 )); then
  print -u2 "usage: scripts/verify-xcode-app.sh [path/to/Kromora.app]"
  exit 2
fi

if (( $# == 1 )); then
  app_bundle="$1"
  [[ "$app_bundle" == /* ]] || app_bundle="$caller_directory/$app_bundle"
else
  app_bundle="$project_root/.build/xcode/Build/Products/Release/Kromora.app"
fi

[[ -d "$app_bundle" ]] || { print -u2 "missing app bundle: $app_bundle"; exit 1; }

info_plist="$app_bundle/Contents/Info.plist"
executable="$app_bundle/Contents/MacOS/Kromora"
[[ -f "$info_plist" ]] || { print -u2 "missing app Info.plist: $info_plist"; exit 1; }
[[ -f "$executable" ]] || { print -u2 "missing app executable: $executable"; exit 1; }

python3 - "$info_plist" <<'PY'
import pathlib
import plistlib
import sys

info = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
expected = {
    "CFBundleIdentifier": "com.last8.kromora.photo",
    "LSApplicationCategoryType": "public.app-category.photography",
    "ITSAppUsesNonExemptEncryption": False,
    "LSMinimumSystemVersion": "26.0",
}
incorrect = {
    key: {"actual": info.get(key), "expected": value}
    for key, value in expected.items()
    if info.get(key) != value or type(info.get(key)) is not type(value)
}
usage = info.get("NSPhotoLibraryUsageDescription")
if not isinstance(usage, str) or not usage.strip():
    incorrect["NSPhotoLibraryUsageDescription"] = {"actual": usage, "expected": "non-empty string"}
if incorrect:
    raise SystemExit(f"Xcode app Info.plist does not match required metadata: {incorrect}")

print("verified bundle identifier, category, encryption flag, Photos usage string, and macOS 26 minimum")
PY

# Exercise the same Foundation Bundle lookup used by KromoraKitResourceBundle and
# BundledLookLibrary against this app bundle, including every manifest-listed LUT.
/usr/bin/swift - "$app_bundle" <<'SWIFT'
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("expected the Xcode-built app bundle path")
}
let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard let appBundle = Bundle(url: appURL), let resourcesURL = appBundle.resourceURL else {
    fatalError("could not open Xcode app bundle or its resource directory: \(appURL.path)")
}
let packageURL = resourcesURL.appendingPathComponent("Kromora_KromoraKit.bundle", isDirectory: true)
guard let packageBundle = Bundle(url: packageURL) else {
    fatalError("could not resolve Kromora_KromoraKit.bundle from Bundle.main.resourceURL: \(packageURL.path)")
}
guard let manifestURL = packageBundle.url(
    forResource: "manifest",
    withExtension: "json",
    subdirectory: "Resources/StarterLooks"
) else {
    fatalError("could not resolve Resources/StarterLooks/manifest.json from the Xcode app's package bundle")
}
let manifestData = try Data(contentsOf: manifestURL)
let manifest = try JSONSerialization.jsonObject(with: manifestData)
guard let object = manifest as? [String: Any],
      let looks = object["looks"] as? [[String: Any]],
      !looks.isEmpty else {
    fatalError("Starter Looks manifest contains no Looks")
}
for look in looks {
    guard let resource = look["resource"] as? String else {
        fatalError("Starter Looks manifest has an entry without a resource")
    }
    let name = (resource as NSString).deletingPathExtension
    let ext = (resource as NSString).pathExtension
    guard packageBundle.url(
        forResource: name,
        withExtension: ext,
        subdirectory: "Resources/StarterLooks"
    ) != nil else {
        fatalError("could not resolve Starter Look resource from the Xcode app bundle: \(resource)")
    }
}
print("verified Xcode app bundle lookup for StarterLooks/manifest.json and all \(looks.count) bundled Looks")
SWIFT

updater_matches="$(/usr/bin/strings "$executable" | /usr/bin/grep -F 'api.github.com' || true)"
[[ -z "$updater_matches" ]] || {
  print -u2 "Xcode app executable contains GitHub updater endpoint remnants:"
  print -u2 -- "$updater_matches"
  exit 1
}
print "verified executable has no api.github.com updater endpoint remnants"

"$project_root/scripts/verify-app-signature.sh" "$app_bundle"
"$project_root/scripts/verify-app-icon.sh" "$app_bundle"

print "verified Xcode-built app: $app_bundle"
