---
id: KRMA-903
title: Own edit-history tasks and drain durable operations before package shutdown
type: bug
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Gated refresh success or failure released during shutdown cannot publish history or current revision state.
      result: pass
      notes: Reviewed lifecycle/source fences and ran gated refresh shutdown regression; no published-state notifications occur after shutdown begins.
    - criterion: Gated snapshot, restore, and virtual-copy operations are owned and cannot access released package resources; accepted writes settle before lease release.
      result: pass
      notes: Found and fixed cancellation of accepted writes while awaiting persistence flush. Shutdown now cancels refresh reads only and drains accepted writes; gated-flush snapshot regression confirms the write settles before shutdown returns.
    - criterion: New work is rejected after shutdown starts, nested refreshes included, and repeated shutdown is safe.
      result: pass
      notes: Coordinator rejects new operations, nested refreshes are rejected by the lifecycle guard, and repeated shutdown remains safe.
    - criterion: Existing flush-before-write, named-snapshot, virtual-copy, and source-switch behavior is retained.
      result: pass
      notes: Covered by the focused coordinator and store test suites.
    - criterion: Shutdown does not hang on cancellation-oblivious work; tests release deterministic gates and observe completion.
      result: pass
      notes: The gated refresh and snapshot tests release their continuation gates and await shutdown completion.
    - criterion: No fire-and-forget durable-history task remains outside the coordinator owner.
      result: pass
      notes: AppViewModel forwards to EditHistoryCoordinator; every coordinator operation is registered and drained.
  checks_run:
    - "swift build: exit 0."
    - "swift test --no-parallel --filter 'EditHistoryCoordinatorTests|EditDocumentStoreTests|AppViewModelTests|PackageSettingsTests': exit 0; 70 tests passed."
    - "dg validate: exit 0; emitted existing agent-model-name warnings."
    - "git diff --check: exit 0."
  findings:
    - "Fixed during verification: beginShutdown cancelled accepted snapshot/restore/copy operations even while they awaited persistence.flush(); the flush observes Task cancellation and could abort an accepted durable write before it reached the store."
  fixes:
    - Tracked whether owned operations are cancellable reads; shutdown now cancels refresh reads and allows accepted restore/snapshot/virtual-copy operations to finish before the package lease is released.
    - Added a deterministic gated-flush snapshot regression test confirming shutdown drains an accepted write and prevents its nested history refresh.
  verification_commits:
    - 2cbb253f
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T21:17:28.561Z
  session: 01MV5R243L7BY6CYJU
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - app-view-model
  - maintainability
  - concurrency
created: 2026-10-12T17:11:39.897Z
updated: 2026-10-12T21:17:28.565Z
blockers: []
order: zzv
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/EditHistoryCoordinator.swift
    - Tests/KromoraKitTests/EditHistoryCoordinatorTests.swift
    - Tests/KromoraKitTests/AppViewModelTests.swift
    - Sources/KromoraKit/ViewModels/EditPersistenceCoordinator.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - CLAUDE.md
    - AGENTS.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-887
    - KRMA-904
    - KRMA-900
  commands:
    - swift build
    - swift test --no-parallel --filter 'EditHistoryCoordinatorTests|EditDocumentStoreTests|AppViewModelTests|PackageSettingsTests'
    - dg validate
    - git diff --check
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/EditHistoryCoordinator.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/EditHistoryCoordinatorTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/AppViewModelTests.swift
      access: write
      confidence: 1
    - path: docs/APP_ARCHITECTURE.md
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-12T21:09:09.853Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 2cbb253f
---

## Objective

Make AppViewModel shutdown a real barrier for durable-history reads, restores, named snapshots and virtual copies. No history callback may publish after teardown starts, and accepted durable work must settle before the package writer lease is released.

## Evidence

`AppViewModel.refreshDurableEditHistory`, `restoreEditRevision`, `saveEditSnapshot` (approximately 3863-3868), and `createVirtualCopy` discard the Task handles returned by `EditHistoryCoordinator`. The coordinator has no task registry or shutdown method. Its Environment closures at AppViewModel 373-388 return the still-active source and publish restored documents/status without an `isShuttingDown` guard. `AppViewModel.shutdown()` disconnects many other callbacks and ultimately calls `portableLibrary.shutdown()` to release the writer lease, but never shuts down editHistory. Its active-reference fence remains true while the same photo is retained during teardown.

