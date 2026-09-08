---
id: LUMO-274
title: Crop overlay top-left handle, frame dragging, and portrait/landscape ratios are broken
type: bug
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - crop
  - editing
  - ux
created: 2026-09-07T03:46:06.834Z
updated: 2026-09-08T00:50:39.131Z
order: zx
board: product
claim:
  actor: claude
  session: 01MTRY9DSJFTQ9GXW4
  claimed_at: 2026-09-08T00:47:09.331Z
  expires_at: 2026-09-08T01:47:09.331Z
  model: sonnet
---

## Objective

Make the crop overlay reliably resize from every corner, move as a fixed-size frame, and offer
explicit quick-ratio orientation choices for portrait and landscape crops.

## Context

In the crop tool, the top-left grab handle does not respond when dragged to the right to bring the
left edge inward. The top-right handle can resize in the analogous direction, so the two corners
are not symmetric. The crop frame's interior should drag the complete frame around the photo while
keeping its width and height unchanged; it currently does not provide that dependable move
interaction.

The quick-ratio control also needs a way to switch the conventional presets between portrait and
landscape. Selecting a ratio such as 3:2 should make it possible to choose both 3:2 landscape and
2:3 portrait explicitly, regardless of the source image orientation. Square and Freeform remain
unchanged.

Relevant code is in `Sources/LumoKit/Views/CropOverlayView.swift` and
`Sources/LumoKit/Models/CropAdjustments.swift`. The fixed-ratio resize path currently derives the
new width with a `max` against the unchanged dimension, which can preserve the old width during a
top-left horizontal inward drag even though the requested width is smaller.

## Acceptance criteria

- [ ] Dragging the top-left handle right shrinks the crop from the left edge and moves `minX`
      right; dragging it left expands the crop, subject to image bounds and the selected ratio.
- [ ] All four corner handles resize symmetrically in Freeform and fixed-ratio modes, including
      inward and outward horizontal-only and vertical-only drags.
- [ ] Dragging inside the crop frame translates the entire frame without changing its width or
      height, and clamps the frame to the image bounds.
- [ ] The crop UI exposes explicit portrait and landscape quick-ratio choices for each non-square
      preset; selecting one updates the frame, preserves a sensible center when possible, and
      persists the selected orientation through Apply/reopen.
- [ ] Add model-level regression tests for the top-left inward resize, fixed-size frame movement,
      and portrait/landscape ratio selection; existing crop, render, and export tests continue to
      pass.

## Implementation notes

- Keep crop rectangles in normalized bottom-left source coordinates and keep pointer conversion in
  the overlay/model interaction boundary.
- Ensure the move gesture has priority only for the crop interior and does not steal corner-handle
  drags; maintain accessible labels/hints for the ratio and handle controls.
- Do not infer the requested portrait/landscape choice solely from the source image orientation;
  represent the selected ratio orientation in the crop state or derive it losslessly from the
  normalized frame.

### Comment — codex @ 2026-09-07T03:46:40.960Z

Reproduced from code inspection: fixed-ratio resizing uses the unchanged dimension as a max constraint, so a top-left horizontal inward drag can return the original width. The ticket also captures the required fixed-size interior move gesture and explicit portrait/landscape quick-ratio choices.

### Comment — codex @ 2026-09-08T00:47:01.164Z

Implemented in commit 0ec4c48: fixed one-axis corner resizing across all handles, bounded fixed-size interior frame movement, explicit portrait/landscape quick-ratio choices with persisted orientation, clipboard propagation, and model/workflow regressions. Verification: swift test — 940 passed, 43 expected skips; focused crop workflow tests pass.

### Comment — claude @ 2026-09-08T00:50:36.384Z

## Counterpoint verification report — LUMO-274

**Verdict: PASS**

**Scope reviewed:** commit 0ec4c48 (Sources/LumoKit/Models/{CropAdjustments,CanvasNavigation,EditClipboard}.swift, ViewModels/AppViewModel.swift, Views/{CropOverlayView,PreviewView}.swift, Tests/LumoKitTests/CropTests.swift).

**Correctness**
- `CropOverlayInteraction.resized` now branches on which axis actually moved (`horizontalDrag`/`verticalDrag`) instead of unconditionally taking `max(requestedWidth, requestedHeight*targetRatio)`. Traced through all four handles by hand: each one-axis drag drives the corresponding raw dimension and the other dimension is derived from `targetRatio`, so all four corners are symmetric in both fixed-ratio and freeform modes. Confirmed against the new `testTopLeftFixedRatioHorizontalInwardDragMovesLeftEdgeRight` and `testFixedRatioOneAxisResizesSymmetricallyFromEveryCorner`.
- `CropAspectRatioOrientation` (`automatic`/`landscape`/`portrait`) is threaded end-to-end: `CropAspectRatio.normalizedRatio(orientation:)` → `CropAdjustments` (Codable, defaults `.automatic` on decode, so old documents/clipboard payloads stay neutral) → `EditClipboardPayload.CropCategory` → `CanvasInteractionState` → `AppViewModel` → `CropOverlayView` menu. No orientation dependency exists outside these files (checked `RecipeExtractor`/export path — it only reads `normalizedRect`, not `aspectRatio`/`orientation`), so no export-side gap.
- Interior move gesture (`translated`) unchanged in substance; frame-size preservation and bounds clamping verified by existing + new `testDraggingCropAreaPreservesFixedFrameSize`.
- `Rectangle().inset(by: 14)` used to keep the move-gesture hit area from stealing corner-handle drags on small frames is a reasonable, localized UI fix; handles are drawn after the move rectangle in the ZStack so they already win hit-testing, this is defense in depth, not load-bearing.

**Maintainability/API**: additive `orientation` parameters all default to `.automatic`, preserving old call sites; Codable back-compat verified by `testMissingCropFieldKeepsLegacyDocumentsNeutral`/clipboard legacy test.

**Security**: no new I/O, network, or privilege-sensitive code paths; N/A.

**Performance**: pure value-type geometry, no new allocations in hot paths; unaffected.

**Tests run**: `swift test` — 940 passed, 43 expected skips, 0 failures (full deterministic lane, ~121s). Targeted `swift test --filter Crop` — 30/30 passed, including the 4 new regression tests.

**Findings**: none blocking. No broader non-blocking findings warranting a child ticket — the inset-based hit-testing tweak is small enough to not need follow-up.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
