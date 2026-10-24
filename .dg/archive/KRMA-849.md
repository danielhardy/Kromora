---
id: KRMA-849
title: "Fix smart mask flicker while zooming: ignore render size in semantic warmth"
type: bug
status: done
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Zooming with a warm smart mask produces one resolved render per step and no masks=deferred render.
      result: pass
      notes: Regression test confirms the zoomed request is resolved and no second base frame is admitted.
    - criterion: Adding or editing a smart mask still publishes a base frame while Vision resolves it (existing test).
      result: pass
      notes: PreviewCoordinatorTests.testMaskedPreviewPublishesABaseFrameBeforeTheResolvedOne and PreviewCutoverTests.testAddingASmartMaskPublishesABaseFrameThenRefinesIt passed.
    - criterion: PreviewCoordinatorTests and PreviewCutoverTests pass.
      result: pass
      notes: Both suites passed; PreviewCoordinatorTests executed 16 tests with 1 opt-in benchmark skipped and 0 failures; PreviewCutoverTests executed 17 tests with 0 failures.
  checks_run:
    - swift test --filter PreviewCoordinatorTests — passed (16 tests, 1 opt-in benchmark skipped, 0 failures)
    - swift test --filter PreviewCutoverTests — passed (17 tests, 0 failures)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-10T14:55:34.106Z
  session: 01MV2IMP1Z4OKOCX3S
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:02:25.400Z
updated: 2026-10-10T14:55:34.109Z
blockers: []
order: zh
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-10T13:03:49.626Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 32ecba1eed906791a52029f549d3331172fa220d
---

## Objective

With a smart mask (for example Person) applied and fully rendered, zooming made just the mask area flicker off and on while the rest of the photo rendered steadily.

## Root cause

`PreviewCoordinator` publishes a mask-less base frame (`maskResolution: .deferSemantic`) first, then the resolved frame, unless the semantic masks are "warm". The warm identity (`SemanticWarmth`) included the render `targetSize`, so every zoom step looked cold. A Person layer is dropped whole from the base frame (`allowsDeferredSemanticPreview` is false), so each zoom published a frame without the mask followed by one with it.

## Work done

`Sources/KromoraKit/ViewModels/PreviewCoordinator.swift`: removed `targetSize` from `SemanticWarmth` and updated its doc comment. Warmth is now source, asset, mask recipe and mask quality. Vision output is cached independent of size; a new size only costs a resize of the cached matte, during which the previous frame stays on screen. Added `testZoomingAWarmSmartMaskDoesNotPublishAMasklessBaseFrame` in `PreviewCoordinatorTests`. Confirmed in a dev build with `log stream --signpost`: zoom renders no longer carry `masks=deferred`.

## Known remaining risk

Mask quality stays in the identity, so the preview→full-resolution settle after a zoom can still be two-phase. If a flicker remains at settle, a separate ticket should keep the previous mask in the base frame rather than dropping the layer.

## Acceptance criteria

- Zooming with a warm smart mask produces one resolved render per step and no `masks=deferred` render.
- Adding or editing a smart mask still publishes a base frame while Vision resolves it (existing test).
- PreviewCoordinatorTests and PreviewCutoverTests pass.


### Comment — claude @ 2026-10-10T13:03:49.138Z

Implemented in 32ecba1e with regression test testZoomingAWarmSmartMaskDoesNotPublishAMasklessBaseFrame; PreviewCoordinatorTests and PreviewCutoverTests pass. Dev-build signpost capture showed zoom renders without masks=deferred. Known risk: the preview-to-full-resolution settle can still be two-phase (see ticket).


### Comment — claude @ 2026-10-10T13:11:12.645Z

Verifier note: implementation commit(s) 32ecba1e are now recorded in the ticket's commits field. Review with: git show 32ecba1e. Verifier is codex (verification_agent). Acceptance criteria and known gaps are in the ticket body.

## Agent log

- 2026-10-10T14:55:34.106Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Zooming with a warm smart mask produces one resolved render per step and no masks=deferred render. (pass) — Regression test confirms the zoomed request is resolved and no second base frame is admitted.
- [x] Adding or editing a smart mask still publishes a base frame while Vision resolves it (existing test). (pass) — PreviewCoordinatorTests.testMaskedPreviewPublishesABaseFrameBeforeTheResolvedOne and PreviewCutoverTests.testAddingASmartMaskPublishesABaseFrameThenRefinesIt passed.
- [x] PreviewCoordinatorTests and PreviewCutoverTests pass. (pass) — Both suites passed; PreviewCoordinatorTests executed 16 tests with 1 opt-in benchmark skipped and 0 failures; PreviewCutoverTests executed 17 tests with 0 failures.
Checks run:
- swift test --filter PreviewCoordinatorTests — passed (16 tests, 1 opt-in benchmark skipped, 0 failures)
- swift test --filter PreviewCutoverTests — passed (17 tests, 0 failures)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: unknown
Pickup session: 01MV2IMP1Z4OKOCX3S
Summary: Verification passed: warm smart-mask zoom stays single-phase; required preview suites passed.
