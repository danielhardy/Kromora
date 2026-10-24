---
id: KRMA-938
title: Handle opening .kromoralibrary packages (Finder double-click) and add Open Library…
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
created: 2026-10-13T14:47:48.238Z
updated: 2026-10-24T13:05:10.915Z
parent: KRMA-922
blockers: []
order: zzzzzz
board: product
---

## Objective

Double-clicking a `.kromoralibrary` in Finder (or File › Open Library…) opens that library in the app,
instead of doing nothing.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M6. Only start if KRMA-936 decided to build it. `App/Info.plist` already declares
`CFBundleDocumentTypes` (role Editor, rank Owner) for `com.kromora.kromoralibrary` but there is no
handler. The library location is fixed in `KromoraStorage.portableLibraryPackageName`
(`Sources/KromoraKit/Models/KromoraStorage.swift` ~L89); the session is created at app start by
`AppViewModel` (see `ApplicationShellCoordinator`, `Sources/KromoraKit/ViewModels/`, and
`docs/APP_ARCHITECTURE.md`). A switch must close the current session through the ordered shutdown
path, then open the new one with a writer lease; lease-conflict alerts exist already (see
`PortablePackageTransaction` lease recovery).

## Acceptance criteria

- [ ] `KromoraAppDelegate` implements `application(_:open:)` (or SwiftUI `onOpenURL` on the scene) that
      validates the URL is a package (reuse the package's own validator, do not just check the
      extension) and asks `AppViewModel` to switch libraries.
- [ ] Switching: flush pending writes, ordered shutdown of the current session, open the new package;
      on failure keep or reopen the previous library and show one error.
- [ ] "Open Library…" in the File menu with an `NSOpenPanel` configured to pick the package (through
      `AppKitFileDialogAdapter`, fakeable). The chosen path is remembered across launches using a
      security-scoped bookmark (sandbox), stored with the other durable app settings (see
      `docs/STORAGE_POLICY.md` for what may be stored where).
- [ ] If a library is opened elsewhere the default `~/Pictures` library is untouched.
- [ ] Tests with a fake dialog and temp packages: open valid package; reject an invalid folder; failed
      open restores the previous library; a bookmark round-trips.
- [ ] `docs/STORAGE_POLICY.md` and `docs/APP_ARCHITECTURE.md` describe the active-library selection.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0.

## Implementation notes

Out of scope: New Library…, Move Library…, multiple open libraries. File them as separate backlog
tickets if you think they are needed.


### Comment — claude @ 2026-10-13T23:12:12.178Z

Closed unbuilt per ADR-936: no runtime Open Library or Finder handler; relaunch-based Settings > Choose Library… is KRMA-988.
