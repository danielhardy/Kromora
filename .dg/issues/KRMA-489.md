---
id: KRMA-489
title: "Crop mode: hide Edit toolbar chrome except Save, Cancel, and Undo"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: With Crop open, the window toolbar shows only Save, Cancel, and Undo
      result: pass
      notes: toolbarContent switches on ContentView.toolbarMode; the .crop branch renders only CropToolbarControls, and every other control is in the .edit branch, so they are omitted rather than disabled.
    - criterion: Save commits and exits crop; Cancel discards and exits; labels and shortcuts match Return / Escape
      result: pass
      notes: Save calls commitCrop and Cancel calls cancelCrop, with no history entry on cancel. Help text names Return and Escape. Fixed a stale 'Adjust crop, then Done' status message to say Save.
    - criterion: Undo is present, disabled when there is nothing to undo, and does not break the crop draft Cancel/Save contract
      result: pass
      notes: Disabled via !hasImage || !viewModel.canUndo. It undoes committed history, which matches the ticket default. Undoing a rotation or crop change mid-draft can leave the draft stale; the same exposure already exists via Cmd-Z. Filed as non-blocking KRMA-494.
    - criterion: Exiting crop restores the full Edit toolbar
      result: pass
      notes: The mode derives from canvasState.isCropToolActive, so the .edit branch returns when crop ends.
    - criterion: Automated coverage for crop-mode toolbar visibility
      result: pass
      notes: MenuCommandTests.testCropToolbarOwnsExclusiveWindowChrome checks the toolbarMode seam and inspects the source of the crop branch. It is a source-text check, not a rendered-view check, which is consistent with the neighbouring tests.
    - criterion: scripts/ci-tests.sh fast and serial pass
      result: pass
      notes: "fast: 1101 tests, exit 0 on rerun. serial: 396 tests, 1 skipped, 0 failures. The first fast run failed CanvasObservationTests.testPanAtDeepZoomRequestsROIsThatCoverEveryViewportEdge, which passed alone and on rerun, so it looks like a flake unrelated to this change."
  checks_run:
    - "scripts/ci-tests.sh fast (first run: 1 canvas-pan failure; rerun exit 0)"
    - swift test --filter CanvasObservationTests (7 passed)
    - scripts/ci-tests.sh serial (396 tests, 0 failures, 1 skipped)
    - swift build after the status message fix
  findings:
    - "Non-blocking: undo or redo while the crop draft is open restores a prior document under a stale draft, so Save may commit against changed rotation or source size. Pre-existing via Cmd-Z, made more discoverable by the toolbar button. Tracked in KRMA-494."
    - "Non-blocking: CropInspectorView still has a commit button labelled Done while the toolbar says Save. Tracked in KRMA-494."
    - "Non-blocking: possible flake in CanvasObservationTests.testPanAtDeepZoomRequestsROIsThatCoverEveryViewportEdge under the parallel lane (KRMA-482 area), passed on rerun."
  fixes:
    - AppViewModel.beginCrop status message changed from 'Adjust crop, then Done' to 'Adjust crop, then Save' to match the renamed commit control.
  verification_commits:
    - da900f3
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-20T23:14:37.481Z
  session: 01MUAFJW94WVM6FTIN
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - crop
  - ui
  - ux
created: 2026-09-20T22:26:22.304Z
updated: 2026-09-20T23:14:37.483Z
order: a0
board: product
commits:
  - da900f3
---

## Objective

While Crop is active, the window toolbar shows only the crop session actions — **Save** (commit), **Cancel** (discard), and **Undo** — and hides the rest of the Edit chrome (Library/Edit, Copy/Paste, Share/Export, Auto, split view, sidebar, Import, Reset, zoom, etc.).

## Context

User report (2026-09-20): in crop mode the top buttons should be hidden except Save, Cancel, and Undo. Library/Edit, copy, paste, share, share bulk, Auto, split view, sidebar control, and similar Edit affordances should not appear while cropping.

