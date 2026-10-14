---
id: KRMA-988
title: Add Settings > Choose Library… (applied on relaunch, security-scoped bookmark)
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Settings shows the current library path and Choose Library… opens a folder-only NSOpenPanel through AppKitFileDialogAdapter.
      result: pass
    - criterion: The selected URL is checked with PortableLibraryPackage.open; an invalid folder reports one error and does not change the stored choice.
      result: pass
    - criterion: The selection is stored as a security-scoped bookmark; stale or unresolvable bookmarks clear the choice, fall back to default, and show a one-time notice without modifying the old path.
      result: pass
      notes: Fixed stale bookmarks that were previously refreshed and opened; the regression test verifies fallback, notice-once behavior, and that scoped access is not started.
    - criterion: AppLaunch resolves the stored choice for packageURL and choosing a library offers Relaunch / Later with the required prompt.
      result: pass
    - criterion: Use Default Library clears the bookmark.
      result: pass
    - criterion: Choosing another location does not modify or move the default Pictures library.
      result: pass
    - criterion: Fast-lane tests cover valid and invalid packages, bookmark round-trip, stale fallback, and launch resolution.
      result: pass
    - criterion: STORAGE_POLICY.md and APP_ARCHITECTURE.md document active-library selection.
      result: pass
    - criterion: swift build is warning-free and the Swift 6 restrictions remain satisfied.
      result: pass
      notes: Build completed with no warnings.
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
    - criterion: scripts/ci-tests.sh serial exits 0.
      result: pass
  checks_run:
    - "swift build: passed, exit 0, no warnings"
    - "scripts/ci-tests.sh fast: passed, 1,881 required-fast tests, exit 0"
    - "scripts/ci-tests.sh serial: passed, 543 tests, exit 0"
    - "git diff --check: passed, exit 0"
    - Reviewed bookmark resolution, validation, security-scope lifetime, relaunch flow, and settings/docs coverage
  findings:
    - Stale bookmarks were refreshed and the selected package kept opening, contrary to the requirement to fall back to the default.
  fixes:
    - Stale bookmark resolution now clears the saved choice and falls back to the default with the one-time notice; added a regression test for fallback and no access start.
  verification_commits:
    - 9d9b8632b8268a5cf211009ade86d32adef4d4b8
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T00:50:14.211Z
  session: 01MV7DY87SCYJ64NBF
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - library
  - settings
created: 2026-10-13T23:11:53.399Z
updated: 2026-10-14T00:50:14.214Z
parent: KRMA-922
blockers: []
order: w
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T00:17:40.343Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 9d9b8632b8268a5cf211009ade86d32adef4d4b8
---

## Objective

Let the user choose which `.kromoralibrary` package Kromora uses via Settings. The choice applies on
the next launch (the app offers to quit/relaunch); there is no runtime session swap. This replaces
the dropped Open Library / Restore flows (ADR-936): to "restore", the user copies a package anywhere
and points Kromora at it.

## Context

Decision: `.dg/decisions/ADR-936-*.md`. Review finding M6 in `.context/2026-10-13-release-readiness-review.md`.

- The library location is hard-wired: `KromoraStorage.defaultPortableLibraryPackageURL`
  (`Sources/KromoraKit/Models/KromoraStorage.swift` ~L93), `~/Pictures/Kromora Library.kromoralibrary`.
  It is read in `AppViewModel`'s convenience inits (`Sources/KromoraKit/ViewModels/AppViewModel.swift`
  ~L1008, ~L1020) and as the default `packageURL` of the launch coordinator in
  `Sources/KromoraKit/Presentation/AppLaunch.swift`, which already injects `packageURL`.
- `KromoraSettings` (`UserDefaults`) is where preferences and security-scoped bookmarks live; see the
  table in `docs/STORAGE_POLICY.md` and the settings UI in `Sources/KromoraKit/Views/KromoraSettingsView.swift`.
- Dialogs go through `AppKitFileDialogAdapter` (`Sources/KromoraKit/Presentation/AppKitFileDialogAdapter.swift`) so tests can fake panels.
- Writer-lease conflict and recovery prompts already exist (`PortablePackageLeaseRecoveryPrompt`); a
  library opened from a chosen location uses the same path.
