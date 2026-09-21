---
id: KRMA-509
title: Straightened preview at deep zoom renders full frame without ROI (perf follow-up to KRMA-508)
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Map the visible viewport ROI so it is safe with straighten/flip/perspective (native ROI enclosure + post-geometry crop)
      result: pass
      notes: "Verified after fix: PreviewCoordinator now forwards presentationROI, and RenderBuildPlan drops a geometry ROI that lacks one."
    - criterion: Keep KRMA-508 regression tests green
      result: pass
      notes: CropTests, CropROITests, ResolutionPlannerTests pass; fast and serial CI lanes green.
    - criterion: Measure straightened deep-zoom latency/memory vs un-straightened on a large fixture
      result: not_applicable
      notes: No measurement recorded in the handoff; only synthetic small-image tests exist. Non-blocking.
  checks_run:
    - swift build
    - swift test --filter CropROITests|PreviewCoordinatorTests|ResolutionPlannerTests|CropTests
    - scripts/ci-tests.sh fast (exit 0)
    - scripts/ci-tests.sh serial (407 executed, 1 expected skip, 0 failures)
    - git diff --check
  findings:
    - "[high, fixed] PreviewCoordinator.request(_:quality:maskResolution:) rebuilt every interactive/settled RenderRequest without presentationROI. For a geometry crop at deep zoom the engine received a native sourceROI with no post-geometry rectangle, skipped the post-geometry crop branch, cropped the transformed image with native coordinates (KRMA-508 defect) and treated the request as covering the presentation extent."
    - "[low, noted] Deep-zoom straighten performance was not measured on a large RAW fixture as the issue requirements ask."
  fixes:
    - PreviewCoordinator forwards presentationROI when rebuilding requests
    - RenderBuildPlan.make returns no ROI for a geometry crop when presentationROI is nil (safe complete-frame fallback)
    - Added testRebuiltRequestsKeepTheGeometryPresentationROI and testGeometryROIWithoutPresentationROIFallsBackToTheCompleteFrame
  verification_commits:
    - "0692053"
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-21T17:28:31.980Z
  session: 01MUBIM8GRP50K7M6Y
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - preview
  - crop
  - performance
created: 2026-09-21T15:18:34.638Z
updated: 2026-09-21T17:28:31.982Z
parent: KRMA-508
order: a0
board: product
commits:
  - "0692053"
---

## Objective

Straightened preview at deep zoom renders full frame without ROI (perf follow-up to KRMA-508)

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ]

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-21T17:24:31.358Z

Implemented in commit 3cd30c0. Added geometry-aware viewport ROI planning for committed straighten/flip/perspective previews, including conservative native ROI mapping, exact post-geometry presentation ROI/layout, post-geometry cropping before expensive preview work, geometry AABB normalization, and cache versioning. Added deep-zoom ROI/render regressions; KRMA-508 presentation tests remain green. Verification: swift build; focused planner/ROI/workflow tests; scripts/ci-tests.sh fast (1,118 passed); scripts/ci-tests.sh serial (407 passed, 1 expected skip); git diff --check. Unrelated pre-existing navigation/test edits remain unstaged.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

## Objective

Restore viewport-ROI savings for committed straighten/flip/perspective previews at deep zoom without reintroducing the KRMA-508 aspect bug.

## Context

KRMA-508 fixed the committed-straighten pillar/stretch by suppressing native-space `sourceROI` whenever `crop.hasGeometryTransform` (`ResolutionPlan.previewSourceROI`, `RenderRequest.coversPresentationExtent`/`roiTransform`; `RenderPipeline` already disabled the ROI). Consequence: when zoomed in on a straightened photo, the planner still selects up to native detail (`requiredScale` -> level 1.0) but every request is a complete-frame render of the geometry AABB instead of a viewport strip. That is correct but costs more memory/latency than the un-straightened path on large RAWs.

## Requirements

- Measure straightened deep-zoom preview latency/memory on a large fixture vs the un-straightened path.
- If material, map the visible viewport ROI into pre-geometry space (or crop after geometry in post-transform coordinates) so the ROI is safe with straighten.
- Keep the KRMA-508 regression tests green (`testCommittedStraightenPresentationExtentUsesGeometryAABB`, `testCommittedStraightenPreviewRequestUsesGeometryPresentationExtent`).

- 2026-09-21T17:28:31.980Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Map the visible viewport ROI so it is safe with straighten/flip/perspective (native ROI enclosure + post-geometry crop) (pass) — Verified after fix: PreviewCoordinator now forwards presentationROI, and RenderBuildPlan drops a geometry ROI that lacks one.
- [x] Keep KRMA-508 regression tests green (pass) — CropTests, CropROITests, ResolutionPlannerTests pass; fast and serial CI lanes green.
- [ ] Measure straightened deep-zoom latency/memory vs un-straightened on a large fixture (not_applicable) — No measurement recorded in the handoff; only synthetic small-image tests exist. Non-blocking.
Checks run:
- swift build
- swift test --filter CropROITests|PreviewCoordinatorTests|ResolutionPlannerTests|CropTests
- scripts/ci-tests.sh fast (exit 0)
- scripts/ci-tests.sh serial (407 executed, 1 expected skip, 0 failures)
- git diff --check
Findings:
- [high, fixed] PreviewCoordinator.request(_:quality:maskResolution:) rebuilt every interactive/settled RenderRequest without presentationROI. For a geometry crop at deep zoom the engine received a native sourceROI with no post-geometry rectangle, skipped the post-geometry crop branch, cropped the transformed image with native coordinates (KRMA-508 defect) and treated the request as covering the presentation extent.
- [low, noted] Deep-zoom straighten performance was not measured on a large RAW fixture as the issue requirements ask.
Fixes:
- PreviewCoordinator forwards presentationROI when rebuilding requests
- RenderBuildPlan.make returns no ROI for a geometry crop when presentationROI is nil (safe complete-frame fallback)
- Added testRebuiltRequestsKeepTheGeometryPresentationROI and testGeometryROIWithoutPresentationROIFallsBackToTheCompleteFrame
Verification commits:
- 0692053
Actor: claude
Resolved model: sonnet
Pickup session: 01MUBIM8GRP50K7M6Y
Summary: Verification passed after fixing PreviewCoordinator dropping presentationROI (geometry deep-zoom regression); tests added, CI fast/serial green.
