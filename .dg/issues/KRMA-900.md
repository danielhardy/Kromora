---
id: KRMA-900
title: Scope dust suggestions and visualization to the active photo and request generation
type: bug
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A late success or failure for A cannot change B's suggestions, overlay candidates, status, or document.
      result: pass
      notes: Deterministic gated success and failure cases; stale requests are discarded after source change.
    - criterion: Completed A suggestions are cleared when moving to B, clearing the source, or removing the active asset; stale Accept/Accept All is harmless.
      result: pass
      notes: Source-change reset clears photo state; stale accept checks the owning source.
    - criterion: Turning visualization off while analysis is suspended leaves candidates empty after the old request completes.
      result: pass
    - criterion: Slow request A finishing after request B cannot replace B's output, including repeated Detect Dust on the same photo.
      result: pass
      notes: Deterministic same-photo latest-request-wins test passes.
    - criterion: Shutdown rejects new requests, clears transient output, and awaits owned work without post-return publications.
      result: pass
      notes: Gated shutdown regression test passes.
    - criterion: Accepting current-photo suggestions still creates the existing undo grouping and persisted retouch recipe.
      result: pass
      notes: Current-photo Accept All regression test confirms spots are added and undo grouping closes.
  checks_run:
    - swift build — passed
    - swift test --no-parallel --filter 'RetouchWorkflowCoordinatorTests|RetouchDustDetectorTests|AppViewModelTests|PackageSettingsTests' — passed; 68 tests, 0 failures
    - dg validate — passed; emitted existing agent model-name warnings
    - git diff --check — passed
  findings: []
  fixes:
    - Added a deterministic regression test ensuring a stale nil proxy result cannot publish a failure status on the newly selected photo.
  verification_commits:
    - d1bb5996
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T19:41:03.241Z
  session: 01MV5NO3Y3OWOGDVTX
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - app-view-model
  - maintainability
  - concurrency
created: 2026-10-12T17:11:37.825Z
updated: 2026-10-12T19:41:03.244Z
blockers: []
order: z
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift
    - Sources/KromoraKit/Models/RetouchInteractionState.swift
    - Tests/KromoraKitTests/RetouchWorkflowCoordinatorTests.swift
    - Tests/KromoraKitTests/AppViewModelTests.swift
    - Sources/KromoraKit/Models/RetouchAnalysis/RetouchAnalysisProxy.swift
    - Sources/KromoraKit/Views/RetouchInspectorView.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - CLAUDE.md
    - AGENTS.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-901
  commands:
    - swift build
    - swift test --no-parallel --filter 'RetouchWorkflowCoordinatorTests|RetouchDustDetectorTests|AppViewModelTests|PackageSettingsTests'
    - dg validate
    - git diff --check
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Models/RetouchInteractionState.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/RetouchWorkflowCoordinatorTests.swift
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
    captured_at: 2026-10-12T19:36:31.687Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - d1bb5996
---

## Objective

Prevent dust suggestions or visualization candidates from photo A from appearing on or being accepted into photo B. Give retouch analysis one explicit source/request lifecycle in the existing retouch workflow owner.

## Evidence and reproduction

The 2026-10-12 AppViewModel review found that `detectRetouchDust()` (approximately lines 3467-3478) captures `imageSource`, awaits `engine.retouchAnalysisProxy`, then publishes suggestions/status without validating the current source or request. `refreshRetouchVisualization()` (3481-3490) checks visualization enabled only before its suspension. Its result can publish after the feature is switched off. Both paths launch unowned tasks. `RetouchInteractionState.disarm()` clears gesture state but leaves suggestions and visualization candidates; the source-switch path in AppViewModel does not reset those buffers. `RetouchWorkflowCoordinator.acceptDustSuggestion/acceptAllDustSuggestions` inserts suggestions into whichever document is current.

Reproduce deterministically with a gated proxy provider: start detection for A, switch to B while suspended, release A, and inspect B's interaction state and status. Also detect A to completion, switch to B, then inspect/attempt Accept All. The expected result is no A suggestions on B. This is a correctness defect even when CPU analysis is fast.

## Context to read

- `Sources/KromoraKit/ViewModels/AppViewModel.swift`: retouch entry points, `openImage`, `load`, source installation, removal/clear paths, `shutdown`.
- `Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift`: interaction ownership, accept/dismiss operations, destination protocol, source picking.
- `Sources/KromoraKit/Models/RetouchInteractionState.swift`: suggestion storage and disarm behavior.
- `Sources/KromoraKit/Models/RetouchAnalysis/RetouchDustDetector.swift` and `RetouchAnalysisProxy.swift`: value-only inputs/results.
- `Sources/KromoraKit/Views/RetouchInspectorView.swift`, `Models/RenderEngine.swift`, and `docs/APP_ARCHITECTURE.md`.
- Existing `RetouchWorkflowCoordinatorTests`, `RetouchDustDetectorTests`, `AppViewModelTests`, and the fake-engine synchronization helpers.

