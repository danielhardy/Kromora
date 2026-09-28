---
id: KRMA-653
title: Make Edit History a single-position undo timeline
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Single current-position marker by revision identity, even for equal documents
      result: pass
      notes: InfoInspectorView keys isCurrent off durableCurrentEditRevision (revision identity) rather than document equality; store-level test covers equal-document revisions (first/second) retaining distinct identity.
    - criterion: Selecting a history step navigates/renders without appending a new revision
      result: pass
      notes: AppViewModel.restoreEditRevision now calls EditDocumentStore.selectRevision (PortableLibraryPackage.selectEditRevision), which only updates currentRevision pointers in a transaction; applyHistoryDocument is called with persist:false so no new revision is appended. Verified in testHistoryNavigationBranchesWithoutWritingAndPreservesNamedSnapshots (history count unchanged after selectRevision).
    - criterion: Editing after navigating to an earlier step branches; later ordinary steps disappear from active/redo timeline
      result: pass
      notes: appendEditRevision now filters editHistory.edits to <= currentRevision plus any forward named snapshots before appending the new revision; EditorDocumentCoordinator.adoptHistoryPosition rebuilds the in-memory undo stack from only prior (non-snapshot) documents so redo cannot reach the discarded branch.
    - criterion: Normal edits still create history steps; Undo/Redo and Edit History agree on current position
      result: pass
      notes: Ordinary save path (EditDocumentStore.save -> appendEditRevision) unchanged aside from branch filtering; durableCurrentEditRevision is refreshed alongside durableEditHistory after every navigation/save.
    - criterion: Named snapshots remain independently restorable and are not erased by navigation/branching
      result: pass
      notes: "Branch-retention logic explicitly re-adds forward pointers whose revision has snapshotName != nil. Covered by test: snapshot at revision 3 survives branching from revision 1 and remains independently selectable after reopening the package."
    - criterion: "Focused tests added: navigation without write, branch truncation, single current marker, reopen behavior"
      result: pass
      notes: testHistoryNavigationBranchesWithoutWritingAndPreservesNamedSnapshots covers navigation-without-write, branch truncation, snapshot retention, and reopen. UI-level 'single marker' behavior is exercised structurally via durableCurrentEditRevision identity rather than a dedicated InfoInspectorView test; no regression risk found on inspection.
  checks_run:
    - swift build
    - swift test --filter PackageEditProjectionTests (5/5 passed)
    - swift test --filter PackageSettingsTests (4/4 passed, Swift 6 zero-escape-hatch gate)
    - scripts/ci-tests.sh fast (1277/1277 passed)
    - scripts/ci-tests.sh serial (430/430 passed, 1 skipped)
    - scripts/ci-tests.sh warning-gate (zero-warning build, passed)
    - scripts/ci-tests.sh verify (lane coverage audit, passed)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T17:13:21.487Z
  session: 01MUK2HO7E103RG9FM
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - product
  - ui
  - history
created: 2026-09-27T15:52:35.173Z
updated: 2026-09-28T14:41:33.558Z
blockers: []
order: jte79kso
board: product
---

## Objective

Make Edit History behave like a navigable undo timeline. Selecting an earlier step moves the current position to that saved edit so the user can inspect it. Merely moving through history must not create another edit. If the user edits from an earlier step, discard the later steps from the active timeline, just as making a new edit after Undo clears Redo.

## Context

The current Edit History list compares each revision's `EditDocument` to the current document and puts a checkmark on every equal entry. Identical documents at different revisions can therefore show multiple checkmarks, and the UI does not clearly communicate the current position. Selecting a row calls `restoreEditRevision`, which applies the document and immediately saves it as a new revision. That makes browsing history look like an edit and leaves the former forward steps in the list.

Relevant implementation:

- `Sources/KromoraKit/Views/InfoInspectorView.swift` — Edit History rows and current-state checkmark.
- `Sources/KromoraKit/ViewModels/AppViewModel.swift` — durable history loading, `restoreEditRevision`, and document application/persistence.
- `Sources/KromoraKit/Models/EditDocumentStore.swift` and `Sources/KromoraKit/Models/PortableLibraryPackage.swift` — revision storage and history reads/writes.
- `Sources/KromoraKit/Models/EditHistory.swift` and `Sources/KromoraKit/ViewModels/EditorDocumentCoordinator.swift` — in-memory undo/redo semantics to keep aligned with the durable timeline.
- `Tests/KromoraKitTests/PackageEditProjectionTests.swift` and history-related tests — revision, snapshot, branching, and reopen coverage.

