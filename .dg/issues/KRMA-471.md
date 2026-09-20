---
id: KRMA-471
title: "Crop workspace chrome: replace overlay toolbar with a dedicated crop mode"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Entering Crop hides filmstrip, culling bar, and source browser; photo + crop overlay own the canvas
      result: pass
      notes: ContentView.detailContent gates CullingBarView/FilmstripView and SourceBrowserView on !canvasState.isCropToolActive
    - criterion: Right inspector is a Crop panel while cropping; Edit tabs unreachable until crop ends
      result: pass
      notes: availableInspectorTabs returns [] during crop; selectInspectorTab is guarded; InfoInspectorView branches to CropInspectorView
    - criterion: CropToolbarView gone from preview; no second Apply/Cancel/aspect bar on canvas
      result: pass
      notes: CropToolbarView deleted from CropOverlayView.swift/PreviewView.swift; controls moved to new CropInspectorView.swift
    - criterion: Done (and Enter) commit draft crop + in-crop rotation and restore Edit workspace
      result: pass
      notes: commitCrop() applies rotation+crop then restoreCropPresentation()
    - criterion: Cancel, Escape, Crop toggle discard draft (incl. rotation) and restore chrome without a history entry
      result: pass
      notes: cancelCrop() calls finishCrop/restoreCropPresentation without updateDocument
    - criterion: Switching to Library cannot silently commit; cancels or is blocked
      result: pass
      notes: "navigate(to: .grid) calls cancelCrop() before moving; same for selectCollectionImage and resetForSource"
    - criterion: Overlay handles remain hittable; 90° rotate stays in-crop and animated; Escape/Enter match KRMA-444
      result: pass
      notes: CropOverlayView hit-testing untouched; rotate controls relocated into CropInspectorView; KeyboardShortcuts.swift crop Escape/Return wiring unchanged
    - criterion: Automated coverage for enter/exit chrome lifecycle at model/view-model boundary; swift build; focused tests; dg validate; git diff --check
      result: pass
      notes: New testCropModeOwnsAndRestoresEditChromeState in CropTests.swift; all checks re-run clean below
  checks_run:
    - swift build (clean, only pre-existing CI kernel deprecation warnings)
    - swift test --filter 'CropWorkflowTests|ImageRotationTests|KeyMonitorTests' (30 passed)
    - scripts/ci-tests.sh fast (1077 tests; one PortablePackageMaintenanceTests timing test flaked once under parallel load, passed standalone and on full rerun — pre-existing flake unrelated to this change)
    - git diff --check b1aadfd~1 b1aadfd (clean)
    - dg validate (only pre-existing unknown-model/low-context warnings)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-20T02:31:11.592Z
  session: 01MU971YD8YE74XX7S
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - crop
  - editor
created: 2026-09-19T22:18:53.228Z
updated: 2026-09-20T02:31:11.594Z
order: a0
board: product
---

Parent: KRMA-470. Lands the **mode**. Overlay-toolbar-only is a fail even if rotate/aspect still work.

## Objective

Entering Crop replaces the Edit workspace with a dedicated crop mode: filmstrip and sibling Edit chrome recede, the canvas is the crop surface, and framing controls live in a **crop inspector** with **Done** / Cancel (Escape), not a bar laid on the photo.

## Context

KRMA-463 added 90° rotate to `CropToolbarView` and kept crop as an overlay on the existing Edit layout. The photographer still sees filmstrip, culling, source browser, and Light/Color/Info while dragging a crop. Apple Photos does the opposite: Crop is a mode.

`beginCrop()` already fits the canvas, shows an uncropped preview, and keeps the draft off `EditDocument` until Apply. Keep that draft contract. Change **presentation ownership**.

## Scope

1. **Enter/exit workspace** — `isCropToolActive` drives a workspace, not just an overlay.
   - Hide filmstrip, culling bar, and source browser while cropping.
   - Present the right inspector as a Crop panel (always shown in crop mode). Hide Light/Color/Develop/Effects/Look/Masking/Info tabs until crop ends.
   - Remove `CropToolbarView` from `PreviewView`. Do not leave a second Apply/Cancel/aspect bar on the canvas.
   - Toolbar: prominent **Done** commits (same as Enter / today’s Apply). Cancel / Escape / the Crop toggle still discard the draft. Existing KRMA-444 and KRMA-463 rotate-in-crop lifecycle stay valid.
   - Library/Edit picker: either disable Library until Done/Cancel, or leaving Edit cancels the draft. Do not commit a draft by switching workspace.

2. **Crop inspector (existing tools only)** — Relocate what already works:
   - Aspect presets currently in the overlay menu.
   - 90° rotate CW/CCW (KRMA-463).
   - Reset (draft → full image).
   - Done / Cancel if they are not in the window toolbar.

3. **Canvas** — Keep `CropOverlayView` on the photo (dimmed outside, handles, rule-of-thirds). Optional: L-shaped corner handles instead of circles if cheap; not a blocker. Do not add straighten/perspective/flip in this ticket.

4. **Motion** — Short ease when entering/leaving crop mode (filmstrip/inspector swap), same family as the 0.2s crop-enter animation already on `PreviewView`.

## Acceptance criteria

