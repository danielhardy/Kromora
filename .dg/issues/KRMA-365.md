---
id: KRMA-365
title: Silence arrow-key navigation when a filmstrip thumbnail has focus
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Focused filmstrip Left/Right navigation preserves filtered display order
      result: pass
    - criterion: Boundary Left/Right presses are silent no-ops
      result: pass
    - criterion: Down, repeat, and up arrow phases are consumed at the focused SwiftUI button boundary
      result: pass
    - criterion: Thumbnail activation, focus, accessibility, and global-control ownership remain intact
      result: pass
    - criterion: Regression coverage and existing suites remain green
      result: pass
    - criterion: macOS UI smoke check exercised focused navigation and both boundaries; speaker output remains human-listenable
      result: pass
  checks_run:
    - swift test --filter FilmstripNavigationTests — 7 passed
    - swift test — 1271 passed, 48 expected skips
    - swift build -c release — passed
    - scripts/build-macos-app.sh — packaged and ad-hoc signature verified
    - macOS UI smoke — Edit filmstrip second→third, first Left boundary, last Right boundary
    - git diff --check — passed
    - dg validate — passed with pre-existing unknown-model warnings
  findings: []
  fixes: []
  verification_commits:
    - 0f723c2
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-11T22:58:37.666Z
  session: 01MTXJWZ0MLYINU6E6
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - editor
  - filmstrip
  - keyboard
  - navigation
  - ux
  - macos
created: 2026-09-11T22:25:34.921Z
updated: 2026-09-11T22:58:37.668Z
order: a0
board: product
commits:
  - 0f723c2
---

## Objective

Finish the arrow-navigation audio fix for the lower filmstrip. When a thumbnail has keyboard focus, Left/Right should navigate between images silently because this is expected application behavior.

## Residual behavior after KRMA-364

KRMA-364 (commit `0ad31ac`) quiets the editor canvas/global-monitor navigation path, but an audible error tone is still heard when Left/Right arrows are used with focus in the lower thumbnail strip. The thumbnails continue to navigate, so the beep is spurious feedback for a successful action.

## Investigation notes

- `Sources/KromoraKit/Views/FilmstripView.swift:20-42` renders each thumbnail as a plain `Button` and attaches `.onKeyPress(keys: [.leftArrow, .rightArrow])`.
- The filmstrip handler returns `.handled` after finding an adjacent filtered item, but returns `.ignored` at either end of the strip.
- `KeyMonitorPolicy.controlOwnsKeyboard` treats the focused AppKit button as owning keyboard input, so the global arrow handler intentionally defers when the thumbnail button is focused.
- Investigate whether the remaining tone comes from an ignored boundary event, a key-up event escaping after a handled key-down, the native button responder receiving the event during view replacement, or a duplicate event path. Do not assume the canvas fix covers the filmstrip focus path.

## Acceptance criteria

- [ ] With a filmstrip thumbnail focused, Left/Right still navigate to adjacent images in filtered display order and produce no audible error tone.
- [ ] Left at the first visible thumbnail and Right at the last visible thumbnail are silent no-ops.
- [ ] Key repeat, rapid navigation, and the selected-thumbnail view replacement remain silent and do not cause duplicate selection changes or loads.
- [ ] Both key-down and key-up/event propagation are handled at the correct SwiftUI/AppKit boundary so a successful or intentional no-op filmstrip navigation event does not reach a responder that beeps.
- [ ] Thumbnail Button activation, Tab/full-keyboard-access focus, VoiceOver behavior, and selection scrolling remain intact.
- [ ] Focus ownership remains correct for sliders, text fields, masking controls, and other controls that genuinely need arrow keys for their own input.
- [ ] Add regression coverage for focused-filmstrip navigation, filtered lists, boundaries, rapid repeats, and the relevant event-consumption contract; include a human-listenable macOS smoke check for the actual system sound.
- [ ] Existing canvas navigation and the rest of the keyboard, filmstrip, grid, masking, comparison, and rendering test suites remain green.

## Implementation notes

Start with `FilmstripView.swift`, `KeyboardShortcuts.swift`, `KeyMonitorPolicy`, and `Tests/KromoraKitTests/FilmstripNavigationTests.swift` / `KeyMonitorTests.swift`. Keep this as a follow-up to KRMA-364: preserve the successful canvas fix and make the filmstrip path equally quiet.

## Agent log

- 2026-09-11T22:58:37.666Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Focused filmstrip Left/Right navigation preserves filtered display order (pass)
- [x] Boundary Left/Right presses are silent no-ops (pass)
- [x] Down, repeat, and up arrow phases are consumed at the focused SwiftUI button boundary (pass)
- [x] Thumbnail activation, focus, accessibility, and global-control ownership remain intact (pass)
- [x] Regression coverage and existing suites remain green (pass)
- [x] macOS UI smoke check exercised focused navigation and both boundaries; speaker output remains human-listenable (pass)
Checks run:
- swift test --filter FilmstripNavigationTests — 7 passed
- swift test — 1271 passed, 48 expected skips
- swift build -c release — passed
- scripts/build-macos-app.sh — packaged and ad-hoc signature verified
- macOS UI smoke — Edit filmstrip second→third, first Left boundary, last Right boundary
- git diff --check — passed
- dg validate — passed with pre-existing unknown-model warnings
Findings:
- None
Fixes:
- None
Verification commits:
- 0f723c2
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTXJWZ0MLYINU6E6
Summary: Focused filmstrip arrow navigation now consumes down, repeat, and up phases; filtered navigation and boundary no-ops remain silent.
