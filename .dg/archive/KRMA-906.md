---
id: KRMA-906
title: Build idle-warming candidates from one off-main ordered library snapshot
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Planning a multi-page library performs one full ordering per stable snapshot, not one per requested page.
      result: pass
      notes: IdleFrameWarmPlanner.rank orders via orderedAssetIDs once; the multi-page coordinator test observed one planning run for three bounded pages.
    - criterion: A gated planner allows an independent main-actor sentinel to run before planning finishes.
      result: pass
      notes: The gated planner test ran the sentinel while planning was held, then confirmed cancellation caused no page materialization or render.
    - criterion: Candidate and asset materialization is bounded by requested page/work budget; early capacity or cancellation stops further pages.
      result: pass
      notes: Multi-page test observed page sizes [2, 2, 1]; cancellation and low-water capacity tests confirmed no subsequent work.
    - criterion: Viewport/launch-hint order, duplicate-ID handling, placeholder exclusion, persisted-tier skips, and no-visible-publication behavior remain correct.
      result: pass
      notes: Ranker and existing warmer tests passed, including distance/recency/index ordering, placeholder filtering, exact stored tiers, and presentation isolation.
    - criterion: Library mutation, source replacement, cancellation, and shutdown reject stale pages/results and settle owned planning work.
      result: pass
      notes: Generation-change tests confirmed stale plans/pages are abandoned and replanned; cancellation/shutdown tests confirmed owned work settles without publishing. AppViewModel retains one package session for its lifetime.
    - criterion: Generated index fixtures verify scaling structurally with counts, without machine-specific latency thresholds or a large disk library.
      result: pass
      notes: LibraryQueryController generated 10,000-entry query canaries passed; no latency threshold was added.
  checks_run:
    - swift build — passed
    - swift test --no-parallel --filter IdleFrameWarmerCoordinatorTests|LibraryQueryControllerTests|LibraryBrowsingProjectionTests|RelaunchParityTests|PackageSettingsTests — passed (48 tests, 0 failures)
    - dg validate — passed; emitted existing model-name warnings
    - git diff --check — passed
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T20:07:19.715Z
  session: 01MV5OML1WZSBVBHE0
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - app-view-model
  - maintainability
  - concurrency
created: 2026-10-12T17:11:42.029Z
updated: 2026-10-12T20:07:19.719Z
blockers: []
order: zy
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/IdleFrameWarmerCoordinator.swift
    - Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift
    - Sources/KromoraKit/Models/LibraryQueryController.swift
    - Sources/KromoraKit/Models/PortableLibrarySession.swift
    - Tests/KromoraKitTests/IdleFrameWarmerCoordinatorTests.swift
    - Tests/KromoraKitTests/LibraryQueryControllerTests.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - CLAUDE.md
    - AGENTS.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-519
    - KRMA-769
  commands:
    - swift build
    - swift test --no-parallel --filter 'IdleFrameWarmerCoordinatorTests|LibraryQueryControllerTests|LibraryBrowsingProjectionTests|RelaunchParityTests|PackageSettingsTests'
    - dg validate
    - git diff --check
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/ViewModels/IdleFrameWarmerCoordinator.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Models/LibraryQueryController.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Models/PortableLibrarySession.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/IdleFrameWarmerCoordinatorTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/LibraryQueryControllerTests.swift
      access: write
      confidence: 1
    - path: docs/APP_ARCHITECTURE.md
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-12T20:01:53.719Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Remove repeated full-index sorting and whole-library PhotoAsset construction from the main-actor idle-warming setup path. Preserve sequential warming order and generation fences while consuming bounded candidate pages from one ordered snapshot.

## Evidence and complexity

`AppViewModel.idleFrameWarmerCandidates` (approximately lines 4944-5000) loops over every `portableLibrary.browsingWindow(pageIndex:query:.all)`, collects all PhotoAssets, builds position/recency dictionaries, computes distance against anchors for each asset, and constructs every eligible IdleFrameWarmCandidate. `IdleFrameWarmerCoordinator.run` synchronously requests this array and sorts it again before the first photo job.

`LibraryQueryController.page(at:query:)` (approximately 648-674) filters and sorts the full index for every page. For N assets and P pages, this path repeats the index ordering roughly P times, plus asset materialization and the final candidate sort. Session startup may cache page zero, but subsequent pages still repeat the full sort. The synchronous getter runs on MainActor even though the eventual renders are background work. Browsing assets with extensionless names may additionally resolve a record. KRMA-519 introduced paged browsing, and KRMA-769 introduced idle warming; do not undo their UI/persistence contracts.

## Context to read

- `Sources/KromoraKit/ViewModels/AppViewModel.swift`: IdleFrameWarmerDestination conformance, readiness/blocked conditions and viewport anchors.
- `ViewModels/IdleFrameWarmerCoordinator.swift`: scheduling, candidate ordering, performOnePhoto, capacity stop, shutdown.
- `ViewModels/LibraryBrowsingCoordinator.swift`: launch-hint order and loaded windows.
- `Models/LibraryQueryController.swift`: value snapshot, filter/sort comparator and query page representation.
- `Models/PortableLibrarySession.swift`: browsingWindow, browsingAsset, queryController replacement, session generations and worker boundaries.
- `Tests/KromoraKitTests/IdleFrameWarmerCoordinatorTests.swift`, `LibraryQueryControllerTests.swift`, `LibraryBrowsingProjectionTests.swift`, `RelaunchParityTests.swift` and `LibraryScaleRegressionPerformanceTests.swift`.

## Implementation steps

