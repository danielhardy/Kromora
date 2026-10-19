#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_root="$script_dir/.."
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

"$script_dir/check-sandbox-entitlements.py" "$dump" embedded
print "verified strict code signature on $app_bundle"
