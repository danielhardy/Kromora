---
id: KRMA-896
title: Fence Derive Look progress and completion against cancellation and supersession
type: bug
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Cancellation during late extraction cannot publish success, ordinary failure, or queued progress after dismissal.
      result: pass
      notes: Deterministic stale success/failure and delayed progress tests passed.
    - criterion: A dismissed operation cannot affect a newer derive; the newer operation can complete and retain its scratch result.
      result: pass
      notes: Supersession test passed and saved the newer operation’s LUT.
    - criterion: Shutdown cancels and awaits every owned worker, including workers retired by dismiss, with no stale callbacks publishing.
      result: pass
      notes: Shutdown regression test passed; shutdown now also rejects a new derive while draining.
    - criterion: Completed-result retention and scratch save/atomic replacement behavior remain correct.
      result: pass
      notes: Existing DeriveCoordinatorTests passed.
    - criterion: Regression coverage uses controlled workers and generated LUT data, without RAW fixtures or timing sleeps.
      result: pass
      notes: New race coverage uses semaphore-controlled fake extraction and generated LUT values.
    - criterion: Synchronous framework rendering may remain non-interruptible, but stale output cannot publish.
      result: pass
      notes: RecipeExtractor cancellation checkpoints and coordinator generation fencing prevent publication after render returns.
  checks_run:
    - swift build (passed)
    - swift test --filter DeriveCoordinatorTests (17 tests passed)
    - swift test --filter RecipeExtractorTests (10 tests passed)
    - dg validate (passed; existing model-name warnings)
    - git diff --check (passed)
  findings: []
  fixes:
    - Clean operation-specific scratch directories when serialization fails or is cancelled after directory creation.
    - Reject new derive requests once shutdown begins, closing the actor-reentrancy window while retired workers drain.
  verification_commits:
    - 3642faea45d10d8fbd2dbf314ceefa553a378b22
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T19:43:08.428Z
  session: 01MV5NRHL1RPCFWSBJ
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - concurrency
  - derive
  - correctness
created: 2026-10-12T16:38:00.858Z
updated: 2026-10-12T19:43:08.431Z
blockers: []
order: zh
board: product
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/DeriveCoordinator.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/DeriveCoordinatorTests.swift
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-12T19:39:07.483Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 3642faea45d10d8fbd2dbf314ceefa553a378b22
---

## Objective

Ensure dismissing, replacing, or shutting down a Derive Look operation prevents every stale progress, success, and failure callback from affecting the current operation or active photo.

## Problem and user impact

`DeriveCoordinator.derive` starts a detached task at roughly line 127. Progress creates separate unstructured main-actor tasks. Success uses `MainActor.run` at lines 148-156 without a cancellation or generation check; the non-cancellation failure path is likewise unfenced. `dismiss()` cancels the current task, sets its handle to nil, and immediately resets `isDeriving`, allowing another derive to start while the previous worker is still finishing.

`RecipeExtractor.derive` checks cancellation after sampling, but not after cube construction, EXIF reading, serialization, or before final publication. Cancellation during those stages can therefore return normally and still call `onDerived`. `AppViewModel.wireCoordinators` wires `onDerived` to `selectLook` for whichever photo is active at that time. A cancelled operation can overwrite a newer derive's result, reset its busy state, or unexpectedly apply the old Look to the active photo. Queued progress callbacks can also restore progress after dismissal. `shutdown()` cannot await workers whose handles were dropped by `dismiss()`.

This is a code-path/race finding, not a claim that a real RAW reproduction was run. Swift cancellation is cooperative: https://docs.swift.org/latest/documentation/swift/task/cancel%28%29/.

## Context to read

- `Sources/KromoraKit/ViewModels/DeriveCoordinator.swift`: `derive`, `dismiss`, `shutdown`, scratch file ownership, `performSave`.
- `Sources/KromoraKit/Models/RecipeExtractor.swift`: cancellation checkpoints and progress callbacks, especially after sampling through the final return.
- `Sources/KromoraKit/ViewModels/AppViewModel.swift`: `derive.onDerived` wiring and shutdown composition.
- `Tests/KromoraKitTests/DeriveCoordinatorTests.swift`: existing tests cover idle dismissal and completed results, not cancellation during extraction/publication.
- `Tests/KromoraKitTests/TestSynchronization.swift`: existing deterministic async test helpers.

## Implementation guidance

