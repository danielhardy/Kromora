---
id: KRMA-902
title: Move Open Image dialog imports onto the existing asynchronous package worker
type: bug
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A gated importer proves Open Image returns control and permits a main-actor sentinel before the import completes.
      result: pass
      notes: Added testOpenImagesReturnsWhilePackageWorkerIsGated; the import remains queued and unpublished while the main-actor sentinel runs, then completes after gate release.
    - criterion: Generated multiple-file and repeated-URL imports preserve sorted names, embedded URL backing, duplicate summary, and initial selection.
      result: pass
      notes: OpenImageDialogTests sorted multi-file, URL-backed asset, repeated URL, and first-item source-loading assertions pass.
    - criterion: Empty input and panel cancellation leave collection, document, and navigation unchanged.
      result: pass
      notes: OpenImageDialogTests and FileIntegrationBoundaryTests pass for empty result and cancelled dialog behavior.
    - criterion: Cancellation, partial commits, failure, supersession, and shutdown produce a correct terminal outcome without stale publication.
      result: pass
      notes: The operation observer fences terminal callbacks by current operation and shutdown state; superseded import regression passes. Existing worker cancellation coverage confirms committed assets remain queryable.
    - criterion: Security access remains valid through worker reads and is released on terminal paths; package writer concurrency stays one.
      result: pass
      notes: Reviewed PortableLibrarySession.startImport ownership transfer and terminal release; focused package import coordinator and durability tests pass.
    - criterion: Dialog callers use the asynchronous import API and do not depend on an immediate final summary.
      result: pass
      notes: openImages starts startImportURLs and observes completion; callers/tests await the completion callback.
  checks_run:
    - swift build (pass)
    - swift test --no-parallel --filter OpenImageDialogTests|ImportedPhotoDurabilityTests|FileIntegrationBoundaryTests|PackageSourceImportCoordinatorTests|PackageSettingsTests (30 tests passed)
    - swift test --no-parallel --filter OpenImageDialogTests.testOpenImagesReturnsWhilePackageWorkerIsGated (1 test passed)
    - dg validate (pass; emitted existing unknown-model warnings)
    - git diff --check (pass)
  findings: []
  fixes:
    - Added deterministic gated-worker responsiveness coverage to OpenImageDialogTests.
  verification_commits:
    - b9a9950694dcf95d7429cedee409b6c8be391e9a
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T20:04:09.206Z
  session: 01MV5OHE2Z8UHBLC15
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - app-view-model
  - maintainability
  - concurrency
created: 2026-10-12T17:11:39.167Z
updated: 2026-10-12T20:04:09.211Z
blockers: []
order: zx
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/LibraryImportCoordinator.swift
    - Sources/KromoraKit/ViewModels/PackageSourceImportCoordinator.swift
    - Sources/KromoraKit/ViewModels/LibraryMediaWorkflowCoordinator.swift
    - Tests/KromoraKitTests/OpenImageDialogTests.swift
    - Tests/KromoraKitTests/FileIntegrationBoundaryTests.swift
    - Tests/KromoraKitTests/PackageSourceImportCoordinatorTests.swift
    - Sources/KromoraKit/Models/SecurityScopedResourceAccess.swift
    - Tests/KromoraKitTests/ImportedPhotoDurabilityTests.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - CLAUDE.md
    - AGENTS.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-518
    - KRMA-540
  commands:
    - swift build
    - swift test --no-parallel --filter 'OpenImageDialogTests|ImportedPhotoDurabilityTests|FileIntegrationBoundaryTests|PackageSourceImportCoordinatorTests|PackageSettingsTests'
    - dg validate
    - git diff --check
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/ViewModels/LibraryImportCoordinator.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/ViewModels/PackageSourceImportCoordinator.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/ViewModels/LibraryMediaWorkflowCoordinator.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/OpenImageDialogTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/FileIntegrationBoundaryTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/PackageSourceImportCoordinatorTests.swift
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-12T19:52:58.949Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - b9a9950694dcf95d7429cedee409b6c8be391e9a
---