1. Expose a Sendable index/query snapshot for candidate planning. Build its ordering once off MainActor for a stable library generation; reuse query matching/comparison semantics rather than adding a subtly different sort.
2. Move candidate planning under IdleFrameWarmerCoordinator and/or LibraryBrowsingCoordinator. Replace the root's synchronous all-candidates getter with a narrow asynchronous paged provider. Keep the root responsible for readiness/activity and immutable viewport/source snapshots only.
3. Rank by the existing viewport distance, then launch-hint rank, then stable index ordering. Compute distance without mapping every anchor for every asset when a sorted-position lookup suffices. Preserve fallback behavior for empty/off-window anchors.
4. Retain only lightweight ordered IDs/index entries for the snapshot and materialize bounded work pages as needed. Do not create all PhotoAssets/ImageSources/references just to stop on the first capacity limit. Keep placeholder fingerprints excluded as today; avoid an eager original decode/hash sweep.
5. Fence the plan/page against library membership/query-generation changes, source lifetime, activity cancellation and shutdown. A stale snapshot may be abandoned/replanned; removed assets must not be warmed against obsolete package state. Do not make the library grid eagerly load every page.
6. Instrument a narrow planner/provider seam in tests to count full sorts and page materializations. Preserve sequential warming, pinned assets, saved edit/Look signatures and no presentation side effects.

## Acceptance criteria

- [ ] Planning a multi-page library performs one full ordering per stable snapshot, not one per requested page.
- [ ] A gated planner allows an independent main-actor sentinel to run before planning finishes.
- [ ] Candidate/asset materialization is bounded by requested page/work budget; early capacity/cancellation stops further pages.
- [ ] Existing viewport/launch-hint order, duplicate-ID handling, placeholder exclusion, persisted-tier skips and no-visible-publication behavior remain correct.
- [ ] Library mutation, source replacement, cancellation and shutdown reject stale pages/results and settle all owned planning work.
- [ ] Generated index fixtures verify scaling structurally with counts; no machine-specific latency threshold or large disk library is required.

## Verification caveat from the review

The 2026-10-12 selected test run built successfully and passed the retouch/history/observation selections, but all seven IdleFrameWarmerCoordinatorTests failed during fixture creation because they used the user's Application Support Indexes directory and sandbox writes were denied. Make these touched fixtures supply temporary `indexURL`/storage paths explicitly, using existing injection points. This is test isolation work, not a reason to alter production storage destinations or request access to user data.

## Reading the source context

Source and test paths above are relative to the repository root, `/Users/dhardy/Dev/Kromora`. The installed `dg context` reader currently resolves file/doc contents inside the `.dg` space, so it can list existing repository sources as missing. Read those paths directly from the checkout; their existence was verified when this ticket was written. Keep the repository-relative context hints for planning. Do not copy product source into `.dg` or weaken DispatchGraph path validation to work around this reader limitation.

## Required checks

```sh
swift build
swift test --no-parallel --filter 'IdleFrameWarmerCoordinatorTests|LibraryQueryControllerTests|LibraryBrowsingProjectionTests|RelaunchParityTests|PackageSettingsTests'
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


### Comment — claude @ 2026-10-12T20:01:49.965Z

Idle warming now ranks the library once per index generation off the main actor (IdleFrameWarmPlanner over a LibraryQueryController snapshot; orderedAssetIDs does one filter+sort). The coordinator keeps lightweight ranked entries and asks AppViewModel to materialize pages of 24 candidates; stale index generation abandons and replans (max 4). PortableLibrarySession.indexGeneration and browsingAssets(forIDs:) added. Tests: one plan per multi-page run, bounded page sizes, gated planner with main-actor sentinel, cancel/stale/replan, ranker order, and orderedAssetIDs parity. Warmer and relaunch fixtures use temp indexURL. Checks: swift build OK; the targeted swift test selection (47 tests) passed; git diff --check clean; dg validate only printed pre-existing model warnings. Commit 4a56bbdb.

## Agent log

- 2026-10-12T20:07:19.715Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Planning a multi-page library performs one full ordering per stable snapshot, not one per requested page. (pass) — IdleFrameWarmPlanner.rank orders via orderedAssetIDs once; the multi-page coordinator test observed one planning run for three bounded pages.
- [x] A gated planner allows an independent main-actor sentinel to run before planning finishes. (pass) — The gated planner test ran the sentinel while planning was held, then confirmed cancellation caused no page materialization or render.
- [x] Candidate and asset materialization is bounded by requested page/work budget; early capacity or cancellation stops further pages. (pass) — Multi-page test observed page sizes [2, 2, 1]; cancellation and low-water capacity tests confirmed no subsequent work.
- [x] Viewport/launch-hint order, duplicate-ID handling, placeholder exclusion, persisted-tier skips, and no-visible-publication behavior remain correct. (pass) — Ranker and existing warmer tests passed, including distance/recency/index ordering, placeholder filtering, exact stored tiers, and presentation isolation.
- [x] Library mutation, source replacement, cancellation, and shutdown reject stale pages/results and settle owned planning work. (pass) — Generation-change tests confirmed stale plans/pages are abandoned and replanned; cancellation/shutdown tests confirmed owned work settles without publishing. AppViewModel retains one package session for its lifetime.
- [x] Generated index fixtures verify scaling structurally with counts, without machine-specific latency thresholds or a large disk library. (pass) — LibraryQueryController generated 10,000-entry query canaries passed; no latency threshold was added.
Checks run:
- swift build — passed
- swift test --no-parallel --filter IdleFrameWarmerCoordinatorTests|LibraryQueryControllerTests|LibraryBrowsingProjectionTests|RelaunchParityTests|PackageSettingsTests — passed (48 tests, 0 failures)
- dg validate — passed; emitted existing model-name warnings
- git diff --check — passed
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5OML1WZSBVBHE0
