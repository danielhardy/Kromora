#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

python3 - "App/Info.plist" "App/Kromora.entitlements" <<'PY'
import pathlib
import plistlib
import sys

info_path, entitlements_path = map(pathlib.Path, sys.argv[1:])
info = plistlib.loads(info_path.read_bytes())
entitlements = plistlib.loads(entitlements_path.read_bytes())

expected_security_entitlements = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.files.removable-media.read-only": True,
    "com.apple.security.files.bookmarks.app-scope": True,
    "com.apple.security.assets.pictures.read-write": True,
}
security_entitlements = {
    key: value for key, value in entitlements.items() if key.startswith("com.apple.security.")
}
missing = sorted(expected_security_entitlements.keys() - security_entitlements.keys())
unexpected = sorted(security_entitlements.keys() - expected_security_entitlements.keys())
incorrect = {
    key: {"actual": security_entitlements[key], "expected": expected_security_entitlements[key]}
    for key in expected_security_entitlements.keys() & security_entitlements.keys()
    if security_entitlements[key] is not expected_security_entitlements[key]
}
if missing or unexpected or incorrect:
    raise SystemExit(
        "source App Sandbox entitlements do not match the expected set: "
        f"missing={missing}, unexpected={unexpected}, incorrect={incorrect}"
    )

photos_usage_description = info.get("NSPhotoLibraryUsageDescription")
if not isinstance(photos_usage_description, str) or not photos_usage_description.strip():
    raise SystemExit("Photos library usage description is missing or empty")

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

print("verified Photos usage description, Kromora Library package declaration, and exact App Sandbox entitlement set")
PY
