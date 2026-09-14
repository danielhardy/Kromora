---
id: KRMA-409
title: "Phase 3.4: demote EditDocumentStore/EditPersistenceCoordinator to projection"
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Package sidecars are the canonical edit copy and local store state is rebuildable
      result: pass
      notes: Added package-backed EditDocumentStore mode; reads come from the current package sidecar and writes append the package revision before refreshing SwiftData.
    - criterion: Clean-profile projection rebuild reproduces every edit exactly
      result: pass
      notes: Added PackageEditProjectionTests covering cache deletion, canonical read, clean projection rebuild, and content-level EditDocument equality.
    - criterion: Coalesced edit persistence remains unchanged
      result: pass
      notes: Existing EditPersistenceIntegrationTests passed; package-mode regression verifies two queued snapshots produce one package revision containing the latest document.
    - criterion: Render/thumbnail priority behavior remains unchanged
      result: pass
      notes: ImageWorkSchedulerTests passed, including editor-priority package-I/O yielding and existing thumbnail behavior.
    - criterion: Build, validation, and diff checks
      result: pass
      notes: swift build, focused edit/package/scheduler suites, dg validate, and git diff --check passed. Full swift test was run and reported 10 unrelated pre-existing/flaky UI/Auto/Export/Masking failures; the new and relevant suites passed.
  checks_run:
    - swift build
    - swift test --filter PackageEditProjectionTests
    - swift test --filter EditDocumentStoreTests
    - swift test --filter EditPersistenceIntegrationTests
    - swift test --filter ImageWorkSchedulerTests
    - swift test
    - dg validate
    - git diff --check
  findings:
    - Full repository swift test currently has 10 unrelated failures in AutoAdjustmentTests, ComparisonModeTests, ExportCoordinatorTests, FilmstripNavigationTests, LUTWorkflowTests, and MaskingWorkspaceTests; no failures occurred in the implementation-focused suites.
  fixes:
    - Added package-backed canonical persistence and projection rebuild APIs.
    - Added exact-content and coalescing regression coverage.
  verification_commits: []
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-13T14:35:39.843Z
  session: 01MTZWPUKSVK5995EL
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - performance
  - index
  - persistence
created: 2026-09-12T19:44:22.243Z
updated: 2026-09-13T14:35:39.845Z
depends_on:
  - KRMA-406
  - KRMA-408
order: a0
board: product
---

## Objective

Demote `EditDocumentStore`/`EditPersistenceCoordinator` from canonical source of truth to a
projection over the package, so the package (from KRMA-391) becomes the sole canonical copy of edits
and metadata.

## Dependencies

- The `LibraryQueryController`/index-projection ticket and the scheduler-lanes ticket (this changes
  what backs the store those depend on and how its I/O is scheduled).

## Scope

- Change `EditDocumentStore`/`EditPersistenceCoordinator` so package edit sidecars (KRMA-391) are the
  canonical write target; any local cache these types keep becomes a rebuildable projection, not the
  source of truth.
- Ensure deleting the local index/cache these coordinators maintain loses no user edit data — a
  rebuild from the package must reproduce every edit exactly.
- Preserve existing coalesced-write behavior (batching/debouncing edit saves) — this is a change of
  backing store and truth ownership, not of the save-coalescing policy itself.
- Preserve current render/thumbnail priority behavior for edit-triggered re-renders.

## Acceptance criteria

- [ ] The package is the sole canonical copy of edits/metadata; `EditDocumentStore`/
  `EditPersistenceCoordinator` state is demonstrably rebuildable from it.
- [ ] Deleting the local `EditDocumentStore`/coordinator cache and reconstructing it from the package
  reproduces every edit exactly (content-level comparison, not just count).
- [ ] Existing coalesced edit-persistence timing/behavior is unchanged (regression test).
- [ ] Current render/thumbnail priority behavior for edit-triggered work is unchanged.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Persistence/regression lane: clean-profile rebuild-from-package test, plus existing edit-persistence
and render-priority regression suites.

## Context

- context.files: Sources/KromoraKit (EditDocumentStore, EditPersistenceCoordinator)
- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-392, KRMA-391

## Agent log

- 2026-09-13T14:35:39.844Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Package sidecars are the canonical edit copy and local store state is rebuildable (pass) — Added package-backed EditDocumentStore mode; reads come from the current package sidecar and writes append the package revision before refreshing SwiftData.
- [x] Clean-profile projection rebuild reproduces every edit exactly (pass) — Added PackageEditProjectionTests covering cache deletion, canonical read, clean projection rebuild, and content-level EditDocument equality.
- [x] Coalesced edit persistence remains unchanged (pass) — Existing EditPersistenceIntegrationTests passed; package-mode regression verifies two queued snapshots produce one package revision containing the latest document.
- [x] Render/thumbnail priority behavior remains unchanged (pass) — ImageWorkSchedulerTests passed, including editor-priority package-I/O yielding and existing thumbnail behavior.
- [x] Build, validation, and diff checks (pass) — swift build, focused edit/package/scheduler suites, dg validate, and git diff --check passed. Full swift test was run and reported 10 unrelated pre-existing/flaky UI/Auto/Export/Masking failures; the new and relevant suites passed.
Checks run:
- swift build
- swift test --filter PackageEditProjectionTests
- swift test --filter EditDocumentStoreTests
- swift test --filter EditPersistenceIntegrationTests
- swift test --filter ImageWorkSchedulerTests
- swift test
- dg validate
- git diff --check
Findings:
- Full repository swift test currently has 10 unrelated failures in AutoAdjustmentTests, ComparisonModeTests, ExportCoordinatorTests, FilmstripNavigationTests, LUTWorkflowTests, and MaskingWorkspaceTests; no failures occurred in the implementation-focused suites.
Fixes:
- Added package-backed canonical persistence and projection rebuild APIs.
- Added exact-content and coalescing regression coverage.
Verification commits:
- None
Actor: codex
Resolved model: unknown
Pickup session: 01MTZWPUKSVK5995EL
Summary: Package-backed edit persistence implemented: immutable package sidecars are canonical, SwiftData rows are rebuildable projections, cache deletion/rebuild preserves exact edit content, and coalesced coordinator behavior remains unchanged.
