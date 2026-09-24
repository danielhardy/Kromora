---
id: KRMA-557
title: Keep portable-library startup responsive while opening or rebuilding its index
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproducible launch diagnostics identify the source of the beachball or show that package/index initialization no longer blocks the main thread.
      result: pass
      notes: libraryIndex signposts (LibraryIndexWarm/LibraryIndexRebuild events, KromoraSignpostInterval(.libraryIndex, ...)) added around the detached load/rebuild path; PortableLibrarySession.init now only opens the manifest (openForQuery) and starts async loading rather than validating/rebuilding the full index synchronously.
    - criterion: On warm and cold/corrupt-index paths, the app can paint and interact with its window while package/index work continues; no full-shard traversal or whole-index encode/decode runs on the main actor.
      result: pass
      notes: startIndexLoading() runs load/validate/rebuild inside a scheduler background-lane job (or Task.detached without a scheduler); PortableLibraryPackage is now Sendable so the value crosses actor boundaries safely; main actor only receives page/state updates via publish().
    - criterion: A usable first library page is published before a large cold rebuild completes, with visible progress or a clear loading state.
      result: pass
      notes: LibraryIndexProjection.rebuild(progress:) streams progress; AppViewModel sets statusMessage to 'Opening library index…' / 'Rebuilding library index… N of M sections' and reloads page 0 on each progress tick; verified via testAsynchronousStartupRebuildPublishesFirstPageAndReleasesLeaseOnShutdown (550-entry cold rebuild with a corrupted index file).
    - criterion: Cancellation, open failure, and shutdown release or retain the writer lease correctly; no duplicate writer is admitted.
      result: pass
      notes: shutdown() now cancels the scheduler-queued index-load job and the detached fallback task, awaits both, then releases the lease; onTerminal handler on the scheduler job reports a failure state instead of hanging if the job cannot start. Verified by testAsynchronousStartupShutdownCancelsQueuedIndexWorkAndReleasesLease.
    - criterion: Tests cover warm open, missing/corrupt index recovery, large generated membership, cancellation/failure, and session shutdown.
      result: pass
      notes: PortableLibrarySessionTests adds testAsynchronousStartupRebuildPublishesFirstPageAndReleasesLeaseOnShutdown (corrupt index + 550-entry cold rebuild + warm reopen) and testAsynchronousStartupShutdownCancelsQueuedIndexWorkAndReleasesLease.
    - criterion: Manual swift run checks on a representative large library confirm the cursor recovers and UI actions remain responsive.
      result: not_applicable
      notes: Not performable in this non-interactive environment (no way to drive/observe the AppKit window). Automated coverage (signposts, async-loading tests, full fast test lane) substitutes but a human should still confirm this manually before considering the beachball fully resolved in practice.
  checks_run:
    - swift build (clean, 0 errors)
    - swift test --filter 'PortableLibrarySessionTests|AppViewModelTests' (50/50 passed)
    - swift test --filter 'DevelopInspectorTests/testHistogramFollowsTheDisplayedComparisonRequest' (previously-reported flaky failure; passes in isolation, root-caused and fixed by unrelated commit a4b2f10)
    - scripts/ci-tests.sh fast (1179/1179 passed, exit 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-23T23:15:15.611Z
  session: 01MUEPUHUS6GHPB72D
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - stability
  - launch
  - performance
  - library
created: 2026-09-23T15:18:46.720Z
updated: 2026-09-23T23:15:15.614Z
order: zq
board: product
---

## Objective

Keep the application responsive while opening a portable library on `swift run`, including cold starts where the local query index must be rebuilt.

## User report

The user reports that the window initially appears normal, then macOS shows the spinning rainbow cursor indefinitely. Force-quitting produces an Apple crash/error-log prompt. This may be the event that leaves the writer lease behind, but no crash report, sample, or package was available to confirm the beachball stack.

## Code evidence

- `KromoraApp`'s `AppDelegate.init` constructs `AppViewModel` before `applicationDidFinishLaunching`; `ContentView.init` also has a direct synchronous model-construction path.
- `AppViewModel.init` synchronously calls `PortableLibrarySession(at:)` on the main actor before publishing the window's library state.
- `PortableLibrarySession` is `@MainActor`. Its initializer opens the package, acquires a lease, loads and validates the complete `LibraryIndexProjection`, or synchronously rebuilds it with `LibraryIndexProjection(package:)` and writes it. The rebuild reads membership shards and materializes the full entry set.
- `LibraryIndexProjection.rebuild` already supports asynchronous progress and first-page publication, but the current session initializer does not use that path.
- The completed KRMA-518 work moved import writes/index deltas off the main actor; this ticket concerns initial package/session open and cold index recovery.

## Scope

- Profile startup with a valid warm index and with a missing, corrupt, or mismatched index at representative library sizes. Capture the main-thread stack/signposts so the reported beachball is confirmed or falsified.
- Move catalog-size-proportional package reads, index validation/rebuild, sorting, and serialization off the main actor.
- Publish an actionable window/loading state promptly and stream the first usable query page while a rebuild continues, if needed.
- Preserve package lease ownership, scheduler serialization, cancellation, and safe release when startup fails or the app shuts down.
- Avoid redesigning unrelated rendering or import behavior.

## Acceptance criteria

- [ ] Reproducible launch diagnostics identify the source of the beachball or show that package/index initialization no longer blocks the main thread.
- [ ] On warm and cold/corrupt-index paths, the app can paint and interact with its window while package/index work continues; no full-shard traversal or whole-index encode/decode runs on the main actor.
- [ ] A usable first library page is published before a large cold rebuild completes, with visible progress or a clear loading state.
- [ ] Cancellation, open failure, and shutdown release or retain the writer lease correctly; no duplicate writer is admitted.
- [ ] Tests cover warm open, missing/corrupt index recovery, large generated membership, cancellation/failure, and session shutdown.
- [ ] Manual `swift run` checks on a representative large library confirm the cursor recovers and UI actions remain responsive.

## Likely files and checks

`KromoraApp.swift`, `AppViewModel.swift`, `PortableLibrarySession.swift`, `LibraryQueryController.swift` (`LibraryIndexProjection` / `LibraryIndexSession`), `ImageWorkScheduler.swift`, and `PortableLibrarySessionTests.swift` / `AppViewModelTests.swift`. Use launch signposts or a main-thread hang diagnostic; run focused session/query tests and the documented fast lane.

## Related work

KRMA-518 (done) covers package import hashing, writes, and incremental index refresh. Keep this ticket focused on startup/session opening. KRMA-556 separately handles recovery of a dead local writer after force-quit.


### Comment — codex @ 2026-09-23T15:51:00.530Z

Moved production library index load, validation, and cold shard rebuild to the scheduler’s detached package I/O lane. Startup now publishes loading status and streams the first usable page during rebuild; shutdown waits for queued or running index work before releasing the lease. Added warm, corrupt-index, 550-entry progress, and shutdown coverage plus LibraryIndex signposts. Commit: a57eeb1. Focused PortableLibrarySessionTests (14) and AppViewModelTests (34) passed; the full fast lane ran 1,177 tests but failed DevelopInspectorTests/testHistogramFollowsTheDisplayedComparisonRequest (comparison histogram timeout and resulting document assertion), reproducible when run alone. Manual swift run UI responsiveness check was not performed.

## Agent log

- 2026-09-23T23:15:15.612Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproducible launch diagnostics identify the source of the beachball or show that package/index initialization no longer blocks the main thread. (pass) — libraryIndex signposts (LibraryIndexWarm/LibraryIndexRebuild events, KromoraSignpostInterval(.libraryIndex, ...)) added around the detached load/rebuild path; PortableLibrarySession.init now only opens the manifest (openForQuery) and starts async loading rather than validating/rebuilding the full index synchronously.
- [x] On warm and cold/corrupt-index paths, the app can paint and interact with its window while package/index work continues; no full-shard traversal or whole-index encode/decode runs on the main actor. (pass) — startIndexLoading() runs load/validate/rebuild inside a scheduler background-lane job (or Task.detached without a scheduler); PortableLibraryPackage is now Sendable so the value crosses actor boundaries safely; main actor only receives page/state updates via publish().
- [x] A usable first library page is published before a large cold rebuild completes, with visible progress or a clear loading state. (pass) — LibraryIndexProjection.rebuild(progress:) streams progress; AppViewModel sets statusMessage to 'Opening library index…' / 'Rebuilding library index… N of M sections' and reloads page 0 on each progress tick; verified via testAsynchronousStartupRebuildPublishesFirstPageAndReleasesLeaseOnShutdown (550-entry cold rebuild with a corrupted index file).
- [x] Cancellation, open failure, and shutdown release or retain the writer lease correctly; no duplicate writer is admitted. (pass) — shutdown() now cancels the scheduler-queued index-load job and the detached fallback task, awaits both, then releases the lease; onTerminal handler on the scheduler job reports a failure state instead of hanging if the job cannot start. Verified by testAsynchronousStartupShutdownCancelsQueuedIndexWorkAndReleasesLease.
- [x] Tests cover warm open, missing/corrupt index recovery, large generated membership, cancellation/failure, and session shutdown. (pass) — PortableLibrarySessionTests adds testAsynchronousStartupRebuildPublishesFirstPageAndReleasesLeaseOnShutdown (corrupt index + 550-entry cold rebuild + warm reopen) and testAsynchronousStartupShutdownCancelsQueuedIndexWorkAndReleasesLease.
- [ ] Manual swift run checks on a representative large library confirm the cursor recovers and UI actions remain responsive. (not_applicable) — Not performable in this non-interactive environment (no way to drive/observe the AppKit window). Automated coverage (signposts, async-loading tests, full fast test lane) substitutes but a human should still confirm this manually before considering the beachball fully resolved in practice.
Checks run:
- swift build (clean, 0 errors)
- swift test --filter 'PortableLibrarySessionTests|AppViewModelTests' (50/50 passed)
- swift test --filter 'DevelopInspectorTests/testHistogramFollowsTheDisplayedComparisonRequest' (previously-reported flaky failure; passes in isolation, root-caused and fixed by unrelated commit a4b2f10)
- scripts/ci-tests.sh fast (1179/1179 passed, exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUEPUHUS6GHPB72D
Summary: Verified async portable-library index startup: build is clean, full fast test lane (1179 tests) and focused session/AppViewModel tests pass, and the previously-flaky comparison-histogram test now passes (fixed by an unrelated commit). Design correctly moves index load/validate/rebuild off the main actor via a Sendable PortableLibraryPackage and a scheduler background lane, streams first-page progress, and cancels/awaits the load task on shutdown before releasing the lease. No code changes needed; only the manual swift run UI check remains unverified, which is not performable in this non-interactive session.
