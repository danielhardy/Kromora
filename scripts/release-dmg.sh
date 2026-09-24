#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

usage() {
  cat <<'EOF'
Usage: scripts/release-dmg.sh [version]

Build, sign, notarize, staple, and verify a universal Kromora DMG.

Environment:
  KROMORA_VERSION                 Version override when no positional version is given
  KROMORA_BUILD_NUMBER            CFBundleVersion override (default: git commit count)
  KROMORA_CODESIGN_IDENTITY       Developer ID Application identity (required for distribution)
  KROMORA_PROVISIONING_PROFILE    App Sandbox provisioning profile (required for distribution)
  KROMORA_NOTARY_PROFILE           Keychain profile for xcrun notarytool (required unless skipped)
  KROMORA_BUNDLE_IDENTIFIER        Optional bundle identifier override
  KROMORA_SKIP_NOTARIZE=1          Local signed dry-run; never suitable for shipping
  KROMORA_RELEASE_DIR              Output directory (default: .build/releases)

The default build is arm64+x86_64. Set KROMORA_SKIP_NOTARIZE=1 to build locally
without contacting Apple; an identity is optional in that mode and defaults to ad hoc.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

info_plist="Sources/Kromora/Info.plist"
entitlements="Sources/Kromora/Kromora.entitlements"
app_bundle=".build/Kromora.app"
release_dir="${KROMORA_RELEASE_DIR:-.build/releases}"
skip_notarize="${KROMORA_SKIP_NOTARIZE:-0}"
version="${1:-${KROMORA_VERSION:-}}"

[[ -f "$info_plist" ]] || { print -u2 "missing bundle metadata: $info_plist"; exit 1; }
[[ -f "$entitlements" ]] || { print -u2 "missing entitlements: $entitlements"; exit 1; }
[[ -n "$version" ]] || version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$info_plist")"
[[ "$version" =~ '^[0-9]+([.][0-9]+){1,2}([.-][0-9A-Za-z-]+)?$' ]] || {
  print -u2 "invalid version '$version'; use a numeric CFBundleShortVersionString such as 1.2.3"
  exit 1
}

build_number="${KROMORA_BUILD_NUMBER:-}"
if [[ -z "$build_number" ]]; then
  build_number="$(git rev-list --count HEAD 2>/dev/null || true)"
fi
[[ "$build_number" =~ '^[0-9]+$' && "$build_number" != 0 ]] || {
  print -u2 "KROMORA_BUILD_NUMBER or a git history is required for CFBundleVersion"
  exit 1
}

signing_identity="${KROMORA_CODESIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}"
if [[ "$skip_notarize" == "1" ]]; then
  signing_identity="${signing_identity:--}"
else
  [[ -n "$signing_identity" && "$signing_identity" != "-" ]] || {
    print -u2 "distribution requires KROMORA_CODESIGN_IDENTITY (a Developer ID Application identity)"
    exit 1
  }
  notary_profile="${KROMORA_NOTARY_PROFILE:-}"
  [[ -n "$notary_profile" ]] || {
    print -u2 "distribution requires KROMORA_NOTARY_PROFILE"
    exit 1
  }
  provisioning_profile="${KROMORA_PROVISIONING_PROFILE:-}"
  [[ -n "$provisioning_profile" ]] || {
    print -u2 "distribution requires KROMORA_PROVISIONING_PROFILE for the App Sandbox bundle"
    exit 1
  }
  [[ -f "$provisioning_profile" ]] || {
    print -u2 "configured provisioning profile does not exist: $provisioning_profile"
    exit 1
  }
  identity_line="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep -F "$signing_identity" | head -1 || true)"
  [[ "$identity_line" == *"Developer ID Application:"* ]] || {
    print -u2 "identity '$signing_identity' is not an available Developer ID Application certificate"
    exit 1
  }
fi

command -v swift >/dev/null || { print -u2 "missing swift"; exit 1; }
[[ -x /usr/bin/codesign ]] || { print -u2 "missing /usr/bin/codesign"; exit 1; }
[[ -x /usr/bin/hdiutil ]] || { print -u2 "missing /usr/bin/hdiutil"; exit 1; }
[[ -x /usr/bin/xcrun ]] || { print -u2 "missing /usr/bin/xcrun"; exit 1; }

mkdir -p "$release_dir"
release_dmg="$release_dir/Kromora-$version.dmg"
work_dmg="$release_dir/.Kromora-$version.work.dmg"
app_notarize_zip="$release_dir/.Kromora-$version.app.zip"
staging_dir=".build/Kromora-dmg-staging"
mount_dir=".build/Kromora-dmg-mount"
success=0
mounted=0

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  if [[ "$mounted" == 1 ]]; then
    /usr/bin/hdiutil detach "$mount_dir" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$staging_dir" "$mount_dir" "$work_dmg"
  rm -f "$app_notarize_zip"
  if [[ "$success" != 1 ]]; then
    rm -f "$release_dmg"
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

print "Building Kromora $version (build $build_number; identity: $signing_identity)"
KROMORA_CODESIGN_IDENTITY="$signing_identity" \
KROMORA_BUILD_ARCHS="arm64,x86_64" \
KROMORA_DIRECT_DISTRIBUTION=1 \
  scripts/build-macos-app.sh

[[ -x "$app_bundle/Contents/MacOS/Kromora" ]] || { print -u2 "missing app executable"; exit 1; }
[[ -f "$app_bundle/Contents/Info.plist" ]] || { print -u2 "missing app Info.plist"; exit 1; }
[[ -f "$app_bundle/Contents/Resources/Kromora.icns" ]] || { print -u2 "missing app icon"; exit 1; }
[[ -d "$app_bundle/Contents/Resources/Kromora_KromoraKit.bundle" ]] || {
  print -u2 "missing KromoraKit resource bundle"
  exit 1
}
[[ -f "$app_bundle/Contents/Resources/Kromora_KromoraKit.bundle/Contents/Resources/Resources/StarterLooks/manifest.json" ]] || {
  print -u2 "missing StarterLooks resource manifest"
  exit 1
}

/usr/bin/plutil -replace CFBundleShortVersionString -string "$version" "$app_bundle/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$build_number" "$app_bundle/Contents/Info.plist"
if [[ -n "${KROMORA_BUNDLE_IDENTIFIER:-}" ]]; then
  /usr/bin/plutil -replace CFBundleIdentifier -string "$KROMORA_BUNDLE_IDENTIFIER" "$app_bundle/Contents/Info.plist"
fi
[[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$app_bundle/Contents/Info.plist")" == "$version" ]] || {
  print -u2 "app version did not update to $version"
  exit 1
}
scripts/verify-app-icon.sh

codesign_args=(--force --sign "$signing_identity" --entitlements "$entitlements")
if [[ "$signing_identity" != "-" ]]; then
  codesign_args+=(--options runtime --timestamp)
fi
/usr/bin/codesign "${codesign_args[@]}" "$app_bundle"
/usr/bin/codesign --verify --deep --strict "$app_bundle"
scripts/verify-app-signature.sh "$app_bundle"
if [[ "$signing_identity" != "-" ]]; then
  signature_details="$(/usr/bin/codesign -d --verbose=4 "$app_bundle" 2>&1)"
  [[ "$signature_details" == *"runtime"* ]] || {
    print -u2 "Developer ID app signature is missing the hardened runtime option"
    exit 1
  }
fi

archs="$(/usr/bin/lipo -archs "$app_bundle/Contents/MacOS/Kromora")"
[[ "$archs" == *"arm64"* && "$archs" == *"x86_64"* ]] || {
  print -u2 "app executable is not universal (reported architectures: $archs)"
  exit 1
}

if [[ "$skip_notarize" != "1" ]]; then
  print "Notarizing and stapling app"
  rm -f "$app_notarize_zip"
  /usr/bin/ditto -c -k --keepParent "$app_bundle" "$app_notarize_zip"
  /usr/bin/xcrun notarytool submit "$app_notarize_zip" --keychain-profile "$notary_profile" --wait
  rm -f "$app_notarize_zip"
  /usr/bin/xcrun stapler staple "$app_bundle"
  /usr/bin/xcrun stapler validate "$app_bundle"
fi

rm -rf "$staging_dir" "$mount_dir" "$work_dmg"
mkdir -p "$staging_dir" "$mount_dir"
cp -R "$app_bundle" "$staging_dir/Kromora.app"
ln -s /Applications "$staging_dir/Applications"

/usr/bin/hdiutil create \
  -volname "Kromora $version" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -ov \
  "$work_dmg" >/dev/null

codesign_dmg_args=(--force --sign "$signing_identity")
if [[ "$signing_identity" != "-" ]]; then
  codesign_dmg_args+=(--timestamp)
fi
/usr/bin/codesign "${codesign_dmg_args[@]}" "$work_dmg"
/usr/bin/codesign --verify --strict "$work_dmg"

if [[ "$skip_notarize" != "1" ]]; then
  print "Notarizing and stapling DMG"
  /usr/bin/xcrun notarytool submit "$work_dmg" --keychain-profile "$notary_profile" --wait
  /usr/bin/xcrun stapler staple "$work_dmg"
  /usr/bin/xcrun stapler validate "$work_dmg"
fi

/usr/bin/hdiutil attach "$work_dmg" -nobrowse -readonly -mountpoint "$mount_dir" >/dev/null
mounted=1
[[ -d "$mount_dir/Kromora.app" ]] || { print -u2 "DMG does not contain Kromora.app"; exit 1; }
[[ -x "$mount_dir/Kromora.app/Contents/MacOS/Kromora" ]] || { print -u2 "DMG app is missing its executable"; exit 1; }
[[ -f "$mount_dir/Kromora.app/Contents/Info.plist" ]] || { print -u2 "DMG app is missing Info.plist"; exit 1; }
[[ -f "$mount_dir/Kromora.app/Contents/Resources/Kromora.icns" ]] || { print -u2 "DMG app is missing its icon"; exit 1; }
[[ -d "$mount_dir/Kromora.app/Contents/Resources/Kromora_KromoraKit.bundle" ]] || {
  print -u2 "DMG app is missing KromoraKit resources"
  exit 1
}
[[ -f "$mount_dir/Kromora.app/Contents/Resources/Kromora_KromoraKit.bundle/Contents/Resources/Resources/StarterLooks/manifest.json" ]] || {
  print -u2 "DMG app is missing StarterLooks resources"
  exit 1
}
scripts/verify-app-signature.sh "$mount_dir/Kromora.app"
/usr/bin/hdiutil detach "$mount_dir" >/dev/null
mounted=0

mv "$work_dmg" "$release_dmg"
success=1
print "Release artifact: $release_dmg"
if [[ "$skip_notarize" == "1" ]]; then
  print "WARNING: KROMORA_SKIP_NOTARIZE=1 produced a local dry-run artifact; it is not shippable."
fi
