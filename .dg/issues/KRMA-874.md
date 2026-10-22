---
id: KRMA-874
title: Extract removable-media import workflow from AppViewModel
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A focused coordinator owns removable-media workflow state and behavior, with tests that do not construct AppViewModel.
      result: pass
      notes: LibraryMediaWorkflowCoordinator owns volume discovery, scanning, selection, membership checks, folder/drop routing, cancellation, and access-scope handoff. LibraryMediaWorkflowCoordinatorTests exercises it directly without AppViewModel.
    - criterion: AppViewModel keeps thin forwards while the package import transaction remains at the application composition boundary.
      result: pass
      notes: AppViewModel forwards selector state/actions and hands a RemovableMediaImportRequest to PackageSourceImportCoordinator. No broad AppViewModel back-reference is introduced.
    - criterion: docs/APP_ARCHITECTURE.md records current ownership boundaries.
      result: pass
      notes: The ownership table and removable-media workflow section describe LibraryMediaWorkflowCoordinator and PackageSourceImportCoordinator responsibilities.
    - criterion: swift build and scripts/ci-tests.sh fast pass.
      result: pass
      notes: Both declared checks exited 0; the fast lane completed all 1,954 required tests.
  checks_run:
    - swift build — exit 0; no warnings.
    - scripts/ci-tests.sh fast — exit 0; all 1,954 required fast tests completed.
    - Source review — checked coordinator lifecycle, task fencing, cancellation, security-scoped access transfer/release, import destination boundary, focused test coverage, and architecture documentation.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-21T15:40:45.248Z
  session: 01MVI9YBLGCNXQFMTA
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - maintainability
created: 2026-10-11T13:33:40.807Z
updated: 2026-10-21T15:40:45.251Z
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

## Agent log

- 2026-10-21T15:40:45.248Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A focused coordinator owns removable-media workflow state and behavior, with tests that do not construct AppViewModel. (pass) — LibraryMediaWorkflowCoordinator owns volume discovery, scanning, selection, membership checks, folder/drop routing, cancellation, and access-scope handoff. LibraryMediaWorkflowCoordinatorTests exercises it directly without AppViewModel.
- [x] AppViewModel keeps thin forwards while the package import transaction remains at the application composition boundary. (pass) — AppViewModel forwards selector state/actions and hands a RemovableMediaImportRequest to PackageSourceImportCoordinator. No broad AppViewModel back-reference is introduced.
- [x] docs/APP_ARCHITECTURE.md records current ownership boundaries. (pass) — The ownership table and removable-media workflow section describe LibraryMediaWorkflowCoordinator and PackageSourceImportCoordinator responsibilities.
- [x] swift build and scripts/ci-tests.sh fast pass. (pass) — Both declared checks exited 0; the fast lane completed all 1,954 required tests.
Checks run:
- swift build — exit 0; no warnings.
- scripts/ci-tests.sh fast — exit 0; all 1,954 required fast tests completed.
- Source review — checked coordinator lifecycle, task fencing, cancellation, security-scoped access transfer/release, import destination boundary, focused test coverage, and architecture documentation.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MVI9YBLGCNXQFMTA
Summary: Independent verification passed: removable-media workflow ownership, package import boundary, focused coordinator tests, and architecture documentation meet acceptance criteria.
