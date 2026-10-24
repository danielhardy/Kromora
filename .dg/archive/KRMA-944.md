---
id: KRMA-944
title: Move package open, lease acquisition and crash recovery out of AppViewModel.init
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Production AppViewModel initialization does not open or recover the package before the first window; package I/O runs asynchronously off the main actor.
      result: pass
      notes: AppLaunch.makeViewModel enables deferred open; KromoraRootView first presents its progress shell, then AppLaunch starts PortablePackageOpener through the @concurrent opener path.
    - criterion: Opening state gates library-dependent commands, and failed or declined opens reach the existing error path exactly once.
      result: pass
      notes: LibraryOpenState, the readiness gates, and LibraryOpenTests/AppLaunchTests cover opening, successful bind, failure-once, and declined takeover.
    - criterion: Shutdown during an open cancels the operation and releases any acquired unbound lease.
      result: pass
      notes: LibraryOpenTests.testShutdownMidOpenCancelsAndReleasesLease gates the real opener after lease acquisition and verifies the lease file is removed after shutdown.
    - criterion: Fast-lane tests cover deferred init, successful open, failure, and shutdown; the required fast lane passes.
      result: pass
      notes: The final scripts/ci-tests.sh fast run passed all 1,885 tests. Its first run had one unrelated failure in StoredEditAdoptionTests.testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult; that test passed alone and the full rerun passed.
    - criterion: docs/APP_ARCHITECTURE.md records the launch sequence.
      result: pass
      notes: The Launch sequence section documents deferred model creation, prompt, asynchronous open, bind, index load, readiness, failure, and shutdown.
    - criterion: Build is warning-free and Swift 6 mode has no prohibited concurrency escape hatches or availability branches in the opener path.
      result: pass
      notes: swift build completed without diagnostics; the structural scan found no matches.
  checks_run:
    - swift build (exit 0; no diagnostics)
    - scripts/ci-tests.sh fast (final rerun exit 0; 1,885 tests passed)
    - swift test --filter StoredEditAdoptionTests/testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult (exit 0; 1 test passed after the first parallel-lane failure)
    - "Structural scan of PackageOpening.swift, LibraryOpenCoordinator.swift, AppViewModel+Library.swift, and AppLaunch.swift for @unchecked Sendable, nonisolated(unsafe), @preconcurrency, and #available (no matches)"
    - git show --check for bbe7e94e, 75128dbb, and 73d5a921 (exit 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T01:32:49.060Z
  session: 01MV7FJ32XPJL0LTDD
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
updated: 2026-10-24T13:05:13.505Z
parent: KRMA-922
depends_on:
  - KRMA-985
blockers: []
order: zv
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T01:23:27.169Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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


### Comment — claude @ 2026-10-14T01:10:02.311Z

KRMA-985 re-check against shipped behavior: init does not open (AppLaunch.init/delegate do no I/O; model built in KromoraRootView .task via AppLaunch.open()); 'Opening library…' state via LibraryOpenCoordinator .opening; single error on .failed/declined takeover; shutdown mid-open cancels open and releases unbound lease (KRMA-984); fast-lane tests in AppLaunchTests + library-open tests pass; docs: APP_ARCHITECTURE.md Launch sequence section added.


### Comment — codex @ 2026-10-14T01:22:53.921Z

KRMA-985 counterpoint verification re-check against shipped behavior:

1. Init does not open the package. `KromoraAppDelegate.init` creates only `AppLaunch`; `AppLaunch.init` stores dependencies; `AppViewModel` construction is deferred to `AppLaunch.open()`. The required grep output is:
   `Sources/KromoraKit/Presentation/AppLaunch.swift:27:            AppViewModel(`
   The delegate and `KromoraScene.init` contain no package I/O; the opener is `PortablePackageOpener` and runs off the main actor.
2. The first window shows the progress shell, then `LibraryOpenState.opening` publishes “Opening library…” and gates library commands. `LibraryOpenTests.testCompletedOpenBindsLibraryAndClearsOpeningStatus` covers the transition through bind and ready.
3. `LibraryOpenTests.testFailedOpenPresentsExactlyOneError` verifies one error on failed open; `AppLaunchTests.testLaunchStaysClosedWhenTakeoverDeclined` verifies decline leaves the library closed with an error.
4. `LibraryOpenTests.testShutdownMidOpenCancelsAndReleasesLease` verifies cancellation and release of the unbound lease.
5. The final `scripts/ci-tests.sh fast` run passed all 1,884 tests with exit 0.
6. `docs/APP_ARCHITECTURE.md` now records the ordered launch, named opener/state, error, and shutdown paths; the stale-init search in `docs/STORAGE_POLICY.md` and `docs/ENGINEERING_GUIDE.md` found no claim that init opens the package. The sandbox audit now documents the selected-library bookmark and default Pictures fallback.

The nil-model termination case is reachable before the first frame task, is documented, and is directly covered by `AppLaunchTests.testDelegateTerminatesBeforeFirstFrameCreatesModel`. The activation-policy workaround remains KRMA-945 scope (currently backlog).


### Comment — claude @ 2026-10-14T01:23:26.666Z

Verified children KRMA-983/984/985 are done; launch-time open, Opening state, single error, shutdown-mid-open lease release, tests and docs/APP_ARCHITECTURE.md Launch sequence all shipped. No source changes in this pickup; handing off to review.

## Agent log

- 2026-10-14T01:32:49.060Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Production AppViewModel initialization does not open or recover the package before the first window; package I/O runs asynchronously off the main actor. (pass) — AppLaunch.makeViewModel enables deferred open; KromoraRootView first presents its progress shell, then AppLaunch starts PortablePackageOpener through the @concurrent opener path.
- [x] Opening state gates library-dependent commands, and failed or declined opens reach the existing error path exactly once. (pass) — LibraryOpenState, the readiness gates, and LibraryOpenTests/AppLaunchTests cover opening, successful bind, failure-once, and declined takeover.
- [x] Shutdown during an open cancels the operation and releases any acquired unbound lease. (pass) — LibraryOpenTests.testShutdownMidOpenCancelsAndReleasesLease gates the real opener after lease acquisition and verifies the lease file is removed after shutdown.
- [x] Fast-lane tests cover deferred init, successful open, failure, and shutdown; the required fast lane passes. (pass) — The final scripts/ci-tests.sh fast run passed all 1,885 tests. Its first run had one unrelated failure in StoredEditAdoptionTests.testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult; that test passed alone and the full rerun passed.
- [x] docs/APP_ARCHITECTURE.md records the launch sequence. (pass) — The Launch sequence section documents deferred model creation, prompt, asynchronous open, bind, index load, readiness, failure, and shutdown.
- [x] Build is warning-free and Swift 6 mode has no prohibited concurrency escape hatches or availability branches in the opener path. (pass) — swift build completed without diagnostics; the structural scan found no matches.
Checks run:
- swift build (exit 0; no diagnostics)
- scripts/ci-tests.sh fast (final rerun exit 0; 1,885 tests passed)
- swift test --filter StoredEditAdoptionTests/testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult (exit 0; 1 test passed after the first parallel-lane failure)
- Structural scan of PackageOpening.swift, LibraryOpenCoordinator.swift, AppViewModel+Library.swift, and AppLaunch.swift for @unchecked Sendable, nonisolated(unsafe), @preconcurrency, and #available (no matches)
- git show --check for bbe7e94e, 75128dbb, and 73d5a921 (exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7FJ32XPJL0LTDD
Summary: Independent verification passed; deferred package open, command gating, single-error handling, shutdown lease release, docs, build, and fast lane verified.