## Acceptance criteria

- [ ] Edit History clearly identifies one current position by revision identity, even if multiple revisions contain equal documents. Never show multiple current markers at once; use a selected row/current label or another clear single-position treatment.
- [ ] Selecting an existing history step navigates to and renders that saved state without appending a new edit revision solely because it was selected. The selected position and current edit remain coherent after saving and reopening the library.
- [ ] Editing after navigating to an earlier step starts a new branch at that step. Later ordinary edit steps disappear from the active history timeline and are no longer available as forward/redo steps; they must not remain presented as the current future of the edit sequence.
- [ ] Normal edits still create history steps, and Undo/Redo and Edit History navigation agree about the current position and which forward steps remain available.
- [ ] Preserve explicitly named snapshots as independently restorable saved states; navigating to or restoring one must not accidentally erase the snapshot itself.
- [ ] Retain photo isolation, package durability, and the existing edit-history refresh behavior. Add/update focused tests for navigation without a write, branch truncation after an edit, a single current marker when documents compare equal, and history behavior after reopening.

## Implementation notes

Treat this as a history model and persistence behavior change as well as a UI cleanup. Define the active timeline/current-position representation explicitly; do not infer the selected step solely by comparing document values. The package currently appends immutable revision files, so branching may update which revisions belong to the active timeline while retaining immutable backing data as needed by package recovery or named snapshots. That storage choice must not leave discarded forward steps visible or redoable. Preserve the named snapshot workflow from KRMA-604.

### Comment — codex @ 2026-09-27T17:02:59.938Z

Implemented single-position edit history navigation with revision identity, durable selection without appending, branch truncation of later ordinary edits, and named snapshot retention. Added package branch/navigation/reopen coverage, including equal-document revisions. Checks: swift test --filter PackageEditProjectionTests (5 passed); focused branch/reopen test passed. Commit: d17983d.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T17:13:21.487Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Single current-position marker by revision identity, even for equal documents (pass) — InfoInspectorView keys isCurrent off durableCurrentEditRevision (revision identity) rather than document equality; store-level test covers equal-document revisions (first/second) retaining distinct identity.
- [x] Selecting a history step navigates/renders without appending a new revision (pass) — AppViewModel.restoreEditRevision now calls EditDocumentStore.selectRevision (PortableLibraryPackage.selectEditRevision), which only updates currentRevision pointers in a transaction; applyHistoryDocument is called with persist:false so no new revision is appended. Verified in testHistoryNavigationBranchesWithoutWritingAndPreservesNamedSnapshots (history count unchanged after selectRevision).
- [x] Editing after navigating to an earlier step branches; later ordinary steps disappear from active/redo timeline (pass) — appendEditRevision now filters editHistory.edits to <= currentRevision plus any forward named snapshots before appending the new revision; EditorDocumentCoordinator.adoptHistoryPosition rebuilds the in-memory undo stack from only prior (non-snapshot) documents so redo cannot reach the discarded branch.
- [x] Normal edits still create history steps; Undo/Redo and Edit History agree on current position (pass) — Ordinary save path (EditDocumentStore.save -> appendEditRevision) unchanged aside from branch filtering; durableCurrentEditRevision is refreshed alongside durableEditHistory after every navigation/save.
- [x] Named snapshots remain independently restorable and are not erased by navigation/branching (pass) — Branch-retention logic explicitly re-adds forward pointers whose revision has snapshotName != nil. Covered by test: snapshot at revision 3 survives branching from revision 1 and remains independently selectable after reopening the package.
- [x] Focused tests added: navigation without write, branch truncation, single current marker, reopen behavior (pass) — testHistoryNavigationBranchesWithoutWritingAndPreservesNamedSnapshots covers navigation-without-write, branch truncation, snapshot retention, and reopen. UI-level 'single marker' behavior is exercised structurally via durableCurrentEditRevision identity rather than a dedicated InfoInspectorView test; no regression risk found on inspection.
Checks run:
- swift build
- swift test --filter PackageEditProjectionTests (5/5 passed)
- swift test --filter PackageSettingsTests (4/4 passed, Swift 6 zero-escape-hatch gate)
- scripts/ci-tests.sh fast (1277/1277 passed)
- scripts/ci-tests.sh serial (430/430 passed, 1 skipped)
- scripts/ci-tests.sh warning-gate (zero-warning build, passed)
- scripts/ci-tests.sh verify (lane coverage audit, passed)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUK2HO7E103RG9FM
