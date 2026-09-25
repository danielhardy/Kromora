---
id: KRMA-572
title: Keep the side-by-side Original pane free of masks and stable during Adjusted-only edits
type: bug
status: backlog
priority: high
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - comparison
  - masking
  - preview
created: 2026-09-25T01:33:32.931Z
updated: 2026-09-25T01:34:06.891Z
blockers: []
order: zx
board: product
context:
  files:
    - Sources/KromoraKit/Views/PreviewView.swift
    - Sources/KromoraKit/ViewModels/ComparisonFramePolicy.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift
    - Sources/KromoraKit/Models/EditDocument.swift
    - Tests/KromoraKitTests/ComparisonModeTests.swift
    - Tests/KromoraKitTests/AdjustInspectorTests.swift
  docs:
    - docs/COMPARISON_MODE.md
  issues:
    - KRMA-573
  commands:
    - swift test --filter 'ComparisonModeTests|AdjustInspectorTests|PreviewAdmissionCoordinatorTests'
    - swift build
    - git diff --check
---

## Objective

In side-by-side view, the left pane is Original and the right pane is Adjusted. Original must show the comparison baseline only. Today, opening the mask page paints the mask on Original as well, and editing something that does not change that baseline, such as exposure, makes Original flicker while Adjusted stays steady.

## What is going wrong

Two separate paths. Fix both.

**Mask chrome is attached to every preview surface.** `PreviewView.canvasSurface` builds both the Original panel and the Adjusted panel (`sideBySideView` calls it twice, about lines 94–120). The mask wash lives inside `canvasSurface` (`MaskCanvasOverlay`, about lines 267–286) and is shown whenever `isMaskingWorkspaceActive`. Person, subject, brush, linear, and radial guides therefore draw on Original. The wash is inspection chrome for the edit being made. It belongs on the Adjusted pane only.

**Original is cleared and rendered again when its pixels did not change.** `EditDocument.originalForComparison` keeps `rawDevelop`, crop, and rotation, and strips Light, Color, Effects, Looks, adjustments, and `localAdjustments`. `docs/COMPARISON_MODE.md` says the same thing. `ComparisonFramePolicy.changesBaseline` still returns true when `localAdjustments` change (about lines 22–32). `updateDocument` then advances the comparison revision, calls `originalPreviewSurface.clear()`, and reschedules Original (about lines 3331–3336). A mask-page exposure edit writes `localAdjustments`, so Original blanks and comes back with the same baseline. Adjusted does not clear its last frame, which is why only Original flickers.

Global Light/Adjust exposure is already excluded by that policy. `AdjustInspectorTests.testAnAdjustmentEditDoesNotReRenderTheComparisonBaseline` locks that. If a global exposure slider still flickers Original, the comparison job shares the editor lane and an evicted comparison sets `comparisonPreviewScheduledRevision` back to nil (`PreviewAdmissionCoordinator.scheduleOriginalPreview`, the `onTerminal` path). The next settled Adjusted frame then renders Original again. Original must keep the frame it already showed unless the baseline document actually changed.

## Required behavior

- Side-by-side plus the masking workspace: overlay, guides, and brush cursor are on the Adjusted pane only. Original has no mask wash.
- Original pixels stay on `comparisonBaseline` / `originalForComparison`. A local mask, including mask-layer exposure, does not appear in Original.
- Dragging exposure, contrast, or any other Light, Color, Effects, Look, adjustment, or local-mask control does not clear Original and does not request a new Original render when `originalForComparison` is unchanged.
- Crop, rotation, and a raw-develop change that `ComparisonFramePolicy.rawDevelopChangesFrame` reports still refresh Original.
- Single-image view and Space-hold comparison still show the mask overlay on the one visible surface when the masking workspace is open.

## Tests

- Extend `ComparisonFramePolicy` coverage: a `localAdjustments` edit does not change the baseline; a crop or qualifying raw-develop edit still does.
- A side-by-side local-mask edit does not call `originalPreviewSurface.clear()` and does not enqueue another comparison request. Follow `AdjustInspectorTests.testAnAdjustmentEditDoesNotReRenderTheComparisonBaseline`.
- Keep `ComparisonModeTests` and `AdjustInspectorTests` green.
- The overlay split is view structure. Assert it from the `PreviewView` construction if an existing view test can see the overlay modifier; otherwise state in the handoff that the Original `canvasSurface` call no longer installs `MaskCanvasOverlay`, and that Adjusted still does.

## Checks

- `swift build`
- `swift test --filter 'ComparisonModeTests|AdjustInspectorTests|PreviewAdmissionCoordinatorTests'`
- `git diff --check`

## Out of scope

Changing how Subject or Foreground mattes are generated (KRMA-573). Changing export. Moving preview publication (KRMA-565).
