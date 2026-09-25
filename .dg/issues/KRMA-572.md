---
id: KRMA-572
title: Keep the side-by-side Original pane free of masks and stable during Adjusted-only edits
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "Side-by-side + masking workspace: mask overlay, guides, brush cursor appear on Adjusted pane only, not Original"
      result: pass
      notes: PreviewView.canvasSurface now takes showsMaskOverlay; sideBySideView passes false for the Original panel and true for Adjusted; single-image/Space-hold path still passes true.
    - criterion: Original pixels stay on comparisonBaseline/originalForComparison; local mask edits (including mask-layer exposure) do not appear in Original
      result: pass
      notes: Original canvasSurface call disables the overlay; originalForComparison already strips localAdjustments.
    - criterion: Dragging exposure/contrast/Light/Color/Effects/Look/local-mask controls does not clear Original or request a new Original render when originalForComparison is unchanged
      result: pass
      notes: ComparisonFramePolicy.changesBaseline now compares old/new comparisonBaseline (which already excludes localAdjustments, Light, Color, Effects, adjustments, LUT) instead of separately checking localAdjustments. PreviewAdmissionCoordinator's onTerminal eviction path and the failure-retry path both added an admissionHasOriginalPreview guard so a still-valid displayed baseline is not cleared or re-enqueued.
    - criterion: Crop, rotation, and a raw-develop change that rawDevelopChangesFrame reports still refresh Original
      result: pass
      notes: comparisonBaseline retains crop/rotation/rawDevelop; changesBaseline neutralizes only neutralTemperature/neutralTint before comparing, matching rawDevelopChangesFrame's exclusions. Verified via testComparisonFramePolicyTracksTheDerivedBaseline and existing white-balance tests.
    - criterion: Single-image view and Space-hold comparison still show the mask overlay on the one visible surface
      result: pass
      notes: "Line 160 canvasSurface call (used by both single-image and Space-hold) passes showsMaskOverlay: true; unchanged from prior behavior."
  checks_run:
    - swift build — pass
    - swift test --filter 'ComparisonModeTests|AdjustInspectorTests|PreviewAdmissionCoordinatorTests' — pass, 41 tests, 0 failures
    - swift test --filter 'CoordinatorBoundaryTests' — pass, 7 tests, 0 failures, includes new ComparisonFramePolicy coverage
    - git diff --check — pass
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-25T04:35:37.143Z
  session: 01MUGGUSG68CI641P7
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - comparison
  - masking
  - preview
created: 2026-09-25T01:33:32.931Z
updated: 2026-09-25T04:35:37.145Z
blockers: []
order: a0
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


### Comment — codex @ 2026-09-25T04:34:01.670Z

Implemented and committed as cc692f7. Original now excludes mask overlay chrome; comparison invalidation follows the derived baseline while preserving the Temperature/Tint exception, and retained Original frames survive redundant job eviction/failure. Added regressions for local-mask no-clear/no-baseline-render, crop/rotation/raw baseline changes, and kept preview admission behavior covered. Verified: focused comparison/adjustment/admission suite (41 tests), CoordinatorBoundaryTests (7 tests), swift build, and git diff --check. Overlay call-site review: Original canvasSurface disables MaskCanvasOverlay; Adjusted and single-image canvases enable it.

## Agent log

- 2026-09-25T04:35:37.143Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Side-by-side + masking workspace: mask overlay, guides, brush cursor appear on Adjusted pane only, not Original (pass) — PreviewView.canvasSurface now takes showsMaskOverlay; sideBySideView passes false for the Original panel and true for Adjusted; single-image/Space-hold path still passes true.
- [x] Original pixels stay on comparisonBaseline/originalForComparison; local mask edits (including mask-layer exposure) do not appear in Original (pass) — Original canvasSurface call disables the overlay; originalForComparison already strips localAdjustments.
- [x] Dragging exposure/contrast/Light/Color/Effects/Look/local-mask controls does not clear Original or request a new Original render when originalForComparison is unchanged (pass) — ComparisonFramePolicy.changesBaseline now compares old/new comparisonBaseline (which already excludes localAdjustments, Light, Color, Effects, adjustments, LUT) instead of separately checking localAdjustments. PreviewAdmissionCoordinator's onTerminal eviction path and the failure-retry path both added an admissionHasOriginalPreview guard so a still-valid displayed baseline is not cleared or re-enqueued.
- [x] Crop, rotation, and a raw-develop change that rawDevelopChangesFrame reports still refresh Original (pass) — comparisonBaseline retains crop/rotation/rawDevelop; changesBaseline neutralizes only neutralTemperature/neutralTint before comparing, matching rawDevelopChangesFrame's exclusions. Verified via testComparisonFramePolicyTracksTheDerivedBaseline and existing white-balance tests.
- [x] Single-image view and Space-hold comparison still show the mask overlay on the one visible surface (pass) — Line 160 canvasSurface call (used by both single-image and Space-hold) passes showsMaskOverlay: true; unchanged from prior behavior.
Checks run:
- swift build — pass
- swift test --filter 'ComparisonModeTests|AdjustInspectorTests|PreviewAdmissionCoordinatorTests' — pass, 41 tests, 0 failures
- swift test --filter 'CoordinatorBoundaryTests' — pass, 7 tests, 0 failures, includes new ComparisonFramePolicy coverage
- git diff --check — pass
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUGGUSG68CI641P7