A history read can therefore finish during/after teardown and publish. A snapshot/restore/copy waiting for persistence can resume after the shutdown sequence has advanced toward resource release. This is a lifecycle ownership gap, not a reason to remove durable-history functionality. KRMA-887 extracted this coordinator; preserve that boundary rather than moving its operations back into the root.

## Context to read

- `Sources/KromoraKit/ViewModels/EditHistoryCoordinator.swift`: every returned Task, nested refresh, Environment callbacks and store protocol.
- `Sources/KromoraKit/ViewModels/AppViewModel.swift`: lazy editHistory construction, history/copy façade, shutdown order and `adoptRestoredEditRevision`.
- `ViewModels/EditPersistenceCoordinator.swift`: flush/discard behavior and queued writes.
- `Models/EditDocumentStore.swift`: actor reentrancy, select/saveSnapshot/save operations and package transactions.
- `Models/PortableLibrarySession.swift`: writer lease and shutdown; `Models/PortablePackageCopies.swift`.
- `Tests/KromoraKitTests/EditHistoryCoordinatorTests.swift` fake-store seam and `AppViewModelTests.swift` shutdown tests; `docs/APP_ARCHITECTURE.md` lifecycle table.

## Implementation steps

1. Give EditHistoryCoordinator an explicit lifecycle state, generation and registry/handles for all outstanding operations, including refreshes spawned from other operations. Do not retain only the last handle while older operations remain active.
2. Reject new operations after shutdown starts. Invalidate publication generation synchronously before the first await. Apply source/request/lifecycle checks consistently to success, error, state-notification and root Environment callbacks.
3. Define durable teardown behavior: cancel obsolete reads; drain already accepted snapshot/restore/copy operations before releasing the package lease. A transaction already committing must finish atomically. Task cancellation is not a rollback mechanism and must not silently lose accepted user snapshots.
4. Add an idempotent async shutdown barrier that covers nested refresh work and returns only after owned operations are quiescent. Guard against operations scheduling another refresh while teardown is in progress.
5. Call this barrier from AppViewModel while persistence, the edit store and package lease are still usable, before portableLibrary.shutdown and persistence.discard. Disconnect/invalidate publication first so drained work cannot revive UI state.
6. Keep source-change semantics explicit: pending operations continue to target their captured source where that is existing durable behavior; they cannot publish into a different active photo. Preserve flush-before-write and the root's single document publisher.

## Acceptance criteria

- [ ] Gated refresh success/failure released during shutdown cannot alter history, current revision, root document, status or objectWillChange output.
- [ ] Gated snapshot, restore and virtual-copy operations are owned and cannot access released package resources; a lease-release probe occurs only after accepted writes settle.
- [ ] New work is rejected after shutdown starts, including nested refreshes; repeated shutdown calls are safe and await the same outstanding barrier when necessary.
- [ ] Existing flush-before-write, named-snapshot, virtual-copy and source-switch tests retain their behavior.
- [ ] Shutdown does not hang because a cancelled handle is awaited without releasing the test gate; tests explicitly release cancellation-oblivious work and observe termination.
- [ ] No fire-and-forget durable-history task remains outside this owner.

## Coordination

Independent of KRMA-904, which owns the source-materialization task, and KRMA-900, which owns retouch analysis. These tickets edit the common shutdown composition root, so implement them sequentially in the shared working tree and retain each other's barriers. Update the documented shutdown ownership/order.

## Reading the source context

Source and test paths above are relative to the repository root, `/Users/dhardy/Dev/Kromora`. The installed `dg context` reader currently resolves file/doc contents inside the `.dg` space, so it can list existing repository sources as missing. Read those paths directly from the checkout; their existence was verified when this ticket was written. Keep the repository-relative context hints for planning. Do not copy product source into `.dg` or weaken DispatchGraph path validation to work around this reader limitation.

## Required checks

