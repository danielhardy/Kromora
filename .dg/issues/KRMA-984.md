---
id: KRMA-984
title: "KRMA-944b: Add shell-owned async package opener (gated fake in tests) with Opening library state, command gating, error-once and ordered shutdown"
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: AppViewModel.init returns without calling the package opener.
      result: pass
      notes: LibraryOpenTests.testInitDoesNotCallOpener uses a gated fake and confirms the opener call count remains zero.
    - criterion: A successful open binds the library, loads the collection, reaches ready, and clears the opening status.
      result: pass
      notes: LibraryOpenTests.testCompletedOpenBindsLibraryAndClearsOpeningStatus passes; bindPortableLibrary wires and reloads the collection before the coordinator publishes ready.
    - criterion: An open failure presents exactly one error, reaches failed, and leaves imports unavailable.
      result: pass
      notes: LibraryOpenTests.testFailedOpenPresentsExactlyOneError and testFailedLibraryKeepsCommandsGatedAndImportsUnavailable pass.
    - criterion: Shutdown during open cancels and waits for the open to unwind, releases an unbound lease, and returns.
      result: pass
      notes: LibraryOpenTests.testShutdownMidOpenCancelsAndReleasesLease gates the real opener after lease acquisition and verifies the lease file is gone after shutdown.
    - criterion: Library-dependent commands are gated while opening or failed and enabled once ready.
      result: pass
      notes: Audited File-menu Open Image, Photos, source folder, removable media; export, export selected, external editor, export original settings, reset, copy/paste edits, save look, delete selected; virtual-copy creation; and toolbar, grid, preview, and Welcome import actions. MenuCommandAvailability and canImportIntoPortableLibrary drive these gates. Verification fixed the direct File-menu actions to fail closed when focused-scene availability is nil.
    - criterion: Lease contention and expired-lease recovery use the existing prompt once without blocking the first frame.
      result: pass
      notes: AppLaunchTests verify opening state is returned synchronously, the takeover decision is asked exactly once, acceptance opens the package, and decline leaves it closed.
    - criterion: Swift 6 build is clean with no concurrency escape hatches; non-Sendable session construction remains main-actor isolated.
      result: pass
      notes: "swift build completed without diagnostics. Structural search found no @unchecked Sendable, nonisolated(unsafe), @preconcurrency, or #available in the opener and gating implementation files; only the Sendable package and lease cross to the main-actor session constructor."
    - criterion: AppViewModel.swift is no longer than before the migration.
      result: pass
      notes: Current file is 5064 lines; the parent implementation baseline is 5106 lines.
    - criterion: Required build, fast, and serial checks pass.
      result: pass
      notes: Build passed; final fast lane passed 1881 tests; serial lane passed 544 tests.
  checks_run:
    - swift build (exit 0, no diagnostics)
    - swift test --filter 'LibraryOpenTests|AppLaunchTests|MenuCommandTests' (29 tests passed)
    - scripts/ci-tests.sh fast (final run exit 0, 1881 tests); the first attempt had one unrelated parallel timeout in EditedThumbnailCoordinatorTests.testFailedEditedThumbnailDoesNotSettleFallbackAndVisibleDemandRetries; that test passed in isolation before the successful full rerun
    - scripts/ci-tests.sh serial (exit 0, 544 tests)
    - git diff --check (exit 0)
    - Structural scan for prohibited Swift concurrency escape hatches and availability branches (no matches); AppViewModel.swift line count compared to parent baseline
    - Manual swift run smoke was not performed because it would open the existing user library at ~/Pictures/Kromora Library.kromoralibrary and the launcher has no temporary-package override; temporary-package launch, takeover, failure, and shutdown behavior was covered by automated tests
  findings:
    - Four direct File-menu open/import actions treated missing focused-scene availability as ready; the Welcome sheet import actions were also interactive before library readiness.
  fixes:
    - "Changed direct File-menu gating to fail closed when scene availability is absent and disabled Welcome import, Photos, and sample actions until library readiness. Added a unit test for nil and explicit readiness values. Verification commit: 75128dbb."
  verification_commits:
    - 75128dbb
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T01:07:03.317Z
  session: 01MV7EER27RZ37G8KU
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
updated: 2026-10-14T01:07:03.320Z
depends_on:
  - KRMA-983
blockers: []
order: y
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T00:42:35.647Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 75128dbb
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

### Comment — claude @ 2026-10-14T00:42:31.546Z

Implemented in bbe7e94e. New: PackageOpening/OpenedPackage (Models/PackageOpening.swift), LibraryOpenCoordinator (idle/opening/ready/failed). PortableLibrarySession split into nonisolated static acquire(...) + init(opened:), so only Sendable package+lease cross actors (no sending needed). AppLaunch.open() is now synchronous: builds the model (defersLibraryOpen) and starts the open; takeover prompt runs inside the open task. beginOpeningLibrary/openLibrary(takeOver:) live in AppViewModel+Library.swift; AppViewModel.swift is 5064 lines (was 5106). shutdown() cancels and awaits the open first; a cancelled open releases its unbound lease (blocking recover cannot be interrupted); quit during the takeover sheet does not wait on the sheet. Gated commands: all MenuCommand cases via MenuCommandAvailability.isLibraryReady; menu items Open Image, Import from Photos, Open Source Folder, Import from Removable Media; toolbar/grid/preview import buttons (canImportIntoPortableLibrary); AppViewModel entry points guarded on portableLibrary (openImageDialog, openImage(data:), importFromPhotos, removable media import/open, chooseSourceFolder, handleDrop, virtual copy) report 'still opening' as status only while opening. Tests: LibraryOpenTests (gated fake, failure once, shutdown mid-open with real opener + lease file check, gating), extended AppLaunchTests. fast and serial lanes pass. Not done: manual swift run smoke (needs display).

