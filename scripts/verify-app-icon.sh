#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

icon_composer="Kromora.icon"
app_bundle=".build/Kromora.app"

[[ -f "$icon_composer/icon.json" ]] || { print -u2 "missing Icon Composer manifest"; exit 1; }
[[ -d "$app_bundle" ]] || { print -u2 "missing $app_bundle; run scripts/build-macos-app.sh first"; exit 1; }

python3 - "$icon_composer" "$app_bundle" <<'PY'
import json
import pathlib
import plistlib
import sys

icon_dir, app_dir = map(pathlib.Path, sys.argv[1:])
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
if info.get("CFBundleIconFile") != "Kromora.icns":
    raise SystemExit("application target does not reference Kromora.icns")
if not (app_dir / "Contents/Resources/Assets.car").is_file():
    raise SystemExit("compiled application is missing Icon Composer Contents/Resources/Assets.car")
if not (app_dir / "Contents/Resources/Kromora.icns").is_file():
    raise SystemExit("compiled application is missing Contents/Resources/Kromora.icns")
resource_bundle = app_dir / "Contents/Resources/Kromora_KromoraKit.bundle"
if not (resource_bundle / "Resources/StarterLooks/manifest.json").is_file():
    raise SystemExit("compiled application resource bundle is missing Resources/StarterLooks/manifest.json")
if not (app_dir / "Contents/MacOS/Kromora").is_file():
    raise SystemExit("compiled application is missing Contents/MacOS/Kromora")

print("verified Icon Composer manifest and layer assets, CFBundleIconName=Kromora, Kromora.icns, Assets.car, and executable")
PY
