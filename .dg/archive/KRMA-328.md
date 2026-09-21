---
id: KRMA-328
title: Build preview disk-cache entries for idle library items in the background
type: feature
status: done
priority: medium
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Idle background cache builder
      result: pass
      notes: Implemented inside AppViewModel with 1500ms cancellable quiet admission, filtered nearest-first ordering, 20-item session cap, persistent cursor, canonical 2048 preview requests, exact-key contains checks, and detached cache writes.
    - criterion: Visible-work preemption and stale-result safety
      result: pass
      notes: Idle task and dedicated scheduler job are cancelled before load, collection navigation, interaction, settled/interactive preview scheduling, scans, and shutdown; generation/sourceRevision/activeAssetID guards are checked between items.
    - criterion: No publication or supporting-work side effects
      result: pass
      notes: The cache-fill job only calls makeCIImage and PreviewDiskCache writing; its doc comment explicitly records that no publication path is reachable from it.
    - criterion: Verification commands
      result: pass
      notes: swift build, swift test --filter PreviewDiskCacheTests (5/5), scripts/ci-tests.sh fast (678/678), scripts/ci-tests.sh serial (326/326), dg validate, and git diff --check passed.
  checks_run:
    - swift build
    - swift test --filter PreviewDiskCacheTests
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - dg validate
    - git diff --check
  findings:
    - Build output contains only pre-existing Core Image kernel deprecation warnings.
    - Opt-in real-ARW report was not run because LUMO_RAW_FIXTURE_DIR was not present.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T23:03:22.973Z
  session: 01MTUP2GVHB2FY3LX1
labels:
  - performance
  - preview
  - raw
created: 2026-09-09T21:26:04.394Z
updated: 2026-09-10T12:53:57.213Z
depends_on:
  - KRMA-327
order: z
board: product
---

## Objective

Make the third, fourth, and twentieth photo open as fast as the second by developing preview disk-cache entries for not-yet-opened library items during genuine idle time — without ever delaying, preempting, or evicting the user's visible work. Depends on KRMA-327 (the disk cache this builder fills); do NOT start this ticket before KRMA-327 is done.

## Context / where things live

