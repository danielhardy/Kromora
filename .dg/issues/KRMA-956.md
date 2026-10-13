---
id: KRMA-956
title: "DECISION: shortcut conventions (Delete → ⌘⌫, ⌘S, ⌘D) per Photos/Mac conventions"
type: task
status: backlog
priority: low
human_review_required: true
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - decision
  - menus
  - keyboard
created: 2026-10-13T14:48:06.569Z
updated: 2026-10-13T14:48:36.381Z
parent: KRMA-922
depends_on:
  - KRMA-924
  - KRMA-920
blockers: []
order: zy
board: product
---

## Objective

Decide and implement conventional shortcuts for destructive and save-like commands.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S11 (bullets 1-2). `Sources/KromoraKit/Views/MenuCommands.swift`:

- "Delete Selected Photos" uses bare Delete (`.keyboardShortcut(.delete)`); Photos.app uses ⌘⌫ for
  destructive removal, bare Delete is easy to hit by accident and also edits text.
- ⌘S runs Export (users expect Save; Photos uses ⌘E-style export; Lightroom uses ⌘⇧E); ⌘D runs
  "Derive Look from JPG…" (⌘D is Duplicate in most Mac apps).
- KRMA-920's key surface also handles Delete/Forward Delete for retouch spots and grid removal, so
  any change must keep the `KeyboardCommandRouter` and the shortcut reference sheet in sync (they are
  generated from one table; a test fails if they disagree).

## Acceptance criteria

- [ ] A comment lists the three proposed remaps with reasoning; the human approves or amends them
      (record with `dg decision`).
- [ ] Approved remaps are implemented in the single shortcut table (not scattered), including the
      reference sheet; Delete in the grid still works when the human keeps bare Delete as an
      additional binding.
- [ ] Tests: the table has no duplicate key equivalents across menus (add this assertion if missing);
      the moved bindings fire the same notifications/commands.
- [ ] `docs/` and `README.md` shortcut lists updated.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0.

## Implementation notes

Human decision: block with action "Approve or amend the shortcut remaps". Do the code only after
approval. Depends on the Undo/Redo move and KRMA-920.
