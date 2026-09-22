#!/bin/zsh
set -euo pipefail

# Rebuilds Kromora's precompiled shader libraries from their Metal sources and records a
# checksum of those sources beside each library.
#
# Why checked-in binaries: SwiftPM has no Metal build rule, so `.metal` files in Resources are
# copied verbatim, never compiled. The app must not compile shader source at runtime (first-frame
# latency for presentation, deprecated CIKL compilation for render kernels), so the compiled
# libraries are build inputs like any other source file: edited via their `.metal` sources,
# regenerated with this script, and reviewed as source diffs plus rebuilt binaries.
#
#   scripts/build-metal-libraries.sh         rebuild libraries + checksums
#   scripts/build-metal-libraries.sh --check verify checked-in files match sources
#
# MetalKernelParityTests fail with this script's name in the message when a library is missing,
# unloadable, has unexpected kernel names, or its checksum does not match the bundled sources.

project_root="${0:A:h}/.."
cd "$project_root"

resources="Sources/KromoraKit/Resources"
min_version="14.0"

ci_source="$resources/KromoraCIKernels.ci.metal"
ci_library="$resources/KromoraCIKernels.ci.metallib"
ci_checksum="$resources/KromoraCIKernels.sha256"

presentation_sources=("$resources/PreviewSurface.metal" "$resources/MaskOverlay.metal")
presentation_library="$resources/KromoraPresentation.metallib"
presentation_checksum="$resources/KromoraPresentation.sha256"

checksum_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

if [[ "${1:-}" == "--check" ]]; then
    failures=0
    for library in "$ci_library" "$presentation_library"; do
        if [[ ! -f "$library" ]]; then
            print -u2 "missing $library — run scripts/build-metal-libraries.sh"
            failures=1
        fi
    done
    if [[ "$(cat "$ci_checksum")" != "$(checksum_file "$ci_source")" ]]; then
        print -u2 "stale $ci_library — $ci_source changed without a rebuild; run scripts/build-metal-libraries.sh"
        failures=1
    fi
    if [[ "$(cat "$presentation_checksum")" != "$(cat "${presentation_sources[@]}" | shasum -a 256 | awk '{print $1}')" ]]; then
        print -u2 "stale $presentation_library — presentation Metal sources changed without a rebuild; run scripts/build-metal-libraries.sh"
        failures=1
    fi
    exit $failures
fi

# Core Image kernels need the CI kernel language mode; the presentation shaders are plain Metal.
xcrun metal -fcikernel -mmacosx-version-min="$min_version" "$ci_source" -o "$ci_library"
xcrun metal -mmacosx-version-min="$min_version" "${presentation_sources[@]}" -o "$presentation_library"

checksum_file "$ci_source" > "$ci_checksum"
cat "${presentation_sources[@]}" | shasum -a 256 | awk '{print $1}' > "$presentation_checksum"

print "rebuilt $ci_library and $presentation_library"
