---
id: KRMA-585
title: "KRMA-573 verification follow-up: add Subject/Background regression coverage and coarse-matte diagnostics"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Add a Subject shape test asserting non-rectangular segmented shape survives selection (rectangle-fill must fail)
      result: pass
      notes: testSubjectSelectionKeepsNonRectangularSegmentedInstanceShape exercises the new internal-for-testing VisionSemanticMaskProvider.selectSubjectPixels seam with a plus-shaped mask and asserts the returned pixels retain the non-rectangular contour (values[0] == 0).
    - criterion: Add a Background complement test with partial (non-empty, non-full-frame) Foreground on Foreground's coordinate space
      result: pass
      notes: testPartialForegroundBackgroundIsPixelComplementOnAnalysisGrid seeds a single-pixel partial foreground into MaskStore, then asserts background pixels equal 1 - foreground pixels on the same analysis-grid size.
    - criterion: "Record coarse-result diagnostics: source/analysis width, height, aspect ratio; raw instanceMask/provider buffer width/height; generated scaled-mask width/height; selected instance IDs; foreground/subject coverage percentage"
      result: pass
      notes: recordMatteDiagnostics logs all required fields via the existing Logger/os_log mechanism using the project's established 'com.kromora.app' subsystem convention (matches Observability.swift), without swallowing generateScaledMaskForImage failures or reintroducing a synthetic fallback shape.
  checks_run:
    - swift build — pass
    - swift test --filter 'VisionSemanticMaskProviderTests|PhotoAnalysis|MaskingWorkflow|LocalMask' — pass (99 executed, 0 failures, 9 opt-in benchmark skips)
    - git diff --check — pass
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-25T06:29:49.219Z
  session: 01MUGKXPCS6TQEWJKE
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - masking
  - vision
created: 2026-09-25T04:42:22.697Z
updated: 2026-09-25T06:29:49.221Z
blockers: []
order: a0
board: product
---

## Objective

KRMA-573 (commit dd0e599) fixed Subject/Foreground mattes to use
`VNInstanceMaskObservation.generateScaledMaskForImage(forInstances:from:)` instead of a filled
saliency bounding box / raw provider-resolution instance mask, and this passed verification: build,
the focused test filter, and `git diff --check` all pass, and manual code review of
`VisionSemanticMaskProvider.swift` confirms the implementation matches the ticket's intended
pipeline (saliency selects an instance, Person is preferred when it overlaps, Background stays the
complement of Foreground).

Two things the ticket explicitly asked for are still missing:

1. **Test coverage.** `VisionSemanticMaskProviderTests.swift` was only updated to rename/adjust the
   pre-existing provider-resolution union regression
   (`testForegroundUnionNormalizesDifferingInstanceResolutionsToAnalysisImage`). The ticket's "Tests"
   section also asked for:
   - A **Subject shape test**: a fixture where the selected foreground instance is visibly
     non-rectangular, asserting Subject contains the segmented shape rather than the filled saliency
     box (a rectangle-fill result must fail this test).
   - A **Background complement test** with a *partial* (non-empty, non-full-frame) Foreground,
     asserting Background is the pixel complement and shares Foreground's coordinate space.
     `testNoForegroundIsEmptyAndBackgroundIsItsComplementThroughCoordinator` only covers the
     empty-foreground case.

   Existing tests bypass live Vision saliency/segmentation inference by using flat solid-color
   fixtures (Vision detects nothing) or by seeding `MaskStore` directly under
   `.foregroundInstance(0)` so `foregroundMasks`/`foregroundUnionMask` hit the cache instead of
   calling Vision. `subjectMask` is `private` and still calls `VNGenerateAttentionBasedSaliencyImageRequest`
   against the real image even when the foreground instance is cache-seeded, so a deterministic,
   non-flaky non-rectangular-subject test needs either a real photo fixture Vision reliably segments,
   or a small testability seam (e.g. exposing subject selection as an internal method that accepts a
   pre-supplied salient rect, the way `foregroundUnionMask` is already internal for its own
   regression test).

