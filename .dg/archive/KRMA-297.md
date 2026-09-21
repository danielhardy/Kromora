---
id: KRMA-297
title: Verify single-view performance gains and lock in regression tests
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Before/after numbers recorded for identity, edited, and masked single-view opens.
      result: pass
      notes: "Issue comment records the pre-change admission contract and current three-sample deterministic rerun: identity 1/0/0/6.95 ms, edited 1/1/0/25.61 ms, masked 2/1/1/6.80 ms (preview/thumbnails/mask-resolution admissions/first-visible median)."
    - criterion: Edited opens admit one settled preview and slider bursts avoid mid-gesture thumbnails.
      result: pass
      notes: SingleViewLatencyBenchmark asserts one edited preview; ThumbnailSwitchLifecycleTests assert zero interaction thumbnails and one trailing render after a ten-tick burst.
    - criterion: Masked first pixels are bounded by a base render plus refinement, with no global-only Vision re-resolution.
      result: pass
      notes: Benchmark asserts [deferSemantic, resolved] and exactly one semantic-mask resolution admission; LocalMaskRenderingTests.testGlobalOnlyEditHitsTheResolvedSemanticMaskCacheWithoutCallingProviderAgain passes.
    - criterion: Stored-document prefetch remains correct.
      result: pass
      notes: FilmstripNavigationTests.testAdjacentPrefetchUsesStoredEditsForNeverOpenedNeighbor passes and verifies the prefetched request carries the stored document.
    - criterion: Regression suite is deterministic and CI-friendly.
      result: pass
      notes: FakeRenderEngine admission counts and cache/provider assertions contain no timing thresholds; waits are only for state/event settlement.
  checks_run:
    - swift test --filter SingleViewLatencyBenchmark/testSingleViewOpenBaselineReportsIdentityEditedAndMaskedShapes — 1 passed
    - swift test --filter FilmstripNavigationTests — 5 passed
    - swift test --filter ThumbnailSwitchLifecycleTests — 9 passed
    - swift test --filter LocalMaskRenderingTests — 31 executed, 30 passed, 1 designed opt-in skip
    - swift test --filter RenderEngineTests — 29 executed, 26 passed, 3 environment-dependent RAW skips
    - scripts/ci-tests.sh fast — 652 required tests reached with no failures
    - dg validate — OK
    - git diff --check — clean
  findings:
    - Real-engine timing benchmark remains opt-in because GPU, Vision, OS, and power-state variance make a universal timing threshold flaky.
    - dg validate reports pre-existing warnings for the unknown pickup-runner model and low context completeness on LUMO-297/LUMO-298.
  fixes: []
  verification_commits:
    - 3a58f5c
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T01:54:59.218Z
  session: 01MTTFU840YANYD3JJ
labels:
  - performance
  - preview
  - verification
created: 2026-09-08T23:48:32.185Z
updated: 2026-09-10T12:53:54.479Z
depends_on:
  - KRMA-291
  - KRMA-292
  - KRMA-293
  - KRMA-294
  - KRMA-295
  - KRMA-296
order: zx
board: product
commits:
  - 3a58f5c
---

## Objective

Prove the epic's gains with numbers and lock them in with regression tests.

## Context

Parent: KRMA-289. Depends on all Stage 1-3 tickets. Uses the KRMA-290 harness.

## Plan

- Re-run the KRMA-290 benchmark on the same fixtures: report open-to-presented latency and per-open submission counts (previews, thumbnails, mask resolutions) for identity/edited/masked photos, before vs after.
- Assert the structural properties in CI-friendly deterministic tests (FakeRenderEngine submission counting, cache-hit assertions): one preview per edited open; <=1 trailing thumbnail per burst; no Vision re-resolution on global-only edits; prefetch renders stored docs.
- File follow-ups for anything the numbers show is still hot (feeds KRMA-058).

## Acceptance

- Before/after numbers recorded on this ticket; targets: edited open submits 1 settled preview (was 2); slider bursts submit 0 thumbnails mid-gesture; masked first-pixels bounded by base render + refinement.
- Deterministic regression tests in the suite; no timing-flaky assertions.


