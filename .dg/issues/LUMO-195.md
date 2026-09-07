---
id: LUMO-195
title: "Analysis coordinator: cancellation + request dedup"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: actor PhotoAnalysisCoordinator exposes analyze(assetID:source:level:) and mask(assetID:source:kind:quality:)
      result: pass
      notes: Both entry points present in PhotoAnalysisCoordinator.swift; mask(...) does not require a full analyze() call and only invokes SemanticMaskProviding for the requested kind/quality.
    - criterion: Concurrent calls for the same underlying work share one in-flight Task
      result: pass
      notes: 8-way concurrent dedup verified for both analyze() and mask() (CountingMaskProvider callCount == 1 in both tests).
    - criterion: PhotoAnalysisLevel maps to registered mask stages, Tier 0 wired for real, registry-shaped for later stages
      result: pass
      notes: "defaultStages is a [PhotoAnalysisLevel: [PhotoAnalysisStage]] dictionary, injectable via init(stages:), so later tickets register additional stages without touching dedup/cancellation machinery."
    - criterion: Every awaited stage checks Task.checkCancellation() between stages
      result: pass
      notes: checkCancellation() present before/after each stage in performAnalysis, in performMask, and in the assembler's per-region loop.
    - criterion: No @MainActor requirement anywhere in this actor
      result: pass
      notes: PhotoAnalysisCoordinator is a plain actor; no @MainActor annotations anywhere in the file.
    - criterion: Swift 6 clean, zero escape hatches
      result: pass
      notes: PackageSettingsTests (language mode, tools version, zero-escape-hatch grep) pass unchanged after the fix.
  checks_run:
    - swift build (clean; pre-existing CIKernel deprecation warnings only, unrelated to this file)
    - swift test --filter PhotoAnalysisCoordinatorTests (6 passed, 0 failed, includes new regression test)
    - swift test --filter PackageSettingsTests (3 passed, 0 failed)
    - dg validate (OK; pre-existing unrelated warnings only)
    - git status --porcelain (clean aside from this verification commit)
  findings:
    - "Cancelling one of several concurrent callers sharing a deduped analyze()/mask() request cancelled the underlying work for every other concurrent caller keyed to the same request, not just the one that cancelled. Editor entry and the thumbnail prefetcher both request the same photo's subject mask concurrently and share the in-flight Task per the dedup contract; the thumbnail prefetcher's request is cancelled (e.g. scrolled off-screen) before the shared work finishes. withTaskCancellationHandler's onCancel fired on the prefetcher's own cancellation and called task.cancel() on the *shared* Task, so the editor's still-active request also failed with CancellationError even though nothing about the editor's own call was cancelled. Reproduced directly: a scratch two-waiter test (one cancelled, one left running) failed the uncancelled waiter with CancellationError before the fix, using the actual coordinator + a gated mask provider. Fixed in commit c5237a8 (file: Sources/LumoKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift)."
  fixes:
    - Added a waiter count to each in-flight dedup entry (InFlightEntry<Value>); the shared Task is only cancelled once every attached waiter has itself cancelled, via analysisWaiterCancelled(_:)/maskWaiterCancelled(_:) reached through withTaskCancellationHandler's onCancel. The dictionary entry is still only ever removed by the task's own completion handler, so a late waiter-cancel can't evict an unrelated later request that reused the same key.
    - "Added testCancellingOneOfSeveralWaitersDoesNotCancelTheOthers to PhotoAnalysisCoordinatorTests.swift: two concurrent mask() callers share one in-flight request, one is cancelled, and the test asserts the other still receives its result and the provider was never cancelled."
  verification_commits:
    - c5237a8b6e7b48a70713dfed0732263ae1875fbd
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-04T15:49:02.309Z
  session: 01MTN4FNOCJMA29HH6
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:53.761Z
updated: 2026-09-07T04:02:45.835Z
depends_on:
  - LUMO-187
  - LUMO-192
