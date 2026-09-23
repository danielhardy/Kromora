---
id: KRMA-557
title: Keep portable-library startup responsive while opening or rebuilding its index
type: bug
status: ready
priority: high
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
updated: 2026-09-23T15:19:08.746Z
order: n
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
