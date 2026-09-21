---
id: KRMA-494
title: Crop toolbar Undo can leave stale crop draft; inspector still says Done
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Decide and implement product behaviour for Undo/Redo during an open crop
      result: pass
      notes: "Chosen behaviour: history restore re-seeds the transient draft (rect, aspect, orientation, straighten, flips, perspective; cropRotation reset) from the restored committed crop via CanvasInteractionState.reseedCrop, updates sourceSize first, and schedules the uncropped crop-entry preview instead of the cropped settled preview."
    - criterion: "Test: committed rotation/crop in history, open Crop, Undo, then Save/Cancel matches chosen behaviour"
      result: pass
      notes: CropWorkflowTests.testUndoRedoWhileCropIsOpenReseedsDraftBeforeSaveOrCancel covers Undo, Redo, Cancel and Save with no stale draft leakage; passes.
    - criterion: Inspector commit button label matches toolbar (Save)
      result: pass
      notes: CropInspectorView button is now Save; MenuCommandTests asserts it.
  checks_run:
    - "swift test --filter CropWorkflowTests|MenuCommandTests|CropTests: 21 tests, 0 failures"
    - "swift test --filter testUndoRedoWhileCropIsOpenReseedsDraftBeforeSaveOrCancel: passed"
    - Manual code review of applyHistoryDocument, reseedCrop/seedCrop refactor, commitCrop/cancelCrop
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-21T00:15:49.467Z
  session: 01MUAHUFPV083H89TG
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-20T23:14:12.844Z
updated: 2026-09-21T00:15:49.469Z
parent: KRMA-489
order: a0
board: product
---

## Objective

Make Undo/Redo while the crop draft is open safe, and make the crop commit label consistent.

## Context

Found while verifying KRMA-489 (non-blocking).

1. `viewModel.undo()` (toolbar Undo, Cmd-Z in `KeyboardShortcuts.swift`, Edit ▸ Undo) restores a prior committed `EditDocument` through `applyHistoryDocument` while `canvasState` still holds the crop draft. If the undone step changed rotation or crop, `sourceSize` and orientation change under the draft, so the overlay rectangle, `cropRotation`, and the entry preview (rebuilt from `document.rotation + cropRotation`) no longer match, and Save then commits the stale draft over the restored document. The Cmd-Z path had this exposure before KRMA-489; the toolbar button makes it more discoverable.
2. `CropInspectorView` still has a commit button titled "Done" while the toolbar commit is now "Save".

## Acceptance criteria

- [ ] Decide the product behaviour for Undo/Redo during an open crop (for example re-seed the draft from the restored document, cancel the crop first, or disable Undo until Save/Cancel) and implement it.
- [ ] Test: with a committed rotation/crop in history, open Crop, Undo, then Save/Cancel; the result matches the chosen behaviour.
- [ ] The inspector commit button label matches the toolbar (Save) or the difference is a documented decision.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-21T00:15:07.098Z

Implemented and tested in commit 5e4168b. Undo/Redo during an open Crop now re-seed the transient draft from the restored committed document, including orientation/source geometry, and refresh the uncropped crop-entry preview before Save/Cancel. Added regression coverage for rotation/crop history with Undo, Redo, Save, and Cancel. Renamed the inspector commit action from Done to Save. Verification: swift test — 1,553 executed, 55 skipped, 0 failures; dg validate passes.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-21T00:15:49.467Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Decide and implement product behaviour for Undo/Redo during an open crop (pass) — Chosen behaviour: history restore re-seeds the transient draft (rect, aspect, orientation, straighten, flips, perspective; cropRotation reset) from the restored committed crop via CanvasInteractionState.reseedCrop, updates sourceSize first, and schedules the uncropped crop-entry preview instead of the cropped settled preview.
- [x] Test: committed rotation/crop in history, open Crop, Undo, then Save/Cancel matches chosen behaviour (pass) — CropWorkflowTests.testUndoRedoWhileCropIsOpenReseedsDraftBeforeSaveOrCancel covers Undo, Redo, Cancel and Save with no stale draft leakage; passes.
- [x] Inspector commit button label matches toolbar (Save) (pass) — CropInspectorView button is now Save; MenuCommandTests asserts it.
Checks run:
- swift test --filter CropWorkflowTests|MenuCommandTests|CropTests: 21 tests, 0 failures
- swift test --filter testUndoRedoWhileCropIsOpenReseedsDraftBeforeSaveOrCancel: passed
- Manual code review of applyHistoryDocument, reseedCrop/seedCrop refactor, commitCrop/cancelCrop
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUAHUFPV083H89TG
Summary: Verified: Undo/Redo during open Crop re-seeds the draft from the restored document and refreshes the uncropped entry preview; inspector button renamed to Save; regression test passes.
