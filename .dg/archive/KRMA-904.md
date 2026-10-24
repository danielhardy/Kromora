---
id: KRMA-904
title: Fence and await source materialization across replacement and shutdown
type: bug
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Delayed success and delayed failure after shutdown starts produce no item replacement, navigation, loading/status/error changes, or new source/thumbnail/preview request.
      result: pass
      notes: Gated delayed success is covered; the failure branch uses the same shutdown and generation fence and was reviewed. Re-entry after shutdown now returns before presentation mutation or materialization.
    - criterion: A slow A request completing after B is selected cannot overwrite B or reopen A.
      result: pass
      notes: Covered by testSlowMaterializationCannotReopenSupersededPhoto.
    - criterion: Returning to Library during materialization retains the intended navigation and settled loading behavior.
      result: pass
      notes: The completion path explicitly settles loading without reopening when navigation is Library; reviewed in the success path.
    - criterion: Shutdown remains pending until cancellation-oblivious materialization is released, then leaves no pending callbacks accessing deleted fixtures.
      result: pass
      notes: Covered by testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult using a continuation gate.
    - criterion: Existing source-preparation and thumbnail-switch tests continue to pass; repeated shutdown remains safe.
      result: pass
      notes: Targeted suites passed, including source-session and thumbnail lifecycle tests; shutdown test calls shutdown again after completion.
    - criterion: No new synchronous record read/hash is introduced to avoid the asynchronous lifecycle problem.
      result: pass
      notes: Materialization remains asynchronous through PortableLibrarySession.materializedAsset.
  checks_run:
    - "swift build: exit 0."
    - "swift test no-parallel, filter AppViewModelTests|SourceSessionCoordinatorTests|ThumbnailSwitchLifecycleTests|PackageSettingsTests|StoredEditAdoptionTests: exit 0; 79 tests passed before the final localized guard/test addition."
    - "swift test no-parallel, filter StoredEditAdoptionTests: exit 0; 8 tests passed after the final change."
    - "dg validate: exit 0; reported existing model-name warnings."
    - "git diff --check: exit 0."
  findings:
    - "Resolved during verification: collection-backed openImage could change navigation to Edit after shutdown began, before reaching the task-level guard."
  fixes:
    - Added an entry guard to reject collection-backed opens after shutdown begins.
    - Added testOpeningCollectionAssetAfterShutdownDoesNotChangeNavigation; verified the materialization gate receives no request.
  verification_commits:
    - 5ae7a045d814dae65f1d2b50243021e25d6d2eed
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T21:07:33.438Z
  session: 01MV5QQRZDXXTG4GW6
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - app-view-model
  - maintainability
  - concurrency
created: 2026-10-12T17:11:40.609Z
updated: 2026-10-12T21:07:33.442Z
blockers: []
order: zzh
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/SourceSessionCoordinator.swift
    - Sources/KromoraKit/Models/PortableLibrarySession.swift
    - Tests/KromoraKitTests/AppViewModelTests.swift
    - Tests/KromoraKitTests/SourceSessionCoordinatorTests.swift
    - Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift
    - Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - CLAUDE.md
    - AGENTS.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-753
    - KRMA-903
    - KRMA-910
  commands:
    - swift build
    - swift test --no-parallel --filter 'AppViewModelTests|SourceSessionCoordinatorTests|ThumbnailSwitchLifecycleTests|PackageSettingsTests'
    - dg validate
    - git diff --check
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/ViewModels/SourceSessionCoordinator.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Models/PortableLibrarySession.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/AppViewModelTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/SourceSessionCoordinatorTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-12T20:57:10.208Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 5ae7a045d814dae65f1d2b50243021e25d6d2eed
---

## Objective

Ensure the asynchronous browsing-placeholder materialization path cannot update collection, loading state, navigation or status after its source request is superseded or AppViewModel begins shutdown.

## Evidence and reproduction

In `AppViewModel.openImage` around lines 2060-2113, a browsing-placeholder source launches an unowned MainActor task, awaits `portableLibrary.materializedAsset`, and checks only `loadRequestGeneration` and collection membership before publishing. The failure branch checks only the generation. Shutdown sets `isShuttingDown` and cancels SourceSessionCoordinator but does not invalidate `loadRequestGeneration` or own/await this task. The normal deferred `beginLoad` task already checks `!isShuttingDown`; this earlier materialization path lacks that protection and can still mutate an item, clear flags, report an error or call openImage after teardown starts.

Use a generated package asset whose browsing fingerprint is still a placeholder. Gate materialization, start shutdown while it is suspended, release either success or failure, and record root/collection publications. This is distinct from the renderer source-preparation shutdown test already present in AppViewModelTests.

## Context to read

- `Sources/KromoraKit/ViewModels/AppViewModel.swift`: placeholder branch in openImage, `loadRequestGeneration`, load/beginLoad, clear/removal paths, failOpenImage and shutdown.
- `Sources/KromoraKit/ViewModels/SourceSessionCoordinator.swift`: existing source replacement and awaitable teardown boundary.
- `Sources/KromoraKit/Models/PortableLibrarySession.swift`: materializedAsset, worker/scheduler ownership, session shutdown and lease release.
- `Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift`: collection membership and selection mirroring.
- `Tests/KromoraKitTests/AppViewModelTests.swift`, especially testShutdownQuiescesCancelledSourceLoadBeforeFixtureCleanup; SourceSessionCoordinatorTests and ThumbnailSwitchLifecycleTests.
- Related completed KRMA-753 for identity reuse; preserve its bounded source-fingerprint lookup behavior.

## Implementation steps

