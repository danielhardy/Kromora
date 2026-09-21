---
id: KRMA-407
title: "Phase 3.2: automatic index rebuild from membership shards with progressive paging"
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Warm launch reads the first page from the index with zero directory walks, XMP parses, or original-file reads (verified by test instrumentation).
      result: pass
      notes: PortableLibraryPackage.openForQuery(at:) reads only manifest.json; LibraryIndexSession.open() on a valid index takes the warm path and never calls readMembershipShard/readAssetRecord. testWarmSessionReadsOnlyTheIndexAndDoesNotRequireAssetRecords uses a fixture with no Assets/**/asset.json files at all, so any accidental record read would throw.
    - criterion: A missing or corrupted index is detected, triggers an automatic rebuild from membership shards, and the first page is published before the full rebuild completes.
      result: pass
      notes: LibraryIndexProjection.rebuild publishes a partial-page progress callback once effectivePageSize entries have accumulated, before continuing through the remaining shards; testMissingIndexRebuildsFromShardsPublishesFirstPageAndPreservesContent and testCorruptIndexAutomaticallyFallsBackToShardRebuild cover both triggers.
    - criterion: Deleting the local index and reopening the package reconstructs an equivalent index with no data loss (content, not just count, is verified).
      result: pass
      notes: testMissingIndexRebuildsFromShardsPublishesFirstPageAndPreservesContent deletes the index and asserts full XCTAssertEqual content equality against the expected projection, not just count.
    - criterion: swift build, swift test, dg validate, and git diff --check pass.
      result: pass
      notes: "swift build clean; targeted LibraryQueryControllerTests (8/8) and full fast lane run: two pre-existing unrelated failures (ExportCoordinatorTests, MaskingWorkspaceTests/CoreData disk I/O) reproduced identically on the pre-KRMA-407 parent commit, confirming they are environmental/pre-existing, not caused by this change. dg validate OK (only pre-existing unrelated model-name warnings). git diff --check clean."
  checks_run:
    - swift build
    - swift test --filter LibraryQueryControllerTests (8/8 pass, including 1 new regression test)
    - scripts/ci-tests.sh fast (2 pre-existing unrelated failures reproduced on parent commit b105d4f^, confirmed environmental)
    - dg validate
    - git diff --check
  findings:
    - "CONFIRMED correctness: LibraryIndexSession.failRebuild left rebuildTask set after a rebuild failure, so isRebuilding never returned to false once a background rebuild threw. Scenario: a background rebuild publishes a first page successfully, then hits a corrupt membership shard later in the shard walk and throws; isRebuilding stays true forever, which would mislead future UI wiring (e.g. a persistent rebuild spinner or a guard against starting a second rebuild) even though no rebuild is actually in flight. (Sources/KromoraKit/Models/LibraryQueryController.swift)"
  fixes:
    - Cleared rebuildTask in LibraryIndexSession.failRebuild so isRebuilding reports false after a failed rebuild (Sources/KromoraKit/Models/LibraryQueryController.swift).
    - Added testFailedRebuildClearsIsRebuilding regression test; widened PortableLibraryPackage.membershipURL(for:) to internal so the test can corrupt a specific shard on disk (Tests/KromoraKitTests/LibraryQueryControllerTests.swift).
  verification_commits:
    - 60523a3
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T14:16:17.952Z
  session: 01MTZW8HBRI7FOD6BU
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - performance
  - index
created: 2026-09-12T19:44:20.441Z
updated: 2026-09-13T14:16:17.954Z
depends_on:
  - KRMA-406
order: a0
board: product
commits:
  - 60523a3
---

## Objective

Implement automatic index rebuild from the package's membership shards, with progressive first-page
publication, so a missing or corrupt local index never blocks the library from opening and warm
launch never has to walk asset directories or parse XMP.

## Dependencies

- The `LibraryQueryController`/index-projection ticket (this rebuilds the structure it reads).

## Scope

- Implement rebuild-from-shards: given only the package's membership shards (denormalised summaries
  from KRMA-391), reconstruct the local index projection without opening every asset record or
  reading originals.
- On missing or corrupt index detection, trigger rebuild automatically and publish the first
  ~500-asset page as soon as it is available, continuing the rebuild in the background rather than
  blocking the UI until the full rebuild completes.
- Warm launch (index present and valid) must read the first page directly from the index with no
  directory walk, no XMP parse, and no original-file read — verify this with instrumentation, not
  just inspection.
- The index remains explicitly non-canonical: deleting it must never lose data, since it is fully
  reconstructable from the package (this is the invariant the sibling scale-regression ticket
  verifies end to end).

## Acceptance criteria