- Security-scope lifetime pitfalls: see KRMA-818. Start access before opening the package and keep it
  for the session lifetime.
- Do NOT grow `AppViewModel` (at its line guard); put resolution logic in a small type next to `KromoraSettings` / `AppLaunch`.

## Acceptance criteria

- [ ] Settings shows the current library path and a "Choose Library…" button (single `…` character).
      The button opens an `NSOpenPanel` (via `AppKitFileDialogAdapter`) that selects a package folder.
- [ ] The chosen URL is validated with the package's own validator (not just the extension). An
      invalid folder shows one error and changes nothing.
- [ ] The choice is stored as a security-scoped bookmark in `KromoraSettings`. A stale or unresolvable
      bookmark falls back to the default location and shows a one-time notice; it never deletes or
      recreates anything at the old path.
- [ ] `AppLaunch` resolves the bookmark (else the default) to produce `packageURL`. After choosing,
      the user sees a prompt "Kromora needs to relaunch to use this library" with Relaunch / Later.
- [ ] A "Use Default Library" action clears the bookmark.
- [ ] The default `~/Pictures` library is never modified or moved when another location is chosen.
- [ ] Tests (fast lane, fake dialog, temp packages): valid package accepted; invalid folder rejected;
      bookmark round-trips; stale bookmark falls back to default; launch resolution picks the chosen URL.
- [ ] `docs/STORAGE_POLICY.md` and `docs/APP_ARCHITECTURE.md` describe active-library selection.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0 (settings UI tests).

## Implementation notes

Out of scope: runtime library switching, Finder double-click, New Library…, Move Library…, multiple
open libraries, backup/restore UI. File any of these as separate backlog tickets if needed.


### Comment — claude @ 2026-10-14T00:17:33.358Z

Implemented ActiveLibrarySelection (bookmark store/resolve/validate via PortableLibraryPackage.open), ActiveLibraryChooser (Settings flow, Relaunch/Later), AppLaunch resolution holding the scope for the session, tests, docs. fast and serial lanes exit 0; swift build has no warnings.

## Agent log

- 2026-10-14T00:50:14.211Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Settings shows the current library path and Choose Library… opens a folder-only NSOpenPanel through AppKitFileDialogAdapter. (pass)
- [x] The selected URL is checked with PortableLibraryPackage.open; an invalid folder reports one error and does not change the stored choice. (pass)
- [x] The selection is stored as a security-scoped bookmark; stale or unresolvable bookmarks clear the choice, fall back to default, and show a one-time notice without modifying the old path. (pass) — Fixed stale bookmarks that were previously refreshed and opened; the regression test verifies fallback, notice-once behavior, and that scoped access is not started.
- [x] AppLaunch resolves the stored choice for packageURL and choosing a library offers Relaunch / Later with the required prompt. (pass)
- [x] Use Default Library clears the bookmark. (pass)
- [x] Choosing another location does not modify or move the default Pictures library. (pass)
- [x] Fast-lane tests cover valid and invalid packages, bookmark round-trip, stale fallback, and launch resolution. (pass)
- [x] STORAGE_POLICY.md and APP_ARCHITECTURE.md document active-library selection. (pass)
- [x] swift build is warning-free and the Swift 6 restrictions remain satisfied. (pass) — Build completed with no warnings.
- [x] scripts/ci-tests.sh fast exits 0. (pass)
- [x] scripts/ci-tests.sh serial exits 0. (pass)
Checks run:
- swift build: passed, exit 0, no warnings
- scripts/ci-tests.sh fast: passed, 1,881 required-fast tests, exit 0
- scripts/ci-tests.sh serial: passed, 543 tests, exit 0
- git diff --check: passed, exit 0
- Reviewed bookmark resolution, validation, security-scope lifetime, relaunch flow, and settings/docs coverage
Findings:
- Stale bookmarks were refreshed and the selected package kept opening, contrary to the requirement to fall back to the default.
Fixes:
- Stale bookmark resolution now clears the saved choice and falls back to the default with the one-time notice; added a regression test for fallback and no access start.
Verification commits:
- 9d9b8632b8268a5cf211009ade86d32adef4d4b8
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7DY87SCYJ64NBF
Summary: Verification passed; stale-bookmark fallback fixed and required checks passed.