1. Give each derive a monotonically changing token/generation. Invalidate it synchronously on dismiss, replacement, and shutdown, before stale callbacks can publish.
2. Capture the token in progress, success, and failure callbacks. On the main actor, check that the operation remains current before mutating any UI/result state or invoking callbacks. A `Task.isCancelled` check inside a newly created progress task does not describe the original extraction task; use operation identity.
3. Add cancellation checkpoints after extraction and before writing/publishing. Main-actor generation validation is still required because cancellation can race the final actor hop.
4. Keep dismissal immediate. Retain or otherwise track cancelled workers until they finish so shutdown can await all outstanding work. Do not block the UI awaiting synchronous extraction.
5. Use an operation-specific scratch URL/directory so overlapping retired and current workers cannot overwrite or delete each other's file. Clean up unpublished stale scratch output. Keep a successfully completed result available across ordinary sheet close/reopen.
6. Introduce only the smallest injectable extraction/progress seam needed for deterministic tests; fake workers should return normal values even after cancellation to test the publication fence. Keep Core Image objects out of cross-actor values.

## Acceptance criteria

- [ ] Cancel during late extraction/serialization: later success, ordinary error, and queued progress do not repopulate dismissed state or call `onDerived`/`onError`.
- [ ] Start A, dismiss A, start B, finish A after B starts: A cannot change B's busy state, progress, result, status, or scratch ownership; B can finish normally.
- [ ] Tests exercise both stale success and stale non-CancellationError, plus delayed progress delivery.
- [ ] Shutdown cancels and awaits all owned workers, including one previously cancelled by dismiss; no callbacks publish after shutdown.
- [ ] Existing completed-result retention and scratch save/atomic replacement tests remain green.
- [ ] Regression tests use controlled continuations/signals and generated LUT values, without a real RAW fixture or sleep-based timing assumptions.

## Verification

Run `swift build`, `swift test --filter DeriveCoordinatorTests`, `swift test --filter RecipeExtractorTests`, `dg validate`, and `git diff --check`. A synchronous framework render may remain non-interruptible; document that separately from the guarantee that its stale output cannot publish.
## Repository and workflow constraints

- Read `CLAUDE.md` and `.dg/AGENTS.md` before implementation. Target macOS 26+ on Apple Silicon, Swift 6, and Apple frameworks only. Keep the zero-opt-out concurrency contract: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
- Claim this issue before changing code. Preserve unrelated working-tree changes. Work on the current branch, commit only coherent issue work with this issue ID in the subject, and hand off to `review` according to `.dg/AGENTS.md`.
- Use generated temporary fixtures and deterministic synchronization. Do not run display-bound release capture benchmarks for these fixes. Product implementations belong in `Sources/KromoraKit`, not the launchers or Xcode packaging target.
- Review evidence was collected on 2026-10-12 using Xcode 27 / Swift 6.4. The combined existing `PackagePathTests|DeriveCoordinatorTests|PhotosDeliveryTests|AnalysisValueTypesTests` selection passed 24 tests, but those green results do not cover the defects described here. Do not treat them as regression coverage for the new behavior.


### Comment — claude @ 2026-10-12T19:39:03.979Z

Added per-derive generation fence, tracked retired workers (shutdown awaits all), per-operation scratch dirs, extra RecipeExtractor cancellation checkpoints, and an injectable extractor seam. New tests cover stale success/failure/progress, A/B supersession, shutdown. DeriveCoordinatorTests/RecipeExtractorTests/PackageSettingsTests pass. Note: a synchronous Core Image render inside the extractor remains non-interruptible; its stale output cannot publish.

## Agent log

- 2026-10-12T19:43:08.428Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Cancellation during late extraction cannot publish success, ordinary failure, or queued progress after dismissal. (pass) — Deterministic stale success/failure and delayed progress tests passed.
- [x] A dismissed operation cannot affect a newer derive; the newer operation can complete and retain its scratch result. (pass) — Supersession test passed and saved the newer operation’s LUT.
- [x] Shutdown cancels and awaits every owned worker, including workers retired by dismiss, with no stale callbacks publishing. (pass) — Shutdown regression test passed; shutdown now also rejects a new derive while draining.
- [x] Completed-result retention and scratch save/atomic replacement behavior remain correct. (pass) — Existing DeriveCoordinatorTests passed.
- [x] Regression coverage uses controlled workers and generated LUT data, without RAW fixtures or timing sleeps. (pass) — New race coverage uses semaphore-controlled fake extraction and generated LUT values.
- [x] Synchronous framework rendering may remain non-interruptible, but stale output cannot publish. (pass) — RecipeExtractor cancellation checkpoints and coordinator generation fencing prevent publication after render returns.
Checks run:
- swift build (passed)
- swift test --filter DeriveCoordinatorTests (17 tests passed)
- swift test --filter RecipeExtractorTests (10 tests passed)
- dg validate (passed; existing model-name warnings)
- git diff --check (passed)
Findings:
- None
Fixes:
- Clean operation-specific scratch directories when serialization fails or is cancelled after directory creation.
- Reject new derive requests once shutdown begins, closing the actor-reentrancy window while retired workers drain.
Verification commits:
- 3642faea45d10d8fbd2dbf314ceefa553a378b22
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5NRHL1RPCFWSBJ
Summary: Verification passed: stale derive publications are fenced, shutdown tracks retired workers, and verification cleanup/reentrancy fixes are committed.
