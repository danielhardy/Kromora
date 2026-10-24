---
id: KRMA-668
title: Verify Remove engine timings meet targets and run KRMA-658 corpus through the render engine
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Either get swift test -c release linking again on the current Xcode/SDK (if that is a quick, unrelated toolchain fix) or find another way to measure optimized Remove solve timings in the running engine, and record real optimized dust-spot and 3000 px-wire cache-miss/cache-hit numbers in docs/RETOUCH.md against KRMA-665's stated targets. If targets still are not met once measured optimized, say so plainly rather than leaving only debug numbers in the doc.
      result: pass
      notes: Remove was retired and its solver/render path deleted by 04100fa; optimized Remove timings are no longer applicable.
    - criterion: Add a render-engine-level variant of the KRMA-658 ground-truth corpus (or a representative subset) that drives Remove spots through RenderEngine/RetouchRenderer (the real field-sampling kernel and membrane composite), not the standalone PatchMatchInpainter.solve + test-local composite path that testPatchMatchRemoveQualityAcrossGroundTruthCorpus uses today. Report any rows where the engine path disagrees with the standalone-solver path, since that gap is the specific defect this check exists to catch.
      result: pass
      notes: Remove spots and the engine path were removed; this verification is superseded by the product retirement.
    - criterion: Update docs/RETOUCH.md to reflect whatever is actually measured/verified once this lands.
      result: pass
      notes: docs/RETOUCH.md now documents supported Heal/Clone behavior and no longer claims a Remove engine path.
  checks_run:
    - Reviewed retirement commit 04100fa and its source, test, and documentation changes
    - swift build (pass)
    - Focused retouch model/workflow tests (pass in 130-test run)
    - git diff --check (pass)
  findings: []
  fixes: []
  verification_commits:
    - 04100fa
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T14:42:42.866Z
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - retouch
  - remove-heal-clone
created: 2026-09-27T22:52:07.331Z
updated: 2026-09-28T14:42:42.868Z
parent: KRMA-665
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Models/RenderEngine.swift
    - Sources/KromoraKit/Models/RetouchRenderer.swift
    - Tests/KromoraKitTests/RetouchEnginePerformanceTests.swift
    - Tests/KromoraKitTests/RetouchQualityEvaluationTests.swift
  docs:
    - docs/RETOUCH.md
  issues:
    - KRMA-658
    - KRMA-665
  commands:
    - swift test --filter 'RetouchFill|RenderPipeline|Retouch'
    - KROMORA_RUN_RETOUCH_ENGINE_BENCHMARK=1 swift test --filter RetouchEnginePerformanceTests
commits:
  - 04100fa
---

## Objective

Close two disclosed, non-blocking gaps left open by KRMA-665's Remove engine integration: engine-level
solve timings that miss the documented targets, and a KRMA-658 quality corpus test that still exercises
the standalone `PatchMatchInpainter` solver rather than the full render-engine pipeline.

## Context

