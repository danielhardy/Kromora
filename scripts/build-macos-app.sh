#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

icon_composer="Kromora.icon"
info_plist="Sources/Kromora/Info.plist"
entitlements="Sources/Kromora/Kromora.entitlements"
asset_output=".build/kromora-icon-asset-validation"
app_bundle=".build/Kromora.app"
signing_identity="${KROMORA_CODESIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
provisioning_profile="${KROMORA_PROVISIONING_PROFILE:-${PROVISIONING_PROFILE:-}}"
build_arches="${KROMORA_BUILD_ARCHS:-native}"

[[ -d "$icon_composer" ]] || { print -u2 "missing Icon Composer asset: $icon_composer"; exit 1; }
[[ -f "$icon_composer/icon.json" ]] || { print -u2 "missing Icon Composer manifest: $icon_composer/icon.json"; exit 1; }
[[ -f "$info_plist" ]] || { print -u2 "missing bundle metadata: $info_plist"; exit 1; }
[[ -f "$entitlements" ]] || { print -u2 "missing entitlements: $entitlements"; exit 1; }
if [[ -n "$provisioning_profile" && ! -f "$provisioning_profile" ]]; then
  print -u2 "configured provisioning profile does not exist: $provisioning_profile"
  exit 1
fi

# Generate into disposable paths so packaging never mutates tracked source assets.
rm -rf "$asset_output" "$app_bundle"
mkdir -p "$asset_output" "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"

# Build the executable through SwiftPM, then put it in a normal macOS bundle.
# SPM intentionally has no app-bundle Info.plist phase, so this small
# packaging step is the reproducible bridge used by local/archive workflows.
if [[ "$build_arches" == "native" ]]; then
  swift build -c release --product Kromora
  bin_path="$(swift build -c release --show-bin-path)"
  cp "$bin_path/Kromora" "$app_bundle/Contents/MacOS/Kromora"
  resource_bundle="$bin_path/Kromora_KromoraKit.bundle"
else
  [[ "$build_arches" == "arm64,x86_64" ]] || {
    print -u2 "KROMORA_BUILD_ARCHS must be native or arm64,x86_64"
    exit 1
  }
  command -v lipo >/dev/null || { print -u2 "missing lipo for a universal build"; exit 1; }

  universal_inputs=()
  resource_bundle=""
  for arch in arm64 x86_64; do
    scratch_path=".build/swiftpm-$arch"
    swift build -c release --product Kromora \
      --scratch-path "$scratch_path" \
      --triple "$arch-apple-macosx14.0"
    arch_bin_path="$(swift build -c release --product Kromora \
      --scratch-path "$scratch_path" \
      --triple "$arch-apple-macosx14.0" --show-bin-path)"
    universal_inputs+=("$arch_bin_path/Kromora")
    [[ -n "$resource_bundle" ]] || resource_bundle="$arch_bin_path/Kromora_KromoraKit.bundle"
  done
  lipo -create "${universal_inputs[@]}" -output "$app_bundle/Contents/MacOS/Kromora"
fi

# SwiftPM emits resources for the KromoraKit target as a sibling bundle next to
# the executable. Package code resolves it from Bundle.main.resourceURL when
# running inside the packaged app, so ship it in the standard Resources folder.
[[ -d "$resource_bundle" ]] || {
  print -u2 "missing SwiftPM resource bundle: $resource_bundle"
  exit 1
}
cp -R "$resource_bundle" "$app_bundle/Contents/Resources/"

# Icon Composer assets are compiled by Xcode's actool. `/usr/bin/actool` on
# some macOS installations is an older compatibility tool, so resolve the
# Xcode-provided compiler explicitly through xcrun.
/usr/bin/xcrun actool "$icon_composer" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --target-device mac \
  --app-icon Kromora \
  --include-all-app-icons \
  --output-partial-info-plist "$asset_output/asset-info.plist" \
  --compile "$app_bundle/Contents/Resources" >/dev/null

cp "$info_plist" "$app_bundle/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIconName -string Kromora "$app_bundle/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIconFile -string Kromora.icns "$app_bundle/Contents/Info.plist"
[[ -f "$app_bundle/Contents/Resources/Kromora.icns" ]] || {
  print -u2 "actool did not produce the Icon Composer ICNS output"
  exit 1
}

if [[ -n "$provisioning_profile" ]]; then
  cp "$provisioning_profile" "$app_bundle/Contents/embedded.provisionprofile"
fi

# Sign after every distributed resource is present. '-' is the documented local/CI
# fallback and still embeds the declared entitlements.
codesign_args=(--force --sign "$signing_identity" --entitlements "$entitlements")
if [[ "$signing_identity" != "-" ]]; then
  codesign_args+=(--options runtime --timestamp)
fi
/usr/bin/codesign "${codesign_args[@]}" "$app_bundle"
/usr/bin/codesign --verify --deep --strict "$app_bundle"

print "Built and verified $app_bundle (identity: $signing_identity; arches: $build_arches)"