2. **Coarse-result diagnostics.** The ticket's "Failure handling / diagnostics" section asked that,
   when a real photo's scaled foreground instance still produces a coarse/box-like result, the
   handoff/debug output records: source/analysis width, height, and aspect ratio; raw
   `instanceMask`/provider-resolution buffer width/height; generated scaled-mask width/height;
   selected instance IDs; foreground coverage percentage; and subject coverage percentage. No such
   diagnostic recording exists in `VisionSemanticMaskProvider.swift` today (the signpost interval
   only carries `sourceToken` and `quality`).

Neither gap is a functional regression — the production matte-generation logic reviewed correctly
against the ticket's intent, and the required checks (`swift build`, the focused test filter,
`git diff --check`) all pass — so KRMA-573 was completed rather than blocked. This ticket tracks
closing the coverage/diagnostics gap as a fast follow.

## What to implement

- Add the Subject shape test and the partial-Foreground Background complement test described above,
  using whatever seam is least invasive (prefer a small internal-for-testing hook over widening
  `subjectMask` broadly).
- Add the diagnostic fields listed in KRMA-573's "Failure handling / diagnostics" section, recorded
  through the existing signpost/trace-context mechanism or an equivalent debug hook, without
  swallowing a `generateScaledMaskForImage` failure or reintroducing a synthetic fallback shape.

## Context

- files:
  - Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift
  - Tests/KromoraKitTests/VisionSemanticMaskProviderTests.swift
- issues: KRMA-573
- commands:
  - swift build
  - swift test --filter 'VisionSemanticMaskProviderTests|PhotoAnalysis|MaskingWorkflow|LocalMask'
  - git diff --check


### Comment — codex @ 2026-09-25T06:28:18.002Z

Implemented and committed as e72d07c. Added deterministic non-rectangular Subject selection coverage and a partial Foreground/Background pixel-complement test on the analysis grid. Added vision-matte debug diagnostics for source/analysis size and aspect, provider and generated mask size, instance IDs, selected instance ordinal, and foreground/subject coverage. Verification: swift build; swift test --filter 'VisionSemanticMaskProviderTests|PhotoAnalysis|MaskingWorkflow|LocalMask' (99 executed, 0 failures, 9 opt-in skips); git diff --check. Findings: none.

## Agent log

- 2026-09-25T06:29:49.219Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Add a Subject shape test asserting non-rectangular segmented shape survives selection (rectangle-fill must fail) (pass) — testSubjectSelectionKeepsNonRectangularSegmentedInstanceShape exercises the new internal-for-testing VisionSemanticMaskProvider.selectSubjectPixels seam with a plus-shaped mask and asserts the returned pixels retain the non-rectangular contour (values[0] == 0).
- [x] Add a Background complement test with partial (non-empty, non-full-frame) Foreground on Foreground's coordinate space (pass) — testPartialForegroundBackgroundIsPixelComplementOnAnalysisGrid seeds a single-pixel partial foreground into MaskStore, then asserts background pixels equal 1 - foreground pixels on the same analysis-grid size.
- [x] Record coarse-result diagnostics: source/analysis width, height, aspect ratio; raw instanceMask/provider buffer width/height; generated scaled-mask width/height; selected instance IDs; foreground/subject coverage percentage (pass) — recordMatteDiagnostics logs all required fields via the existing Logger/os_log mechanism using the project's established 'com.kromora.app' subsystem convention (matches Observability.swift), without swallowing generateScaledMaskForImage failures or reintroducing a synthetic fallback shape.
Checks run:
- swift build — pass
- swift test --filter 'VisionSemanticMaskProviderTests|PhotoAnalysis|MaskingWorkflow|LocalMask' — pass (99 executed, 0 failures, 9 opt-in benchmark skips)
- git diff --check — pass
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUGKXPCS6TQEWJKE
Summary: Verified KRMA-573 follow-up: new Subject shape and partial-Foreground/Background complement tests plus vision-matte diagnostics all pass build, focused test filter (99 tests, 0 failures), and git diff --check. No fixes needed.
