---
id: KRMA-959
title: Remove OSAllocatedUnfairLock(uncheckedState:) / withLockUnchecked from Thumbnails.swift
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
created: 2026-10-13T14:48:09.498Z
updated: 2026-10-13T14:48:23.168Z
blockers: []
order: zzq
board: product
---

## Objective

Eliminate the one Swift 6 escape hatch not caught by `PackageSettingsTests`, and extend that test to
catch it.

## Context

Review `.context/2026-10-13-release-readiness-review.md` "Nice to have: Concurrency escape hatch". `Sources/KromoraKit/Models/Thumbnails.swift`
~L209 `OSAllocatedUnfairLock(uncheckedState: State())` and `withLockUnchecked` at ~L213, 226, 252, 262.
The unchecked variants bypass `Sendable` checking of the protected state; they were probably needed
because `State` holds a `CGImage`. `CGImage` is `Sendable` on the macOS 26 SDK, so the checked
`OSAllocatedUnfairLock(initialState:)`/`withLock` should compile now. `CLAUDE.md` forbids escape hatches;
`PackageSettingsTests` (`Tests/KromoraKitTests/PackageSettingsTests.swift`) enforces
`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`.

## Acceptance criteria

- [ ] The class uses `OSAllocatedUnfairLock(initialState:)` and `withLock`; the compiler accepts it with
      zero warnings. If some stored member is genuinely non-`Sendable`, restructure (store `Sendable`
      values or use an actor) rather than keeping an unchecked call; explain in the review comment.
- [ ] `PackageSettingsTests` gains assertions that `uncheckedState:` and `withLockUnchecked` do not
      appear anywhere under `Sources/`.
- [ ] `grep -rn "uncheckedState\|withLockUnchecked" Sources` is empty; thumbnail tests pass.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
