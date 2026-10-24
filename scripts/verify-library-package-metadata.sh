#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_root="$script_dir/.."
cd "$project_root"

"$script_dir/check-sandbox-entitlements.py" Kromora/Kromora.entitlements source
python3 - "Kromora/Info.plist" Config/Base.xcconfig <<'PY'
import pathlib
import plistlib
import re
import sys

info_path = pathlib.Path(sys.argv[1])
info = plistlib.loads(info_path.read_bytes())

# The Photos usage string is generated from an INFOPLIST_KEY_ build setting, not the source plist.
match = re.search(
    r"^INFOPLIST_KEY_NSPhotoLibraryUsageDescription\s*=\s*(.*?)\s*$",
    pathlib.Path(sys.argv[2]).read_text(),
    re.MULTILINE,
)
photos_usage_description = match.group(1) if match else None
if "NSPhotoLibraryUsageDescription" in info:
    raise SystemExit("NSPhotoLibraryUsageDescription must come from Config/Base.xcconfig, not the source plist")
if not isinstance(photos_usage_description, str) or not photos_usage_description.strip():
    raise SystemExit("Photos library usage description is missing or empty")

expected_uti = "com.kromora.kromoralibrary"
expected_extension = "kromoralibrary"
if "CFBundleDocumentTypes" in info:
    raise SystemExit("CFBundleDocumentTypes must stay absent: the MVP has no Finder open-library handler (ADR-936)")

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

print("verified Photos usage description, Kromora Library package UTI declaration (no document type)")
PY
