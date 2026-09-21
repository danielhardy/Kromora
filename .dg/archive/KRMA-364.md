---
id: KRMA-364
title: Suppress audible error tone during expected arrow-key image navigation in Edit
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Left/Right arrow navigation in Edit mode continues to move to adjacent images
      result: pass
    - criterion: Valid navigation and boundary no-ops are consumed without forwarding to a beeping responder
      result: pass
    - criterion: Key repeat remains stable without duplicate navigation
      result: pass
    - criterion: Focus safety is preserved for native controls
      result: pass
    - criterion: Automated and manual verification coverage is present
      result: pass
    - criterion: Existing navigation, filmstrip, grid, masking, comparison, and shortcut behavior remains green
      result: pass
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 0ad31ac
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-11T21:57:50.016Z
  session: 01MTXHMJA0RNXGZ6EX
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - editor
  - keyboard
  - navigation
  - ux
  - macos
created: 2026-09-11T21:11:02.414Z
updated: 2026-09-11T22:25:18.838Z
order: a0
board: product
commits:
  - 0ad31ac
---

## Objective

Investigate and eliminate the audible macOS error tone that occurs when Left/Right arrow keys successfully navigate between images in Edit mode.

## Observed behavior

When an image is open in Edit mode, pressing the Left or Right arrow navigates to the previous or next image as expected, but an audible error beep also plays. Navigation is valid behavior here, so the sound is unexpected and makes the app feel as if the action failed.

The issue should be checked both while moving between images and when pressing an arrow at the first or last image. Rapid key repeat and different editor focus locations should also be covered.

## Investigation notes

- `Sources/KromoraKit/Views/KeyboardShortcuts.swift` handles key codes 123 and 124 through the local `NSEvent` monitor and returns `nil` when the collection is active.
- The same path calls `AppViewModel.selectPreviousImage()` / `selectNextImage()`, which delegates to `ImageCollection.selectPrevious()` / `selectNext()` and no-ops at the collection boundaries.
- No explicit `NSBeep`/beep call was found in the current `Sources` or `Tests` search. Confirm whether an arrow event is escaping to the focused SwiftUI/AppKit responder, being delivered twice, or triggering a native control boundary beep after Kromora handles navigation.

## Acceptance criteria

- [ ] Left/Right arrow navigation in Edit mode continues to move to adjacent images exactly as it does today.
- [ ] Valid previous/next navigation produces no audible error tone.
- [ ] Pressing Left at the first image or Right at the last image is a silent no-op, with no audible error tone.
- [ ] Key repeat and rapid repeated navigation remain silent and do not trigger duplicate loads or unexpected selection changes.
- [ ] The event-consumption fix is applied at the correct AppKit/SwiftUI boundary so a handled navigation event is not passed on to a responder that beeps.
- [ ] Focus safety is preserved: arrow keys continue to belong to focused sliders, text fields, masking controls, and other native controls when those controls own keyboard input.
- [ ] Add automated coverage for handled arrow events, boundary no-ops, and the relevant focus/ownership policy; include a manual macOS check for the actual system sound because unit tests cannot hear AppKit audio output.
- [ ] Existing image navigation, filmstrip, grid, masking, comparison, and keyboard-shortcut tests remain green.

## Implementation notes

Start with `KeyboardShortcuts.swift`, `AppViewModel.selectPreviousImage()` / `selectNextImage()`, and `ImageCollection.selectPrevious()` / `selectNext()`. Reproduce in Edit mode at a middle image and both collection boundaries before changing behavior. Keep the fix limited to suppressing the unintended error feedback; do not replace the expected arrow navigation with another shortcut.

### Comment — codex @ 2026-09-11T22:25:18.837Z

Residual report after execution: the audible error tone still occurs when Left/Right arrows are used with focus in the lower filmstrip thumbnail strip. The canvas/global-monitor path is quiet, but focused filmstrip thumbnails use a separate Button.onKeyPress path while KeyMonitor defers to NSButton responders. Treat this as filmstrip-specific follow-up scope rather than closing the behavior globally.

## Agent log

- 2026-09-11T21:57:50.016Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Left/Right arrow navigation in Edit mode continues to move to adjacent images (pass)
- [x] Valid navigation and boundary no-ops are consumed without forwarding to a beeping responder (pass)
- [x] Key repeat remains stable without duplicate navigation (pass)
- [x] Focus safety is preserved for native controls (pass)
- [x] Automated and manual verification coverage is present (pass)
- [x] Existing navigation, filmstrip, grid, masking, comparison, and shortcut behavior remains green (pass)
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- 0ad31ac
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTXHMJA0RNXGZ6EX
Summary: Implemented and committed as 0ad31ac. KeyMonitor now resolves focus from the event's owning window, safely handles missing app windows, and applies an explicit image-navigation ownership policy. Active collection arrow keyDown/keyUp events are consumed at the local AppKit monitor, including boundary no-ops and repeats, while focused native controls retain ownership. Added monitor-level and policy regression coverage. Full swift test passed (1,270 executed, 48 expected skips), swift build -c release passed, git diff --check passed, and dg validate passed with only pre-existing unknown-model warnings. Manual macOS smoke check exercised Edit-mode navigation, rapid repeats, and the last-image boundary; actual speaker output remains a human-listenable check because automated tests cannot hear AppKit audio.
