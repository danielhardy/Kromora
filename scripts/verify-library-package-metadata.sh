#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

python3 - "Sources/Kromora/Info.plist" "Sources/Kromora/Kromora.entitlements" <<'PY'
import pathlib
import plistlib
import sys

info_path, entitlements_path = map(pathlib.Path, sys.argv[1:])
info = plistlib.loads(info_path.read_bytes())
entitlements = plistlib.loads(entitlements_path.read_bytes())

expected_uti = "com.kromora.kromoralibrary"
expected_extension = "kromoralibrary"
document_types = info.get("CFBundleDocumentTypes", [])
if not any(
    expected_uti in entry.get("LSItemContentTypes", [])
    and entry.get("CFBundleTypeRole") == "Editor"
    and entry.get("LSHandlerRank") == "Owner"
    for entry in document_types
):
    raise SystemExit("Kromora Library document declaration is missing or not editor/owner")

declarations = info.get("UTExportedTypeDeclarations", [])
if not any(
    entry.get("UTTypeIdentifier") == expected_uti
    and expected_extension in entry.get("UTTypeTagSpecification", {}).get(
        "public.filename-extension", []
    )
    and "com.apple.package" in entry.get("UTTypeConformsTo", [])
    for entry in declarations
):
    raise SystemExit("Kromora Library UTI declaration is missing package/extension metadata")

if entitlements.get("com.apple.security.assets.pictures.read-write") is not True:
    raise SystemExit("Pictures read-write entitlement is missing")

print("verified Kromora Library package declaration and Pictures entitlement")
PY
