#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

app_bundle="${1:-.build/xcode/Build/Products/Release/Kromora.app}"
[[ -d "$app_bundle" ]] || {
  print -u2 "missing $app_bundle; run scripts/app-store-build.sh first"
  exit 1
}

/usr/bin/codesign --verify --deep --strict "$app_bundle"
dump="$(mktemp -t kromora-entitlements).plist"
trap 'rm -f "$dump"' EXIT
/usr/bin/codesign -d --entitlements :- "$app_bundle" > "$dump" 2>/dev/null

python3 - "$dump" "$app_bundle" <<'PY'
import pathlib
import plistlib
import sys

entitlements_path, app_dir = map(pathlib.Path, sys.argv[1:])
try:
    entitlements = plistlib.loads(entitlements_path.read_bytes())
except Exception as exc:
    raise SystemExit(f"could not decode embedded entitlements: {exc}")

expected = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.files.removable-media.read-only": True,
    "com.apple.security.files.bookmarks.app-scope": True,
    "com.apple.security.assets.pictures.read-write": True,
}
security_entitlements = {
    key: value for key, value in entitlements.items() if key.startswith("com.apple.security.")
}
missing = sorted(expected.keys() - security_entitlements.keys())
unexpected = sorted(security_entitlements.keys() - expected.keys())
incorrect = {
    key: {"actual": security_entitlements[key], "expected": expected[key]}
    for key in expected.keys() & security_entitlements.keys()
    if security_entitlements[key] is not expected[key]
}
if missing or unexpected or incorrect:
    raise SystemExit(
        "embedded App Sandbox entitlements do not match the expected set: "
        f"missing={missing}, unexpected={unexpected}, incorrect={incorrect}"
    )

print(f"verified strict code signature and {len(expected)} expected entitlements on {app_dir}")
PY