- Today's prefetch: `AppViewModel.scheduleAdjacentPreviewPrefetch()` (~line 1484): 350ms after install, resolves stored docs for up to 2 neighbors (`abs(index-selected) <= 2`), enqueues ONE `.editor`-lane job (`adjacentPreviewPrefetchJobID`, `.background` priority) that calls `engine.makeCIImage` per request and DISCARDS the result (it only warms in-memory caches that KRMA-308 may evict). This ticket generalizes that mechanism folder-wide and retargets its output into the KRMA-327 disk cache.
- Cancellation primitives to reuse, not reinvent: `sourceRevision`/`activeAssetID` staleness guards (as in `prepareAndInstall`), `workScheduler.cancel(id:pump:)`, `previewCoordinator.cancel()`, `editedThumbnailGenerations`-style generation counters, and the `isPreviewInteractionActive` / `previewDebounceTask != nil` admission gates from `requestEditedThumbnail` (the canonical "visible work is active" signal).
- Scheduler: `ImageWorkScheduler.enqueue(id:lane:priority:operation:)` with `.editor` / `.thumbnail` lanes and `.background` priority; `contains(_:)` + `updatePriority` for coalescing. Admission ordering is by `(priority, sequence)` — background work inherently yields.
- Ordering source: `collection.filteredIndices` (respects the active culling filter — never build previews for filtered-out items) + `collection.selectedIndex` for distance ranking. Dimensions gate: `item.asset.dimensions` (skip until deferred metadata lands, exactly like the current prefetch's guard).
- Stored docs: `editStore.load(for:)` batch overload (current prefetch already uses `editStore.load(for: [references])`); `isUsableForPrefetch` is the existing validity gate — reuse it.

## Prescriptive plan

1. Add `PreviewIdleBuilder` ownership INSIDE `AppViewModel` (new private section + 3 properties: `idleBuildTask: Task<Void,Never>?`, `idleBuildGeneration: UInt64`, reuse `adjacentPreviewPrefetchJobID`? NO — create a dedicated `idlePreviewBuildJobID` so cancelling the builder never cancels the neighbor prefetch and vice versa; state the reason in a comment). Do NOT create a new coordinator class — the policy (what is idle, what cancels) belongs to the view model that owns `sourceRevision`, and reviewers must see the preemption logic next to `scheduleAdjacentPreviewPrefetch`, which this builder EXTENDS (keep the 2-neighbor 350ms prefetch exactly as-is; the builder is the second, slower wave).
2. Trigger conditions (ALL must hold; check in this order, cheapest first):
   a. `collection.isScanning == false` (scan streams batches and owns the I/O budget; building during scan just contends — the scan's own thumbnails already warm the disk cache for tiny files, and RAWs are handled below).
   b. No `pendingSourceLoad`, `previewDebounceTask == nil`, `!isPreviewInteractionActive`, no `loadTask` in flight (mirror the `requestEditedThumbnail` admission gate verbatim).
   c. 1500ms of continuous quiet after the LAST of: install, settled publication (`didPresentVisibleFrame` is the right hook — set `lastSettledAt = Date()` there... actually `ContinuousClock.now` to stay testable via injected clock? NO — keep it simple and deterministic: drive the quiet period with a cancellable `Task.sleep(for: .milliseconds(1500))` exactly like `prefetchDelayTask`'s 350ms sleep, not wall-clock timestamps; cancellable-sleep is already the codebase idiom and is directly testable via task cancellation).
   d. App is active (`NSApplication.shared.isActive` — building while the user is in another app burns battery for nothing; re-arm on `didBecomeActive` via the existing notification surface if trivially available, otherwise note as follow-up — do NOT build new notification plumbing in this ticket; the sleep task simply re-checks `isActive` before each item and suspends (cancels + re-arms on next settled frame) if inactive).
3. Build loop (in the scheduler job, `.editor` lane, `.background` priority, ONE item per loop iteration with a cancellation check between items):
   - Candidate order: `filteredIndices` excluding selected, sorted by `abs(index - selectedIndex)` ascending (nearest-first = most likely to be opened next), capped per idle session at 20 items (constant `maxItemsPerIdleSession`; prevents an overnight runaway on a 10k folder — the NEXT idle session continues where this one stopped; persist the cursor as a plain `idleBuildCursor: Int?` reset on any selection change or scan).
   - Skip fast: item already has a fresh disk entry — ask KRMA-327's cache for a `contains(key)` (add this method in KRMA-327 if missing; file the gap back if so) WITHOUT reading pixels; skip on hit. This makes repeat idle sessions O(stat) instead of O(develop) and is what bounds the feature's cost.
   - For misses: resolve document exactly like the current prefetch (in-memory session first, else batched `editStore.load`, `isUsableForPrefetch` gate), build the SAME `RenderRequest` the settled path would (copy the `submitSettledPreview` request construction: `resolutionPlan` + canonical 2048 target from KRMA-327 — share a helper, do not duplicate the math), `await engine.makeCIImage(request)`, then hand the result to the disk cache writer from KRMA-327. Then loop.
   - NEVER touch `previewSurface`, `PreviewCoordinator`, `previewState`, histogram, or selection. The builder is cache-fill only. State this as a doc comment on the job: "no publication path reachable from here."
4. Preemption (correctness-critical — a builder that delays a real open by even one frame is a regression):
   - `load()`, `selectCollectionImage`, `beginPreviewInteraction`, and ANY `schedulePreview` call path must cancel `idleBuildTask` + `workScheduler.cancel(id: idlePreviewBuildJobID)` FIRST, before doing their own work (follow the existing `workScheduler.cancel(id: adjacentPreviewPrefetchJobID, pump: false)` line in `load()` — add the builder's cancel directly adjacent with a comment).
   - Bump `idleBuildGeneration` on every cancel; the loop re-checks `generation` + `sourceRevision` + `activeAssetID` per item (same triple as the prefetch job).
   - The `.background` priority + single editor-lane slot already guarantee a visible `.activeEditor` job submitted mid-build waits at most for the CURRENT item's `makeCIImage` to finish (non-preemptible Core Image tail). Document this bound in the code: worst-case added latency to a user open = one in-flight background develop, and ONLY if it started before the cancel landed.
5. Resource caps: `maxItemsPerIdleSession = 20`, one scheduler job at a time (re-entrancy guard `guard idleBuildTask == nil`), disk-cache cap from KRMA-327 is the backstop. No new UserDefaults keys, no Settings UI in this ticket.

## Acceptance criteria

- [ ] `IdleBuildFillsCacheTest` (FakeRenderEngine): 5-item collection, open item 0, advance past quiet period (cancel-safe: inject short quiet delay? NO test hooks for timing — instead await the deterministic condition `diskCacheEntryCount == expected` with the existing `waitUntil` test idiom from `SingleViewLatencyBenchmark`); assert disk entries exist for nearest-first order (1, 2, ...) and ZERO `previewSurface.present` calls / `previewState` untouched / selection unchanged.
- [ ] `IdleBuildSkipsFreshEntriesTest`: pre-populate disk entries for items 1-2; run builder; assert ZERO engine `makeCIImage` calls for 1-2 (only `contains` stats) and builds for 3+.
- [ ] `IdleBuildPreemptedByNavigationTest`: start builder, `selectCollectionImage` mid-run; assert the in-flight job cancels (FakeRenderEngine records no FURTHER `makeCIImage` after the cancel point modulo one non-preemptible tail), the newly selected photo's settled preview submits at `.activeEditor` priority ahead of any builder work, and the cursor resets.
- [ ] `IdleBuildNeverPublishesTest`: full run over all items; assert no `Publication` handler invocations, no histogram, no edited-thumbnail admissions attributable to the builder (ambient settled-open admissions for the selected photo excepted — scope the assertion to non-selected assetIDs).
- [ ] `IdleBuildRespectsFilterTest`: with a rating/pick filter hiding half the folder, assert no disk entries are created for hidden items.
- [ ] Opt-in real-ARW report (`LUMO_RAW_FIXTURE_DIR`, 4 ARWs present): open item 0, wait for idle session to cover items 1-3, quit caches (flush memory only), open item 2 -> disk hit, print time (report only).

## Verification

- `swift build` clean, zero diagnostics; Swift 6: no new shared mutable state (cursor+generation are `@MainActor` view-model state like their neighbors), no opt-outs.
- `scripts/ci-tests.sh fast` + `serial` green.
- Manual: 4-ARW folder, open first, wait ~10s idle, Activity Monitor shows a bounded burst then quiet; quit, relaunch, open third photo -> near-instant from disk; start dragging a slider the instant a build is running -> interaction stays smooth, build stops.
- KRMA-327 MUST be merged first — this ticket's tests construct its cache type. If `contains(key:)` is missing from KRMA-327's API, send it back rather than working around it.

## Constraints

macOS 14 minimum, zero third-party deps, Swift 6 all targets. No Settings UI, no new persistence besides KRMA-327's cache dir, no network, no notification-center plumbing beyond what exists. Per-session cap 20 items; `.background` priority only; cache-fill path shares KRMA-327's key builder verbatim (no second key implementation — import it).

## Agent log

- 2026-09-09T23:03:22.974Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Idle background cache builder (pass) — Implemented inside AppViewModel with 1500ms cancellable quiet admission, filtered nearest-first ordering, 20-item session cap, persistent cursor, canonical 2048 preview requests, exact-key contains checks, and detached cache writes.
- [x] Visible-work preemption and stale-result safety (pass) — Idle task and dedicated scheduler job are cancelled before load, collection navigation, interaction, settled/interactive preview scheduling, scans, and shutdown; generation/sourceRevision/activeAssetID guards are checked between items.
- [x] No publication or supporting-work side effects (pass) — The cache-fill job only calls makeCIImage and PreviewDiskCache writing; its doc comment explicitly records that no publication path is reachable from it.
- [x] Verification commands (pass) — swift build, swift test --filter PreviewDiskCacheTests (5/5), scripts/ci-tests.sh fast (678/678), scripts/ci-tests.sh serial (326/326), dg validate, and git diff --check passed.
Checks run:
- swift build
- swift test --filter PreviewDiskCacheTests
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- dg validate
- git diff --check
Findings:
- Build output contains only pre-existing Core Image kernel deprecation warnings.
- Opt-in real-ARW report was not run because LUMO_RAW_FIXTURE_DIR was not present.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTUP2GVHB2FY3LX1
Summary: Implemented bounded, cancellable idle preview cache filling in AppViewModel. The builder waits for 1500ms of quiet, respects scan/interaction/load/app-active gates, orders filtered candidates nearest-first with a 20-item cursor, resolves stored edits in batch, skips exact cache hits via contains(key), renders canonical settled requests on the background editor lane, and writes rasters without any publication path. Added preemption and generation/source/asset guards across navigation, interaction, preview scheduling, scans, and shutdown; shared settled request construction with the 2048px cache plan.