## Objective

Make Open Image responsive during copying, hashing and package persistence by using the existing scheduler-backed import path, while preserving sorted collection publication, duplicate handling, outcome reporting and initial selection.

## Evidence and historical context

`AppViewModel.openImageDialog()` calls `openImages(urls:access:)`. At approximately lines 2735-2741, `openImages` deliberately invokes synchronous `libraryImportCoordinator.importURLs`, then reloads the collection. That coordinator delegates to main-actor `PortableLibrarySession.importURLs/importPackageSources`, which calls `package.importSources` and persists the resulting index synchronously. All selected originals can therefore be copied/hashed/committed before the UI regains control. Empty input is currently an immediate no-op.

KRMA-518 implemented the worker-backed API, but completed KRMA-540 restored synchronous publication to satisfy OpenImageDialogTests. Read both for context: preserve their user-visible result while removing the immediate-return test assumption. Do not reopen either completed ticket. Folder/Photos imports already use `startImportURLs/startImportData` and handle observation. Apple's file-system guidance is https://developer.apple.com/documentation/foundation/improving-performance-and-stability-when-accessing-the-file-system.

## Context to read

- `Sources/KromoraKit/ViewModels/AppViewModel.swift`: `openImages`, `openImageDialog`, `beginImportOperation`, outcome presentation, reload/open helpers, shutdown, and protocol forwarding near the end of the file.
- `ViewModels/LibraryImportCoordinator.swift`: start methods, operation generations, progress merging, cancellation and observation.
- `ViewModels/PackageSourceImportCoordinator.swift` and `LibraryMediaWorkflowCoordinator.swift`: existing observer/result contracts and callers of `openImages`.
- `Models/PortableLibrarySession.swift`, `PortablePackageImport.swift`, `SecurityScopedResourceAccess.swift`, and `ImageWorkScheduler.swift`.
- `Tests/KromoraKitTests/OpenImageDialogTests.swift`, `ImportedPhotoDurabilityTests.swift`, `FileIntegrationBoundaryTests.swift`, `PackageSourceImportCoordinatorTests.swift`.

## Implementation steps

1. Inventory all `openImages` callers, including protocol adapters and tests. Replace reliance on an immediately returned final summary with an explicit asynchronous terminal result/completion or the existing observer contract. Keep the panel-facing action simple and nonblocking.
2. Start the existing worker-backed URL import; reuse the same operation ID, progress, cancellation, committed-item merge, and outcome owner used by other package imports. Do not add another package writer, duplicate copy loop, or new scheduler lane.
3. Transfer security-scoped access ownership to the asynchronous operation. Remove any defer that releases it on the initiating method's return; release exactly once through the existing access owner after terminal completion/cancellation/error.
4. On current-operation success, preserve display-name stem overrides, deduplication, sorted URL-backed assets, collection reload and initial-open behavior. Preserve current selection semantics in a nonempty library; do not silently redesign selection as part of the performance fix.
5. Fence late success/failure and UI updates against a newer import, package lifetime and shutdown. Preserve already committed assets on partial cancellation and truthful ImportOutcomeSummary accounting.
6. Rewrite immediate collection assertions in OpenImageDialogTests to await a deterministic completion/event before inspecting assets. Keep empty/cancelled panel selection a no-op that does not cancel unrelated work or disturb the current edit.

## Acceptance criteria

- [ ] A gated importer proves Open Image returns control and permits a main-actor sentinel before the import completes.
- [ ] Generated multiple-file and repeated-URL imports produce the same sorted names, embedded URL backing, duplicate summary and initial selection as the current tests.
- [ ] Empty input/panel cancellation leaves existing collection, document and navigation unchanged.
- [ ] Cancellation, partial commits, failure, a superseding import and shutdown produce one correct terminal outcome with no stale open/status publication.
- [ ] Security access remains valid for the full worker read and is released on every terminal path; package writer concurrency stays one.
- [ ] Updated callers no longer invoke the synchronous import API from the dialog UI path or depend on an immediate final summary.