## Implementation steps

1. Extend `RetouchWorkflowCoordinator` with an explicit active-source lifecycle, or a small owned collaborator if this is clearer. Keep AppViewModel entry points as forwarding/wiring; retain the root's sole published EditDocument.
2. Track task handles and monotonically changing generations. Capture immutable source identity/revision, request identity, and threshold when starting. Cancellation must invalidate generation before awaiting cleanup.
3. On source switch, source removal, and shutdown, cancel/invalidate outstanding requests and clear photo-specific suggestions/candidates/gesture selection. Preserve user preferences such as threshold and overlay policy unless existing product behavior requires otherwise.
4. Before every success/failure/status publication after suspension, require the same source, current request, and a live owner. Visualization additionally requires that it is still enabled. Cancelling an obsolete request must not display a failure on the new photo.
5. Defensively scope acceptance to the source that owns the suggestions. A stale UI command must not insert A's coordinates into B's document, even if a future caller retains a suggestion ID.
6. Wire explicit shutdown from AppViewModel before renderer/session resources are released. Use deterministic continuation gates to test cancellation-oblivious completions; cancellation alone is not a publication fence.

## Acceptance criteria

- [ ] A late success or failure for A cannot change B's suggestions, overlay candidates, status, or document.
- [ ] Completed A suggestions are cleared when moving to B, clearing the source, or removing the active asset; stale Accept/Accept All is harmless.
- [ ] Turning visualization off while analysis is suspended leaves candidates empty after the old request completes.
- [ ] Slow request A finishing after request B cannot replace B's output, including repeated Detect Dust on the same photo.
- [ ] Shutdown rejects new requests, clears transient output, and awaits owned work without post-return publications.
- [ ] Accepting current-photo suggestions still creates the existing undo grouping and persisted retouch recipe.

## Coordination and non-goals

This is the prerequisite for KRMA-901, which moves CPU work and coalesces slider requests. Establish lifecycle correctness here without changing detector mathematics, thresholds, quality limits, or renderer cache identity. The existing detector tests pass but do not cover these cross-photo races. Update architecture ownership documentation for the new lifecycle.

## Reading the source context

Source and test paths above are relative to the repository root, `/Users/dhardy/Dev/Kromora`. The installed `dg context` reader currently resolves file/doc contents inside the `.dg` space, so it can list existing repository sources as missing. Read those paths directly from the checkout; their existence was verified when this ticket was written. Keep the repository-relative context hints for planning. Do not copy product source into `.dg` or weaken DispatchGraph path validation to work around this reader limitation.

## Required checks

```sh
swift build
swift test --no-parallel --filter 'RetouchWorkflowCoordinatorTests|RetouchDustDetectorTests|AppViewModelTests|PackageSettingsTests'
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


### Comment — claude @ 2026-10-12T19:36:28.475Z

Moved dust/visualization analysis into RetouchWorkflowCoordinator with per-request generations, source fingerprint fences, source-change/shutdown invalidation, and source-scoped Accept. Added 7 deterministic gated-provider tests. swift build, focused swift test (67 pass), dg validate, git diff --check all ok.

## Agent log

- 2026-10-12T19:41:03.241Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A late success or failure for A cannot change B's suggestions, overlay candidates, status, or document. (pass) — Deterministic gated success and failure cases; stale requests are discarded after source change.
- [x] Completed A suggestions are cleared when moving to B, clearing the source, or removing the active asset; stale Accept/Accept All is harmless. (pass) — Source-change reset clears photo state; stale accept checks the owning source.
- [x] Turning visualization off while analysis is suspended leaves candidates empty after the old request completes. (pass)
- [x] Slow request A finishing after request B cannot replace B's output, including repeated Detect Dust on the same photo. (pass) — Deterministic same-photo latest-request-wins test passes.
- [x] Shutdown rejects new requests, clears transient output, and awaits owned work without post-return publications. (pass) — Gated shutdown regression test passes.
- [x] Accepting current-photo suggestions still creates the existing undo grouping and persisted retouch recipe. (pass) — Current-photo Accept All regression test confirms spots are added and undo grouping closes.
Checks run:
- swift build — passed
- swift test --no-parallel --filter 'RetouchWorkflowCoordinatorTests|RetouchDustDetectorTests|AppViewModelTests|PackageSettingsTests' — passed; 68 tests, 0 failures
- dg validate — passed; emitted existing agent model-name warnings
- git diff --check — passed
Findings:
- None
Fixes:
- Added a deterministic regression test ensuring a stale nil proxy result cannot publish a failure status on the newly selected photo.
Verification commits:
- d1bb5996
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5NO3Y3OWOGDVTX
Summary: Verification passed: source/request fencing, stale failure regression, and all declared checks pass.
