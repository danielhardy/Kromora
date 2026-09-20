---
id: KRMA-463
title: "Crop-mode rotate: hide always-on rotate controls; Apple Photos–style crop/rotate UI with animation"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Main toolbar no longer shows Rotate Left/Right outside crop mode
      result: pass
      notes: CanvasToolbarControls rotate buttons removed (ContentView.swift); no menu/command equivalents exist outside crop.
    - criterion: Rotate 90 CW/CCW available inside crop mode
      result: pass
      notes: CropToolbarView adds rotate buttons wired to viewModel.rotateClockwise/CounterClockwise; [ and ] keys also route to rotate while isCropToolActive.
    - criterion: Rotating in crop mode does not cancel/exit crop; Apply commits combined crop+rotation, Cancel/Escape discards draft
      result: pass
      notes: rotateImage branches on canvasState.isCropToolActive and calls canvasState.rotateCrop instead of cancelCrop; commitCrop folds cropRotation into document.rotation and replaces crop with the remapped draft; cancelCrop/finishCrop resets cropRotation to .zero without touching the document. Verified via testRotatingWhileCroppingKeepsDraftTransientUntilApplyOrCancel and by re-deriving the coordinate math (CropAdjustments.rotated, ImageRotation.addingClockwiseQuarterTurns, cropSourceSize composition) by hand.
    - criterion: 90 degree rotate in crop mode is animated, not a hard cut
      result: pass
      notes: "PreviewView adds .animation(.snappy(duration: 0.3, extraBounce: 0.04), value: canvasState.cropRotation) scoped to the crop subtree; manual QA of feel is out of scope for this pass."
    - criterion: Outside crop mode, existing committed rotation still displays correctly; no regression to Fit/Fill/zoom or crop presets
      result: pass
      notes: sourceSize/orientedExtent paths for committed rotation are unchanged; ImageRotationTests suite (9 tests) and existing crop/fit tests pass.
    - criterion: Automated coverage for rotate-while-cropping lifecycle
      result: pass
      notes: ImageRotationTests.testRotatingWhileCroppingKeepsDraftTransientUntilApplyOrCancel covers draft transience, cancel-discards, and commit-combines-crop+rotation at the model/canvas-state level, satisfying the 'at least model/canvas state' bar. Keyboard [ ] routing while cropping has no dedicated KeyMonitorTests case; noted as a minor gap, not blocking.
  checks_run:
    - swift build (clean; only pre-existing CIKernel deprecation warnings, unrelated to this change)
    - swift test --filter 'MenuCommandTests|ImageRotationTests|CropWorkflowTests|KeyMonitorTests' (35 passed)
    - git diff --check c1aac21^ c1aac21 (clean)
    - dg validate (only pre-existing unknown-model warnings for other issues)
    - manual re-derivation of rotation/crop coordinate composition (ImageRotation.addingClockwiseQuarterTurns, CropAdjustments.rotated, cropSourceSize orientedExtent parity) to confirm no off-by-one or double-swap bug when combining committed document.rotation with transient cropRotation
    - grep sweep confirming no dangling Rotate Left/Right toolbar/menu affordance remains outside crop mode and no unused view-model bindings were left behind in ContentView.swift
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-19T16:52:20.738Z
  session: 01MU8MI8V4JKN8H1FV
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - crop
  - editor
created: 2026-09-19T15:50:10.713Z
updated: 2026-09-19T16:52:20.741Z
order: a0
board: product
---

## Objective

Make rotate a **crop-mode-only** control with an Apple Photos–quality crop/rotate experience (clean chrome, intentional motion), instead of always-visible toolbar buttons that fight the crop tool.

## Context

Today `CanvasToolbarControls` in `ContentView` always shows **Rotate Left** / **Rotate Right** next to Crop. Those buttons are even **disabled while crop is active** (`disabled(!hasImage || canvasState.isCropToolActive)`), and `rotateImage` cancels an in-progress crop before applying a quarter-turn. That is the opposite of the desired product:

- Outside crop: no rotate affordances in the main toolbar (cleaner Edit chrome).
- Inside crop: rotate lives with the crop tool, with UI and motion closer to **Apple Photos** Adjust → Crop (90° rotate controls colocated with crop; smooth animated re-layout of the image and crop frame).

Current crop chrome (`CropToolbarView`) only has aspect-ratio menu + Reset / Cancel / Apply — no rotate.

Existing durable model: `ImageRotation` / `document.rotation` (quarter-turns) and `CropAdjustments`; pipeline already applies rotation in `RenderPipeline`. The gap is **presentation and interaction**, not inventing a new rotation stage from scratch.

Reference feel (Apple Photos): entering crop focuses the canvas; rotate 90° animates the photo (and crop geometry) with a short, confident transition rather than a hard cut; controls stay inside the crop surface, not the global window toolbar.

## Scope

1. **Toolbar cleanup** — Remove always-visible Rotate Left/Right from `CanvasToolbarControls` (and any menu/command equivalents that imply “always available” unless intentionally kept as keyboard-only).
2. **Crop-mode rotate UI** — Add rotate controls inside crop mode (e.g. extend `CropToolbarView` or a sibling crop chrome), enabled only while `isCropToolActive`.
3. **Apple Photos–like motion** — Animate 90° rotates: image orientation change and crop-frame remapping should feel continuous (transform / layout animation), not a jarring snap. Match Kromora’s existing preview surface (GPU preview) without breaking live edit latency.
4. **Crop lifecycle** — Rotating while cropping must **not** cancel the draft crop; draft crop + rotation stay coherent until Apply / Cancel / Escape / Enter (existing KRMA-444 contract).
5. **Keyboard** — Keep or relocate shortcuts so rotate still works when crop is active; do not leave dead always-on toolbar icons.

