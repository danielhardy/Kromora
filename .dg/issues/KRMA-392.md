---
id: KRMA-392
title: "Phase 3: add paged library queries, index projection, and unified scheduling"
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Warm launch and cold index rebuild provide progressive, index-only paged library access
      result: pass
      notes: LibraryIndexSession reads a valid local projection without asset directories and rebuilds corrupt/missing indexes from membership shards, publishing the first page before completion.
    - criterion: 100,000-asset materialization remains bounded and queries retain UUID selection
      result: pass
      notes: The package-backed scale lane verifies 60-item pages, zero observable PhotoAsset objects, bounded thumbnail decoding, index-side filtering/sorting, and UUID selection at 1k/10k/100k.
    - criterion: Interactive work wins shared scheduler admission and package commits remain single-writer
      result: pass
      notes: ImageWorkScheduler package I/O lanes yield under editor/active-thumbnail contention; the 100k lane verifies editor admission, positive yielding, one concurrent writer, and all revisions committed.
    - criterion: Package is canonical and local projection/cache is rebuildable
      result: pass
      notes: Immutable package edit sidecars are written before SwiftData projection updates; deleting/rebuilding the local projection reproduces the exact document and coalesced persistence remains one revision.
    - criterion: Regression and required verification lanes pass
      result: pass
      notes: swift build, focused Phase 3/package/deletion/persistence tests 46/46, serial 375/375, lane audit, dg validate, and git diff --check pass. Fast lane reaches all 987 tests but has four unrelated pre-existing failures documented in KRMA-409/KRMA-410.
  checks_run:
    - swift build
    - swift test --no-parallel --filter LibraryQueryControllerTests|PackageEditProjectionTests|ImageWorkSchedulerTests|LibraryDeletionTests|EditPersistenceIntegrationTests|PortablePackageEndToEndRegressionTests
    - scripts/ci-tests.sh serial
    - scripts/ci-tests.sh fast
    - dg validate --json
    - git diff --check
  findings:
    - scripts/ci-tests.sh fast has four unrelated pre-existing asynchronous/environmental failures in AutoAdjustmentTests, ExportCoordinatorTests, LUTWorkflowTests, and MaskingWorkspaceTests; all changed and Phase 3-focused suites pass.
  fixes:
    - Added package-backed edit projection behavior, scale/concurrency regression coverage, optional benchmark lane registration, and comparison documentation.
  verification_commits:
    - a95c454
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-13T14:59:25.580Z
  session: 01MTZXO6E7BZEP03AX
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - library
  - architecture
  - performance
  - index
created: 2026-09-12T19:19:22.252Z
updated: 2026-09-13T14:59:25.582Z
depends_on:
  - KRMA-391
  - KRMA-389
  - KRMA-406
  - KRMA-407
  - KRMA-408
  - KRMA-409
  - KRMA-410
order: zzzyq
board: product
commits:
  - a95c454
---

## Objective

Make a large package usable without materialising the entire library, while keeping the package as
truth and ensuring package I/O yields to interactive editing.

## Dependencies

- KRMA-391 — package records and membership summaries must be stable before an index projection is
  introduced.
- KRMA-389 — scale generator and baseline are required for the 100,000-asset exit gate.

## Scope

Add `LibraryQueryController` with value-summary pages of roughly 500 assets, UUID-keyed selection,
index-side filtering/sorting, progressive first-page publication, bounded thumbnail materialisation,
automatic index rebuild, and `EditDocumentStore`/`EditPersistenceCoordinator` demotion from canonical
truth to projection. Extend `ImageWorkScheduler` with package I/O lanes; do not add a second
scheduler. Preserve coalesced edit persistence and existing render/thumbnail priority behavior.

## Acceptance criteria

- [ ] Warm launch reads the first page from the index without walking asset directories, parsing XMP,
  or reading originals; missing/corrupt index rebuilds from membership shards and publishes the first
  page before the full rebuild completes.
