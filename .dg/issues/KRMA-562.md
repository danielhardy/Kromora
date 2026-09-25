---
id: KRMA-562
title: "Finish Stage 3: move comparison-retry admission into PreviewAdmissionCoordinator and add missing fence tests"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Comparison-retry state/methods move to PreviewAdmissionCoordinator; AppViewModel keeps only forwarders and the comparison-baseline document; behavior and call sites preserved
      result: pass
      notes: "Verified via git show c8bc39b: comparisonPreviewScheduledRevision/RetriedRevision/RetryTask/JobID and scheduleOriginalPreview/comparisonPreviewDidFail/cancelComparisonPreview moved to PreviewAdmissionCoordinator with identical fence logic. AppViewModel retains only thin forwarders and comparisonBaselineDocument; grep confirms no leftover state references in AppViewModel. All original call sites (load/undo/comparison toggle at lines 2015, 3327, 3630, 3688, 3698, 3781, 3852, 3936-3939) and shutdown() retry-task cancellation order (line 4298) are preserved."
    - criterion: Add four missing fake-based tests to PreviewAdmissionCoordinatorTests.swift
      result: pass
      notes: testStaleDisplayRevisionAndAssetDropCacheHit, testIdleAdmissionNeverCallsPreviewPublication, testComparisonRetryRunsOncePerComparisonRevision, and testROIRequestDoesNotAdoptCanonicalCacheHit added; all pass.
    - criterion: docs/APP_ARCHITECTURE.md Preview-presentation ownership section reflects final ownership
      result: pass
      notes: Section now states PreviewAdmissionCoordinator owns comparison-preview admission including scheduled/retried revision state and retry task, matching the code.
    - criterion: swift build, focused test filter, scripts/ci-tests.sh fast, dg validate, git diff --check all pass
      result: pass
      notes: swift build succeeded; focused filter ran 50 tests, 0 failures; ci-tests.sh fast ran 1190 tests, exit 0; dg validate returned OK (unrelated pre-existing model-name warnings only); git diff --check exit 0.
  checks_run:
    - swift build
    - swift test --filter 'PreviewAdmissionCoordinatorTests|PreviewPresentationCoordinatorTests|FilmstripNavigationTests|HistogramTests|ComparisonModeTests|PreviewDiskCacheTests' (50 tests, 0 failures)
    - scripts/ci-tests.sh fast (1190 tests, exit 0)
    - dg validate (OK)
    - git diff --check (exit 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-24T14:06:56.103Z
  session: 01MUFLPTCA9SHTFPBD
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - verification
created: 2026-09-24T03:54:41.695Z
updated: 2026-09-24T14:06:56.105Z
blockers: []
order: a0
board: product
---

Parent: KRMA-467

## Objective

KRMA-467 (Stage 3) moved histogram admission, idle/adjacent-prefetch, and interactive/settled
submit admission into `PreviewAdmissionCoordinator`, but the comparison-retry cluster — explicitly
listed in KRMA-467's "Slice C" and its ownership contract ("State owned: ... comparison retry ...")
— was never moved. It still lives entirely on `AppViewModel`:

- `comparisonPreviewScheduledRevision`, `comparisonPreviewRetriedRevision`,
  `comparisonPreviewRetryTask`, `comparisonPreviewJobID`
- `scheduleOriginalPreview(...)` (~3891), `comparisonPreviewDidFail(...)` (~4019),
  `cancelComparisonPreview(...)` (~4049)

`docs/APP_ARCHITECTURE.md` was updated by KRMA-467 to claim `PreviewAdmissionCoordinator` "owns
... comparison-retry admission," which is currently false — either finish the extraction or correct
the doc, but the ticket's explicit ownership contract calls for the extraction.

Separately, `Tests/KromoraKitTests/PreviewAdmissionCoordinatorTests.swift` only has 1 test
(`testIdleAndAdjacentPrefetchJobsHaveIndependentCancellationIDs`) of the 5 fake-based cases KRMA-467
required:

- stale display revision / asset id drops a cache hit and a histogram result
- idle admission never calls the preview publication fake
- idle and adjacent-prefetch job ids cancel independently (done)
- comparison retry runs once per comparison revision
- ROI requests do not adopt a canonical cache hit

## Acceptance criteria

- [ ] Comparison-retry state/methods (`comparisonPreviewScheduledRevision`,
      `comparisonPreviewRetriedRevision`, `comparisonPreviewRetryTask`, `comparisonPreviewJobID`,
      `scheduleOriginalPreview`, `comparisonPreviewDidFail`, `cancelComparisonPreview`) move to
      `PreviewAdmissionCoordinator`, following the same destination-protocol pattern as the rest of
      the coordinator. `AppViewModel` keeps only forwarders and the comparison-baseline document.
  - Preserve "runs once per comparison revision" retry behavior and existing call sites
    (`scheduleOriginalPreview` calls at load/undo/comparison toggle, `shutdown()` cancellation order).
- [ ] Add the four missing fake-based tests to `PreviewAdmissionCoordinatorTests.swift`: stale
      display revision/asset id drop, idle admission never publishing, comparison retry runs once
      per revision, and ROI requests not adopting a canonical cache hit.
- [ ] `docs/APP_ARCHITECTURE.md`'s "Preview-presentation ownership" section accurately reflects
      final ownership after the move.
- [ ] `swift build`, `swift test --filter 'PreviewAdmissionCoordinatorTests|PreviewPresentationCoordinatorTests|FilmstripNavigationTests|HistogramTests|ComparisonModeTests|PreviewDiskCacheTests'`,
      `scripts/ci-tests.sh fast`, `dg validate`, and `git diff --check` pass.

## Context

- Sources/KromoraKit/ViewModels/AppViewModel.swift (comparison-retry cluster, lines ~332-336,
  ~812, ~3891-4051)
- Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift
- Tests/KromoraKitTests/PreviewAdmissionCoordinatorTests.swift
- docs/APP_ARCHITECTURE.md
- docs/COMPARISON_MODE.md
- KRMA-467 (source ticket; this is the remainder of Slice C left incomplete)

### Comment — codex @ 2026-09-24T14:02:21.722Z

Moved comparison preview admission and its once-per-revision retry state into PreviewAdmissionCoordinator. Added fake-based stale cache/histogram, idle publication, retry, and ROI cache tests; updated Preview-presentation ownership. Checks passed: swift build; focused preview/comparison/histogram/cache tests (50); scripts/ci-tests.sh fast (1190); dg validate; git diff --check. Commit c8bc39b.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-24T14:06:56.103Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Comparison-retry state/methods move to PreviewAdmissionCoordinator; AppViewModel keeps only forwarders and the comparison-baseline document; behavior and call sites preserved (pass) — Verified via git show c8bc39b: comparisonPreviewScheduledRevision/RetriedRevision/RetryTask/JobID and scheduleOriginalPreview/comparisonPreviewDidFail/cancelComparisonPreview moved to PreviewAdmissionCoordinator with identical fence logic. AppViewModel retains only thin forwarders and comparisonBaselineDocument; grep confirms no leftover state references in AppViewModel. All original call sites (load/undo/comparison toggle at lines 2015, 3327, 3630, 3688, 3698, 3781, 3852, 3936-3939) and shutdown() retry-task cancellation order (line 4298) are preserved.
- [x] Add four missing fake-based tests to PreviewAdmissionCoordinatorTests.swift (pass) — testStaleDisplayRevisionAndAssetDropCacheHit, testIdleAdmissionNeverCallsPreviewPublication, testComparisonRetryRunsOncePerComparisonRevision, and testROIRequestDoesNotAdoptCanonicalCacheHit added; all pass.
- [x] docs/APP_ARCHITECTURE.md Preview-presentation ownership section reflects final ownership (pass) — Section now states PreviewAdmissionCoordinator owns comparison-preview admission including scheduled/retried revision state and retry task, matching the code.
- [x] swift build, focused test filter, scripts/ci-tests.sh fast, dg validate, git diff --check all pass (pass) — swift build succeeded; focused filter ran 50 tests, 0 failures; ci-tests.sh fast ran 1190 tests, exit 0; dg validate returned OK (unrelated pre-existing model-name warnings only); git diff --check exit 0.
Checks run:
- swift build
- swift test --filter 'PreviewAdmissionCoordinatorTests|PreviewPresentationCoordinatorTests|FilmstripNavigationTests|HistogramTests|ComparisonModeTests|PreviewDiskCacheTests' (50 tests, 0 failures)
- scripts/ci-tests.sh fast (1190 tests, exit 0)
- dg validate (OK)
- git diff --check (exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUFLPTCA9SHTFPBD
Summary: Independent verification confirmed the comparison-retry extraction is a faithful mechanical move: all state/methods relocated to PreviewAdmissionCoordinator with fences preserved, call sites unchanged, four new fake-based tests added and passing, and docs updated accurately. All required checks (build, focused tests, ci-tests.sh fast, dg validate, git diff --check) pass.