Optional stretch (same ticket only if cheap; otherwise child): continuous straighten dial like Photos. Not required for first pass if quarter-turn + animation ships cleanly.

## Acceptance criteria

- [ ] Main window toolbar no longer shows Rotate Left/Right when crop mode is inactive (Edit chrome is crop-entry + zoom/nav only for orientation).
- [ ] While crop mode is active, the user can rotate 90° CW/CCW from controls inside the crop UI.
- [ ] Rotating in crop mode does not cancel/exit crop; Apply still commits the combined crop+rotation result; Cancel/Escape discards the in-progress crop draft (and any uncommitted rotate-in-crop state per the chosen draft model).
- [ ] 90° rotate in crop mode uses a visible, polished animation of the image (and crop frame as needed) — no hard cut; motion should be in the Apple Photos ballpark (short ease/spring, readable orientation change).
- [ ] Outside crop mode, existing committed rotation still displays correctly; no regression to Fit/Fill/zoom or crop aspect presets.
- [ ] Automated coverage for the new “rotate while cropping” lifecycle (at least model/canvas state); animation can be manual QA.

## Out of scope

- Library mosaic crop-aspect bug (KRMA-461).
- Top-bar / inspector chrome gap (KRMA-462).
- Full Photos parity for straighten angle / perspective / flip unless pulled in as a follow-up.

## Implementation notes

- `Sources/KromoraKit/Views/ContentView.swift` — `CanvasToolbarControls` rotate buttons (~396–406)
- `Sources/KromoraKit/Views/CropOverlayView.swift` — `CropToolbarView`
- `Sources/KromoraKit/Views/PreviewView.swift` — crop chrome placement / animation hooks
- `Sources/KromoraKit/ViewModels/AppViewModel.swift` — `rotateImage` / `rotateClockwise` / crop begin-commit-cancel; today cancels crop on rotate
- `Sources/KromoraKit/Models/CanvasNavigation.swift` — `isCropToolActive`, crop draft
- Preview path: `PreviewSurface` / live preview — ensure animation does not force full-res thrash

Related: KRMA-101 (crop landed), KRMA-444 (Escape/Enter in crop).

### Comment — codex @ 2026-09-19T16:49:57.655Z

Implemented crop-mode rotation in commit c1aac21: removed always-on Rotate Left/Right toolbar buttons, added Crop toolbar rotate controls and [ ] shortcuts, kept rotation/crop transient until Apply or discarded by Cancel/Escape, remapped crop geometry and effective source axes, and added animation plus model coverage. Verification: swift test --filter 'MenuCommandTests|ImageRotationTests|CropWorkflowTests|KeyMonitorTests' (35 passed), git diff --check, and dg validate (existing unknown-model warnings only).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-19T16:52:20.739Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Main toolbar no longer shows Rotate Left/Right outside crop mode (pass) — CanvasToolbarControls rotate buttons removed (ContentView.swift); no menu/command equivalents exist outside crop.
- [x] Rotate 90 CW/CCW available inside crop mode (pass) — CropToolbarView adds rotate buttons wired to viewModel.rotateClockwise/CounterClockwise; [ and ] keys also route to rotate while isCropToolActive.
- [x] Rotating in crop mode does not cancel/exit crop; Apply commits combined crop+rotation, Cancel/Escape discards draft (pass) — rotateImage branches on canvasState.isCropToolActive and calls canvasState.rotateCrop instead of cancelCrop; commitCrop folds cropRotation into document.rotation and replaces crop with the remapped draft; cancelCrop/finishCrop resets cropRotation to .zero without touching the document. Verified via testRotatingWhileCroppingKeepsDraftTransientUntilApplyOrCancel and by re-deriving the coordinate math (CropAdjustments.rotated, ImageRotation.addingClockwiseQuarterTurns, cropSourceSize composition) by hand.
- [x] 90 degree rotate in crop mode is animated, not a hard cut (pass) — PreviewView adds .animation(.snappy(duration: 0.3, extraBounce: 0.04), value: canvasState.cropRotation) scoped to the crop subtree; manual QA of feel is out of scope for this pass.
- [x] Outside crop mode, existing committed rotation still displays correctly; no regression to Fit/Fill/zoom or crop presets (pass) — sourceSize/orientedExtent paths for committed rotation are unchanged; ImageRotationTests suite (9 tests) and existing crop/fit tests pass.
- [x] Automated coverage for rotate-while-cropping lifecycle (pass) — ImageRotationTests.testRotatingWhileCroppingKeepsDraftTransientUntilApplyOrCancel covers draft transience, cancel-discards, and commit-combines-crop+rotation at the model/canvas-state level, satisfying the 'at least model/canvas state' bar. Keyboard [ ] routing while cropping has no dedicated KeyMonitorTests case; noted as a minor gap, not blocking.
Checks run:
- swift build (clean; only pre-existing CIKernel deprecation warnings, unrelated to this change)
- swift test --filter 'MenuCommandTests|ImageRotationTests|CropWorkflowTests|KeyMonitorTests' (35 passed)
- git diff --check c1aac21^ c1aac21 (clean)
- dg validate (only pre-existing unknown-model warnings for other issues)
- manual re-derivation of rotation/crop coordinate composition (ImageRotation.addingClockwiseQuarterTurns, CropAdjustments.rotated, cropSourceSize orientedExtent parity) to confirm no off-by-one or double-swap bug when combining committed document.rotation with transient cropRotation
- grep sweep confirming no dangling Rotate Left/Right toolbar/menu affordance remains outside crop mode and no unused view-model bindings were left behind in ContentView.swift
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU8MI8V4JKN8H1FV
