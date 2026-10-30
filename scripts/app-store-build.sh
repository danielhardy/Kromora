#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

if (( $# > 1 )); then
  print -u2 "usage: scripts/app-store-build.sh [verify|archive]"
  exit 2
fi

mode="${1:-verify}"
if [[ "$mode" != "verify" && "$mode" != "archive" ]]; then
  print -u2 "usage: scripts/app-store-build.sh [verify|archive]"
  exit 2
fi

project="Kromora.xcodeproj"
configuration="Release"
destination="platform=macOS,arch=arm64"
derived_data_path=".build/xcode"

[[ -d "$project" ]] || { print -u2 "missing Xcode project: $project"; exit 1; }

# The Swift package exports a product with the same name. Once Xcode has resolved the package it
# lists the app scheme as "Kromora (Kromora project)"; a fresh checkout, such as CI, lists plain
# "Kromora". Select whichever name this checkout actually exposes.
scheme="Kromora"
if xcodebuild -project "$project" -list 2>/dev/null | grep -qx '[[:space:]]*Kromora (Kromora project)'; then
  scheme="Kromora (Kromora project)"
fi

signing_args=()
if [[ "$mode" == "archive" ]]; then
  [[ -n "${DEVELOPMENT_TEAM:-}" ]] || {
    print -u2 "archive mode requires DEVELOPMENT_TEAM; set it to your Apple Developer team ID."
    exit 1
  }
  signing_args+=("CODE_SIGN_STYLE=Automatic" "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
  signing_args+=("CODE_SIGN_IDENTITY=${KROMORA_CODESIGN_IDENTITY:-Apple Development}")
else
  if [[ -n "${KROMORA_CODESIGN_IDENTITY:-}" ]]; then
    signing_args+=("CODE_SIGN_STYLE=Manual" "CODE_SIGN_IDENTITY=$KROMORA_CODESIGN_IDENTITY")
    if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
      signing_args+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
    fi
  elif [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    signing_args+=("CODE_SIGN_STYLE=Automatic" "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
    signing_args+=("CODE_SIGN_IDENTITY=Apple Development")
  else
    signing_args+=("CODE_SIGN_STYLE=Manual" "CODE_SIGN_IDENTITY=-")
  fi
fi

xcodebuild_args=(
  -project "$project"
  -scheme "$scheme"
  -configuration "$configuration"
  -destination "$destination"
  -derivedDataPath "$derived_data_path"
)

# Preserve the short revision shown in About for distributable builds while letting
# direct Xcode development builds use the existing "Development build" fallback.
git_commit="$(git rev-parse --short=12 HEAD 2>/dev/null || true)"
build_metadata_args=()
if [[ -n "$git_commit" ]]; then
  build_metadata_args+=("KROMORA_GIT_COMMIT=$git_commit")
fi

# KROMORA_VERIFICATION_BUILD=1 enables the KROMORA_LIBRARY_PACKAGE override for an isolated smoke
# against a throwaway bundle id. It is verify-only so no archive can carry the override.
if [[ "${KROMORA_VERIFICATION_BUILD:-}" == "1" ]]; then
  [[ "$mode" == "verify" ]] || { print -u2 "KROMORA_VERIFICATION_BUILD=1 is not allowed for archive builds."; exit 1; }
  build_metadata_args+=("KROMORA_ALLOW_LIBRARY_OVERRIDE=YES")
fi

if [[ "$mode" == "verify" ]]; then
  xcodebuild "${xcodebuild_args[@]}" "${signing_args[@]}" "${build_metadata_args[@]}" build
  "$project_root/scripts/verify-xcode-app.sh"
else
  archive_path="$derived_data_path/Kromora.xcarchive"
  xcodebuild "${xcodebuild_args[@]}" "${signing_args[@]}" "${build_metadata_args[@]}" -archivePath "$archive_path" archive
  print "Archive created at ${archive_path:A}"
  print "Open that .xcarchive to show it in Xcode Organizer, then choose Distribute App > App Store Connect."
fi