- [ ] A 100,000-asset library materialises neither 100,000 observable objects nor 100,000 decoded
  thumbnails; filtering/sorting stays in the index and selection is UUID-based.
- [ ] Visible/active editor work is not queued behind import, index rebuild, validation, or
  maintenance; background work yields under editor contention and package commits remain single-writer.
- [ ] The package remains the sole canonical copy of edits/metadata; deleting the local index loses
  no user data.
- [ ] Scale, concurrency, memory, scheduler fairness, edit persistence, relocation, render, and
  deletion regression tests pass without changing KRMA-371 behavior.
- [ ] `swift build`, applicable fast/serial lanes, `dg validate`, and `git diff --check` pass.

## Verification lane

Large-library performance/concurrency lane at 1k/10k/100k assets, plus the existing render/UI
regression lanes. Capture p95 and p99.9 results against KRMA-389's baseline.

### Comment — codex @ 2026-09-13T14:59:25.156Z

Implemented and integrated Phase 3 in commit a95c454. The shipped query/index path provides value-summary paging with UUID selection, index-side filtering/sorting, cold first-page publication and automatic rebuild; package-backed EditDocumentStore keeps immutable package sidecars canonical while SwiftData is a rebuildable projection; ImageWorkScheduler package-I/O lanes preserve editor/thumbnail priority and single-writer commits; and the 1k/10k/100k regression report is documented against the KRMA-389 baseline. Verification: swift build; focused Phase 3/package/deletion/persistence suites 46/46; scripts/ci-tests.sh serial 375/375; scripts/ci-tests.sh verify; git diff --check. scripts/ci-tests.sh fast reached 987 tests but reproduced four unrelated pre-existing Auto/Export/LUT/Masking failures documented in the dependent verification reports.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-13T14:59:25.580Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Warm launch and cold index rebuild provide progressive, index-only paged library access (pass) — LibraryIndexSession reads a valid local projection without asset directories and rebuilds corrupt/missing indexes from membership shards, publishing the first page before completion.
- [x] 100,000-asset materialization remains bounded and queries retain UUID selection (pass) — The package-backed scale lane verifies 60-item pages, zero observable PhotoAsset objects, bounded thumbnail decoding, index-side filtering/sorting, and UUID selection at 1k/10k/100k.
- [x] Interactive work wins shared scheduler admission and package commits remain single-writer (pass) — ImageWorkScheduler package I/O lanes yield under editor/active-thumbnail contention; the 100k lane verifies editor admission, positive yielding, one concurrent writer, and all revisions committed.
- [x] Package is canonical and local projection/cache is rebuildable (pass) — Immutable package edit sidecars are written before SwiftData projection updates; deleting/rebuilding the local projection reproduces the exact document and coalesced persistence remains one revision.
- [x] Regression and required verification lanes pass (pass) — swift build, focused Phase 3/package/deletion/persistence tests 46/46, serial 375/375, lane audit, dg validate, and git diff --check pass. Fast lane reaches all 987 tests but has four unrelated pre-existing failures documented in KRMA-409/KRMA-410.
Checks run:
- swift build
- swift test --no-parallel --filter LibraryQueryControllerTests|PackageEditProjectionTests|ImageWorkSchedulerTests|LibraryDeletionTests|EditPersistenceIntegrationTests|PortablePackageEndToEndRegressionTests
- scripts/ci-tests.sh serial
- scripts/ci-tests.sh fast
- dg validate --json
- git diff --check
Findings:
- scripts/ci-tests.sh fast has four unrelated pre-existing asynchronous/environmental failures in AutoAdjustmentTests, ExportCoordinatorTests, LUTWorkflowTests, and MaskingWorkspaceTests; all changed and Phase 3-focused suites pass.
Fixes:
- Added package-backed edit projection behavior, scale/concurrency regression coverage, optional benchmark lane registration, and comparison documentation.
Verification commits:
- a95c454
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTZXO6E7BZEP03AX
Summary: Completed Phase 3 library queries, index projection, canonical package-backed edit persistence, unified package I/O scheduling, and the 100k scale/concurrency gate.