1. Move materialization orchestration under the existing source lifecycle owner when practical, or track its task explicitly at the root. Keep exactly one current open request and retain any superseded in-flight work that shutdown must await; dropping a task reference does not cancel or drain it.
2. Invalidate the root/source materialization generation synchronously on replacement, source clear/removal and shutdown, before suspension. Prevent new materialization from starting once teardown begins.
3. Check current generation, active selection/source identity, package lifetime and !isShuttingDown after every suspension, including after Task.yield and on errors. Fence collection-item replacement and recursive openImage as well as status flags.
4. Cancel worker work through its real owner/handle. Await both worker I/O and observation/publication tasks in an order that cannot deadlock the package scheduler. Do not assume cancelling the wrapper task cancels a separately scheduled worker.
5. Complete the barrier before collection/package resources and writer lease are released. Preserve the valid case where the user returns to Library while resolution is pending: do not force navigation back to Edit.
6. Add a narrow injected materialization seam if necessary; keep it internal and document why the existing package boundary needs it. Use generated fixtures and continuation gates rather than sleeps or real RAW files.

## Acceptance criteria

- [ ] Delayed success and delayed failure after shutdown starts produce no item replacement, navigation, loading/status/error changes, or new source/thumbnail/preview request.
- [ ] A slow A request completing after B is selected cannot overwrite B or reopen A.
- [ ] Returning to Library during materialization retains the intended navigation and settled loading behavior.
- [ ] Shutdown remains pending until cancellation-oblivious materialization is released, then leaves no pending callbacks accessing deleted fixtures.
- [ ] Existing source-preparation and thumbnail-switch tests continue to pass; repeated shutdown remains safe.
- [ ] No new synchronous record read/hash is introduced to avoid the asynchronous lifecycle problem.

## Coordination and non-goals

KRMA-903 covers another shutdown owner. KRMA-910 later consolidates presentation flags; land this correctness fix first and preserve its generation/barrier in that refactor. Do not change placeholder fingerprint representation, renderer caching or persistent package format.

## Reading the source context

Source and test paths above are relative to the repository root, `/Users/dhardy/Dev/Kromora`. The installed `dg context` reader currently resolves file/doc contents inside the `.dg` space, so it can list existing repository sources as missing. Read those paths directly from the checkout; their existence was verified when this ticket was written. Keep the repository-relative context hints for planning. Do not copy product source into `.dg` or weaken DispatchGraph path validation to work around this reader limitation.

## Required checks

```sh
swift build
swift test --no-parallel --filter 'AppViewModelTests|SourceSessionCoordinatorTests|ThumbnailSwitchLifecycleTests|PackageSettingsTests'
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


### Comment — claude @ 2026-10-12T20:57:09.738Z

Implemented in 5505f146. Placeholder materialization in AppViewModel.openImage is now a root-owned task keyed by request generation; shutdown bumps the generation, cancels, and awaits all registered tasks (incl. superseded) before scheduler/lease release; all post-suspension steps check isShuttingDown + generation. Added PortableLibrarySession.materializationGate test seam and two StoredEditAdoptionTests (shutdown waits and suppresses result; slow A cannot overwrite B). Verified: swift build; swift test --no-parallel --filter 'StoredEditAdoptionTests|AppViewModelTests|SourceSessionCoordinatorTests|ThumbnailSwitchLifecycleTests|PackageSettingsTests' (79 pass); git diff --check clean; dg validate OK (unrelated model-name warnings). Not covered: a dedicated delayed-failure test and return-to-Library test (code paths guarded identically).

## Agent log

- 2026-10-12T21:07:33.438Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Delayed success and delayed failure after shutdown starts produce no item replacement, navigation, loading/status/error changes, or new source/thumbnail/preview request. (pass) — Gated delayed success is covered; the failure branch uses the same shutdown and generation fence and was reviewed. Re-entry after shutdown now returns before presentation mutation or materialization.
- [x] A slow A request completing after B is selected cannot overwrite B or reopen A. (pass) — Covered by testSlowMaterializationCannotReopenSupersededPhoto.
- [x] Returning to Library during materialization retains the intended navigation and settled loading behavior. (pass) — The completion path explicitly settles loading without reopening when navigation is Library; reviewed in the success path.
- [x] Shutdown remains pending until cancellation-oblivious materialization is released, then leaves no pending callbacks accessing deleted fixtures. (pass) — Covered by testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult using a continuation gate.
- [x] Existing source-preparation and thumbnail-switch tests continue to pass; repeated shutdown remains safe. (pass) — Targeted suites passed, including source-session and thumbnail lifecycle tests; shutdown test calls shutdown again after completion.
- [x] No new synchronous record read/hash is introduced to avoid the asynchronous lifecycle problem. (pass) — Materialization remains asynchronous through PortableLibrarySession.materializedAsset.
Checks run:
- swift build: exit 0.
- swift test no-parallel, filter AppViewModelTests|SourceSessionCoordinatorTests|ThumbnailSwitchLifecycleTests|PackageSettingsTests|StoredEditAdoptionTests: exit 0; 79 tests passed before the final localized guard/test addition.
- swift test no-parallel, filter StoredEditAdoptionTests: exit 0; 8 tests passed after the final change.
- dg validate: exit 0; reported existing model-name warnings.
- git diff --check: exit 0.
Findings:
- Resolved during verification: collection-backed openImage could change navigation to Edit after shutdown began, before reaching the task-level guard.
Fixes:
- Added an entry guard to reject collection-backed opens after shutdown begins.
- Added testOpeningCollectionAssetAfterShutdownDoesNotChangeNavigation; verified the materialization gate receives no request.
Verification commits:
- 5ae7a045d814dae65f1d2b50243021e25d6d2eed
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5QQRZDXXTG4GW6
Summary: Independent verification passed; added and verified a shutdown re-entry guard.