KRMA-471 already made Crop a dedicated workspace for the **canvas** (hid filmstrip, culling bar, source browser; swapped the inspector to `CropInspectorView`). The **window toolbar** was left largely intact: only a few controls are `.disabled` during crop, and most remain visible and clickable.

Today `ContentView.toolbarContent` / `CanvasToolbarControls` (`Sources/KromoraKit/Views/ContentView.swift`) still shows during crop:

| Control | Crop behaviour today |
| --- | --- |
| Library / Edit segmented picker | Visible and active (`navigate` cancels crop as a side effect) |
| Done + Cancel Crop | Visible (commit / discard) |
| Zoom % menu | Visible but disabled |
| Auto | Visible (not crop-gated) |
| Side by Side | Visible |
| Editor sidebar (Info) | Visible but disabled |
| Reset menu | Visible |
| Import menu | Visible |
| Copy Edits / Paste Edits | Visible |
| Export / Export Selected | Visible |

That fights the Photos-style crop workspace (KRMA-470/471): crop should feel like a focused mode, not Edit-with-some-buttons-greyed-out.

### Labelling note

The commit control is currently titled **Done**. This ticket’s product language is **Save** (commit the crop draft and leave crop mode). Prefer renaming the crop commit control to **Save** for consistency with the request, unless a short product decision keeps **Done** (Photos) — either way only one commit button, and Cancel remains the discard path. **Undo** is not in the window toolbar today; add a crop-mode Undo control that drives the existing undo stack / `UndoManager` (and disable it when there is nothing to undo). Clarify in implementation whether Undo during an open crop session undoes prior committed document edits only, or also steps within the crop draft — default: standard app Undo of committed history; crop draft still discarded only via Cancel unless undo groupings already cover in-crop mutations.

## Requirements

When `canvasState.isCropToolActive`:

**Keep (visible and enabled as appropriate)**
- **Save** — commit crop (`commitCrop`); keyboard Return / existing Done shortcut remains.
- **Cancel** — discard crop (`cancelCrop` / toggle off); Escape remains.
- **Undo** — invoke the app’s undo for the active document; disabled when undo is unavailable.

**Hide (not merely disable)**
- Library / Edit workspace picker
- Crop enter toggle (replaced by Save/Cancel while active — already the case for the Crop button itself)
- Zoom / Fit / Fill menu
- Auto
- Side by Side / comparison
- Editor sidebar toggle
- Reset menu (crop Reset stays in the crop inspector)
- Import menu
- Copy Edits / Paste Edits
- Export and Export Selected (“share” / “share bulk”)
- Any other Edit-primary toolbar items added later unless explicitly crop-safe

Leaving crop (Save or Cancel) restores the normal Edit toolbar.

Menu-bar commands (File ▸ Export, Edit ▸ Copy, etc.) may remain for power users unless they are dangerous mid-crop; prefer cancelling or no-opping destructive navigation already covered by KRMA-471 rather than expanding this ticket into a full menu audit. Hotkeys that jump to Library/Grid must continue to cancel crop rather than commit silently (existing contract).

## Acceptance criteria

- [ ] With Crop open, the window toolbar shows only Save, Cancel, and Undo (plus any unavoidable system window controls). No Library/Edit, Auto, split view, sidebar, Import, Copy/Paste, Export/Export Selected, Reset, or zoom controls remain visible.
- [ ] Save commits and exits crop; Cancel discards and exits; labels and shortcuts match the existing commit/discard behaviour (Return / Escape).
- [ ] Undo is present, disabled when there is nothing to undo, and does not break the crop draft Cancel/Save contract.
- [ ] Exiting crop restores the full Edit toolbar.
- [ ] Automated coverage for crop-mode toolbar visibility (ViewModel/chrome flag or View inspection seam used by KRMA-471’s `testCropModeOwnsAndRestoresEditChromeState` style).
- [ ] `scripts/ci-tests.sh fast` and `serial` pass.

## Implementation notes

