---
id: KRMA-888
title: Move post-deletion cleanup fan-out from AppViewModel into LibraryDeletionCoordinator
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: LibraryDeletionCoordinator owns the post-deletion cleanup fan-out through a narrow destination and returns active-photo and messaging outcomes.
      result: pass
      notes: Reviewed cleanup sequencing and the cleanup destination; no AppViewModel back-reference was introduced.
    - criterion: Focused tests exercise cleanup order, partial failures, and active-photo outcomes without constructing AppViewModel.
      result: pass
      notes: LibraryDeletionCoordinatorTests covers ordered cleanup callbacks, partial and full failure messaging, and deleted-active-photo outcomes with and without a remaining selection.
    - criterion: AppViewModel remains a thin integration layer and applies the outcome without behavior changes.
      result: pass
      notes: The root applies the active-photo and message values; cache invalidation is awaited before that decision.
    - criterion: Architecture ownership and line-count documentation are updated, with the AppViewModel ceiling just above its current size.
      result: pass
      notes: docs/APP_ARCHITECTURE.md reports 5,105 lines; PackageSettingsTests uses a 5,120-line ceiling.
    - criterion: swift build and scripts/ci-tests.sh fast pass; run serial CI only if render or UI paths are touched, and do not run display-bound capture benchmarks.
      result: pass
      notes: Build and fast CI passed. Serial CI was not required because the change does not touch render or UI paths. No display-bound benchmark was run.
  checks_run:
    - swift build — passed (exit 0)
    - scripts/ci-tests.sh fast — passed (exit 0; 1,707 required fast tests)
    - Independent review of deletion coordinator, focused tests, AppViewModel integration, and architecture/line-count documentation — passed
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T20:00:14.075Z
  session: 01MV48VZMI5R0RVKZD
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - maintainability
created: 2026-10-11T17:09:57.336Z
updated: 2026-10-11T20:00:14.078Z
blockers: []
order: zzq
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T19:54:29.730Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

Child of KRMA-460. AppViewModel.swift is 5,403 lines (ceiling test: PackageSettingsTests.testAppViewModelDoesNotRegrow at 5,500). Extract workflow *ownership*, not just a file split. Keep AppViewModel the composition root and sole owner of the published EditDocument (docs/APP_ARCHITECTURE.md). Swift 6, no escape hatches, no broad AppViewModel back-reference: the new type takes a narrow protocol or closures and returns value outcomes that the root applies (pattern: LookSelectionCoordinator, ExportWorkflowCoordinator). Locate code by function name; line numbers drift. Run serially with other KRMA-460 children, since they edit the same file.

## Scope
`deleteLibraryItems` (~60 lines of orchestration, plus `clearActiveSourceAfterLibraryDeletion`) fans out cleanup after LibraryDeletionCoordinator.delete: edited-thumbnail removal, thumbnail frame store removal, editor session removal, collection removal, portable selection sync, preview-cache identity invalidation, Thumbnails/engine cache invalidation, active-photo handling, and status messaging.

## Plan
Have LibraryDeletionCoordinator (111 lines today) own the sequencing through a narrow cleanup destination (protocol or closures) and return an outcome for the root to apply to the active photo and status/error presentation. Preserve ordering: the engine/preview cache invalidations are awaited before the active-photo decision, and editor sessions are removed so undo snapshots are not retained. Extend LibraryDeletionCoordinatorTests to assert ordering, partial-failure messaging, and the deleted-active-photo cases (next selection exists vs clear source).

## Out of scope
Delete confirmation UI state, the request/confirm methods, source clearing internals beyond calling the existing method.

Acceptance: (1) new/extended coordinator owns the listed state and logic; (2) focused tests that do not construct AppViewModel; (3) AppViewModel keeps thin forwarders only, with no behavior change; (4) docs/APP_ARCHITECTURE.md ownership table and the line count in its AppViewModel paragraph updated, and the PackageSettingsTests ceiling lowered to just above the new size; (5) swift build and scripts/ci-tests.sh fast pass, plus scripts/ci-tests.sh serial if render/UI paths are touched. Do not run the display-bound capture benchmarks (CLAUDE.md).

## Agent log

- 2026-10-11T20:00:14.075Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] LibraryDeletionCoordinator owns the post-deletion cleanup fan-out through a narrow destination and returns active-photo and messaging outcomes. (pass) — Reviewed cleanup sequencing and the cleanup destination; no AppViewModel back-reference was introduced.
- [x] Focused tests exercise cleanup order, partial failures, and active-photo outcomes without constructing AppViewModel. (pass) — LibraryDeletionCoordinatorTests covers ordered cleanup callbacks, partial and full failure messaging, and deleted-active-photo outcomes with and without a remaining selection.
- [x] AppViewModel remains a thin integration layer and applies the outcome without behavior changes. (pass) — The root applies the active-photo and message values; cache invalidation is awaited before that decision.
- [x] Architecture ownership and line-count documentation are updated, with the AppViewModel ceiling just above its current size. (pass) — docs/APP_ARCHITECTURE.md reports 5,105 lines; PackageSettingsTests uses a 5,120-line ceiling.
- [x] swift build and scripts/ci-tests.sh fast pass; run serial CI only if render or UI paths are touched, and do not run display-bound capture benchmarks. (pass) — Build and fast CI passed. Serial CI was not required because the change does not touch render or UI paths. No display-bound benchmark was run.
Checks run:
- swift build — passed (exit 0)
- scripts/ci-tests.sh fast — passed (exit 0; 1,707 required fast tests)
- Independent review of deletion coordinator, focused tests, AppViewModel integration, and architecture/line-count documentation — passed
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV48VZMI5R0RVKZD
Summary: Independent verification passed: build and fast CI passed; no findings or verification fixes.
