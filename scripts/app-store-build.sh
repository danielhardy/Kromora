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

# One "label<TAB>team" line per valid codesigning identity. The team is the certificate
# subject OU. An Apple Development common name puts a different identifier in parentheses,
# so that display name is not the team Xcode shows.
signing_identity_rows() {
  local label pem rest cert hash team valid_hashes
  local -a labels=("Apple Development" "Apple Distribution" "Developer ID Application")
  valid_hashes="$(security find-identity -v -p codesigning 2>/dev/null | sed -nE 's/^[[:space:]]*[0-9]+) ([A-F0-9]{40}) .*/\1/p')"
  for label in "${labels[@]}"; do
    pem="$(security find-certificate -a -c "$label" -p 2>/dev/null || true)"
    rest="$pem"
    while [[ "$rest" == *"BEGIN CERTIFICATE"* ]]; do
      cert="${rest#*-----BEGIN CERTIFICATE-----}"
      cert="-----BEGIN CERTIFICATE-----${cert%%-----END CERTIFICATE-----*}-----END CERTIFICATE-----"
      rest="${rest#*-----END CERTIFICATE-----}"
      hash="$(print -r -- "$cert" | openssl x509 -noout -fingerprint -sha1 2>/dev/null | sed -nE 's/.*=([0-9A-F:]+)/\1/p' | tr -d ':')"
      [[ -n "$hash" && "$valid_hashes" == *"$hash"* ]] || continue
      team="$(print -r -- "$cert" | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null | sed -nE 's/.*OU=([A-Z0-9]{10}).*/\1/p')"
      [[ -n "$team" ]] || continue
      print -r -- "${label}"$'\t'"${team}"
    done
  done
}

signing_args=()
if [[ "$mode" == "archive" ]]; then
  # The team ID stays out of the repo. DEVELOPMENT_TEAM still wins; otherwise use the
  # team stamped on the local codesigning certificates when exactly one team is present.
  identity_rows="$(signing_identity_rows)"
  if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    teams=("${(@f)$(print -r -- "$identity_rows" | cut -f2 | sort -u)}")
    teams=("${(@)teams:#}")
    # A personal team often sits beside the App Store team. Prefer the single team that
    # holds the Apple Distribution certificate so the personal team is not selected.
    distribution_teams=("${(@f)$(print -r -- "$identity_rows" | awk -F '\t' '$1 == "Apple Distribution" { print $2 }' | sort -u)}")
    distribution_teams=("${(@)distribution_teams:#}")
    if (( ${#teams} == 1 )); then
      DEVELOPMENT_TEAM="${teams[1]}"
      print "Using DEVELOPMENT_TEAM ${DEVELOPMENT_TEAM} from the local signing certificate."
    elif (( ${#distribution_teams} == 1 )); then
      DEVELOPMENT_TEAM="${distribution_teams[1]}"
      print "Using DEVELOPMENT_TEAM ${DEVELOPMENT_TEAM} from the local Apple Distribution certificate."
    elif (( ${#teams} == 0 )); then
      print -u2 "archive mode requires DEVELOPMENT_TEAM; no local codesigning certificate includes a team ID. Set DEVELOPMENT_TEAM to your Apple Developer team ID."
      exit 1
    else
      print -u2 "archive mode found more than one team (${(j:, :)teams}). Set DEVELOPMENT_TEAM to the one to use."
      exit 1
    fi
  fi

  if [[ -n "${KROMORA_CODESIGN_IDENTITY:-}" ]]; then
    archive_identity="$KROMORA_CODESIGN_IDENTITY"
  elif print -r -- "$identity_rows" | awk -F '\t' -v team="$DEVELOPMENT_TEAM" '$1 == "Apple Development" && $2 == team { found = 1 } END { exit !found }'; then
    archive_identity="Apple Development"
  else
    print -u2 "No Apple Development certificate for team ${DEVELOPMENT_TEAM} is installed on this Mac."
    print -u2 "Automatic signing cannot use an Apple Distribution or Developer ID certificate. Create an Apple Development certificate in Xcode Settings > Accounts > Manage Certificates, or export that certificate and its private key from the other Mac and import it here."
    exit 1
  fi

  signing_args+=("CODE_SIGN_STYLE=Automatic" "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
  signing_args+=("CODE_SIGN_IDENTITY=$archive_identity")
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
