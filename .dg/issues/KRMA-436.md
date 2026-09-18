---
id: KRMA-436
title: Add explicit stale-rebuildable-analysis coverage for package backup/restore
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Add a test that seeds a stale PhotoAnalysisCache entry (mismatched content hash or superseded analysis version) alongside a package, performs backup/restore, and asserts the stale entry is not served as current after restore.
      result: pass
      notes: testRestoreDoesNotServeStaleAnalysisForReplacedSourceIdentity (commit 27e561d) seeds a same-assetID entry under a superseded sourceFingerprint, backs up and restores the package, confirms the stale entry survives untouched under its own key, asserts the restored source's real cacheIdentity does not resolve it (AnalysisCacheKey equality/hash is keyed on the full PortablePhotoIdentity including content fingerprint, per PhotoAnalysisCache.swift), and proves PhotoAnalysisCoordinator.analyze recomputes fresh analysis (1 histogram request, differing globalTone.mean) rather than serving the stale value.
  checks_run:
    - swift build
    - swift test --filter PortableLibraryRestoreTests|PortableLibraryBackupTests|PortableLibrarySessionTests|PhotoAnalysisCoordinatorTests|PhotoAnalysisCacheTests (25 tests, 0 failures)
    - swift format lint --configuration .swift-format Tests/KromoraKitTests/PortableLibraryRestoreTests.swift (6 pre-existing warnings, all outside the new test's line range 62-130)
    - scripts/check-swift-format.sh (no changed files vs HEAD)
    - dg validate (OK; only pre-existing unknown-model warnings unrelated to this change)
    - git status --porcelain (clean aside from unrelated pre-tracked .dg bookkeeping)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-14T13:43:11.326Z
  session: 01MU1AKXP1CJHNPACJ
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - library
  - testing
created: 2026-09-14T09:37:25.415Z
updated: 2026-09-14T13:43:11.328Z
depends_on:
  - KRMA-431
order: a0
board: product
---

Parent: KRMA-431 (verification finding, non-blocking)

## Objective

Add explicit stale-rebuildable-analysis coverage for package backup/restore

## Context

KRMA-431 satisfied its acceptance criterion "Add tests for package backup/restore with missing
caches, missing package-derived previews, and stale rebuildable analysis" mostly through existing
coverage: `PortableLibraryBackupTests.testBackupFlushesBeforeSnapshotPublishesAndExcludesDerived`
and `PortableLibraryRestoreTests.testRestoreRebuildsCleanIndexAndPreservesEveryEditRepresentation`
(pre-existing, from KRMA-430) plus the new
`PortableLibrarySessionTests.testPackageReopensAfterDisposableProjectionAndDerivedDataAreRemoved`
(missing index + `Derived/`). None of these exercise the specific case of a **stale**
`PhotoAnalysisCache` entry (`Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCache.swift`)
surviving a package backup/restore cycle and being correctly discarded/recomputed rather than
served as if current. This is a test-coverage gap, not a behavior defect — the cache is
source-keyed and `~/Library/Caches/Kromora/PhotoAnalysis/` is excluded from backup by construction,
so staleness is expected to self-resolve, but that expectation is not directly asserted.

## Acceptance criteria

- [ ] Add a test that seeds a stale `PhotoAnalysisCache` entry (mismatched content hash or superseded
      analysis version) alongside a package, performs backup/restore, and asserts the stale entry is
      not served as current after restore.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-14T13:41:52.187Z

Implemented in 27e561d. Added package backup/restore coverage that seeds a same-asset stale analysis with a superseded content hash, confirms it survives externally, verifies the restored identity misses it, and proves the coordinator recomputes fresh analysis. Verification: focused cache/coordinator/backup/restore suites passed (20 tests); swift build -c release passed; git diff --check passed; dg validate OK with pre-existing unknown-model warnings. The format script still reports six pre-existing violations elsewhere in the touched restore test file.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-14T13:43:11.326Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Add a test that seeds a stale PhotoAnalysisCache entry (mismatched content hash or superseded analysis version) alongside a package, performs backup/restore, and asserts the stale entry is not served as current after restore. (pass) — testRestoreDoesNotServeStaleAnalysisForReplacedSourceIdentity (commit 27e561d) seeds a same-assetID entry under a superseded sourceFingerprint, backs up and restores the package, confirms the stale entry survives untouched under its own key, asserts the restored source's real cacheIdentity does not resolve it (AnalysisCacheKey equality/hash is keyed on the full PortablePhotoIdentity including content fingerprint, per PhotoAnalysisCache.swift), and proves PhotoAnalysisCoordinator.analyze recomputes fresh analysis (1 histogram request, differing globalTone.mean) rather than serving the stale value.
Checks run:
- swift build
- swift test --filter PortableLibraryRestoreTests|PortableLibraryBackupTests|PortableLibrarySessionTests|PhotoAnalysisCoordinatorTests|PhotoAnalysisCacheTests (25 tests, 0 failures)
- swift format lint --configuration .swift-format Tests/KromoraKitTests/PortableLibraryRestoreTests.swift (6 pre-existing warnings, all outside the new test's line range 62-130)
- scripts/check-swift-format.sh (no changed files vs HEAD)
- dg validate (OK; only pre-existing unknown-model warnings unrelated to this change)
- git status --porcelain (clean aside from unrelated pre-tracked .dg bookkeeping)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU1AKXP1CJHNPACJ
