---
id: KRMA-957
title: Replace Task.detached { … }.value with @concurrent functions (Sources/KromoraKit/ViewModels)
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - nice-to-have
  - concurrency
  - cleanup
parent: KRMA-922
created: 2026-10-13T14:48:07.524Z
updated: 2026-10-13T14:48:22.764Z
blockers: []
order: zz
board: product
---

## Objective

Stop using `Task.detached { … }.value`, which drops cancellation propagation and priority
inheritance, in the ViewModels directory. Use Swift 6.2 `@concurrent` nonisolated async functions.

## Context

Review `.context/2026-10-13-release-readiness-review.md` "Nice to have: Task.detached". About 39 uses exist across Sources
(`grep -rn "Task.detached" Sources | cut -d: -f1 | sort | uniq -c`). This ticket covers only
`Sources/KromoraKit/ViewModels/` (about 15 uses: `ExportCoordinator` ×3, `IdleFrameWarmerCoordinator` ×3,
`SourceSessionCoordinator` ×2, `VirtualCopyMetadataCoordinator`, `PhotosImportReviewCoordinator`,
`PhotosImportCoordinator`, `LookSaveCoordinator`, `LibraryMediaWorkflowCoordinator`,
`EditedThumbnailCoordinator`, `DeriveCoordinator`). Models/ and Views/ are a separate ticket (KRMA-958).

Mechanics: a `nonisolated` function marked `@concurrent` runs on the global executor, inherits the
caller's cancellation (structured), and returns its value with plain `await`. Pattern:

    // before
    try await Task.detached(priority: .userInitiated) { try Self.writeSelectedFile(data, to: url) }.value
    // after
    @concurrent private static func writeSelectedFile(_ data: Data, to url: URL) async throws { … }
    try await Self.writeSelectedFile(data, to: url)

Where a detached task is stored and cancelled explicitly (not `.value`-awaited inline), leave it and
list it in the review comment. Where the closure captured non-`Sendable` values, the compiler will
say so: pass values, not references; never add `@unchecked Sendable`.

## Acceptance criteria

- [ ] No `Task.detached` remains under `Sources/KromoraKit/ViewModels/` except cases explicitly listed
      (with reason) in the review comment.
- [ ] Priority is preserved where it mattered by setting `Task(priority:)` on the caller or leaving a
      comment; cancellation now propagates (add one test: cancelling the awaiting task cancels a
      `@concurrent` helper that polls `Task.isCancelled`).
- [ ] No behavior change; all existing tests pass.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0.
