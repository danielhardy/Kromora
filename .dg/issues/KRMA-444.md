---
id: KRMA-444
title: "Crop mode: Escape should cancel, Enter should apply"
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Escape calls cancelCrop() and exits crop mode without applying pending crop changes while crop mode is active
      result: pass
      notes: KeyboardShortcuts.swift case 53 checks vm.isCropToolActive first and calls vm.cancelCrop(); cancelCrop() restores the committed framing via canvasState.finishCrop()/fit() with no document mutation.
    - criterion: Enter/Return calls commitCrop(), applies the crop, and exits crop mode while crop mode is active
      result: pass
      notes: KeyboardShortcuts.swift case 36 checks vm.isCropToolActive before the grid-navigation branch and calls vm.commitCrop(), which writes document.crop via updateDocument and exits the tool.
    - criterion: New branches ordered/gated so crop, masking, and grid navigation do not cross-talk
      result: pass
      notes: Crop check is the first condition in both the Escape if/else-if chain and the Return early-return, so it takes priority without disabling the existing masking-gesture/workspace Escape handling or grid-navigation Return handling when crop is inactive.
    - criterion: Regression test covering Escape-cancels and Enter-commits while isCropToolActive is true
      result: pass
      notes: Tests/KromoraKitTests/KeyMonitorTests.swift adds testCropEscapeCancelsAndReturnCommitsThroughKeyboardMonitor, exercising both keys through the real KeyMonitor and asserting document.crop state after each.
  checks_run:
    - dg validate (OK, only pre-existing unrelated model-name warnings)
    - git diff --check bae397c~1..bae397c (clean, no whitespace errors)
    - manual review of KeyboardShortcuts.swift diff and crop lifecycle methods in AppViewModel.swift/CanvasNavigation.swift
    - "swift build / swift test / swiftc -parse: could not run — environment's Xcode license is unaccepted, gating the entire toolchain (same limitation the implementer reported)"
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-18T16:53:49.169Z
  session: 01MU7752G1WG5ZL7WM
labels:
  - ui
  - editor
  - crop
  - bug
created: 2026-09-18T02:23:03.559Z
updated: 2026-09-18T16:53:49.170Z
order: a0
board: product
---

## Objective

While in crop mode, pressing Escape should cancel/exit crop mode (discarding the in-progress crop) and pressing Enter/Return should apply/commit the crop. Neither key currently does anything in crop mode.

## Context

- `Sources/KromoraKit/Views/KeyboardShortcuts.swift:351-363` — the Escape handler (keyCode 53) only covers mask-gesture cancel and masking-workspace tool reset/close; there is no branch checking `vm.isCropToolActive` (or equivalent), so it falls through (`return event`) and does nothing while cropping.
- `Sources/KromoraKit/Views/KeyboardShortcuts.swift:379-384` — the Return handler (keyCode 36) only covers `vm.navigation.isGrid` (opening an image for editing from the grid); no crop-commit branch exists.
- The crop lifecycle methods already exist and just need to be wired up: `AppViewModel.toggleCropTool()` (~line 3939), `AppViewModel.cancelCrop()` (~line 3986), `AppViewModel.commitCrop()` (~line 3963), gated on `canvasState.isCropToolActive` (`Sources/KromoraKit/Models/CanvasNavigation.swift:14`).

## Acceptance criteria

- [ ] While crop mode is active, pressing Escape calls `cancelCrop()` and exits crop mode without applying pending crop changes.
- [ ] While crop mode is active, pressing Enter/Return calls `commitCrop()`, applies the crop, and exits crop mode.
- [ ] These new branches are ordered/gated so they don't shadow or get shadowed by the existing masking-workspace Escape handling or the grid Return handling — crop mode, masking mode, and grid navigation should each get the right key behavior with no cross-talk.
- [ ] Add a regression test (e.g. in a `KeyboardShortcuts`/`AppViewModel` crop test) covering Escape-cancels and Enter-commits while `isCropToolActive` is true.

## Out of scope

- Any other crop-tool keyboard shortcuts (aspect ratio cycling, rotate, etc.) beyond Escape/Enter.


### Comment — codex @ 2026-09-18T16:52:07.187Z

Implemented in commit bae397c. KeyMonitor now gives crop mode priority: Escape calls cancelCrop() before masking Escape behavior, and Return calls commitCrop() before grid navigation. Added KeyMonitor regression coverage for cancel-without-document-change and commit-with-document-update. Verification: dg validate passes; swiftc -parse passes for both changed Swift files; git diff --check passes. Focused swift test was attempted but could not build in this environment because CommandLineTools lacks the SwiftDataMacros plugin (Xcode license gate prevents using the full toolchain).

## Agent log

- 2026-09-18T16:53:49.169Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Escape calls cancelCrop() and exits crop mode without applying pending crop changes while crop mode is active (pass) — KeyboardShortcuts.swift case 53 checks vm.isCropToolActive first and calls vm.cancelCrop(); cancelCrop() restores the committed framing via canvasState.finishCrop()/fit() with no document mutation.
- [x] Enter/Return calls commitCrop(), applies the crop, and exits crop mode while crop mode is active (pass) — KeyboardShortcuts.swift case 36 checks vm.isCropToolActive before the grid-navigation branch and calls vm.commitCrop(), which writes document.crop via updateDocument and exits the tool.
- [x] New branches ordered/gated so crop, masking, and grid navigation do not cross-talk (pass) — Crop check is the first condition in both the Escape if/else-if chain and the Return early-return, so it takes priority without disabling the existing masking-gesture/workspace Escape handling or grid-navigation Return handling when crop is inactive.
- [x] Regression test covering Escape-cancels and Enter-commits while isCropToolActive is true (pass) — Tests/KromoraKitTests/KeyMonitorTests.swift adds testCropEscapeCancelsAndReturnCommitsThroughKeyboardMonitor, exercising both keys through the real KeyMonitor and asserting document.crop state after each.
Checks run:
- dg validate (OK, only pre-existing unrelated model-name warnings)
- git diff --check bae397c~1..bae397c (clean, no whitespace errors)
- manual review of KeyboardShortcuts.swift diff and crop lifecycle methods in AppViewModel.swift/CanvasNavigation.swift
- swift build / swift test / swiftc -parse: could not run — environment's Xcode license is unaccepted, gating the entire toolchain (same limitation the implementer reported)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU7752G1WG5ZL7WM
