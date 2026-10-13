---
id: KRMA-955
title: "Menu cleanups: consistent ellipsis, clearer import/refresh titles"
type: task
status: ready
priority: low
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - menus
  - ux
created: 2026-10-13T14:48:05.615Z
updated: 2026-10-13T20:17:38.171Z
parent: KRMA-922
depends_on:
  - KRMA-924
  - KRMA-925
blockers: []
order: zs
board: product
---

## Objective

Make menu titles consistent and accurate for a package-backed library.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S11 (bullets 3-4). `Sources/KromoraKit/Views/MenuCommands.swift`:

- Titles mix three dots and the HIG ellipsis character: "Open Image...", "Choose Look Folder...",
  "Import Look...", "Import from Photos...", "Open Source Folder...", "Import from Removable
  Media...", "Export...", "Export Originals..." vs "Copy Edits…", "Derive Look from JPG…",
  "Save as Look/LUT…", "Keyboard Shortcuts…".
- "Open Source Folder…" actually IMPORTS a folder into the library (an import source), and "Refresh
  Library" (⌘R) is a leftover from the folder-backed design: the package library is the source of
  truth and indexes are projections (see `CLAUDE.md`, `docs/STORAGE_POLICY.md`).
- Titles may also appear in `KeyboardShortcutReferenceView`, tests (`MenuCommandTests`) and docs
  (`grep -rn "Open Source Folder\|Refresh Library" Sources Tests docs README.md`).

## Acceptance criteria

- [ ] All menu titles that open a dialog or need more input end with the single ellipsis character `…`
      (U+2026) and none use `...`. A `MenuCommandTests` assertion fails if a title in the menu model
      contains `...`.
- [ ] "Open Source Folder…" is renamed "Import Folder…" (keep its shortcut, notification and handler
      names unless trivial to rename; the user-visible string and docs change).
- [ ] "Refresh Library" is investigated: find what `.refreshSourceFolder` does today. If it is a no-op
      or only meaningful for legacy folder mode, remove the item and its ⌘R shortcut (⌘R becomes free);
      if it still has a purpose (rescan import source), rename it to say what it does and keep it.
      Record the decision and evidence in the review comment.
- [ ] All doc/test references updated; no stale titles (`grep` shows none).
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0.
