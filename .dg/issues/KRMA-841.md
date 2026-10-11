---
id: KRMA-841
title: Keep the Library grid responsive while thumbnails render after a large import
type: bug
status: verification
priority: high
agent: claude
verification_agent: codex
human_review_required: false
model: sonnet
verification_report:
  verdict: blocker
  acceptance_criteria:
    - criterion: Reproducible large-import benchmark/profile with baseline scroll hitching, select-all latency, visible-thumbnail fill time, and peak memory recorded in docs/TESTING.md
      result: fail
      notes: An independent 1,500-file Release model benchmark passed and measured visible fill 2,089 ms, simulated-scroll heartbeat max 19.5 ms with 0/1,319 gaps over 33 ms, select-all 0.53–1.10 ms, shift-click 0.67 ms, and peak RSS 1,912 MB. It has no pre-change baseline and does not mount LibraryGridView or measure SwiftUI frame presentation; the acceptance criterion remains unmet.
    - criterion: Root cause(s) recorded from the profile
      result: fail
      notes: The source-level item-index and queue-refill scans were removed, but no comparative profile measures their contribution or remaining mounted-grid causes. docs/TESTING.md records that Instruments could not record on this machine.
    - criterion: Scrolling and selection stay responsive with no multi-frame main-actor stalls while thumbnails generate after a large import
      result: fail
      notes: The model heartbeat showed no gaps over 33 ms in the simulated scroll run, but this does not exercise SwiftUI layout or frame presentation, so the user-visible criterion cannot be established.
    - criterion: Visible thumbnails are prioritized and off-screen requests are cancelled or deprioritized
      result: pass
      notes: Code review confirms bounded priority scheduling and queued off-screen cancellation; the existing large-cold-library scheduling regression test passed in the fast lane.
    - criterion: Scheduling/priority/cancellation tests and required fast and serial lanes pass
      result: fail
      notes: scripts/ci-tests.sh serial passed (510 tests, 0 failures). scripts/ci-tests.sh fast exited 1 only at LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction (LightInspectorTests.swift:160), tracked by KRMA-853; scheduling regression coverage had no reported failure.
  checks_run:
    - Independent review of KRMA-841 implementation commits 92a5ea8f and 1c8b089d, ImageCollection index/cache changes, scheduler policy, benchmark limitations, and docs/TESTING.md.
    - "scripts/ci-tests.sh fast: exit 1; unrelated LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction failure tracked by KRMA-853."
    - "scripts/ci-tests.sh serial: exit 0; 510 tests, 0 failures."
    - "KROMORA_LARGE_IMPORT_BENCHMARK=1 KROMORA_LARGE_IMPORT_COUNT=1500 swift test -c release --filter LargeImportLibraryGridBenchmark: exit 0; 1 test passed in 57.647 s; 2,089 ms visible fill, simulated-scroll heartbeat max 19.5 ms, zero gaps >33 ms, select-all 0.53–1.10 ms, shift-click 0.67 ms, peak RSS 1,912 MB."
    - "Inspected docs/TESTING.md: post-change model metrics are present but no pre-change baseline or mounted LibraryGridView/Instruments profile is recorded."
    - "git show --check 92a5ea8f and git show 1c8b089d: exit 0."
  findings:
    - "Blocking: required comparative mounted-grid Release profile and user-visible scroll/frame responsiveness evidence remain missing; the new model benchmark does not establish those acceptance criteria."
    - Non-blocking unrelated fast-lane failure at LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction is tracked by KRMA-853.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-10T14:47:19.911Z
  session: 01MV2HZUO45LFOCOW3
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-09T18:06:33.347Z
updated: 2026-10-11T14:09:46.604Z
blockers:
  - id: evt_mv2ik03a_q3fb9c
    type: human
    reason: "Remaining acceptance evidence needs a mounted LibraryGridView profile (SwiftUI/main-actor frame behavior while thumbnails generate). That needs an unlocked, awake display and Instruments, which cannot record on this machine; CLAUDE.md also bars unattended display-bound runs. Window-independent pre-change vs post-change Release baselines are now in docs/TESTING.md: scans cost about 1 ms per selection op at 1500 items, 0 gaps over 33 ms either way."
    action: "Run a supervised Release session: swift run -c release, import ~1500 large RAWs, scroll and select-all while thumbnails fill, record SwiftUI/Hangs/Time Profiler results (hitches, select-all latency, fill time, peak memory) in docs/TESTING.md, or accept the model-level evidence and waive the mounted-grid criterion."
    created_at: 2026-10-10T14:52:41.206Z
    resolved_at: 2026-10-11T14:09:11.851Z
    resolved_by: cli