KRMA-665 wired `PatchMatchInpainter` into `RenderEngine.resolveRemoveFills`, added a field cache, and
made preview/export share one solved field. Its own verification (this ticket's parent) confirmed the
integration is correct and covered by `testRemoveFillUsesOneFullResolutionFieldForPreviewAndExport`
(cache hit/miss, invalidation, preview/export parity), but two AC-adjacent items were left open and
documented rather than resolved:

1. `docs/RETOUCH.md`'s "Engine timing capture" section records debug-build measurements far above
   KRMA-665's stated targets (dust spot < 50 ms solve, 3000 px wire < 400 ms solve): a 60 px dust spot
   measured ~972 ms solver / ~1,213 ms total, and a 3,000 px wire measured ~12,711 ms solver / ~13,686 ms
   total, both roughly 20-30x over target. The doc attributes this to unoptimized debug execution and
   notes that `swift test -c release --filter RetouchEnginePerformanceTests` cannot link on the current
   Xcode beta SDK because `SwiftUICore` opaque symbols are unavailable to the XCTest bundle, so optimized
   engine timings have never actually been measured.
2. `RetouchQualityEvaluationTests.testPatchMatchRemoveQualityAcrossGroundTruthCorpus` calls
   `PatchMatchInpainter.solve` directly and composites the result with a test-local `compositeRemove`
   helper — it does not go through `RenderEngine.resolveRemoveFills`, the `retouchSampleField` kernel, or
   `RetouchRenderer`'s membrane composite. KRMA-665's own implementation notes call out that running the
   KRMA-658 harness end-to-end through the render engine (not only through the standalone solver) is
   exactly the check that would localize a defect to "extraction, field sampling, membrane, or
   composition" as opposed to the solver itself. That end-to-end version does not exist yet.

## Acceptance criteria

- [ ] Either get `swift test -c release` linking again on the current Xcode/SDK (if that is a quick,
      unrelated toolchain fix) or find another way to measure optimized Remove solve timings in the
      running engine, and record real optimized dust-spot and 3000 px-wire cache-miss/cache-hit numbers
      in `docs/RETOUCH.md` against KRMA-665's stated targets. If targets still aren't met once measured
      optimized, say so plainly rather than leaving only debug numbers in the doc.
- [ ] Add a render-engine-level variant of the KRMA-658 ground-truth corpus (or a representative subset)
      that drives Remove spots through `RenderEngine`/`RetouchRenderer` (the real field-sampling kernel
      and membrane composite), not the standalone `PatchMatchInpainter.solve` + test-local composite path
      that `testPatchMatchRemoveQualityAcrossGroundTruthCorpus` uses today. Report any rows where the
      engine path disagrees with the standalone-solver path, since that gap is the specific defect this
      check exists to catch.
- [ ] Update `docs/RETOUCH.md` to reflect whatever is actually measured/verified once this lands.

## Implementation notes

Non-blocking: KRMA-665 shipped a working, tested Remove integration (cache correctness, preview/export
parity, cancellation, default mode) independent of these two items, which are specifically about timing
verification depth and test-coverage depth. Do not change solver internals here per KRMA-662/KRMA-665's
existing scoping; if the engine-path corpus run turns up a real quality regression versus the standalone
solver, file that as a further child issue against the appropriate area rather than fixing it inline.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-28T14:42:42.866Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Either get swift test -c release linking again on the current Xcode/SDK (if that is a quick, unrelated toolchain fix) or find another way to measure optimized Remove solve timings in the running engine, and record real optimized dust-spot and 3000 px-wire cache-miss/cache-hit numbers in docs/RETOUCH.md against KRMA-665's stated targets. If targets still are not met once measured optimized, say so plainly rather than leaving only debug numbers in the doc. (pass) — Remove was retired and its solver/render path deleted by 04100fa; optimized Remove timings are no longer applicable.
- [x] Add a render-engine-level variant of the KRMA-658 ground-truth corpus (or a representative subset) that drives Remove spots through RenderEngine/RetouchRenderer (the real field-sampling kernel and membrane composite), not the standalone PatchMatchInpainter.solve + test-local composite path that testPatchMatchRemoveQualityAcrossGroundTruthCorpus uses today. Report any rows where the engine path disagrees with the standalone-solver path, since that gap is the specific defect this check exists to catch. (pass) — Remove spots and the engine path were removed; this verification is superseded by the product retirement.
- [x] Update docs/RETOUCH.md to reflect whatever is actually measured/verified once this lands. (pass) — docs/RETOUCH.md now documents supported Heal/Clone behavior and no longer claims a Remove engine path.
Checks run:
- Reviewed retirement commit 04100fa and its source, test, and documentation changes
- swift build (pass)
- Focused retouch model/workflow tests (pass in 130-test run)
- git diff --check (pass)
Findings:
- None
Fixes:
- None
Verification commits:
- 04100fa
Actor: codex
Resolved model: unknown
Summary: Closed as superseded by KRMA-681: the Remove render-engine path was deleted, so Remove-specific optimized timing and engine-corpus verification no longer apply; the supported retouch workflow and docs are tracked by KRMA-681.
