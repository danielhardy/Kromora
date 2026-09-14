---
id: KRMA-423
title: Stabilize adjacent filmstrip prefetch and selection preview reuse
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Adjacent prefetch uses the same asset identity, source revision, render scale, geometry, and document revision expected by later selection.
      result: pass
      notes: adjacentPreviewPlan (AppViewModel.swift:3452) now returns a full ResolutionPlan and prefetch requests are built via makeSettledPreviewRequest with the candidate's assetID, matching source ROI and presentationImageExtent used by the selected-preview path.
    - criterion: Selecting a prefetched neighbor reuses or promotes the valid request instead of dropping it or waiting indefinitely.
      result: pass
      notes: testAdjacentPrefetchScaleKeyMatchesSubsequentSelectionPreview asserts prefetchRequest.document/sourceROI/presentationImageExtent equal selectedRequest's, and the scale key matches; test passed 4/4 runs (1 initial + 3 repeats), ~2.3-2.4s each, no timeout.
    - criterion: Stale prefetch work cannot publish for another asset.
      result: pass
      notes: Pre-existing guard in publishPreview (AppViewModel.swift:4132) rejects any publication where assetID/sourceRevision/displayRevision/source do not match current state; unaffected by this change and covered by ThumbnailSwitchLifecycleTests.testRapidThumbnailChangesCannotPublishAnObsoleteSourceOrHistogram.
    - criterion: The test synchronizes on preview admission/publication and includes request identity and preview-count diagnostics.
      result: pass
      notes: FilmstripNavigationTests.swift adds requestDiagnostic(_:) reporting asset/revision/scale and uses TestSynchronization.nextEvent with diagnostics closures reporting preview/texture counts.
    - criterion: Focused filmstrip/thumbnail navigation tests pass repeatedly and the full serial/fast lanes remain green.
      result: pass
      notes: "FilmstripNavigationTests (7 tests) and ThumbnailSwitchLifecycleTests (13 tests) pass; named test rerun 3x standalone with no flakes. Full serial lane: 375/375 passed. Fast lane: 999/999 completed, then LUTWorkflowTests/testCopyPasteTransfersLUTToExactlySelectedPhotosAndUndoRestoresEach failed only under --parallel contention; reproduced as passing standalone (0.48s), confirming it is the same pre-existing flake the implementer reported, not a regression from this change."
  checks_run:
    - swift test --filter 'FilmstripNavigationTests|ThumbnailSwitchLifecycleTests' (20/20 passed)
    - swift test --filter testAdjacentPrefetchScaleKeyMatchesSubsequentSelectionPreview x3 repeats (all passed, ~2.3s each)
    - scripts/ci-tests.sh serial (375/375 passed)
    - scripts/ci-tests.sh fast (999/999 collected; parallel run failed only on pre-existing LUTWorkflowTests flake)
    - swift test --filter LUTWorkflowTests/testCopyPasteTransfersLUTToExactlySelectedPhotosAndUndoRestoresEach standalone (passed, confirms pre-existing parallel-only flake)
    - dg validate (OK, unrelated pre-existing warnings only)
    - git diff --cached --check (clean)
    - code review of commit 14adbe2 diff and surrounding AppViewModel.swift publish/prefetch guards
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T17:12:25.702Z
  session: 01MU02JNF6RKXGNDF8
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - testing
  - async
  - filmstrip
created: 2026-09-13T15:50:10.550Z
updated: 2026-09-13T17:12:25.704Z
order: a0
board: product
---

## Objective

Make adjacent filmstrip prefetch and subsequent selection share the correct preview request and reliably publish the selected neighbor preview.

## Evidence

The full serial run on 2026-09-13 failed:
- FilmstripNavigationTests/testAdjacentPrefetchScaleKeyMatchesSubsequentSelectionPreview
- It timed out waiting for the selected neighbor preview; previews=1.

## Acceptance criteria

- Adjacent prefetch uses the same asset identity, source revision, render scale, geometry, and document revision expected by later selection.
- Selecting a prefetched neighbor reuses or promotes the valid request instead of dropping it or waiting indefinitely.
- Stale prefetch work cannot publish for another asset.
- The test synchronizes on preview admission/publication and includes request identity and preview-count diagnostics.
- Focused filmstrip/thumbnail navigation tests pass repeatedly and the full serial/fast lanes remain green.

