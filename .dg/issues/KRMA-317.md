---
id: KRMA-317
title: "PreviewCutoverTests: speculative-then-corrective preview coalesces into one stored-document render"
type: bug
status: done
priority: high
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings:
    - "HIGH correctness/performance: submitCorrective abandoned the speculative predecessor's job ID without ever reclaiming it from the scheduler, so it could occupy the single editor-lane slot indefinitely and block all subsequent editor-lane work (including the next photo open) if the caller navigated away or edited before the predecessor finished. Reproduced by gating FakeRenderEngine previews: after navigating to a second photo while the first (orphaned) speculative render was still parked, the second photo's preview never reached the engine until the orphan was manually released. Fixed in commit 65290e1ee6d373a232d624080715ffb48240d590 by adding PreviewCoordinator.abandonedSettledJobIDs, which admit() populates when it opts out of preemption and cancelSettledJob() drains on the next cancellation or preemptive submit. Covered by new regression test testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto."
  fixes: []
  verification_commits:
    - 65290e1ee6d373a232d624080715ffb48240d590
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-09T15:00:39.389Z
  session: 01MTU7E8PPGJLUFWCK
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-09T13:25:35.983Z
updated: 2026-09-10T12:53:56.191Z
parent: KRMA-316
order: a0
board: product
commits:
  - 65290e1ee6d373a232d624080715ffb48240d590
---

## Objective

Fix (or correct the test for) the KRMA-308 "speculate-then-correct" preview flow: `PreviewCutoverTests.testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument` fails deterministically on `main` as of commit `b01de9d`.

## Context

**Why:** KRMA-308 (`b01de9d`) renamed `testOpeningStoredEditsSubmitsOnePreviewWithTheStoredDocument` to `testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument` and changed its expectations: opening a photo with stored edits should now (1) speculatively render the identity `EditDocument()` immediately, then (2) submit a corrective render once the stored document loads from disk, i.e. 2 preview requests. `AppViewModel.prepareAndInstall`/`adoptStoredEdits` (`Sources/LumoKit/ViewModels/AppViewModel.swift` ~1379-1452) was changed to implement this, calling `schedulePreview()` once before `await storedTask.value` and again in `adoptStoredEdits` if the document changed.

In practice the test observes only **one** preview request ever reaching the render engine, and it already carries the *stored* document (exposure/vibrance), not the speculative identity document — i.e. the two `schedulePreview()` calls are being coalesced into a single request before the first ever reaches `RenderEngine`/`PreviewCoordinator`. This defeats the latency goal the speculative path was added for (first pixels no longer arrive before persistence resolves) and leaves `main`'s test suite red.

This was discovered during KRMA-316 (git-history restoration for KRMA-305/307/308) while re-running the serial test lane after committing KRMA-308's diff verbatim. KRMA-316's own scope was purely commit hygiene, so this defect was filed separately rather than fixed inline — see `docs/CODE_REVIEW.md` conventions and `AGENTS.md`'s "localized fixes only" rule for verifiers.

**Reproduce:**
```
swift test --filter 'PreviewCutoverTests/testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument'
```
Fails 100% of runs (not flaky) with the first observed request already equal to `storedDocument`.

## Scope / Steps

1. Establish whether `PreviewCoordinator.submit(..., phase: .settled, ...)` coalesces two same-phase submissions issued without an intervening await/render-completion (likely cause: the corrective `schedulePreview()` call in `adoptStoredEdits` fires before the speculative request's `.settled` submission is dispatched to `RenderEngine`, so the coordinator drops/replaces it).
2. Either make the coordinator flush/dispatch the first settled submission before accepting a same-phase replacement when the caller intends both to be observed, or change `adoptStoredEdits`'s corrective path to wait for the speculative render to be admitted first.
3. Confirm the fix preserves KRMA-308's actual goal (cheap thumbnail-churn protection) and does not reintroduce the double-render-on-every-open regression the original (pre-KRMA-308) test guarded against.

## Acceptance criteria

- [ ] `PreviewCutoverTests/testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument` passes deterministically (run at least 5x locally).
- [ ] `scripts/ci-tests.sh serial` (or the `PreviewCutoverTests` + `RenderCacheTests` + `LookPreviewTests` suites) green.
- [ ] No regression in `FilmstripNavigationTests`, `PartitionSurvivalTest`, `EvictionAccountingTest`, `ByteCapTest` (KRMA-308's own acceptance tests).

## Out of scope

- Any further git-history/commit-boundary work (that was KRMA-316's job and is complete).

## Constraints

- macOS 14 minimum; Swift 6 zero-opt-out; `CIImage`/`CIFilter`/`CIContext` stay inside `RenderEngine`.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — pi @ 2026-09-09T14:38:18.107Z

Done. Root cause: PreviewCoordinator.submit cancelled the admitted settled job before its scheduler task first ran (pump moves queued->running synchronously, the task body runs later), so the corrective submit in adoptStoredEdits always coalesced the speculative identity render away; only the stored-document request ever reached the engine.

Fix: new PreviewCoordinator.submitCorrective used only by the adoptStoredEdits corrective path — it queues behind the speculative predecessor instead of cancelling it, so both renders reach the engine in order. submit() keeps preempting semantics (testAStaleResultCannotPublishAfterANewRevision still pins lane preemption for stuck renders).

Verification: PreviewCutoverTests/testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument 5/5 green (~0.16s each); serial lane 308/308 green; fast lane green except LUTWorkflowTests/testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest, which fails identically on clean main (pre-existing, unrelated).

Note: testEachFilmstripOpenSubmitsOneSettledPreview opened its second photo with stored edits and asserted one render for it — irreconcilable with speculate-then-correct (any working fix yields two renders there). Renamed to testEachFilmstripOpenAdmitsItsSettledPreview, predicate now matches the stored-document completion, count 2->3 with justification. Commit af8445a.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-09T15:00:39.389Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- HIGH correctness/performance: submitCorrective abandoned the speculative predecessor's job ID without ever reclaiming it from the scheduler, so it could occupy the single editor-lane slot indefinitely and block all subsequent editor-lane work (including the next photo open) if the caller navigated away or edited before the predecessor finished. Reproduced by gating FakeRenderEngine previews: after navigating to a second photo while the first (orphaned) speculative render was still parked, the second photo's preview never reached the engine until the orphan was manually released. Fixed in commit 65290e1ee6d373a232d624080715ffb48240d590 by adding PreviewCoordinator.abandonedSettledJobIDs, which admit() populates when it opts out of preemption and cancelSettledJob() drains on the next cancellation or preemptive submit. Covered by new regression test testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto.
Fixes:
- None
Verification commits:
- 65290e1ee6d373a232d624080715ffb48240d590
Actor: claude
Resolved model: sonnet
Pickup session: 01MTU7E8PPGJLUFWCK
Summary: Verified: speculative-then-corrective preview flow works as intended (confirmed empirically: speculative frame publishes first, corrective supersedes it in order). Found and fixed a real regression the original fix left behind: the abandoned speculative predecessor was never reclaimed from the scheduler's single editor-lane slot, so navigating away (or editing) before it finished could block every later preview -- including the next photo's -- until it happened to finish on its own. Fixed by tracking abandoned settled job IDs and cancelling them on the next cancellation/preemption. Added a regression test (testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto) that fails without the fix and passes with it. Full serial lane (309/309) and target suites green; pre-existing unrelated LUTWorkflowTests failure confirmed to predate this change.
