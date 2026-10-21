---
id: KRMA-874
title: Extract removable-media import workflow from AppViewModel
type: task
status: verification
priority: low
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - maintainability
created: 2026-10-11T13:33:40.807Z
updated: 2026-10-21T12:34:34.103Z
blockers:
  - id: evt_mv3xjodj_6h0ezh
    type: human
    reason: "Stale premise: removable-media state/workflow already live in LibraryMediaWorkflowCoordinator (7 tests, no AppViewModel, documented). What remains in AppViewModel is thin forwarders plus importRemovableMedia, the root-owned package transaction; extracting it needs a broad back-reference. No code changed."
    action: "Decide: close KRMA-874 as already satisfied, or re-scope (e.g. a narrow-protocol import-admission collaborator shared with folder import, or a different AppViewModel section)."
    created_at: 2026-10-11T14:40:06.439Z
    resolved_at: 2026-10-20T02:49:32.471Z
    resolved_by: cli
order: zzzzzh
board: product
blocked_reason: "Stale premise: removable-media state/workflow already live in LibraryMediaWorkflowCoordinator (7 tests, no AppViewModel, documented). What remains in AppViewModel is thin forwarders plus importRemovableMedia, the root-owned package transaction; extracting it needs a broad back-reference. No code changed."
blocked_action: "Decide: close KRMA-874 as already satisfied, or re-scope (e.g. a narrow-protocol import-admission collaborator shared with folder import, or a different AppViewModel section)."
blocked_from_status: ready
---

Child of KRMA-460 (reopened 2026-10-11: AppViewModel.swift grew from 4,293 lines at KRMA-469 to 5,738). Extract workflow *ownership* into a focused coordinator; do not just split files. Keep AppViewModel the composition root and sole owner of the published EditDocument (see docs/APP_ARCHITECTURE.md). Swift 6, no escape hatches, no broad AppViewModel back-reference from the new collaborator. Not a release blocker. Acceptance: coordinator owns the state and workflow with focused tests that do not construct AppViewModel; AppViewModel keeps thin forwarders; docs/APP_ARCHITECTURE.md ownership table updated; swift build and scripts/ci-tests.sh fast pass. Section: `// MARK: - Removable media import` (~490 lines, not covered by the original plan). Check overlap with LibraryMediaWorkflowCoordinator and PhotosImportCoordinator first.


### Comment — codex @ 2026-10-20T02:49:30.430Z

Human review disposition: close as already satisfied. The acceptance criteria are present in the current tree: LibraryMediaWorkflowCoordinator owns removable-media scan/selection/security-scope/import-request workflow; AppViewModel exposes projections and forwards the resulting request to PackageSourceImportCoordinator for the package transaction; docs/APP_ARCHITECTURE.md records the ownership; LibraryMediaWorkflowCoordinatorTests provide focused coordinator coverage (9 tests). No code changes or tests run during this review. Resuming to verification to clear the stale human blocker.
