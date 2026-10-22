#!/bin/zsh
set -euo pipefail

# Launch the development Kromora against a disposable copy of a library package, with its own
# preferences, so live UI verification never opens or changes the personal library.
#
#   scripts/disposable-app.sh start <package.kromoralibrary>   build, clone, launch; prints the bundle id
#   scripts/disposable-app.sh stop                              quit it and delete the clone and preferences
#   scripts/disposable-app.sh status
#
# How it stays isolated: the app is a SwiftPM Release build wrapped in a minimal ad hoc signed bundle
# with its own bundle id (so UI drivers can address it and its preferences domain is separate), and
# it opens the package named by KROMORA_LIBRARY_PACKAGE (an APFS clone, so the source package is
# never touched). It is not sandboxed: it checks the unsandboxed development launcher, not the
# App Store build, which still needs scripts/app-store-build.sh and the packaged-app checks.

project_root="${0:A:h}/.."
cd "$project_root"

bundle_id="com.kromora.disposable"
work=".build/disposable-app"
app="$work/KromoraDisposable.app"
clone="$work/Library.kromoralibrary"

stop() {
  osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
  pkill -f "$app/Contents/MacOS/Kromora" 2>/dev/null || true
  defaults delete "$bundle_id" >/dev/null 2>&1 || true
  rm -rf "$clone"
}

case "${1:-}" in
  start)
    package="${2:?usage: disposable-app.sh start <package.kromoralibrary>}"
    [[ -f "$package/manifest.json" ]] || { print -u2 "not a library package: $package"; exit 2; }
    stop
    swift build -c release --product Kromora >&2
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp .build/release/Kromora "$app/Contents/MacOS/Kromora"
    rm -rf "$app/Contents/Resources/Kromora_KromoraKit.bundle"
    cp -R .build/release/Kromora_KromoraKit.bundle "$app/Contents/Resources/"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>KromoraDisposable</string>
<key>CFBundleExecutable</key><string>Kromora</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
    codesign --force --sign - "$app" >&2
    cp -cR "$package" "$clone"
    defaults write "$bundle_id" hasSeenWelcome -bool true
    KROMORA_LIBRARY_PACKAGE="${clone:A}" "$app/Contents/MacOS/Kromora" >"$work/launch.log" 2>&1 &
    print "launched $bundle_id (pid $!) on ${clone:A}"
    ;;
  stop)
    stop
    print "stopped $bundle_id; clone and preferences removed"
    ;;
  status)
    pgrep -fl "$app/Contents/MacOS/Kromora" || print "not running"
    ;;
  *)
    print -u2 "usage: scripts/disposable-app.sh start <package.kromoralibrary> | stop | status"
    exit 2
    ;;
esac
