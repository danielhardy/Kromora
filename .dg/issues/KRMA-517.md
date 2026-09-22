---
id: KRMA-517
title: Make import outcome accounting truthful across every import entry point
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Injected package failures, duplicates, nil transfers, cancellation, and successes produce truthful counts and actionable messages for every import entry point.
      result: pass
      notes: ImportOutcomeSummary is used by Photos, folder, file-drop, promise-drop, removable-media, openImage(data:), and URL batch imports; focused outcome tests cover inserted, duplicate, failed, nil/cancellation behavior.
    - criterion: Late success, nil, error, or cancellation from import A cannot change import B progress or final status.
      result: pass
      notes: Operation IDs fence Photos provider completions, promise redemption, removable discovery/scan/validation, Photos finish/shutdown, and AppViewModel result presentation; regression test covers a late cancelled provider result.
    - criterion: Failure reasons are retained in the summary and are not routed through legacy collection bookkeeping in package mode.
      result: pass
      notes: Package insertion failures return an explicit outcome, summaries retain source/reason text, and AppViewModel's legacy failure destination is guarded out in package mode.
    - criterion: Existing duplicate and idempotency behavior remains intact.
      result: pass
      notes: PortablePackageImportTests duplicate coverage and the existing portable Photos batch/idempotency tests pass.
    - criterion: Focused Photos/import tests, fast lane, and serial lane pass.
      result: pass
      notes: "Focused import suite: 29/29; fast lane: 1126/1126; serial lane: 409/409 with one existing RAW-fixture skip."
  checks_run:
    - swift build
    - git diff --check
    - swift test --filter 'PhotosImportTests|LibraryMediaWorkflowCoordinatorTests|PortablePackageImportTests'
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - dg validate
  findings:
    - dg validate reports existing unknown historical gpt-5.6-luna model-name warnings; validation passes.
  fixes:
    - Added ImportOutcomeSummary and explicit Photos insertion outcomes.
    - Unified package result accounting and actionable status presentation across import entry points.
    - Added operation-ID fencing for asynchronous import workflows and late result paths.
    - Removed the deprecated PhotosImportCoordinator view-model initializer and compatibility progress shim.
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-21T21:52:36.057Z
  session: 01MUBRDAL41Y3U33HC
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - correctness
  - import
created: 2026-09-21T20:32:59.030Z
updated: 2026-09-21T21:52:36.058Z
depends_on:
  - KRMA-516
estimate: 8
order: a0
board: product
---

## Objective

Make every import path report the actual inserted, duplicate, skipped, and failed outcomes from the package layer, with operation fencing so stale asynchronous results cannot mutate a later import.

## Context and evidence

PhotosImportCoordinator.append currently increments imported after a destination method that returns Void, so it cannot know whether the package write succeeded. In package mode AppViewModel catches failures and records them through the legacy collection path instead of the coordinator's progress state. PortablePackageImportResult failures and duplicates are dropped by folder open, file drop, promise drop, removable-media, and openImage(data:) paths; removable-media hard-codes skipped to zero. Nil-data and generic-error branches can also record into a newer operation after a superseded import.

This defect is especially visible after the lease expiry described by CQ-01: package writes fail while the UI can still report imported items.

## Scope

- Change PhotosImportDestination.insertPhotosImport to return an explicit outcome enum such as inserted(assetID), duplicate(existing), or failed(reason).
- Introduce one ImportOutcomeSummary built from PortablePackageImportResult and use it for Photos, folder, file-drop, promise-drop, removable-media, and openImage(data:) entry points.
- Pass real imported, duplicate, skipped, failed counts and failure reasons through LibraryMediaWorkflowCoordinator.finishImport and status presentation.
- Fence every post-await success, nil, error, cancellation, and finish mutation with the operation ID.
- Remove the deprecated PhotosImportCoordinator view-model initializer and setProgressForCompatibility shim; update tests to use a fake destination/provider.

## Acceptance criteria

- [ ] Injected package failures, duplicates, nil transfers, cancellation, and successes produce truthful counts and actionable messages for every import entry point.
- [ ] Late success, nil, error, or cancellation from import A cannot change import B's progress or final status.
- [ ] Failure reasons are retained in the summary and are not routed through legacy collection bookkeeping in package mode.
- [ ] Existing duplicate and idempotency behavior remains intact.
- [ ] Focused Photos/import tests, fast lane, and serial lane pass.

## Dependencies and coordination

Depends on CQ-01's lease/error contract. Coordinate with CQ-03 because the result value and progress stream become the handoff between the package worker and the main actor. Do not start CQ-03's concurrency migration in this ticket.

## Likely files and checks

PhotosImportCoordinator.swift, AppViewModel import entry points, LibraryMediaWorkflowCoordinator.swift, PortablePackageImportResult consumers, and PhotosImportTests. Use PortablePackageFaultInjector and a package fixture rather than real Photos or removable media.

## Agent log

- 2026-09-21T21:52:36.057Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Injected package failures, duplicates, nil transfers, cancellation, and successes produce truthful counts and actionable messages for every import entry point. (pass) — ImportOutcomeSummary is used by Photos, folder, file-drop, promise-drop, removable-media, openImage(data:), and URL batch imports; focused outcome tests cover inserted, duplicate, failed, nil/cancellation behavior.
- [x] Late success, nil, error, or cancellation from import A cannot change import B progress or final status. (pass) — Operation IDs fence Photos provider completions, promise redemption, removable discovery/scan/validation, Photos finish/shutdown, and AppViewModel result presentation; regression test covers a late cancelled provider result.
- [x] Failure reasons are retained in the summary and are not routed through legacy collection bookkeeping in package mode. (pass) — Package insertion failures return an explicit outcome, summaries retain source/reason text, and AppViewModel's legacy failure destination is guarded out in package mode.
- [x] Existing duplicate and idempotency behavior remains intact. (pass) — PortablePackageImportTests duplicate coverage and the existing portable Photos batch/idempotency tests pass.
- [x] Focused Photos/import tests, fast lane, and serial lane pass. (pass) — Focused import suite: 29/29; fast lane: 1126/1126; serial lane: 409/409 with one existing RAW-fixture skip.
Checks run:
- swift build
- git diff --check
- swift test --filter 'PhotosImportTests|LibraryMediaWorkflowCoordinatorTests|PortablePackageImportTests'
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- dg validate
Findings:
- dg validate reports existing unknown historical gpt-5.6-luna model-name warnings; validation passes.
Fixes:
- Added ImportOutcomeSummary and explicit Photos insertion outcomes.
- Unified package result accounting and actionable status presentation across import entry points.
- Added operation-ID fencing for asynchronous import workflows and late result paths.
- Removed the deprecated PhotosImportCoordinator view-model initializer and compatibility progress shim.
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MUBRDAL41Y3U33HC
Summary: Unified truthful import outcome accounting and operation fencing across Photos, folder, file-drop, promise-drop, removable-media, and data imports.