order: djanm69y
board: product
commits:
  - c5237a8b6e7b48a70713dfed0732263ae1875fbd
---

**Type:** Task
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift`
**Depends on:** LUMO-187, LUMO-192
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §5, original proposal §11–12

## 1. Problem

Multiple callers (editor entry, thumbnail prefetcher, the Masking UI) can request masks/analysis
for the same photo at roughly the same time — without coordination that means duplicate Vision
passes. Work must also be cancellable, mirroring the existing `autoAdjustmentTask?.cancel()`
discipline in `AppViewModel.runAutoAdjustment()`. Note this coordinator now serves **two**
consumers with different needs: Auto wants a full `PhotoAnalysis` at `.analysis` mask quality; the
Masking UI (LUMO-201) wants individual masks, often at `.preview`/`.render` quality, without
necessarily wanting a full `PhotoAnalysis` recomputed.

## 2. Requirement (acceptance criteria)

1. `actor PhotoAnalysisCoordinator` exposing (at least) two entry points:
   ```swift
   func analyze(assetID: PhotoAssetID, source: ..., level: PhotoAnalysisLevel) async throws -> PhotoAnalysis
   func mask(assetID: PhotoAssetID, source: ..., kind: SemanticMaskKind, quality: MaskQuality) async throws -> RegionMask
   ```
   The second is what the Masking UI calls directly — it should **not** need to go through a full
   `analyze(...)` call to get one mask; it should reuse whatever's already cached (`MaskStore`,
   LUMO-185) and only compute what's missing.
2. Concurrent calls for the same underlying work (same `assetID` + `sourceFingerprint` +
   requested kind/quality, or same `level`) share one in-flight `Task` — test with N concurrent
   calls, assert the underlying provider ran exactly once.
3. `enum PhotoAnalysisLevel { case fast, standard, detailed }` (per `docs/PHASE3_SPEC.md` §4) maps
   to which mask kinds + `MaskQuality` get requested for a full `analyze(...)` call; this ticket
   only needs Tier 0 wired for real (LUMO-192) — later tickets (LUMO-197+) don't need to touch the
   coordinator's structure again, just register as additional stages.
4. Every awaited stage checks `Task.checkCancellation()` between stages.
5. No `@MainActor` requirement anywhere in this actor.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Look at `DeriveCoordinator` and `AppViewModel.autoAdjustmentTask` for the existing
  cancel-on-supersede shape to match, rather than inventing a new one.
- Structure the stage list so it's a small internal registry, not a hardcoded call chain — every
  mask-provider ticket that already landed by the time this is implemented (LUMO-188/189/190/191,
  if sequenced first) can register as a stage; if this ticket is implemented before all of them
  exist, keep it registry-shaped so late arrivals don't require restructuring.

## 4. Where to look

- `Sources/LumoKit/ViewModels/DeriveCoordinator.swift`.
- `Sources/LumoKit/ViewModels/AppViewModel.swift:861-913` (`runAutoAdjustment`).
- `Sources/LumoKit/Models/ImageWorkScheduler.swift` — existing scheduler patterns.

## 5. Testing

- `Tests/LumoKitTests/PhotoAnalysisCoordinatorTests.swift` (new): concurrent-dedup test for both
  entry points, cancellation test, direct-mask-request-doesn't-require-full-analyze test (assert a
  `mask(...)` call doesn't trigger unrelated stages).


### Comment — codex @ 2026-09-04T15:41:01.653Z

Implemented in c2464cb. Added actor PhotoAnalysisCoordinator with configurable fast/standard/detailed mask stage registry, source/asset request-keyed in-flight dedup for full analysis and direct masks, cancellation checks and shared-task cancellation propagation, Tier-0 assembly with optional mask-stage degradation, and focused concurrent/cancellation/direct-mask tests. Verification: swift build passed; PhotoAnalysis and PackageSettings suites passed; dg validate passed with existing warnings. Full swift test executed 779 tests with 34 skips and 15 pre-existing unrelated timing/lifecycle failures.

## Agent log

- 2026-09-04T15:49:02.311Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] actor PhotoAnalysisCoordinator exposes analyze(assetID:source:level:) and mask(assetID:source:kind:quality:) (pass) — Both entry points present in PhotoAnalysisCoordinator.swift; mask(...) does not require a full analyze() call and only invokes SemanticMaskProviding for the requested kind/quality.
- [x] Concurrent calls for the same underlying work share one in-flight Task (pass) — 8-way concurrent dedup verified for both analyze() and mask() (CountingMaskProvider callCount == 1 in both tests).
- [x] PhotoAnalysisLevel maps to registered mask stages, Tier 0 wired for real, registry-shaped for later stages (pass) — defaultStages is a [PhotoAnalysisLevel: [PhotoAnalysisStage]] dictionary, injectable via init(stages:), so later tickets register additional stages without touching dedup/cancellation machinery.
- [x] Every awaited stage checks Task.checkCancellation() between stages (pass) — checkCancellation() present before/after each stage in performAnalysis, in performMask, and in the assembler's per-region loop.
- [x] No @MainActor requirement anywhere in this actor (pass) — PhotoAnalysisCoordinator is a plain actor; no @MainActor annotations anywhere in the file.
- [x] Swift 6 clean, zero escape hatches (pass) — PackageSettingsTests (language mode, tools version, zero-escape-hatch grep) pass unchanged after the fix.
Checks run:
- swift build (clean; pre-existing CIKernel deprecation warnings only, unrelated to this file)
- swift test --filter PhotoAnalysisCoordinatorTests (6 passed, 0 failed, includes new regression test)
- swift test --filter PackageSettingsTests (3 passed, 0 failed)
- dg validate (OK; pre-existing unrelated warnings only)
- git status --porcelain (clean aside from this verification commit)
Findings:
- Cancelling one of several concurrent callers sharing a deduped analyze()/mask() request cancelled the underlying work for every other concurrent caller keyed to the same request, not just the one that cancelled. Editor entry and the thumbnail prefetcher both request the same photo's subject mask concurrently and share the in-flight Task per the dedup contract; the thumbnail prefetcher's request is cancelled (e.g. scrolled off-screen) before the shared work finishes. withTaskCancellationHandler's onCancel fired on the prefetcher's own cancellation and called task.cancel() on the *shared* Task, so the editor's still-active request also failed with CancellationError even though nothing about the editor's own call was cancelled. Reproduced directly: a scratch two-waiter test (one cancelled, one left running) failed the uncancelled waiter with CancellationError before the fix, using the actual coordinator + a gated mask provider. Fixed in commit c5237a8 (file: Sources/LumoKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift).
Fixes:
- Added a waiter count to each in-flight dedup entry (InFlightEntry<Value>); the shared Task is only cancelled once every attached waiter has itself cancelled, via analysisWaiterCancelled(_:)/maskWaiterCancelled(_:) reached through withTaskCancellationHandler's onCancel. The dictionary entry is still only ever removed by the task's own completion handler, so a late waiter-cancel can't evict an unrelated later request that reused the same key.
- Added testCancellingOneOfSeveralWaitersDoesNotCancelTheOthers to PhotoAnalysisCoordinatorTests.swift: two concurrent mask() callers share one in-flight request, one is cancelled, and the test asserts the other still receives its result and the provider was never cancelled.
Verification commits:
- c5237a8b6e7b48a70713dfed0732263ae1875fbd
Actor: claude
Resolved model: sonnet
Pickup session: 01MTN4FNOCJMA29HH6
Summary: Verified LUMO-195: coordinator meets all acceptance criteria. Found and fixed a real cross-consumer cancellation leak — cancelling one of several concurrent waiters on a deduped request was cancelling the shared work for all of them, undermining the ticket's multi-consumer motivation. Added waiter refcounting so the shared Task only cancels once every attached waiter has cancelled, plus a regression test.