### Comment — codex @ 2026-10-14T01:06:31.861Z

Verification command audit: File-menu Open Image, Import from Photos, Open Source Folder, and Import from Removable Media; export, export selected, external-editor export, export original with settings, reset photo, selective/all edit copy, paste edits, save look, and delete selected through MenuCommandAvailability and KeyboardCommandRouter; virtual-copy creation through availability/metadata and the AppViewModel guard; and toolbar, grid, preview, and Welcome import/Photos/sample actions through library readiness. Review found the four direct File-menu actions treated missing focused-scene availability as ready; verification commit 75128dbb makes them fail closed and gates Welcome actions until readiness. The first fast-lane attempt hit an unrelated parallel thumbnail retry timeout; the isolated test and second full fast lane passed. Manual swift run was skipped because the launcher targets the existing default package under ~/Pictures and has no temporary-package override; equivalent launch, recovery prompt, failure, and shutdown paths passed automated tests using temporary packages.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-14T01:07:03.317Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] AppViewModel.init returns without calling the package opener. (pass) — LibraryOpenTests.testInitDoesNotCallOpener uses a gated fake and confirms the opener call count remains zero.
- [x] A successful open binds the library, loads the collection, reaches ready, and clears the opening status. (pass) — LibraryOpenTests.testCompletedOpenBindsLibraryAndClearsOpeningStatus passes; bindPortableLibrary wires and reloads the collection before the coordinator publishes ready.
- [x] An open failure presents exactly one error, reaches failed, and leaves imports unavailable. (pass) — LibraryOpenTests.testFailedOpenPresentsExactlyOneError and testFailedLibraryKeepsCommandsGatedAndImportsUnavailable pass.
- [x] Shutdown during open cancels and waits for the open to unwind, releases an unbound lease, and returns. (pass) — LibraryOpenTests.testShutdownMidOpenCancelsAndReleasesLease gates the real opener after lease acquisition and verifies the lease file is gone after shutdown.
- [x] Library-dependent commands are gated while opening or failed and enabled once ready. (pass) — Audited File-menu Open Image, Photos, source folder, removable media; export, export selected, external editor, export original settings, reset, copy/paste edits, save look, delete selected; virtual-copy creation; and toolbar, grid, preview, and Welcome import actions. MenuCommandAvailability and canImportIntoPortableLibrary drive these gates. Verification fixed the direct File-menu actions to fail closed when focused-scene availability is nil.
- [x] Lease contention and expired-lease recovery use the existing prompt once without blocking the first frame. (pass) — AppLaunchTests verify opening state is returned synchronously, the takeover decision is asked exactly once, acceptance opens the package, and decline leaves it closed.
- [x] Swift 6 build is clean with no concurrency escape hatches; non-Sendable session construction remains main-actor isolated. (pass) — swift build completed without diagnostics. Structural search found no @unchecked Sendable, nonisolated(unsafe), @preconcurrency, or #available in the opener and gating implementation files; only the Sendable package and lease cross to the main-actor session constructor.
- [x] AppViewModel.swift is no longer than before the migration. (pass) — Current file is 5064 lines; the parent implementation baseline is 5106 lines.
- [x] Required build, fast, and serial checks pass. (pass) — Build passed; final fast lane passed 1881 tests; serial lane passed 544 tests.
Checks run:
- swift build (exit 0, no diagnostics)
- swift test --filter 'LibraryOpenTests|AppLaunchTests|MenuCommandTests' (29 tests passed)
- scripts/ci-tests.sh fast (final run exit 0, 1881 tests); the first attempt had one unrelated parallel timeout in EditedThumbnailCoordinatorTests.testFailedEditedThumbnailDoesNotSettleFallbackAndVisibleDemandRetries; that test passed in isolation before the successful full rerun
- scripts/ci-tests.sh serial (exit 0, 544 tests)
- git diff --check (exit 0)
- Structural scan for prohibited Swift concurrency escape hatches and availability branches (no matches); AppViewModel.swift line count compared to parent baseline
- Manual swift run smoke was not performed because it would open the existing user library at ~/Pictures/Kromora Library.kromoralibrary and the launcher has no temporary-package override; temporary-package launch, takeover, failure, and shutdown behavior was covered by automated tests
Findings:
- Four direct File-menu open/import actions treated missing focused-scene availability as ready; the Welcome sheet import actions were also interactive before library readiness.
Fixes:
- Changed direct File-menu gating to fail closed when scene availability is absent and disabled Welcome import, Photos, and sample actions until library readiness. Added a unit test for nil and explicit readiness values. Verification commit: 75128dbb.
Verification commits:
- 75128dbb
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7EER27RZ37G8KU
Summary: Passed independent verification; fixed fail-open menu gating and recorded all required checks.
