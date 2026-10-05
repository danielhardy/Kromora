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

# Hosted macOS runners may not have a logged-in WindowServer session. The CI job still invokes this
# path, but leaves the decision to run it to the session rather than producing a false application
# failure from an unavailable accessibility service.
if ! /usr/bin/osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1; then
  print "SKIP: no accessible macOS UI session for application smoke test"
  exit 2
fi

smoke_dir="$(mktemp -d -t kromora-app-smoke)"
# Open Image selects the first sorted library item, so this fixture stays ahead of existing photos.
input_png="$smoke_dir/000-Kromora-Smoke.png"
# Keep atomic export staging inside the sandboxed app's writable temporary directory.
sandbox_temp="$HOME/Library/Containers/$bundle_id/Data/tmp"
output_image="$sandbox_temp/kromora-app-smoke-$$.jpg"
app_pid=""
app_is_running() {
  [[ -z "$app_pid" ]] && return 1
  for candidate in $(/usr/bin/pgrep -x Kromora || true); do
    process_path="$(/bin/ps -o comm= -p "$candidate" | /usr/bin/sed 's/^[[:space:]]*//')"
    [[ "$process_path" == "$app_executable" ]] && return 0
  done
  return 1
}
cleanup() {
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
  /bin/rm -f "$output_image" >/dev/null 2>&1 || true
  rm -rf "$smoke_dir"
}
trap cleanup EXIT

/usr/bin/sips -s format png -z 256 256 App/Branding/KromoraIcon.svg --out "$input_png" >/dev/null
open -n "$app_bundle"

for _ in {1..30}; do
  app_pid=""
  for candidate in $(/usr/bin/pgrep -x Kromora || true); do
    process_path="$(/bin/ps -o comm= -p "$candidate" | /usr/bin/sed 's/^[[:space:]]*//')"
    # A separately installed copy can share Kromora's process name and bundle identifier.
    if [[ "$process_path" == "$app_executable" ]]; then
      app_pid="$candidate"
      break
    fi
  done
  [[ -n "$app_pid" ]] && break
  sleep 1
done
[[ -n "$app_pid" ]] || { print -u2 "Kromora did not launch"; exit 1; }
for _ in {1..30}; do
  [[ -d "$sandbox_temp" ]] && break
  sleep 1
done
[[ -d "$sandbox_temp" ]] || { print -u2 "Kromora sandbox temporary directory is unavailable"; exit 1; }

if ! /usr/bin/osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "System Events"
    tell first process whose unix id is $app_pid to set frontmost to true
end tell
APPLESCRIPT
then
  print "SKIP: macOS refused to activate Kromora through the UI automation service"
  exit 2
fi

export KROMORA_SMOKE_PID="$app_pid"
export KROMORA_SMOKE_INPUT="$input_png"
export KROMORA_SMOKE_OUTPUT="$output_image"
/usr/bin/osascript <<'APPLESCRIPT'
set appPID to (do shell script "printf '%s' \"$KROMORA_SMOKE_PID\"") as integer
set inputPath to do shell script "printf '%s' \"$KROMORA_SMOKE_INPUT\""
set outputDirectory to do shell script "dirname \"$KROMORA_SMOKE_OUTPUT\""
set outputName to do shell script "basename \"$KROMORA_SMOKE_OUTPUT\""

using terms from application "System Events"
on waitForWindow(processID)
    tell application "System Events"
        tell first process whose unix id is processID
            repeat 30 times
                if (count of windows) > 0 then return
                delay 1
            end repeat
            error "Kromora did not create a window"
        end tell
    end tell
end waitForWindow

end using terms from

tell application "System Events"
    tell first process whose unix id is appPID
        set frontmost to true
        my waitForWindow(appPID)

        -- Open through the File menu's keyboard equivalent and native Open panel.
        keystroke "o" using command down
        repeat 20 times
            if exists window "Open Image" then exit repeat
            delay 1
        end repeat
        if not (exists window "Open Image") then error "Open Image panel did not appear"
        keystroke "g" using {command down, shift down}
        repeat 20 times
            if (count of sheets of window "Open Image") > 0 then exit repeat
            delay 1
        end repeat
        if (count of sheets of window "Open Image") = 0 then error "Open Image location sheet did not appear"
        set value of text field 1 of sheet 1 of window "Open Image" to inputPath
        key code 36
        repeat 20 times
            if (count of sheets of window "Open Image") = 0 then
                if enabled of button "Open" of splitter group 1 of window "Open Image" then exit repeat
            end if
            delay 1
        end repeat
        if (count of sheets of window "Open Image") > 0 then error "Open Image file did not become selectable"
        if not (enabled of button "Open" of splitter group 1 of window "Open Image") then error "Open Image file did not become selectable"
        click button "Open" of splitter group 1 of window "Open Image"

        -- Wait until the imported smoke image has finished loading before asking Kromora to export.
        repeat 60 times
            if enabled of first button of group 1 of group 4 of toolbar 1 of window 1 then
                exit repeat
            end if
            delay 1
        end repeat
        if not (enabled of first button of group 1 of group 4 of toolbar 1 of window 1) then
            error "Kromora did not finish loading the smoke image"
        end if

        -- Exercise the application-level Settings scene, then return to the main window.
        key code 43 using command down
        repeat 20 times
            if exists window "Kromora Settings" then exit repeat
            delay 1
        end repeat
        if not (exists window "Kromora Settings") then error "Settings did not open"
        key code 13 using command down
        delay 1

        -- Export through the File menu's keyboard equivalent and native Save panel.
        keystroke "s" using command down
        repeat 20 times
            if exists window "Export" then exit repeat
            delay 1
        end repeat
        if not (exists window "Export") then error "Export save panel did not appear"
        keystroke "g" using {command down, shift down}
        repeat 20 times
            if (count of sheets of window "Export") > 0 then exit repeat
            delay 1
        end repeat
        if (count of sheets of window "Export") = 0 then error "Export location sheet did not appear"
        set value of text field 1 of sheet 1 of window "Export" to outputDirectory
        key code 36
        repeat 20 times
            if (count of sheets of window "Export") = 0 then
                if exists text field "Save As:" of splitter group 1 of window "Export" then exit repeat
            end if
            delay 1
        end repeat
        if (count of sheets of window "Export") > 0 then error "Export destination did not become selectable"
        set value of text field "Save As:" of splitter group 1 of window "Export" to outputName
        repeat 20 times
            if enabled of button "Save" of splitter group 1 of window "Export" then exit repeat
            delay 1
        end repeat
        click button "Save" of splitter group 1 of window "Export"
        repeat 20 times
            if not (exists window "Export") then exit repeat
            delay 1
        end repeat
        if exists window "Export" then error "Export save panel remained open after Save"
    end tell
end tell
APPLESCRIPT

for _ in {1..30}; do
  [[ -s "$output_image" ]] && break
  sleep 1
done
[[ -s "$output_image" ]] || { print -u2 "application smoke export was not created: $output_image"; exit 1; }
print "Application smoke passed: launch, open, Settings, File menu, and export"