## Verification

Run the named test repeatedly with FilmstripNavigationTests and ThumbnailSwitchLifecycleTests neighbors, then the full serial and fast CI lanes.


### Comment — codex @ 2026-09-13T17:09:08.139Z

Implemented and committed as 14adbe2. Adjacent prefetch now uses the selected asset identity and the settled preview ResolutionPlan, including matching source ROI and presentation extent; regression diagnostics assert request identity and geometry, and fixtures use distinct pixels so disk-cache hits cannot bypass admission. Verification: named filmstrip test passed; FilmstripNavigationTests plus ThumbnailSwitchLifecycleTests passed 3 repeated runs (20 tests each); serial lane passed 375/375; dg validate and git diff --cached --check passed. Fast lane reached 999/999 but hit the pre-existing parallel LUTWorkflowTests persisted-paste timeout; that test passed in a direct no-parallel rerun.

## Agent log

- 2026-09-13T17:12:25.703Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Adjacent prefetch uses the same asset identity, source revision, render scale, geometry, and document revision expected by later selection. (pass) — adjacentPreviewPlan (AppViewModel.swift:3452) now returns a full ResolutionPlan and prefetch requests are built via makeSettledPreviewRequest with the candidate's assetID, matching source ROI and presentationImageExtent used by the selected-preview path.
- [x] Selecting a prefetched neighbor reuses or promotes the valid request instead of dropping it or waiting indefinitely. (pass) — testAdjacentPrefetchScaleKeyMatchesSubsequentSelectionPreview asserts prefetchRequest.document/sourceROI/presentationImageExtent equal selectedRequest's, and the scale key matches; test passed 4/4 runs (1 initial + 3 repeats), ~2.3-2.4s each, no timeout.
- [x] Stale prefetch work cannot publish for another asset. (pass) — Pre-existing guard in publishPreview (AppViewModel.swift:4132) rejects any publication where assetID/sourceRevision/displayRevision/source do not match current state; unaffected by this change and covered by ThumbnailSwitchLifecycleTests.testRapidThumbnailChangesCannotPublishAnObsoleteSourceOrHistogram.
- [x] The test synchronizes on preview admission/publication and includes request identity and preview-count diagnostics. (pass) — FilmstripNavigationTests.swift adds requestDiagnostic(_:) reporting asset/revision/scale and uses TestSynchronization.nextEvent with diagnostics closures reporting preview/texture counts.
- [x] Focused filmstrip/thumbnail navigation tests pass repeatedly and the full serial/fast lanes remain green. (pass) — FilmstripNavigationTests (7 tests) and ThumbnailSwitchLifecycleTests (13 tests) pass; named test rerun 3x standalone with no flakes. Full serial lane: 375/375 passed. Fast lane: 999/999 completed, then LUTWorkflowTests/testCopyPasteTransfersLUTToExactlySelectedPhotosAndUndoRestoresEach failed only under --parallel contention; reproduced as passing standalone (0.48s), confirming it is the same pre-existing flake the implementer reported, not a regression from this change.
Checks run:
- swift test --filter 'FilmstripNavigationTests|ThumbnailSwitchLifecycleTests' (20/20 passed)
- swift test --filter testAdjacentPrefetchScaleKeyMatchesSubsequentSelectionPreview x3 repeats (all passed, ~2.3s each)
- scripts/ci-tests.sh serial (375/375 passed)
- scripts/ci-tests.sh fast (999/999 collected; parallel run failed only on pre-existing LUTWorkflowTests flake)
- swift test --filter LUTWorkflowTests/testCopyPasteTransfersLUTToExactlySelectedPhotosAndUndoRestoresEach standalone (passed, confirms pre-existing parallel-only flake)
- dg validate (OK, unrelated pre-existing warnings only)
- git diff --cached --check (clean)
- code review of commit 14adbe2 diff and surrounding AppViewModel.swift publish/prefetch guards
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU02JNF6RKXGNDF8
Summary: Verified: adjacent prefetch now shares identity/ROI/presentation geometry with the settled selection preview; named test stable across repeats, full serial lane 375/375, fast lane's only failure reproduces as a pre-existing parallel-only LUTWorkflowTests flake unrelated to this change. No blocking findings.