order: h
board: product
claim:
  actor: codex
  session: 01MV3WGO6IAXZZEJGC
  claimed_at: 2026-10-11T14:09:46.602Z
  expires_at: 2026-10-11T15:09:46.602Z
  model: gpt-6-luna
  stage: verification
blocked_reason: "Remaining acceptance evidence needs a mounted LibraryGridView profile (SwiftUI/main-actor frame behavior while thumbnails generate). That needs an unlocked, awake display and Instruments, which cannot record on this machine; CLAUDE.md also bars unattended display-bound runs. Window-independent pre-change vs post-change Release baselines are now in docs/TESTING.md: scans cost about 1 ms per selection op at 1500 items, 0 gaps over 33 ms either way."
blocked_action: "Run a supervised Release session: swift run -c release, import ~1500 large RAWs, scroll and select-all while thumbnails fill, record SwiftUI/Hangs/Time Profiler results (hitches, select-all latency, fill time, peak memory) in docs/TESTING.md, or accept the model-level evidence and waive the mounted-grid criterion."
blocked_from_status: ready
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-10T04:06:06.932Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

After importing a large number of large (multi-MB, often RAW) files, the Library page degrades quickly: scrolling stutters and selection (click, shift/cmd-click, select all) lags. Thumbnail generation and rendering should happen in the background with minimal impact on the UI; scrolling and selection must stay at display frame rate while thumbnails fill in.

## Context

Relevant code (static reading only; nothing here is profiled yet, so treat the causes as hypotheses):

- `LibraryGridView` (`Sources/KromoraKit/Views/LibraryGridView.swift`): `LazyVStack` of rows; visible ids are admitted via `admitVisibleThumbnails` -> `collection.requestVisibleThumbnails` / `requestThumbnail`, released in `onDisappear`. `onAppear` also calls `requestThumbnail` and `loadMorePortableIfNeeded`.
- `ImageCollection` (`Sources/KromoraKit/Models/ImageCollection.swift`): per-item `@Observable` thumbnails; every arrival assigns an `NSImage` on the main actor and publishes an observation change.
- `OriginalThumbnailLoader`: memory cache -> packed frame store -> detached decode from the original at `PlatformThumbnailProvider.libraryMaxPixelSize`. A full-size RAW decode per cell on a cold library is the expensive tier, and a bulk import makes every photo a cold miss at once.
- Post-import work (index delta, preview/frame generation, `IdleFrameWarmerCoordinator`) may compete with scrolling for CPU, I/O and the main actor.

Hypotheses to confirm or reject:

1. Decode concurrency is unbounded or too high relative to cores/I/O, starving the main actor and slowing scroll-time admission.
2. Thumbnail decode runs for off-screen or fast-scrolled-past cells (no cancellation/prioritization by visibility and recency), so the queue is stale by the time results arrive.
3. Each thumbnail arrival triggers a main-actor assignment plus observation invalidation that re-evaluates more than the one cell (for example grid-level `thumbnailEntries`, selection state, or row layout).
4. Decoding large RAW files at import time or on first view uses full-resolution paths instead of the embedded preview / a downsampled decode, and allocates large transient buffers (memory pressure).
5. Selection changes invalidate the whole grid (selection set read at the grid level rather than per cell).
6. Thumbnails are not generated and persisted during import, so first scroll after import pays the cost interactively.

## Suggested approach

0. **Rule out the build configuration first.** Reproduce and measure in a release build (`swift run -c release`, or the Xcode Release configuration), not a debug build: unoptimized Swift can dominate grid, observation and import-loop cost, while ImageIO/Core Image/CryptoKit work is unaffected. If the problem disappears in release, record that, keep a debug-build note in `docs/TESTING.md`, and scope the remaining work to release-build hot spots only.
1. Reproduce with a generated large-library fixture (for example 2,000 files of 20-50 MB, or the opt-in `realworldtest/` RAW lane) and add signposts: thumbnail request/start/finish, main-actor time per arrival, frames dropped during scroll and during select-all. Use a window-independent harness where possible; do not run the display-bound capture benchmark (see CLAUDE.md).
2. Profile with Instruments (Time Profiler, SwiftUI, Hangs) to find the actual main-actor and CPU hot spots before changing anything.
3. Fix by measured impact. Candidates: a bounded, priority-ordered thumbnail pipeline (visible first, most recently scrolled-to first, cancel when a cell leaves the viewport, lower QoS for everything else); prefer the embedded preview or a downsampling decode for RAW; generate and persist library thumbnails in a background pass during/after import so scrolling hits the frame store; batch main-actor delivery of arrivals and keep invalidation per cell; make selection state per-cell observable; cap memory-cache size and decoded-buffer lifetime.
4. Keep the existing contracts: admission policy, edited-thumbnail revisions, frame-store signatures, and cancellation semantics.

