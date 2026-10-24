---
id: KRMA-859
title: Characterize and fix possible smart mask dropout when settling to full resolution after zoom
type: bug
status: done
priority: low
agent: codex
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A characterization test verifies no mask-less publication while settling a warm Person mask to full resolution.
      result: pass
      notes: testSettlingWarmSmartMaskToFullResolutionDoesNotPublishAMasklessFrame checks the request policy and all publications across interactive-to-settled transition.
    - criterion: The reproduced dropout is fixed without reintroducing the KRMA-849 zoom flicker.
      result: pass
      notes: Semantic warmth persists across mask quality changes; the settled request publishes resolved masks without an intermediate deferred base frame. Existing warm zoom regression passes.
    - criterion: KRMA-849 zoom guard and cold-start two-phase mask behavior pass.
      result: pass
      notes: Covered in PreviewCoordinatorTests and PreviewCutoverTests.
  checks_run:
    - "swift test --filter PreviewCoordinatorTests — passed: 17 tests, 1 opt-in benchmark skipped, 0 failures"
    - "swift test --filter PreviewCutoverTests — passed: 17 tests, 0 failures"
  findings: []
  fixes: []
  verification_commits:
    - f75e4e9947572eb5d6263868fbadb9ab2c398bd5
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T17:57:28.932Z
  session: 01MV44KDGPH0C7UH5P
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:08:36.761Z
updated: 2026-10-24T13:04:46.571Z
blockers: []
order: zq
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T17:45:38.010Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - f75e4e9947572eb5d6263868fbadb9ab2c398bd5
---

## Objective

KRMA-849 stops zoom from publishing a mask-less base frame while the smart mask is warm. A flicker can remain at settle: `SemanticWarmth` still includes `maskQuality`, and the settled full-resolution render uses render-quality masks (`RenderQuality.maskQuality` maps fullResolution/export to `.render`), so the first settled render after a preview-quality session is still two-phase and drops a Person layer from the base frame (`LocalAdjustmentLayer.allowsDeferredSemanticPreview` is false).

## Work

1. Characterize: add a `PreviewCoordinatorTests` case that submits an interactive then a settled/full-resolution request for a warm Person mask and records whether a `.deferSemantic` frame is published. Capture it with `log stream --signpost --predicate 'subsystem == "com.kromora.app" AND category == "workflow"'` on a real photo, expecting `masks=deferred` on the settle.
2. Decide and implement a fix if the characterisation shows a visible dropout, for example keep the last published mask-bearing frame until the refined frame lands, or let the base frame reuse the cached preview-quality mask instead of dropping the layer. Do not reintroduce the original flicker (KRMA-849 test must still pass).

## Acceptance criteria

1. The characterisation test exists and states the intended behavior (no frame without the smart mask between a settled render and its predecessor).
2. If the characterisation fails, the fix makes it pass; otherwise the ticket records measured evidence (signpost capture) that no dropout occurs and closes with the test as a guard.
3. KRMA-849's zoom test and the existing two-phase cold-start test (new/edited smart mask still publishes a base frame) pass.

Depends on KRMA-849. Display-bound benchmarks are not required (CLAUDE.md); use the log capture only as supporting evidence.


### Comment — codex @ 2026-10-11T17:45:36.290Z

Implemented and committed as f75e4e99. Semantic warmth now survives mask-quality changes, so settling to full resolution keeps the last mask-bearing frame visible while the refined matte renders. Added a Person-mask regression test; it reproduced a deferred base publication before the fix and now passes. Verification: PreviewCoordinatorTests (17 tests, 1 opt-in benchmark skipped) and PreviewCutoverTests (17 tests) pass, including the KRMA-849 zoom guard and cold-start two-phase coverage. The requested real-photo log stream capture was not obtained because the development app launched without an accessible window; the controlled test directly characterized the dropout.

## Agent log

- 2026-10-11T17:57:28.932Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A characterization test verifies no mask-less publication while settling a warm Person mask to full resolution. (pass) — testSettlingWarmSmartMaskToFullResolutionDoesNotPublishAMasklessFrame checks the request policy and all publications across interactive-to-settled transition.
- [x] The reproduced dropout is fixed without reintroducing the KRMA-849 zoom flicker. (pass) — Semantic warmth persists across mask quality changes; the settled request publishes resolved masks without an intermediate deferred base frame. Existing warm zoom regression passes.
- [x] KRMA-849 zoom guard and cold-start two-phase mask behavior pass. (pass) — Covered in PreviewCoordinatorTests and PreviewCutoverTests.
Checks run:
- swift test --filter PreviewCoordinatorTests — passed: 17 tests, 1 opt-in benchmark skipped, 0 failures
- swift test --filter PreviewCutoverTests — passed: 17 tests, 0 failures
Findings:
- None
Fixes:
- None
Verification commits:
- f75e4e9947572eb5d6263868fbadb9ab2c398bd5
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV44KDGPH0C7UH5P
Summary: Independent verification passed: warm smart masks remain published across full-resolution settling; focused coordinator and cutover suites pass.