## Non-goals

Keep folder/Photos behavior, file format, duplicate policy and source-loading renderer unchanged. No large RAW import or display benchmark is needed: use generated small fixtures, a gated worker and call-count/order assertions.

## Reading the source context

Source and test paths above are relative to the repository root, `/Users/dhardy/Dev/Kromora`. The installed `dg context` reader currently resolves file/doc contents inside the `.dg` space, so it can list existing repository sources as missing. Read those paths directly from the checkout; their existence was verified when this ticket was written. Keep the repository-relative context hints for planning. Do not copy product source into `.dg` or weaken DispatchGraph path validation to work around this reader limitation.

## Required checks

```sh
swift build
swift test --no-parallel --filter 'OpenImageDialogTests|ImportedPhotoDurabilityTests|FileIntegrationBoundaryTests|PackageSourceImportCoordinatorTests|PackageSettingsTests'
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


### Comment — claude @ 2026-10-12T19:52:54.898Z

openImages now starts the scheduler-backed startImportURLs import, observed via the shared import coordinator, with security access owned by the worker and a completion callback for the terminal summary (silent when superseded). Photos-drop outcome and drop-directory purge move to completion. Tests rewritten to await completion; added tests for non-blocking return, supersession, and empty input. Checks: swift build; focused swift test (107 passed incl. OpenImageDialog, ImportedPhotoDurability, FileIntegrationBoundary, PackageSourceImportCoordinator, PackageSettings); dg validate; git diff --check. Note: a test fixture's libraryFolderURL is keyed by ObjectIdentifier and goes stale; affected assertions now check the .kromoralibrary path. No gated-worker test was added; non-blocking is asserted via empty collection right after return.

## Agent log

- 2026-10-12T20:04:09.206Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A gated importer proves Open Image returns control and permits a main-actor sentinel before the import completes. (pass) — Added testOpenImagesReturnsWhilePackageWorkerIsGated; the import remains queued and unpublished while the main-actor sentinel runs, then completes after gate release.
- [x] Generated multiple-file and repeated-URL imports preserve sorted names, embedded URL backing, duplicate summary, and initial selection. (pass) — OpenImageDialogTests sorted multi-file, URL-backed asset, repeated URL, and first-item source-loading assertions pass.
- [x] Empty input and panel cancellation leave collection, document, and navigation unchanged. (pass) — OpenImageDialogTests and FileIntegrationBoundaryTests pass for empty result and cancelled dialog behavior.
- [x] Cancellation, partial commits, failure, supersession, and shutdown produce a correct terminal outcome without stale publication. (pass) — The operation observer fences terminal callbacks by current operation and shutdown state; superseded import regression passes. Existing worker cancellation coverage confirms committed assets remain queryable.
- [x] Security access remains valid through worker reads and is released on terminal paths; package writer concurrency stays one. (pass) — Reviewed PortableLibrarySession.startImport ownership transfer and terminal release; focused package import coordinator and durability tests pass.
- [x] Dialog callers use the asynchronous import API and do not depend on an immediate final summary. (pass) — openImages starts startImportURLs and observes completion; callers/tests await the completion callback.
Checks run:
- swift build (pass)
- swift test --no-parallel --filter OpenImageDialogTests|ImportedPhotoDurabilityTests|FileIntegrationBoundaryTests|PackageSourceImportCoordinatorTests|PackageSettingsTests (30 tests passed)
- swift test --no-parallel --filter OpenImageDialogTests.testOpenImagesReturnsWhilePackageWorkerIsGated (1 test passed)
- dg validate (pass; emitted existing unknown-model warnings)
- git diff --check (pass)
Findings:
- None
Fixes:
- Added deterministic gated-worker responsiveness coverage to OpenImageDialogTests.
Verification commits:
- b9a9950694dcf95d7429cedee409b6c8be391e9a
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5OHE2Z8UHBLC15
Summary: Verified the asynchronous Open Image import path, added deterministic package-worker gate coverage, and passed required checks.