## Acceptance criteria

- [ ] Reproducible benchmark/profile of the large-import scenario with baseline numbers (scroll hitching, select-all latency, time to fill visible thumbnails, peak memory) recorded in `docs/TESTING.md`.
- [ ] Root cause(s) recorded from the profile.
- [ ] Scrolling and selection stay responsive (no multi-frame main-actor stalls) while thumbnails are still being generated after importing a large batch of large files.
- [ ] Visible thumbnails are prioritized, and off-screen requests are cancelled or deprioritized.
- [ ] Unit tests for the scheduling/priority/cancellation policy; existing thumbnail, grid-admission and frame-store tests pass (`scripts/ci-tests.sh fast` and `serial`).


## Counterpoint verification blocker (2026-10-10)

The implementation commit `92a5ea8f` reduces repeated main-actor lookup and queue-refill work, and focused regression tests cover index correctness and bounded/cancelled queued work. Verification cannot establish the issue's user-visible acceptance criteria yet: `docs/TESTING.md` explicitly records that no large-import profile or timing numbers exist, and there is no evidence that scrolling/selection remain responsive under sustained thumbnail generation. The root cause is therefore only partly established (the source-level scans were identified, but their contribution to observed hitching and any remaining bottleneck is unmeasured).

Before this issue can pass, reproduce a large import in a Release build and profile the requested interaction path. Record baseline and post-change scroll hitch/frame behavior, select-all latency, visible-thumbnail fill time, and peak memory in `docs/TESTING.md`; identify the measured root cause(s); then verify visible-first scheduling and off-screen cancellation/deprioritization under that scenario. Keep this work within the existing thumbnail, selection, frame-store, and cancellation contracts. Do not run the display-bound capture benchmark; use a supervised large-import profile appropriate to this acceptance criterion.

Verification: run `scripts/ci-tests.sh fast` and `scripts/ci-tests.sh serial`, plus the focused large-import profiling/interaction procedure. The fast lane currently has a known unrelated failure tracked by KRMA-853; report that separately and ensure the focused verification and serial lane are green.

### Counterpoint re-verification blocker (2026-10-10)

The new `LargeImportLibraryGridBenchmark` is useful model/scheduler evidence, but it does not mount `LibraryGridView` or measure SwiftUI layout/frame presentation, and its reported metrics have no pre-change baseline. An independent Release run with 1,500 local RAW copies passed: visible fill 2,089 ms, simulated-scroll heartbeat max 19.5 ms with 0/1,319 gaps over 33 ms, select-all 0.53–1.10 ms, shift-click 0.67 ms, peak RSS 1,912 MB. This supports the model path only; it cannot establish real scrolling/selection responsiveness or the measured contribution of the removed scans. `docs/TESTING.md` also states that Instruments could not record on this machine.

To unblock: record a comparable pre-change and current Release baseline for the mounted large-import Library interaction, including scroll hitch/frame behavior, select-all latency, visible-thumbnail fill, and peak memory; capture the relevant SwiftUI/main-actor profile and identify measured causes; then rerun the interaction while thumbnails are still generating. Keep the display-bound capture benchmark out of scope. Verification requires that evidence in `docs/TESTING.md`, a green serial lane, the focused interaction/profile procedure, and reporting the known unrelated fast-lane KRMA-853 failure separately.

### Comment — human @ 2026-10-11T14:09:11.611Z

