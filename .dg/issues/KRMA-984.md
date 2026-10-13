---
id: KRMA-984
title: "KRMA-944b: Add shell-owned async package opener (gated fake in tests) with Opening library state, command gating, error-once and ordered shutdown"
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
  - startup
  - package
  - needs-decomposition
created: 2026-10-13T20:38:45.433Z
updated: 2026-10-13T22:12:28.254Z
depends_on:
  - KRMA-983
blockers: []
order: zrh
board: product
---

## Objective

Open the library package after the first window exists, off the main actor, with an explicit "Opening library…" state, command gating, a single error report, and an ordered shutdown that works when quit arrives mid-open. This is the behavior change; the late-binding seam it uses is KRMA-983.

## Context

Parent: KRMA-944 (read it and its decomposition comment). Review finding S4: `.context/2026-10-13-release-readiness-review.md`. Also read KRMA-557 (index load already off-main), `docs/APP_ARCHITECTURE.md`, `docs/STORAGE_POLICY.md`.

Depends on KRMA-983, which adds `AppViewModel.openLibrary(confirmer:)`/the bind path, an unbound `EditDocumentStore`, and `private(set) var portableLibrary`. Read its ticket comment for the final names.

Today (verified 2026-10-13): `Presentation/AppLaunch.swift` runs `open()` in a `.task` after the first window; it asks the lease-recovery question through the sheet seam, then builds the whole `AppViewModel` on the main actor, which opens the package synchronously (acquire lease, `PortablePackageTransaction.recover`, index kick-off) and blocks the main thread. `KromoraScene` shows a placeholder until `launch.viewModel` is non-nil. KRMA-986 (done, but uncommitted in the tree) introduced `AppLaunch`/`SheetPresenting`; keep that prompt behavior ("Take Over Library" / "Not Now") and do not reintroduce a modal call before the first frame.

Lifecycle owner: `ApplicationShellCoordinator` (`ViewModels/ApplicationShellCoordinator.swift`) already owns process observers and package maintenance admission and has an ordered `shutdown()`. The opener belongs there or in a small collaborator it owns, not in new global state. The package-I/O scheduler is `ImageWorkScheduler` (created in init, L1073); a detached `@concurrent` function is also acceptable. `PortableLibrarySession` is a non-Sendable `final class` (`Models/PortableLibrarySession.swift:55`); it must be created off-main and handed to the main actor with `sending`, or the whole open must be structured so no non-Sendable value crosses an isolation boundary improperly (no escape hatches).

## Approach

1. **Opener seam.** `protocol PackageOpening` with one async method returning the opened session plus `recoveredPreviousWriter`, taking the URL, confirmer and scheduler. The production implementation wraps the existing `openPortableLibrarySession` logic (move it out of `AppViewModel`, which also shrinks the file). Tests supply a fake whose completion is gated by a continuation.
2. **State.** Add an explicit library-open state (for example `.opening`, `.ready`, `.failed(message)`) owned by the shell/open coordinator and observable by views. `statusMessage` shows "Opening library…" while `.opening`. Do not overload `isLoadingIndex`, which covers the later index load.
3. **Flow.** `AppLaunch.open()` constructs `AppViewModel` immediately with no package (cheap, main actor), returns it so the scene can show the real window, then starts the open task. On success: `bindPortableLibrary`, collection load, index loading as today. On failure: set `.failed`, call the existing error path once (`presentError`), leave `portableLibraryOpenError` populated so imports report unavailable as today.
4. **Command gating.** Library-dependent commands and menu items (import, open folder/Photos, export, delete, new virtual copy; `canImportIntoPortableLibrary` and the menu enablement in `Views/MenuCommands.swift`/`KeyboardShortcuts.swift`) are disabled while `.opening` or `.failed`. Enumerate them by grepping every use of `portableLibrary` and `canImportIntoPortableLibrary`, list them in the ticket comment, and cover each with a test or one parametrized test.
5. **Shutdown.** `shutdown()` and `applicationShouldTerminate` must handle quit while `.opening`: cancel the open task, wait for it to finish unwinding, release a lease that was acquired but not yet bound, and reply to terminate. `KromoraAppDelegate.applicationShouldTerminate` currently returns `.terminateNow` when `viewModel` is nil; with an always-present model that branch needs revisiting so it does not skip the cancel-and-release.
6. **Cancellation hazard.** The blocking filesystem work inside the open (`recover` checksums staged files) cannot be interrupted mid-call. Cancel means "do not bind, release the lease on completion". Say so in code comments and make the release path idempotent.

## Acceptance criteria

- [ ] `AppViewModel.init` returns without calling the opener (fast-lane test with a fake that records calls and never completes).
- [ ] Opener completes -> `portableLibrary` is bound, the collection loads, `.ready` is reached, "Opening library…" clears. Tested with a gated fake.
- [ ] Opener fails -> exactly one error is presented (assert `errorMessage` set once, one alert presentation), state is `.failed`, imports report unavailable.
- [ ] Shutdown mid-open: the open is cancelled, no lease remains afterwards (assert via the package's lease file/`PortablePackageLease` API in a temp directory using the real opener plus a gate before binding), and `shutdown()` returns.
- [ ] Library-dependent commands are disabled during `.opening`/`.failed` and enabled after `.ready` (list of commands in the ticket comment).
- [ ] A lease-contention or expired-lease case still reaches the existing prompt path exactly once and does not block the first frame (existing `AppLaunchTests` stay green; extend them).
- [ ] Swift 6 clean with no escape hatches; non-Sendable session crosses actors only via `sending`/main-actor construction.
- [ ] `AppViewModel.swift` is not longer than before (moving `openPortableLibrarySession` out should shrink it).
- [ ] `scripts/ci-tests.sh fast` and `serial` pass.

## Verification

```
swift build
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
```

Manual smoke with `swift run`: launch against a normal library (window appears, "Opening library…" then grid), against a stale-lease library (prompt appears over the window), against an unreadable package (single error), and quit during a deliberately slow open (use the fake opener's delay in a debug-only test, not in product code).

## Out of scope

Package format or lease semantics, the lease prompt copy (KRMA-945/S6 territory), and the index-load path (KRMA-557). Do not land a half-migration: if gating cannot be completed for every command, stop and decompose.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
