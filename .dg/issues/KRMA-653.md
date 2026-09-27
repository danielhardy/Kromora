---
id: KRMA-653
title: Make Edit History a single-position undo timeline
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - product
  - ui
  - history
created: 2026-09-27T15:52:35.173Z
updated: 2026-09-27T15:52:59.494Z
order: zzzzq
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
