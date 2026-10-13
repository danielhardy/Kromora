---
id: KRMA-944
title: Move package open, lease acquisition and crash recovery out of AppViewModel.init
type: task
status: ready
priority: high
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - startup
  - performance
  - package
  - needs-decomposition
created: 2026-10-13T14:47:53.866Z
updated: 2026-10-13T20:39:03.853Z
parent: KRMA-922
depends_on:
  - KRMA-943
  - KRMA-985
blockers: []
order: zq
board: product
---

## Objective

First window appears without waiting for package open, dead-writer recovery (which can checksum
staged files) or lease acquisition.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S4 (first bullet). `KromoraAppDelegate.init`
(`Sources/KromoraKit/Presentation/KromoraAppDelegate.swift` ~L9-25) calls `AppViewModel(
includeBundledLooks: true)`, whose init opens the portable package: lease acquisition and
`PortablePackageTransaction.recover` run on the main thread before any window exists. KRMA-557
("Keep portable-library startup responsive while opening or rebuilding its index") already moved the
INDEX load off-main; this ticket covers the open/lease/recovery steps that remain synchronous. Read
KRMA-557 and `ApplicationShellCoordinator` (`Sources/KromoraKit/ViewModels/`) first, plus
`docs/APP_ARCHITECTURE.md` and `docs/STORAGE_POLICY.md`. The lease-conflict `NSAlert` presentation is
KRMA-945/S6 territory; keep its behavior but do not block the first frame.

## Acceptance criteria

- [ ] `AppViewModel.init` does not open the package or recover transactions. A new async step (owned
      by the existing shell/lifecycle coordinator, not new global state) opens it after the first
      window is created, off the main actor, via the package-I/O scheduler or a detached
      `@concurrent` function.
- [ ] The UI shows an explicit "Opening library…" state until the session is ready; library-dependent
      commands are disabled in the meantime; a failed/conflicted open reaches the existing error/alert
      path exactly once.
- [ ] Ordered shutdown still works if quit occurs before open completes (cancel the open, release any
      lease acquired). Test this with a gated fake opener.
- [ ] Tests (fast lane): init returns without calling the opener; opener completes → collection
      loads; opener fails → one error; shutdown mid-open leaves no lease behind.
- [ ] Document the launch sequence in `docs/APP_ARCHITECTURE.md`.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).

## Implementation notes

Do not change package formats. If the sequencing proves larger than expected, split by writing child
tickets (label `needs-decomposition`) and stop; do not land a half-migration.


### Comment — claude @ 2026-10-13T20:39:01.818Z

Decomposed instead of landing a half-migration (per implementation notes). The open session feeds a let editStore shared by ~8 coordinators, a let portableLibrary read at ~40 sites, ~60 lines of init tail wiring and 433 test call sites; deferring the open needs late-binding first. Children: KRMA-983 (late-bind store/session), KRMA-984 (async opener, Opening state, shutdown, tests), KRMA-985 (delegate + docs). No source changed.
