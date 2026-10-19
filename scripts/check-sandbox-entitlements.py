#!/usr/bin/env python3
"""Exact-set check for com.apple.security.* entitlements.

Usage: check-sandbox-entitlements.py <entitlements.plist> <label>

Shared by verify-app-signature.sh (embedded entitlements) and
verify-library-package-metadata.sh (source entitlements) so the allowlist lives in one place.
Fails on any missing, unexpected, or incorrectly valued security entitlement.
"""
import pathlib
import plistlib
import sys

EXPECTED = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.files.removable-media.read-only": True,
    "com.apple.security.files.bookmarks.app-scope": True,
    "com.apple.security.assets.pictures.read-write": True,
    "com.apple.security.personal-information.photos-library": True,
}


def main() -> None:
    path, label = pathlib.Path(sys.argv[1]), sys.argv[2]
    try:
        entitlements = plistlib.loads(path.read_bytes())
    except Exception as exc:
        raise SystemExit(f"could not decode {label} entitlements: {exc}")
    actual = {k: v for k, v in entitlements.items() if k.startswith("com.apple.security.")}
    missing = sorted(EXPECTED.keys() - actual.keys())
    unexpected = sorted(actual.keys() - EXPECTED.keys())
    incorrect = {
        k: {"actual": actual[k], "expected": EXPECTED[k]}
        for k in EXPECTED.keys() & actual.keys()
        if actual[k] is not EXPECTED[k]
    }
    if missing or unexpected or incorrect:
        raise SystemExit(
            f"{label} App Sandbox entitlements do not match the expected set: "
            f"missing={missing}, unexpected={unexpected}, incorrect={incorrect}"
        )
    print(f"verified {len(EXPECTED)} expected {label} entitlements")


main()