Owner decision 2026-10-11: waive the mounted-grid Instruments profile criterion. Instruments cannot record on this machine; window-independent Release baselines (1,500 RAWs: 0/1,319 heartbeat gaps over 33 ms, select-all ~1 ms) are in docs/TESTING.md, and the owner reports the grid feels OK in use once images are imported. Verifier: do not require the mounted profile.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-10T14:16:03.653Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] Reproducible large-import benchmark/profile with baseline scroll hitching, select-all latency, visible-thumbnail fill time, and peak memory recorded in docs/TESTING.md (fail) — docs/TESTING.md explicitly says no Instruments profile or timing numbers have been recorded.
- [ ] Root causes recorded from profile (fail) — The source-level item lookup and queue-refill scans are identified, but their measured contribution and remaining causes are unknown without the required profile.
- [ ] Scrolling and selection remain responsive with no multi-frame main-actor stalls during thumbnail generation after a large import (fail) — No large-import interaction or frame responsiveness evidence is recorded, so this criterion cannot be established.
- [x] Visible thumbnails are prioritized and off-screen requests are cancelled or deprioritized (pass) — Existing bounded priority scheduler, release cancellation, and testLargeColdLibraryBoundsDecodeWorkAndReleaseCancelsQueuedDecodes provide policy and regression coverage.
- [ ] Scheduling/priority/cancellation tests and required fast and serial lanes pass (fail) — scripts/ci-tests.sh serial passed (510 tests, 0 failures). scripts/ci-tests.sh fast exited 1 due to LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction at LightInspectorTests.swift:160; unrelated regression already tracked by KRMA-853. The KRMA-841 scheduling regression tests ran in the fast lane without reported failures.
Checks run:
- Independent code review of commit 92a5ea8f and ImageCollection thumbnail scheduling/index changes
- scripts/ci-tests.sh fast — exit 1; unrelated LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction failure tracked by KRMA-853
- scripts/ci-tests.sh serial — exit 0; 510 tests, 0 failures
- Inspected docs/TESTING.md; no large-import performance profile or requested timing/memory baseline is recorded
Findings:
- Blocking: the core user-visible performance acceptance criterion is not demonstrated, and the required large-import Release profile/baseline and measured root cause are missing.
- Non-blocking, unrelated: fast lane fails the LightInspector tone-curve reset source assertion; KRMA-853 already tracks it.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: unknown
Pickup session: 01MV2GZRTSBR8M8YK2
Summary: Large-import performance acceptance remains unverified: no Release profile or user-interaction baseline exists; fast lane also has unrelated KRMA-853 failure.

- 2026-10-10T14:47:20.079Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] Reproducible large-import benchmark/profile with baseline scroll hitching, select-all latency, visible-thumbnail fill time, and peak memory recorded in docs/TESTING.md (fail) — An independent 1,500-file Release model benchmark passed and measured visible fill 2,089 ms, simulated-scroll heartbeat max 19.5 ms with 0/1,319 gaps over 33 ms, select-all 0.53–1.10 ms, shift-click 0.67 ms, and peak RSS 1,912 MB. It has no pre-change baseline and does not mount LibraryGridView or measure SwiftUI frame presentation; the acceptance criterion remains unmet.
- [ ] Root cause(s) recorded from the profile (fail) — The source-level item-index and queue-refill scans were removed, but no comparative profile measures their contribution or remaining mounted-grid causes. docs/TESTING.md records that Instruments could not record on this machine.
- [ ] Scrolling and selection stay responsive with no multi-frame main-actor stalls while thumbnails generate after a large import (fail) — The model heartbeat showed no gaps over 33 ms in the simulated scroll run, but this does not exercise SwiftUI layout or frame presentation, so the user-visible criterion cannot be established.
- [x] Visible thumbnails are prioritized and off-screen requests are cancelled or deprioritized (pass) — Code review confirms bounded priority scheduling and queued off-screen cancellation; the existing large-cold-library scheduling regression test passed in the fast lane.
- [ ] Scheduling/priority/cancellation tests and required fast and serial lanes pass (fail) — scripts/ci-tests.sh serial passed (510 tests, 0 failures). scripts/ci-tests.sh fast exited 1 only at LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction (LightInspectorTests.swift:160), tracked by KRMA-853; scheduling regression coverage had no reported failure.
Checks run:
- Independent review of KRMA-841 implementation commits 92a5ea8f and 1c8b089d, ImageCollection index/cache changes, scheduler policy, benchmark limitations, and docs/TESTING.md.
- scripts/ci-tests.sh fast: exit 1; unrelated LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction failure tracked by KRMA-853.
- scripts/ci-tests.sh serial: exit 0; 510 tests, 0 failures.
- KROMORA_LARGE_IMPORT_BENCHMARK=1 KROMORA_LARGE_IMPORT_COUNT=1500 swift test -c release --filter LargeImportLibraryGridBenchmark: exit 0; 1 test passed in 57.647 s; 2,089 ms visible fill, simulated-scroll heartbeat max 19.5 ms, zero gaps >33 ms, select-all 0.53–1.10 ms, shift-click 0.67 ms, peak RSS 1,912 MB.
- Inspected docs/TESTING.md: post-change model metrics are present but no pre-change baseline or mounted LibraryGridView/Instruments profile is recorded.
- git show --check 92a5ea8f and git show 1c8b089d: exit 0.
Findings:
- Blocking: required comparative mounted-grid Release profile and user-visible scroll/frame responsiveness evidence remain missing; the new model benchmark does not establish those acceptance criteria.
- Non-blocking unrelated fast-lane failure at LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction is tracked by KRMA-853.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: unknown
Pickup session: 01MV2HZUO45LFOCOW3
Summary: Re-verification remains blocked: Release model benchmark passes, but mounted-grid responsiveness and a pre-change profile baseline are still unverified; fast lane has the unrelated KRMA-853 failure.