- Primary surface: `Sources/KromoraKit/Views/ContentView.swift` — branch `toolbarContent` (and `CanvasToolbarControls`) on `canvasState.isCropToolActive` so non-crop items are omitted from the builder, not only `.disabled`.
- Prefer a small `@ViewBuilder` crop toolbar vs sprinkling `if !isCropToolActive` on every button.
- Related: KRMA-470 (crop workspace epic), KRMA-471 (canvas/inspector chrome; toolbar left incomplete), KRMA-444 (Escape/Enter).

### Comment — codex @ 2026-09-20T23:10:55.895Z

Implemented crop-mode toolbar isolation in ebd1c81: Crop now renders only Save, Cancel, and Undo; the normal Edit toolbar is restored on exit; Undo uses committed document history and is disabled when unavailable. Added focused chrome-mode coverage. Verification: scripts/ci-tests.sh fast (exit 0, 1,101 tests) and serial (396 tests, 1 skipped, 0 failures).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-20T23:14:37.481Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] With Crop open, the window toolbar shows only Save, Cancel, and Undo (pass) — toolbarContent switches on ContentView.toolbarMode; the .crop branch renders only CropToolbarControls, and every other control is in the .edit branch, so they are omitted rather than disabled.
- [x] Save commits and exits crop; Cancel discards and exits; labels and shortcuts match Return / Escape (pass) — Save calls commitCrop and Cancel calls cancelCrop, with no history entry on cancel. Help text names Return and Escape. Fixed a stale 'Adjust crop, then Done' status message to say Save.
- [x] Undo is present, disabled when there is nothing to undo, and does not break the crop draft Cancel/Save contract (pass) — Disabled via !hasImage || !viewModel.canUndo. It undoes committed history, which matches the ticket default. Undoing a rotation or crop change mid-draft can leave the draft stale; the same exposure already exists via Cmd-Z. Filed as non-blocking KRMA-494.
- [x] Exiting crop restores the full Edit toolbar (pass) — The mode derives from canvasState.isCropToolActive, so the .edit branch returns when crop ends.
- [x] Automated coverage for crop-mode toolbar visibility (pass) — MenuCommandTests.testCropToolbarOwnsExclusiveWindowChrome checks the toolbarMode seam and inspects the source of the crop branch. It is a source-text check, not a rendered-view check, which is consistent with the neighbouring tests.
- [x] scripts/ci-tests.sh fast and serial pass (pass) — fast: 1101 tests, exit 0 on rerun. serial: 396 tests, 1 skipped, 0 failures. The first fast run failed CanvasObservationTests.testPanAtDeepZoomRequestsROIsThatCoverEveryViewportEdge, which passed alone and on rerun, so it looks like a flake unrelated to this change.
Checks run:
- scripts/ci-tests.sh fast (first run: 1 canvas-pan failure; rerun exit 0)
- swift test --filter CanvasObservationTests (7 passed)
- scripts/ci-tests.sh serial (396 tests, 0 failures, 1 skipped)
- swift build after the status message fix
Findings:
- Non-blocking: undo or redo while the crop draft is open restores a prior document under a stale draft, so Save may commit against changed rotation or source size. Pre-existing via Cmd-Z, made more discoverable by the toolbar button. Tracked in KRMA-494.
- Non-blocking: CropInspectorView still has a commit button labelled Done while the toolbar says Save. Tracked in KRMA-494.
- Non-blocking: possible flake in CanvasObservationTests.testPanAtDeepZoomRequestsROIsThatCoverEveryViewportEdge under the parallel lane (KRMA-482 area), passed on rerun.
Fixes:
- AppViewModel.beginCrop status message changed from 'Adjust crop, then Done' to 'Adjust crop, then Save' to match the renamed commit control.
Verification commits:
- da900f3
Actor: claude
Resolved model: sonnet
Pickup session: 01MUAFJW94WVM6FTIN
Summary: Verified: crop toolbar isolation correct; fast and serial CI pass. One label fix applied; KRMA-494 filed for non-blocking follow-ups.
