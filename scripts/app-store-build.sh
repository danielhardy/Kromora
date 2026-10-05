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

project="Xcode/Kromora.xcodeproj"
# The Swift package exports a product with the same name, so xcodebuild requires
# the project-qualified name shown by `xcodebuild -list` to select the app scheme.
scheme="Kromora (Kromora project)"
configuration="Release"
destination="platform=macOS,arch=arm64"
derived_data_path=".build/xcode"

[[ -d "$project" ]] || { print -u2 "missing Xcode project: $project"; exit 1; }

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

if [[ "$mode" == "verify" ]]; then
  xcodebuild "${xcodebuild_args[@]}" "${signing_args[@]}" build
  "$project_root/scripts/verify-xcode-app.sh"
else
  archive_path="$derived_data_path/Kromora.xcarchive"
  xcodebuild "${xcodebuild_args[@]}" "${signing_args[@]}" -archivePath "$archive_path" archive
  print "Archive created at $archive_path"
  print "Open Xcode Organizer (Window > Organizer), select the Kromora archive, then choose Distribute App > App Store Connect."
fi
