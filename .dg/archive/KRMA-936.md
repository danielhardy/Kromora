---
id: KRMA-936
title: "DECISION: wire Backup/Restore and Open Library into the app, or drop the claims"
type: task
status: done
priority: urgent
human_review_required: true
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - decision
  - library
created: 2026-10-13T14:47:46.406Z
updated: 2026-10-13T23:12:13.783Z
parent: KRMA-922
blockers: []
order: zzzz
board: product
---

## Objective

Get a human decision on release scope for backup/restore and library selection, and record it so the
follow-up tickets (KRMA-937 wire backup/restore, KRMA-938 open library, KRMA-939 remove claims) can proceed.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M6.

- `PortableLibraryBackup` / `PortableLibraryRestore` (`Sources/KromoraKit/Models/`) are implemented
  and tested but have no callers outside their own files (verify: `grep -rn
  "PortableLibraryBackup\|PortableLibraryRestore" Sources`).
- The library path is fixed: `KromoraStorage.portableLibraryPackageName =
  "Kromora Library.kromoralibrary"` (`Sources/KromoraKit/Models/KromoraStorage.swift` ~L89), under
  `~/Pictures`. There is no Open/New/Move Library UI.
- `App/Info.plist` declares `CFBundleDocumentTypes` (role Editor, rank Owner) for
  `com.kromora.kromoralibrary`, but nothing handles opening one, so double-clicking a library in
  Finder does nothing.
- `README.md` and `docs/PRODUCT_SCOPE.md` list "verified backup/restore" in the MVP and release bar.

## Acceptance criteria

- [ ] The human picks one option for EACH of: (1) Backup/Restore in the MVP: wire it (KRMA-937) or remove
      the claim (KRMA-939); (2) Open/Switch Library: build it (KRMA-938) or remove the document-type
      declaration (KRMA-939).
- [ ] The decision is recorded with `dg decision` (see `dg decision --help`) and linked from this
      ticket; the unselected follow-up tickets are moved to `done`/deleted with a one-line reason.
- [ ] The selected follow-up tickets are moved to `ready`.

## Implementation notes

Human decision required, so use `dg issue block` with action "Choose: wire backup/restore (KRMA-937) or
drop the claim; build Open Library (KRMA-938) or drop the document type (KRMA-939)". Recommendation to present
to the human: wire Backup/Restore (it is already built and tested and the docs promise it); and for
Open Library, ship only the Finder double-click handler plus Open Library… if scope allows, otherwise
remove the document type. Do not start KRMA-937/KRMA-938/KRMA-939 before the decision.

## Agent log

- 2026-10-13T23:12:13.780Z: Decided and recorded in ADR-936: drop verified backup/restore and Open Library from the MVP (KRMA-937, KRMA-938 closed unbuilt); remove claims and document manual copy (KRMA-939); add relaunch-based Settings Choose Library… (KRMA-988).
