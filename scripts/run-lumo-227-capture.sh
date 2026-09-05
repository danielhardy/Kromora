#!/bin/zsh
set -euo pipefail

# LUMO-227: real AppKit pointer-stream capture for the transparent Metal sibling.
# The operator moves/drags over the visible capture window while xctrace records.
repo_root="${0:A:h}/.."
cd "$repo_root"
output_dir="${LUMO_CAPTURE_OUTPUT_DIR:-/tmp/lumo-227-capture}"
duration="${LUMO_MASK_OVERLAY_REAL_POINTER_DURATION:-30}"
stamp="$(date +%Y%m%d-%H%M%S)"
trace_path="$output_dir/LUMO-227-mask-overlay-$stamp.trace"
summary_path="$output_dir/LUMO-227-mask-overlay-$stamp-summary.txt"
bin_path="$(swift build -c release --product LumoMaskOverlayCapture --show-bin-path)"
capture_app="$repo_root/.build/LumoMaskOverlayCapture.app"

rm -rf "$capture_app"
mkdir -p "$output_dir" "$capture_app/Contents/MacOS" "$capture_app/Contents/Resources"
cp "$bin_path/LumoMaskOverlayCapture" "$capture_app/Contents/MacOS/LumoMaskOverlayCapture"
cp Sources/Lumo/Info.plist "$capture_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Lumo Mask Overlay Capture' \
  -c 'Set :CFBundleExecutable LumoMaskOverlayCapture' \
  -c 'Set :CFBundleName LumoMaskOverlayCapture' \
  -c 'Set :CFBundleIdentifier com.lumo.mask-overlay-capture' \
  "$capture_app/Contents/Info.plist"
codesign --force --sign - "$capture_app" >/dev/null

{
  print "issue=LUMO-227"
  print "configuration=Release"
  print "prototype_gate=LUMO_MASK_OVERLAY_PROTOTYPE=1"
  print "commit=$(git rev-parse HEAD)"
  print "os=$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  print "hardware=$(system_profiler SPHardwareDataType -detailLevel mini | tr '\n' ';')"
  print "display=$(system_profiler SPDisplaysDataType -detailLevel mini | tr '\n' ';')"
  print "viewport_points=1280x800 backing_scale=2 source_extent=6000x4000"
  print "input=real AppKit NSEvent mouseMoved/mouseDown/mouseDragged/mouseUp"
  print "duration_seconds=$duration"
  print "trace=$trace_path"
  print "capture_app=$capture_app"
} > "$summary_path"

xctrace record \
  --template "Metal System Trace" \
  --instrument "Points of Interest" \
  --output "$trace_path" \
  --time-limit "${LUMO_CAPTURE_TIME_LIMIT:-${duration}s}" \
  --env LUMO_MASK_OVERLAY_PROTOTYPE=1 \
  --env LUMO_MASK_OVERLAY_REAL_POINTER_DURATION="$duration" \
  --target-stdout - \
  --launch -- "$capture_app" \
  >> "$summary_path" 2>&1

print "trace=$trace_path"
print "summary=$summary_path"
