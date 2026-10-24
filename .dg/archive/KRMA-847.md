---
id: KRMA-847
title: "Fix Soften edges breaking smart masks: replace O(r²) feather blur with separable running sum"
type: bug
status: done
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Dragging Soften edges on a smart mask after other edits keeps the mask applied and its overlay visible.
      result: pass
      notes: The feather implementation now has radius-independent linear work and cancellation checks; LocalMaskRenderingTests regression coverage for semantic rendering and overlays passed. No interactive UI drag was performed.
    - criterion: Existing mask tests (MaskRefinementTests, RegionMaskTests, LocalMaskRenderingTests, MaskResamplingPerformanceTests) pass.
      result: pass
      notes: All four suites passed; two environment-gated benchmark cases skipped as expected.
    - criterion: Pin feather output against an edge-clipped reference and cover cancellation.
      result: pass
      notes: Added reference comparisons for radii 1, 2, and 7 on a 5x3 mask, plus a deterministic self-cancelled task check.
  checks_run:
    - "swift test --filter MaskRefinementTests|RegionMaskTests|LocalMaskRenderingTests|MaskResamplingPerformanceTests — passed: 61 tests, 0 failures; 2 opt-in benchmarks skipped"
    - git diff --check — passed
  findings: []
  fixes:
    - Added a naive clipped-window reference test to pin feather values and coverage across edge and oversized-radius cases.
    - Added a direct cancellation test for MaskOperations.feather.
  verification_commits:
    - 6b2e74a4
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-10T14:53:53.207Z
  session: 01MV2IK1C8CVCL6ON4
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:02:23.644Z
updated: 2026-10-10T14:53:53.211Z
blockers: []
order: y
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-10T13:03:47.862Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - c2fae21dd9c7315c2d1bf131793ee02a9d1abfa9
  - 6b2e74a4
---

## Objective

Adjusting a smart mask's "Soften edges" slider (for example on a Person mask after exposure edits) could leave the mask broken: it stopped applying to the photo and its overlay disappeared.

## Root cause

`MaskOperations.feather` was a naive box blur that re-summed the whole (2r+1)² window for every pixel, O(pixels × r²). The radius scales with mask size and the slider, so at large targets it ran effectively forever and was not cancellable; slider ticks stacked more of it.

## Work done

Replaced it with a separable running-sum box blur in `Sources/KromoraKit/Models/PhotoAnalysis/MaskOperations.swift`. It averages over the same edge-clipped window with the same in-bounds count, so output matches, but cost is O(pixels) regardless of radius. It checks `Task.checkCancellation()` every 64 rows in both passes so a dragged slider can abandon stale work. Accumulation is in Double.

## Acceptance criteria

- Dragging Soften edges on a smart mask after other edits keeps the mask applied and its overlay visible.
- Existing mask tests (MaskRefinementTests, RegionMaskTests, LocalMaskRenderingTests, MaskResamplingPerformanceTests) pass.
- Not yet done: a unit test pinning feather output against a reference implementation for an edge-clipped window, and a cancellation test. Verifier may add these as a localized safe fix.


### Comment — claude @ 2026-10-10T13:03:47.374Z

Implemented in c2fae21d. Separable running-sum feather; mask tests pass (MaskRefinement, RegionMask, LocalMaskRendering, MaskResamplingPerformance). No new unit test pins output against a reference or covers cancellation; add one if you can do it as a localized fix.


### Comment — claude @ 2026-10-10T13:11:12.170Z

Verifier note: implementation commit(s) c2fae21d are now recorded in the ticket's commits field. Review with: git show c2fae21d. Verifier is codex (verification_agent). Acceptance criteria and known gaps are in the ticket body.

## Agent log

- 2026-10-10T14:53:53.207Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Dragging Soften edges on a smart mask after other edits keeps the mask applied and its overlay visible. (pass) — The feather implementation now has radius-independent linear work and cancellation checks; LocalMaskRenderingTests regression coverage for semantic rendering and overlays passed. No interactive UI drag was performed.
- [x] Existing mask tests (MaskRefinementTests, RegionMaskTests, LocalMaskRenderingTests, MaskResamplingPerformanceTests) pass. (pass) — All four suites passed; two environment-gated benchmark cases skipped as expected.
- [x] Pin feather output against an edge-clipped reference and cover cancellation. (pass) — Added reference comparisons for radii 1, 2, and 7 on a 5x3 mask, plus a deterministic self-cancelled task check.
Checks run:
- swift test --filter MaskRefinementTests|RegionMaskTests|LocalMaskRenderingTests|MaskResamplingPerformanceTests — passed: 61 tests, 0 failures; 2 opt-in benchmarks skipped
- git diff --check — passed
Findings:
- None
Fixes:
- Added a naive clipped-window reference test to pin feather values and coverage across edge and oversized-radius cases.
- Added a direct cancellation test for MaskOperations.feather.
Verification commits:
- 6b2e74a4
Actor: codex
Resolved model: unknown
Pickup session: 01MV2IK1C8CVCL6ON4
Summary: Verified separable feather output and cancellation; targeted mask suites pass.