```sh
swift build
swift test --no-parallel --filter 'EditHistoryCoordinatorTests|EditDocumentStoreTests|AppViewModelTests|PackageSettingsTests'
dg validate
git diff --check
```

Run any newly added collaborator suite as well. These are targeted regression checks; broaden them only when the changed boundary or new failures justify it.

## Repository constraints and implementation handoff

- Read `CLAUDE.md` and `.dg/AGENTS.md`, then claim this issue before code changes. Work on the current branch and preserve unrelated working-tree changes. Execute one issue at a time; dependency tickets must be implemented before dependent work.
- Target macOS 26+ on Apple Silicon, Swift 6, Apple frameworks only. No backwards-compatibility fallback, third-party dependency, @unchecked Sendable, nonisolated(unsafe), or @preconcurrency. Keep application implementation inside KromoraKit and retain AppViewModel's existing line-count ceiling.
- Use generated temporary fixtures and deterministic continuation/event gates. Put package/index/cache paths under test-owned temporary directories. Do not run display-bound release capture scripts or use arbitrary sleeps as proof of cancellation correctness.
- Run the focused checks below plus `dg validate` and `git diff --check`. Record commands, outcomes and any environmental limitation. Existing green tests do not replace new regression coverage for this issue.
- Commit coherent issue work with this issue ID followed by a colon in the subject. Follow the implementation handoff to `review`; do not mark done or bypass independent verification. Update architecture guidance only for the final ownership/behavior.


### Comment — claude @ 2026-10-12T21:09:06.276Z

EditHistoryCoordinator now registers every op task (nested refreshes included), rejects work after beginShutdown (called early in AppViewModel.shutdown), fences all publication on lifecycle+source, cancels reads, and drains accepted snapshot/restore/copy writes in shutdown() before library/lease release. Tests: gated refresh + gated snapshot shutdown. Checks: swift build; focused swift test (69 pass); dg validate; git diff --check.

## Agent log

- 2026-10-12T21:17:28.561Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Gated refresh success or failure released during shutdown cannot publish history or current revision state. (pass) — Reviewed lifecycle/source fences and ran gated refresh shutdown regression; no published-state notifications occur after shutdown begins.
- [x] Gated snapshot, restore, and virtual-copy operations are owned and cannot access released package resources; accepted writes settle before lease release. (pass) — Found and fixed cancellation of accepted writes while awaiting persistence flush. Shutdown now cancels refresh reads only and drains accepted writes; gated-flush snapshot regression confirms the write settles before shutdown returns.
- [x] New work is rejected after shutdown starts, nested refreshes included, and repeated shutdown is safe. (pass) — Coordinator rejects new operations, nested refreshes are rejected by the lifecycle guard, and repeated shutdown remains safe.
- [x] Existing flush-before-write, named-snapshot, virtual-copy, and source-switch behavior is retained. (pass) — Covered by the focused coordinator and store test suites.
- [x] Shutdown does not hang on cancellation-oblivious work; tests release deterministic gates and observe completion. (pass) — The gated refresh and snapshot tests release their continuation gates and await shutdown completion.
- [x] No fire-and-forget durable-history task remains outside the coordinator owner. (pass) — AppViewModel forwards to EditHistoryCoordinator; every coordinator operation is registered and drained.
Checks run:
- swift build: exit 0.
- swift test --no-parallel --filter 'EditHistoryCoordinatorTests|EditDocumentStoreTests|AppViewModelTests|PackageSettingsTests': exit 0; 70 tests passed.
- dg validate: exit 0; emitted existing agent-model-name warnings.
- git diff --check: exit 0.
Findings:
- Fixed during verification: beginShutdown cancelled accepted snapshot/restore/copy operations even while they awaited persistence.flush(); the flush observes Task cancellation and could abort an accepted durable write before it reached the store.
Fixes:
- Tracked whether owned operations are cancellable reads; shutdown now cancels refresh reads and allows accepted restore/snapshot/virtual-copy operations to finish before the package lease is released.
- Added a deterministic gated-flush snapshot regression test confirming shutdown drains an accepted write and prevents its nested history refresh.
Verification commits:
- 2cbb253f
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5R243L7BY6CYJU
Summary: Independent verification passed; fixed shutdown cancellation of accepted durable history writes.