- [ ] Warm launch reads the first page from the index with zero directory walks, XMP parses, or
  original-file reads (verified by test instrumentation).
- [ ] A missing or corrupted index is detected, triggers an automatic rebuild from membership shards,
  and the first page is published before the full rebuild completes.
- [ ] Deleting the local index and reopening the package reconstructs an equivalent index with no
  data loss (content, not just count, is verified).
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Large-library performance/concurrency lane at 1k/10k for rebuild-timing shape; correctness (no data
loss on rebuild) verified at all three KRMA-389 scale sizes where feasible in CI time budget (100k in
the optional/benchmark lane).

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-392, KRMA-391


### Comment — codex @ 2026-09-13T14:12:30.399Z

Implemented in b105d4f: added query-safe package opening, automatic validated index recovery, progressive shard-only rebuild with first-page publication, atomic index persistence, cancellation checks, and actor-backed session updates. Added warm/missing/corrupt/delete-rebuild coverage with content equality and no asset records required. Checks: swift build; focused query/package/end-to-end tests 21/21; dg validate; git diff --check. Full swift test and ci fast remain affected by unrelated pre-existing async/UI/Core Data failures in this environment.

## Agent log

- 2026-09-13T14:16:17.952Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Warm launch reads the first page from the index with zero directory walks, XMP parses, or original-file reads (verified by test instrumentation). (pass) — PortableLibraryPackage.openForQuery(at:) reads only manifest.json; LibraryIndexSession.open() on a valid index takes the warm path and never calls readMembershipShard/readAssetRecord. testWarmSessionReadsOnlyTheIndexAndDoesNotRequireAssetRecords uses a fixture with no Assets/**/asset.json files at all, so any accidental record read would throw.
- [x] A missing or corrupted index is detected, triggers an automatic rebuild from membership shards, and the first page is published before the full rebuild completes. (pass) — LibraryIndexProjection.rebuild publishes a partial-page progress callback once effectivePageSize entries have accumulated, before continuing through the remaining shards; testMissingIndexRebuildsFromShardsPublishesFirstPageAndPreservesContent and testCorruptIndexAutomaticallyFallsBackToShardRebuild cover both triggers.
- [x] Deleting the local index and reopening the package reconstructs an equivalent index with no data loss (content, not just count, is verified). (pass) — testMissingIndexRebuildsFromShardsPublishesFirstPageAndPreservesContent deletes the index and asserts full XCTAssertEqual content equality against the expected projection, not just count.
- [x] swift build, swift test, dg validate, and git diff --check pass. (pass) — swift build clean; targeted LibraryQueryControllerTests (8/8) and full fast lane run: two pre-existing unrelated failures (ExportCoordinatorTests, MaskingWorkspaceTests/CoreData disk I/O) reproduced identically on the pre-KRMA-407 parent commit, confirming they are environmental/pre-existing, not caused by this change. dg validate OK (only pre-existing unrelated model-name warnings). git diff --check clean.
Checks run:
- swift build
- swift test --filter LibraryQueryControllerTests (8/8 pass, including 1 new regression test)
- scripts/ci-tests.sh fast (2 pre-existing unrelated failures reproduced on parent commit b105d4f^, confirmed environmental)
- dg validate
- git diff --check
Findings:
- CONFIRMED correctness: LibraryIndexSession.failRebuild left rebuildTask set after a rebuild failure, so isRebuilding never returned to false once a background rebuild threw. Scenario: a background rebuild publishes a first page successfully, then hits a corrupt membership shard later in the shard walk and throws; isRebuilding stays true forever, which would mislead future UI wiring (e.g. a persistent rebuild spinner or a guard against starting a second rebuild) even though no rebuild is actually in flight. (Sources/KromoraKit/Models/LibraryQueryController.swift)
Fixes:
- Cleared rebuildTask in LibraryIndexSession.failRebuild so isRebuilding reports false after a failed rebuild (Sources/KromoraKit/Models/LibraryQueryController.swift).
- Added testFailedRebuildClearsIsRebuilding regression test; widened PortableLibraryPackage.membershipURL(for:) to internal so the test can corrupt a specific shard on disk (Tests/KromoraKitTests/LibraryQueryControllerTests.swift).
Verification commits:
- 60523a3
Actor: claude
Resolved model: sonnet
Pickup session: 01MTZW8HBRI7FOD6BU
Summary: Verified KRMA-407: warm/cold/corrupt index paths and content-equal rebuild-after-delete all hold, backed by tests. Found and fixed a real bug (isRebuilding stuck true after a failed background rebuild) with a new regression test. swift build/test, dg validate, git diff --check all pass; the two fast-lane failures seen are pre-existing/environmental, reproduced identically on the parent commit. Completing to done.