### Comment — codex @ 2026-09-09T01:54:40.206Z

Implemented in commit 3a58f5c. The KRMA-290 harness now reports semantic-mask resolution admissions and asserts the masked preview phase order [deferSemantic, resolved]. Existing deterministic coverage also locks one edited-open preview, zero thumbnails during a slider gesture with one trailing thumbnail, global-only mask cache reuse, and stored-edit-aware prefetch.

Before/after admission results:
- Edited open: 2 settled preview submissions before KRMA-291 -> 1 now.
- Ten-tick slider burst: thumbnail admission on each tick before KRMA-292 -> 0 during the gesture and 1 trailing render now.
- Masked open: first pixels previously waited for resolved-mask work -> 1 immediate deferred base plus 1 resolved refinement now; exactly 1 semantic-mask resolution admission.

Current deterministic rerun (three samples; fake-renderer timing is diagnostic): identity 1 preview / 0 thumbnails / 0 mask resolutions / 6.95 ms median first visible; edited 1 / 1 / 0 / 25.61 ms; masked 2 / 1 / 1 / 6.80 ms. The earlier KRMA-290 run recorded 7.32 / 42.06 / 8.03 ms for identity / edited / masked, respectively; GPU timing remains opt-in and is not threshold-asserted.

## Agent log

- 2026-09-09T01:54:59.220Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Before/after numbers recorded for identity, edited, and masked single-view opens. (pass) — Issue comment records the pre-change admission contract and current three-sample deterministic rerun: identity 1/0/0/6.95 ms, edited 1/1/0/25.61 ms, masked 2/1/1/6.80 ms (preview/thumbnails/mask-resolution admissions/first-visible median).
- [x] Edited opens admit one settled preview and slider bursts avoid mid-gesture thumbnails. (pass) — SingleViewLatencyBenchmark asserts one edited preview; ThumbnailSwitchLifecycleTests assert zero interaction thumbnails and one trailing render after a ten-tick burst.
- [x] Masked first pixels are bounded by a base render plus refinement, with no global-only Vision re-resolution. (pass) — Benchmark asserts [deferSemantic, resolved] and exactly one semantic-mask resolution admission; LocalMaskRenderingTests.testGlobalOnlyEditHitsTheResolvedSemanticMaskCacheWithoutCallingProviderAgain passes.
- [x] Stored-document prefetch remains correct. (pass) — FilmstripNavigationTests.testAdjacentPrefetchUsesStoredEditsForNeverOpenedNeighbor passes and verifies the prefetched request carries the stored document.
- [x] Regression suite is deterministic and CI-friendly. (pass) — FakeRenderEngine admission counts and cache/provider assertions contain no timing thresholds; waits are only for state/event settlement.
Checks run:
- swift test --filter SingleViewLatencyBenchmark/testSingleViewOpenBaselineReportsIdentityEditedAndMaskedShapes — 1 passed
- swift test --filter FilmstripNavigationTests — 5 passed
- swift test --filter ThumbnailSwitchLifecycleTests — 9 passed
- swift test --filter LocalMaskRenderingTests — 31 executed, 30 passed, 1 designed opt-in skip
- swift test --filter RenderEngineTests — 29 executed, 26 passed, 3 environment-dependent RAW skips
- scripts/ci-tests.sh fast — 652 required tests reached with no failures
- dg validate — OK
- git diff --check — clean
Findings:
- Real-engine timing benchmark remains opt-in because GPU, Vision, OS, and power-state variance make a universal timing threshold flaky.
- dg validate reports pre-existing warnings for the unknown pickup-runner model and low context completeness on KRMA-297/KRMA-298.
Fixes:
- None
Verification commits:
- 3a58f5c
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTTFU840YANYD3JJ
Summary: Measured the single-view gains and locked deterministic preview, thumbnail, mask-resolution, cache-reuse, and stored-edit-prefetch regressions.
