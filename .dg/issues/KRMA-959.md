---
id: KRMA-959
title: Remove OSAllocatedUnfairLock(uncheckedState:) / withLockUnchecked from Thumbnails.swift
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: ThumbnailImageCache uses OSAllocatedUnfairLock(initialState:) and withLock; the compiler accepts it without warnings, using Sendable state or an actor if necessary.
      result: pass
      notes: The cache uses the checked lock APIs. The macOS 26 SDK accepts State containing CGImage as Sendable; no restructure is needed. swift build emitted no warnings.
    - criterion: "PackageSettingsTests rejects uncheckedState: and withLockUnchecked anywhere under Sources/."
      result: pass
      notes: Added both names to the whole-Sources escape hatch scan; the test passes.
    - criterion: grep -rn "uncheckedState\|withLockUnchecked" Sources is empty, and thumbnail tests pass.
      result: pass
      notes: The guarded grep found no matches. ThumbnailTests (14) and FilmstripThumbnailTests (1) passed.
    - criterion: swift build is warning-free, Swift 6 remains clean with no listed escape hatches or availability branches, and scripts/ci-tests.sh fast exits 0 (with the specified isolated rerun exception if applicable).
      result: pass
      notes: swift build emitted no warnings; PackageSettingsTests confirmed Swift 6 and escape hatch guards; scripts/ci-tests.sh fast exited 0 with all 1,982 selected tests passing. The isolated rerun exception was not needed.
  checks_run:
    - swift build — exit 0; no warnings.
    - swift test --no-parallel --filter '(ThumbnailTests|FilmstripThumbnailTests|PackageSettingsTests)' — exit 0; 21 tests passed.
    - swift test --no-parallel --filter PackageSettingsTests — exit 0; 6 tests passed after formatting the new guard list.
    - scripts/ci-tests.sh fast — exit 0; all 1,982 selected tests passed.
    - grep -rn "uncheckedState\|withLockUnchecked" Sources — no matches.
    - git diff --check — exit 0.
  findings: []
  fixes: []
  verification_commits:
    - 468f75c40029a9e46e782ddd185a3116344f9dc4
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-15T00:52:31.104Z
  session: 01MV8TJQZWJ8FZOD4R
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - nice-to-have
  - concurrency
  - cleanup
created: 2026-10-13T14:48:09.498Z
updated: 2026-10-15T00:52:31.108Z
parent: KRMA-922
blockers: []
order: a0
board: product
context:
  files: []
  docs:
    - .context/2026-10-14-release-readiness-review.md
  issues:
    - KRMA-994
  commands: []
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-15T00:46:55.413Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 468f75c40029a9e46e782ddd185a3116344f9dc4
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

## 2026-10-14 review

Finding under "Semantic architecture guards" in `.context/2026-10-14-release-readiness-review.md`. The unchecked lock is still in `Thumbnails.swift` (around line 194; the earlier citation was around line 209). The review did not demonstrate a race. Audit why the unchecked API was used, and move to the checked API where the SDK allows it. Do not keep `uncheckedState` / `withLockUnchecked` once `CGImage` or the stored state is `Sendable`. Epic KRMA-994 tracks this note. This issue stays a child of KRMA-922. KRMA-999 changes thumbnail retention in the same file's neighborhood; do not take that eviction work on here.


### Comment — claude @ 2026-10-15T00:46:52.176Z

ThumbnailImageCache now uses OSAllocatedUnfairLock(initialState:)/withLock. CGImage is Sendable on the macOS 26 SDK, so State is Sendable and no restructure was needed; stale doc comment fixed. PackageSettingsTests escape-hatch scan now also rejects uncheckedState and withLockUnchecked. swift build: 0 warnings; thumbnail + PackageSettings tests pass; scripts/ci-tests.sh fast exit 0. Changes left uncommitted in the working tree (it holds many pre-existing changes).

## Agent log

- 2026-10-15T00:52:31.105Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] ThumbnailImageCache uses OSAllocatedUnfairLock(initialState:) and withLock; the compiler accepts it without warnings, using Sendable state or an actor if necessary. (pass) — The cache uses the checked lock APIs. The macOS 26 SDK accepts State containing CGImage as Sendable; no restructure is needed. swift build emitted no warnings.
- [x] PackageSettingsTests rejects uncheckedState: and withLockUnchecked anywhere under Sources/. (pass) — Added both names to the whole-Sources escape hatch scan; the test passes.
- [x] grep -rn "uncheckedState\|withLockUnchecked" Sources is empty, and thumbnail tests pass. (pass) — The guarded grep found no matches. ThumbnailTests (14) and FilmstripThumbnailTests (1) passed.
- [x] swift build is warning-free, Swift 6 remains clean with no listed escape hatches or availability branches, and scripts/ci-tests.sh fast exits 0 (with the specified isolated rerun exception if applicable). (pass) — swift build emitted no warnings; PackageSettingsTests confirmed Swift 6 and escape hatch guards; scripts/ci-tests.sh fast exited 0 with all 1,982 selected tests passing. The isolated rerun exception was not needed.
Checks run:
- swift build — exit 0; no warnings.
- swift test --no-parallel --filter '(ThumbnailTests|FilmstripThumbnailTests|PackageSettingsTests)' — exit 0; 21 tests passed.
- swift test --no-parallel --filter PackageSettingsTests — exit 0; 6 tests passed after formatting the new guard list.
- scripts/ci-tests.sh fast — exit 0; all 1,982 selected tests passed.
- grep -rn "uncheckedState\|withLockUnchecked" Sources — no matches.
- git diff --check — exit 0.
Findings:
- None
Fixes:
- None
Verification commits:
- 468f75c40029a9e46e782ddd185a3116344f9dc4
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV8TJQZWJ8FZOD4R
Summary: Counterpoint verification passed; checked thumbnail lock API and source guard verified.
