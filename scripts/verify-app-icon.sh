#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
caller_directory="$PWD"
default_app_bundle="$project_root/.build/xcode/Build/Products/Release/Kromora.app"

if (( $# > 1 )); then
  print -u2 "usage: scripts/verify-app-icon.sh [app-bundle-path]"
  exit 2
fi

icon_composer="Kromora.icon"
if (( $# == 1 )); then
  app_bundle="$1"
  [[ "$app_bundle" == /* ]] || app_bundle="$caller_directory/$app_bundle"
else
  app_bundle="$default_app_bundle"
fi

cd "$project_root"

[[ -f "$icon_composer/icon.json" ]] || { print -u2 "missing Icon Composer manifest"; exit 1; }
[[ -d "$app_bundle" ]] || {
  print -u2 "missing app bundle: $app_bundle; run scripts/app-store-build.sh first"
  exit 1
}

python3 - "$icon_composer" "$app_bundle" <<'PY'
import json
import pathlib
import plistlib
import subprocess
import sys

icon_dir, app_dir = map(pathlib.Path, sys.argv[1:3])
manifest = json.loads((icon_dir / "icon.json").read_text())
if not manifest.get("groups"):
    raise SystemExit("Icon Composer manifest has no groups")

for group in manifest["groups"]:
    for layer in group.get("layers", []):
        filename = layer.get("image-name")
        if not filename or pathlib.Path(filename).name != filename:
            raise SystemExit(f"Icon Composer layer has no safe image filename: {layer}")
        image_path = icon_dir / "Assets" / filename
        if not image_path.is_file():
            raise SystemExit(f"missing Icon Composer layer image: {image_path}")

info = plistlib.loads((app_dir / "Contents/Info.plist").read_bytes())
if info.get("CFBundleIconName") != "Kromora":
    raise SystemExit("application target does not reference Kromora.icon")
assets_car = app_dir / "Contents/Resources/Assets.car"
if not assets_car.is_file():
    raise SystemExit("compiled application is missing Icon Composer Contents/Resources/Assets.car")
asset_info = subprocess.run(
    ["/usr/bin/assetutil", "--info", str(assets_car)],
    check=True,
    capture_output=True,
    text=True,
)
compiled_assets = json.loads(asset_info.stdout)
if not any(asset.get("Name") == "Kromora" for asset in compiled_assets):
    raise SystemExit("compiled Assets.car has no app icon named Kromora")
resource_bundle = app_dir / "Contents/Resources/Kromora_KromoraKit.bundle"
resource_manifest_candidates = [
    resource_bundle / "Resources/StarterLooks/manifest.json",
    resource_bundle / "Contents/Resources/StarterLooks/manifest.json",
    resource_bundle / "Contents/Resources/Resources/StarterLooks/manifest.json",
]
if not any(path.is_file() for path in resource_manifest_candidates):
    raise SystemExit("compiled application resource bundle is missing StarterLooks/manifest.json")
if not (app_dir / "Contents/MacOS/Kromora").is_file():
    raise SystemExit("compiled application is missing Contents/MacOS/Kromora")

print("verified Icon Composer manifest and layer assets, CFBundleIconName=Kromora, Assets.car app icon, and executable")
PY
