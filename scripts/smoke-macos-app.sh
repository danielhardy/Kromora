#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"
project_root="$PWD"

app_bundle="${1:-.build/xcode/Build/Products/Release/Kromora.app}"
[[ "$app_bundle" == /* ]] || app_bundle="$project_root/$app_bundle"
app_executable="$app_bundle/Contents/MacOS/Kromora"
if [[ ! -d "$app_bundle" ]]; then
  print -u2 "missing $app_bundle; run scripts/app-store-build.sh first"
  exit 1
fi
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_bundle/Contents/Info.plist")

# Exit codes: 0 passed, 1 failed (the failed stage is named), 2 deferred (no accessible UI session),
# 3 refused (no disposable-profile confirmation). Only 0 is an executed smoke pass.
#
# The app imports into its own selected/default library, so this script must only run in a disposable
# macOS profile or VM. Setting the variable below is the operator's statement that it is; nothing in
# the shipping app can redirect the library.
if [[ "${KROMORA_SMOKE_DISPOSABLE_PROFILE:-}" != "1" ]]; then
  print -u2 "REFUSED: this test imports into the app's current library. Run it only in a disposable macOS"
  print -u2 "profile/library and set KROMORA_SMOKE_DISPOSABLE_PROFILE=1 to confirm."
  exit 3
fi

# Hosted macOS runners may not have a logged-in WindowServer session. The CI job still invokes this
# path, but leaves the decision to run it to the session rather than producing a false application
# failure from an unavailable accessibility service.
if ! /usr/bin/osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1; then
  print "SKIP: no accessible macOS UI session for application smoke test"
  exit 2
fi
# Reading a process's windows needs Accessibility for the terminal or app running this script; without
# it every later UI stage fails with -25211, which is a missing grant rather than an app failure.
if ! /usr/bin/osascript -e 'tell application "System Events" to get count of windows of first process' >/dev/null 2>&1; then
  print "SKIP: this terminal/app lacks Accessibility access (System Settings > Privacy & Security > Accessibility)"
  exit 2
fi

smoke_dir="$(mktemp -d -t kromora-app-smoke)"
# Open Image selects the first sorted library item, so this fixture stays ahead of existing photos.
fixture_stem="000-Kromora-Smoke"
input_png="$smoke_dir/$fixture_stem.png"
export_dir="$smoke_dir/export"
# The output name comes from the filename policy the setup sheet has selected (it persists across
# launches), so it is read from the sheet's live "Example filename" after the sheet opens rather than
# assumed. The format stays at its default or remembered value and is verified as a JPEG below.
output_name=""
output_image=""
expected_size=256
mkdir -p "$export_dir"
app_pid=""
stage="startup"
app_is_running() {
  [[ -z "$app_pid" ]] && return 1
  for candidate in $(/usr/bin/pgrep -x Kromora || true); do
    process_path="$(/bin/ps -o comm= -p "$candidate" | /usr/bin/sed 's/^[[:space:]]*//')"
    [[ "$process_path" == "$app_executable" ]] && return 0
  done
  return 1
}
find_app_pid() {
  for candidate in $(/usr/bin/pgrep -x Kromora || true); do
    process_path="$(/bin/ps -o comm= -p "$candidate" | /usr/bin/sed 's/^[[:space:]]*//')"
    # A separately installed copy can share Kromora's process name and bundle identifier.
    if [[ "$process_path" == "$app_executable" ]]; then
      print -- "$candidate"
      return 0
    fi
  done
  return 1
}
# Only the instance this script launched (matched by pid and executable path) is closed, and only
# harness-owned fixtures are removed.
cleanup() {
  local exit_status=$?
  if [[ $exit_status -ne 0 && $exit_status -ne 2 ]]; then
    print -u2 "FAILED at stage: $stage"
  fi
  if [[ -n "$app_pid" ]]; then
    /usr/bin/osascript >/dev/null 2>&1 <<APPLESCRIPT || true
tell application "System Events"
    tell first process whose unix id is $app_pid
        set frontmost to true
        keystroke "q" using command down
    end tell
end tell
APPLESCRIPT
    for _ in {1..20}; do
      app_is_running || break
      sleep 1
    done
    app_is_running && kill "$app_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$smoke_dir"
}
trap cleanup EXIT

# Run one bounded UI stage. `ui_stage` records the name for the failure report; every AppleScript
# wait is a bounded repeat loop that raises an error naming what never appeared.
ui_stage() {
  stage="$1"
  print -- "Running UI smoke stage: $stage"
  # zsh can skip the EXIT trap on errexit inside a function; exit explicitly so cleanup still runs.
  KROMORA_SMOKE_PID="$app_pid" KROMORA_SMOKE_INPUT="$input_png" \
    KROMORA_SMOKE_EXPORT_DIR="$export_dir" KROMORA_SMOKE_EXPECT_WELCOME="$expects_welcome" /usr/bin/osascript || exit $?
}

if find_app_pid >/dev/null; then
  print -u2 "a Kromora instance from $app_bundle is already running; quit it so the harness owns its instance"
  exit 1
fi

stage="fixture"
/usr/bin/sips -s format png -z $expected_size $expected_size App/Branding/KromoraIcon.svg --out "$input_png" >/dev/null

# Read the first-run state before launch so an enabled menu cannot race the welcome sheet's
# presentation. The harness exercises onboarding on a fresh profile without seeding preferences.
expects_welcome=1
[[ "$(/usr/bin/defaults read "$bundle_id" hasSeenWelcome 2>/dev/null || true)" == "1" ]] && expects_welcome=0

stage="launch"
# KROMORA_LIBRARY_PACKAGE (an absolute path to a disposable library clone) is forwarded so the
# unsandboxed development bundle from scripts/disposable-app.sh opens that clone; the sandboxed
# packaged app ignores a path outside its container.
launch_env=()
[[ -n "${KROMORA_LIBRARY_PACKAGE:-}" ]] && launch_env=(--env "KROMORA_LIBRARY_PACKAGE=$KROMORA_LIBRARY_PACKAGE")
open -n "${launch_env[@]}" "$app_bundle"
for _ in {1..30}; do
  app_pid="$(find_app_pid || true)"
  [[ -n "$app_pid" ]] && break
  sleep 1
done
[[ -n "$app_pid" ]] || { print -u2 "Kromora did not launch"; exit 1; }

if ! /usr/bin/osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "System Events"
    tell first process whose unix id is $app_pid to set frontmost to true
end tell
APPLESCRIPT
then
  print "SKIP: macOS refused to activate Kromora through the UI automation service"
  exit 2
fi

ui_stage "window" <<'APPLESCRIPT'
set appPID to (do shell script "printf '%s' \"$KROMORA_SMOKE_PID\"") as integer
tell application "System Events"
    tell first process whose unix id is appPID
        set frontmost to true
        repeat 30 times
            if (count of windows) > 0 then exit repeat
            delay 1
        end repeat
        if (count of windows) = 0 then error "Kromora did not create a window"
    end tell
end tell
APPLESCRIPT

ui_stage "first-run onboarding" <<'APPLESCRIPT'
set appPID to (do shell script "printf '%s' \"$KROMORA_SMOKE_PID\"") as integer
set expectsWelcome to do shell script "printf '%s' \"$KROMORA_SMOKE_EXPECT_WELCOME\""
if expectsWelcome is not "1" then return
tell application "System Events"
    tell first process whose unix id is appPID
        set frontmost to true
        set welcomeClicked to false
        repeat 30 times
            try
                -- SwiftUI nests the buttons in a group and exposes attributed labels that
                -- System Events cannot resolve by name. The identifier is a plain AX string.
                set windowElements to entire contents of window 1
                repeat with elementReference in windowElements
                    set targetElement to contents of elementReference
                    try
                        if value of attribute "AXIdentifier" of targetElement is "welcome.startEmpty" then
                            click targetElement
                            set welcomeClicked to true
                            exit repeat
                        end if
                    end try
                end repeat
            end try
            if welcomeClicked then exit repeat
            delay 1
        end repeat
        if not welcomeClicked then error "first-run welcome button did not become available"
        set welcomeDismissed to false
        repeat 30 times
            try
                if (count of sheets of window 1) = 0 then
                    set welcomeDismissed to true
                    exit repeat
                end if
            end try
            delay 1
        end repeat
        if not welcomeDismissed then error "first-run welcome sheet did not dismiss"
    end tell
end tell
APPLESCRIPT

ui_stage "import (Open Image panel)" <<'APPLESCRIPT'
set appPID to (do shell script "printf '%s' \"$KROMORA_SMOKE_PID\"") as integer
set inputPath to do shell script "printf '%s' \"$KROMORA_SMOKE_INPUT\""
tell application "System Events"
    tell first process whose unix id is appPID
        set frontmost to true
        set openCommandReady to false
        repeat 60 times
            try
                if enabled of menu item "Open Image…" of menu 1 of menu bar item "File" of menu bar 1 then
                    set openCommandReady to true
                    exit repeat
                end if
            end try
            delay 1
        end repeat
        if not openCommandReady then error "Open Image command did not become available"
        click menu item "Open Image…" of menu 1 of menu bar item "File" of menu bar 1
        set openPanelPresented to false
        repeat 20 times
            try
                if (count of sheets of window 1) > 0 then
                    set openPanelPresented to true
                    exit repeat
                end if
            end try
            delay 1
        end repeat
        if not openPanelPresented then error "Open Image panel did not appear as a sheet"
        keystroke "g" using {command down, shift down}
        -- The sheet becomes visible before its path field is accessible. Wait for the control
        -- and enter the path in the same retry, rather than treating the sheet count as ready.
        set locationEntered to false
        repeat 20 times
            try
                set value of text field 1 of sheet 1 of sheet 1 of window 1 to inputPath
                key code 36
                set locationEntered to true
                exit repeat
            end try
            delay 1
        end repeat
        if not locationEntered then error "Open Image location field did not become ready"
        set openFileReady to false
        repeat 20 times
            try
                if (count of sheets of sheet 1 of window 1) = 0 and ¬
                    enabled of button "Open" of splitter group 1 of sheet 1 of window 1 then
                    set openFileReady to true
                    exit repeat
                end if
            end try
            delay 1
        end repeat
        if not openFileReady then error "Open Image file did not become selectable"
        click button "Open" of splitter group 1 of sheet 1 of window 1
    end tell
end tell
APPLESCRIPT

# Ready means the File menu's Export command is enabled, not a toolbar position.
ui_stage "import readiness (File > Export enabled)" <<'APPLESCRIPT'
set appPID to (do shell script "printf '%s' \"$KROMORA_SMOKE_PID\"") as integer
tell application "System Events"
    tell first process whose unix id is appPID
        repeat 60 times
            try
                if enabled of menu item "Export…" of menu 1 of menu bar item "File" of menu bar 1 then exit repeat
            end try
            delay 1
        end repeat
        if not (enabled of menu item "Export…" of menu 1 of menu bar item "File" of menu bar 1) then
            error "Kromora did not finish loading the smoke image"
        end if
    end tell
end tell
APPLESCRIPT

ui_stage "Settings" <<'APPLESCRIPT'
set appPID to (do shell script "printf '%s' \"$KROMORA_SMOKE_PID\"") as integer
tell application "System Events"
    tell first process whose unix id is appPID
        key code 43 using command down
        -- The title is "<bundle name> Settings", so the development bundle's differs from the packaged app's.
        repeat 20 times
            if exists (first window whose name ends with " Settings") then exit repeat
            delay 1
        end repeat
        if not (exists (first window whose name ends with " Settings")) then error "Settings did not open"
        key code 13 using command down
        delay 1
    end tell
end tell
APPLESCRIPT

# File > Export… (Command-S): Step 1 is the "Export 1 Photo" setup sheet whose selected settings are
# kept; Continue opens Step 2, a folder chooser whose default button is "Export Here". The sheet's
# "Example filename" static text is the selected policy's resulting name for the single photo.
stage="export setup sheet"
output_name="$(KROMORA_SMOKE_PID="$app_pid" /usr/bin/osascript <<'APPLESCRIPT'
set appPID to (do shell script "printf '%s' \"$KROMORA_SMOKE_PID\"") as integer
tell application "System Events"
    tell first process whose unix id is appPID
        set frontmost to true
        click menu item "Export…" of menu 1 of menu bar item "File" of menu bar 1
        set exportSetupReady to false
        repeat 20 times
            try
                if exists button "Continue" of sheet 1 of window 1 then
                    set exportSetupReady to true
                    exit repeat
                end if
            end try
            delay 1
        end repeat
        if not exportSetupReady then error "Export setup sheet did not appear"
        if not (exists static text "Export 1 Photo" of sheet 1 of window 1) then error "Export setup sheet is not the one-photo setup"
        set exampleName to ""
        repeat 10 times
            -- The label is a direct child of the sheet; `entire contents` returns nothing for it.
            set sheetElements to UI elements of sheet 1 of window 1
            repeat with elementReference in sheetElements
                set targetElement to contents of elementReference
                try
                    if role of targetElement is "AXStaticText" and description of targetElement is "Example filename" then
                        set exampleName to value of targetElement
                        exit repeat
                    end if
                end try
            end repeat
            if exampleName is not "" then exit repeat
            delay 1
        end repeat
        if exampleName is "" then error "Export setup sheet did not expose its example filename"
        click button "Continue" of sheet 1 of window 1
        return exampleName
    end tell
end tell
APPLESCRIPT
)"
[[ -n "$output_name" && "$output_name" != */* ]] || { print -u2 "unusable example filename: '$output_name'"; exit 1; }
output_image="$export_dir/$output_name"

ui_stage "export folder chooser" <<'APPLESCRIPT'
set appPID to (do shell script "printf '%s' \"$KROMORA_SMOKE_PID\"") as integer
set exportDirectory to do shell script "printf '%s' \"$KROMORA_SMOKE_EXPORT_DIR\""
tell application "System Events"
    tell first process whose unix id is appPID
        set exportChooserReady to false
        repeat 20 times
            try
                if exists button "Export Here" of splitter group 1 of sheet 1 of window 1 then
                    set exportChooserReady to true
                    exit repeat
                end if
            end try
            delay 1
        end repeat
        if not exportChooserReady then error "Export folder chooser did not appear"
        keystroke "g" using {command down, shift down}
        set locationEntered to false
        repeat 20 times
            try
                set value of text field 1 of sheet 1 of sheet 1 of window 1 to exportDirectory
                key code 36
                set locationEntered to true
                exit repeat
            end try
            delay 1
        end repeat
        if not locationEntered then error "Export location field did not become ready"
        set exportDestinationReady to false
        repeat 20 times
            try
                if (count of sheets of sheet 1 of window 1) = 0 and ¬
                    enabled of button "Export Here" of splitter group 1 of sheet 1 of window 1 then
                    set exportDestinationReady to true
                    exit repeat
                end if
            end try
            delay 1
        end repeat
        if not exportDestinationReady then error "Export destination did not become selectable"
        click button "Export Here" of splitter group 1 of sheet 1 of window 1
        set exportChooserDismissed to false
        repeat 20 times
            try
                if (count of sheets of window 1) = 0 then
                    set exportChooserDismissed to true
                    exit repeat
                end if
            end try
            delay 1
        end repeat
        if not exportChooserDismissed then error "Export folder chooser remained open after Export Here"
    end tell
end tell
APPLESCRIPT

stage="export output ($output_name)"
for _ in {1..60}; do
  [[ -s "$output_image" ]] && break
  sleep 1
done
[[ -s "$output_image" ]] || { print -u2 "application smoke export was not created: $output_image"; exit 1; }
# Staging is atomic, so a decodable file at the final name is the finished export.
width="$(/usr/bin/sips -g pixelWidth "$output_image" 2>/dev/null | /usr/bin/awk '/pixelWidth/ {print $2}')"
height="$(/usr/bin/sips -g pixelHeight "$output_image" 2>/dev/null | /usr/bin/awk '/pixelHeight/ {print $2}')"
format="$(/usr/bin/sips -g format "$output_image" 2>/dev/null | /usr/bin/awk '/format/ {print $2}')"
if [[ "$format" != "jpeg" || "$width" != "$expected_size" || "$height" != "$expected_size" ]]; then
  print -u2 "export output is not a ${expected_size}x${expected_size} JPEG (format=$format size=${width}x${height})"
  exit 1
fi
stage="done"
print "Application smoke passed: launch, import, Settings, File menu, and export ($output_name, ${width}x${height} JPEG)"