- [ ] Entering Crop hides the filmstrip, culling bar, and source browser; the photo + crop overlay own the canvas.
- [ ] While cropping, the right inspector is a Crop panel (aspect, 90° rotate, Reset). Edit inspector tabs (Info/Light/Color/…) are not reachable until crop ends.
- [ ] `CropToolbarView` is gone from the preview. Apply/Cancel/aspect/rotate do not sit on the image.
- [ ] Done (and Enter) commit draft crop + any in-crop 90° rotation and restore the normal Edit workspace.
- [ ] Cancel, Escape, and toggling Crop off discard the draft (including in-crop rotation) and restore Edit chrome without a history entry.
- [ ] Switching to Library while cropping cannot silently commit; it cancels or is blocked until the session ends.
- [ ] Overlay handles remain hittable (KRMA-387); 90° rotate stays in-crop and animated (KRMA-463); Escape/Enter still match KRMA-444.
- [ ] Automated coverage for enter/exit chrome lifecycle at the model/view-model boundary (filmstrip/inspector not required to be UI-tested if state flags are asserted). `swift build`, focused crop/rotation/keyboard tests, `dg validate`, `git diff --check`.

## Out of scope

- Straighten angle, flip, new aspect ratios, perspective, Auto (KRMA-472 / KRMA-473).
- Changing `ImageRotation` beyond the existing quarter-turn draft.
- Library mosaic, export crop math, or a new render stage.

## Implementation notes

- `Sources/KromoraKit/Views/ContentView.swift` — `detailContent` currently always shows `FilmstripView` / `CullingBarView` / `SourceBrowserView` when the collection is active; gate on `canvasState.isCropToolActive`. Toolbar Done vs Crop toggle.
- `Sources/KromoraKit/Views/PreviewView.swift` — delete the `CropToolbarView` sibling; keep overlay + crop-rotation animation.
- `Sources/KromoraKit/Views/CropOverlayView.swift` — keep overlay; `CropToolbarView` can move or die.
- `Sources/KromoraKit/Views/InfoInspectorView.swift` — crop-mode content branch; do not add a permanent inspector tab that is empty outside crop.
- `Sources/KromoraKit/Models/CanvasNavigation.swift` / `AppViewModel` crop lifecycle — extend presentation flags if needed; do not change commit/cancel semantics.
- Masking already uses inspector-tab “Done”; crop should be a **mode**, not another inspector tab you can leave while the overlay stays active.

Related: KRMA-470 (epic), KRMA-463 (rotate-in-crop, done), KRMA-444 (Escape/Enter), KRMA-101 (crop model).


### Comment — codex @ 2026-09-20T02:25:14.341Z

Implemented in b1aadfd. Crop is now a dedicated workspace: filmstrip/culling/source browser recede, the inspector becomes an always-present Crop panel with existing aspect/rotate/reset/Done/Cancel controls, and CropToolbarView is removed from PreviewView. Done/Enter commit the existing draft contract; Cancel/Escape/Crop toggle and Library/source navigation discard safely. Added model/view-model chrome lifecycle coverage. Verification: swift build; swift test (1,515 passed, 54 expected skips, 0 failures); focused CropWorkflowTests/ImageRotationTests/KeyMonitorTests (30 passed); git diff --check; dg validate (pre-existing unknown-model/low-context warnings only).

## Agent log

- 2026-09-20T02:31:11.592Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Entering Crop hides filmstrip, culling bar, and source browser; photo + crop overlay own the canvas (pass) — ContentView.detailContent gates CullingBarView/FilmstripView and SourceBrowserView on !canvasState.isCropToolActive
- [x] Right inspector is a Crop panel while cropping; Edit tabs unreachable until crop ends (pass) — availableInspectorTabs returns [] during crop; selectInspectorTab is guarded; InfoInspectorView branches to CropInspectorView
- [x] CropToolbarView gone from preview; no second Apply/Cancel/aspect bar on canvas (pass) — CropToolbarView deleted from CropOverlayView.swift/PreviewView.swift; controls moved to new CropInspectorView.swift
- [x] Done (and Enter) commit draft crop + in-crop rotation and restore Edit workspace (pass) — commitCrop() applies rotation+crop then restoreCropPresentation()
- [x] Cancel, Escape, Crop toggle discard draft (incl. rotation) and restore chrome without a history entry (pass) — cancelCrop() calls finishCrop/restoreCropPresentation without updateDocument
- [x] Switching to Library cannot silently commit; cancels or is blocked (pass) — navigate(to: .grid) calls cancelCrop() before moving; same for selectCollectionImage and resetForSource
- [x] Overlay handles remain hittable; 90° rotate stays in-crop and animated; Escape/Enter match KRMA-444 (pass) — CropOverlayView hit-testing untouched; rotate controls relocated into CropInspectorView; KeyboardShortcuts.swift crop Escape/Return wiring unchanged
- [x] Automated coverage for enter/exit chrome lifecycle at model/view-model boundary; swift build; focused tests; dg validate; git diff --check (pass) — New testCropModeOwnsAndRestoresEditChromeState in CropTests.swift; all checks re-run clean below
Checks run:
- swift build (clean, only pre-existing CI kernel deprecation warnings)
- swift test --filter 'CropWorkflowTests|ImageRotationTests|KeyMonitorTests' (30 passed)
- scripts/ci-tests.sh fast (1077 tests; one PortablePackageMaintenanceTests timing test flaked once under parallel load, passed standalone and on full rerun — pre-existing flake unrelated to this change)
- git diff --check b1aadfd~1 b1aadfd (clean)
- dg validate (only pre-existing unknown-model/low-context warnings)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU971YD8YE74XX7S
Summary: Verified KRMA-471: crop is now a dedicated workspace (filmstrip/culling/source browser hidden, Crop inspector replaces CropToolbarView, Done/Cancel/Escape/Library-switch semantics all correct). Build, focused tests, full fast lane, git diff --check, and dg validate all clean. No findings; completing to done.
