---
id: KRMA-937
title: Wire Backup Library… and Restore Library… into the app
type: task
status: done
priority: high
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - library
  - backup
created: 2026-10-13T14:47:47.314Z
updated: 2026-10-13T23:12:12.650Z
parent: KRMA-922
depends_on:
  - KRMA-936
blockers: []
order: zzzzzy
board: product
---

## Objective

Users can back up the open library to a destination of their choice and restore from a backup, from
File menu items, with progress, verification, and clear errors.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M6. Only start if KRMA-936 decided to wire it. The model layer exists:
`PortableLibraryBackup` and `PortableLibraryRestore` in `Sources/KromoraKit/Models/` (read both, and
their tests under `grep -rln "PortableLibraryBackup" Tests`, KRMA-436 added stale-analysis coverage).
The library is owned by `PortableLibrarySession` (writer lease); backup of a live library must not
fight that lease. Dialogs: use the `AppKitFileDialogAdapter`
(`Sources/KromoraKit/Presentation/AppKitFileDialogAdapter.swift`) seam so tests can fake panels.
Menus: `Sources/KromoraKit/Views/MenuCommands.swift`. Coordinator conventions:
`docs/APP_ARCHITECTURE.md` (new workflow = a focused coordinator, composed by `AppViewModel`; do NOT
grow `AppViewModel`, it is at its 5,120-line guard).

## Acceptance criteria

- [ ] New `LibraryBackupCoordinator` (own file in `Sources/KromoraKit/ViewModels/`) owns
      choose-destination → run backup off the main actor → verify → report. It follows the shutdown
      and generation-fencing conventions of the other coordinators (read `ExportCoordinator`).
- [ ] File menu: "Back Up Library…" and "Restore Library from Backup…" (single ellipsis character
      `…`), enabled only when a library is open / always for restore as appropriate.
- [ ] Backup shows progress (reuse the app's existing export/import progress presentation) and is
      cancellable; on completion it reports the backup location and the verification result; a
      failed verification is shown as an error, never as success.
- [ ] Restore never overwrites the open library in place: it restores into a user-chosen new location
      and offers to open it (or tells the user to use Open Library if KRMA-938 exists). Document the choice.
- [ ] Tests (fast lane, fake file dialog + temp-directory package): backup success; cancelled backup
      leaves no partial output at the destination; corrupted backup is reported; restore into an
      existing non-empty folder is refused.
- [ ] `README.md`/`docs/PRODUCT_SCOPE.md` wording matches what shipped; `docs/STORAGE_POLICY.md` has a
      short "Backup and restore" section describing the user-facing flow.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0 (menu/UI tests).

## Implementation notes

Keep sandbox constraints in mind (App Sandbox, user-selected folder grants; see KRMA-818 for the
security-scope lifetime pitfalls) and test only with fakes; do not require the signed app.


### Comment — claude @ 2026-10-13T23:12:11.962Z

Closed unbuilt per ADR-936: backup/restore is post-MVP; manual quit-and-copy is the supported path.
