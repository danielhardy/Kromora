---
id: KRMA-778
title: Flush both frame stores on graceful termination
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A focused test proves both frame stores are asked to flush and termination is not approved until both flush operations finish.
      result: pass
      notes: testTerminationFlushWaitsForBothFrameStores gates each store independently.
    - criterion: The tested failure path still allows termination to complete and leaves the stores safe to reopen as cache misses.
      result: pass
      notes: testFrameStoreFailuresDoNotPreventSuccessfulTerminationFlush plus reopen-as-miss tests for both stores.
    - criterion: Window-close and app-deactivation paths are traced; any required flush request is covered by a deterministic test or documented code-path assertion.
      result: pass
      notes: Last-window close goes through applicationShouldTerminate (documented in code); deactivation covered by AppViewModel and ApplicationShellCoordinator tests.
    - criterion: fast lane and dg validate pass; no display-bound capture is needed.
      result: pass
  checks_run:
    - scripts/ci-tests.sh fast (1494 tests, exit 0)
    - dg validate (exit 0, only unrelated warnings)
    - git diff --check
  findings: []
  fixes: []
  verification_commits:
    - 040a1c3
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-03T04:27:08.292Z
  session: 01MURVYZHRH2N8PX5I
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - cache
  - reliability
created: 2026-10-03T02:59:22.436Z
updated: 2026-10-03T04:27:08.294Z
blockers: []
order: a0
board: product
commits:
  - 040a1c3
---

## Objective

Ensure graceful app termination flushes settled writes from both persisted frame stores before the app exits.

## Context

KRMA-768 tracks the overall frame-cache loss window. This child owns only lifecycle integration for a clean quit or app deactivation; abrupt-kill durability is covered by KRMA-779 and KRMA-780.

`KromoraApp.applicationShouldTerminate` currently calls `viewModel.flushPendingWrites()` for edits. Trace the actual path through `AppViewModel.shutdown()` and verify whether `ThumbnailFrameStore` and `LatestPreviewFrameStore` are both drained before the `.terminateLater` reply. Also inspect the window-close and app-resign-active paths before changing them. Cache files remain disposable: a flush failure must not corrupt package truth or prevent the app from eventually exiting.

Relevant areas: `Sources/Kromora/AppDelegate.swift`, `Sources/KromoraKit/ViewModels/AppViewModel.swift`, the two frame-store implementations, and their lifecycle tests.

## Scope

- Ensure the terminate decision waits for both frame-store flushes to finish, using the existing asynchronous termination path.
- Ensure window close and app deactivation do not strand queued canonical frame writes; deactivation may request a best-effort asynchronous flush.
- Keep shutdown bounded and preserve the existing behavior when a disposable cache write fails.
- Add or extend a focused lifecycle test using the existing termination-flush seam, or introduce a narrow test seam if needed.

## Acceptance criteria

- [ ] A focused test proves both frame stores are asked to flush and termination is not approved until both flush operations finish.
- [ ] The tested failure path still allows termination to complete and leaves the stores safe to reopen as cache misses.
- [ ] Window-close and app-deactivation paths are traced; any required flush request is covered by a deterministic test or documented code-path assertion.
- [ ] `fast` lane and `dg validate` pass; no display-bound capture is needed.

## Implementation notes

- Do not add a synchronous wait to the main thread.
- Keep frame-cache failures best effort; edits and package data are outside this ticket's cache flush policy.
- Swift 6 language mode, macOS 26+ on Apple Silicon, no compatibility branches or third-party dependencies.
- Commit with a subject starting `KRMA-778:`; do not push.

### Comment — codex @ 2026-10-03T04:22:28.944Z

Implemented asynchronous termination flushing for thumbnail and latest-preview stores, with best-effort failure handling and bounded shutdown of unsettled canonical rasterization. App deactivation now requests and tracks an asynchronous cache flush; last-window close uses the same terminate-later path. Added gated lifecycle tests and cache-miss reopen tests. Verification passed: scripts/ci-tests.sh fast (1,494 tests), dg validate, and git diff --check. Commit: 040a1c3.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-03T04:27:08.292Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A focused test proves both frame stores are asked to flush and termination is not approved until both flush operations finish. (pass) — testTerminationFlushWaitsForBothFrameStores gates each store independently.
- [x] The tested failure path still allows termination to complete and leaves the stores safe to reopen as cache misses. (pass) — testFrameStoreFailuresDoNotPreventSuccessfulTerminationFlush plus reopen-as-miss tests for both stores.
- [x] Window-close and app-deactivation paths are traced; any required flush request is covered by a deterministic test or documented code-path assertion. (pass) — Last-window close goes through applicationShouldTerminate (documented in code); deactivation covered by AppViewModel and ApplicationShellCoordinator tests.
- [x] fast lane and dg validate pass; no display-bound capture is needed. (pass)
Checks run:
- scripts/ci-tests.sh fast (1494 tests, exit 0)
- dg validate (exit 0, only unrelated warnings)
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- 040a1c3
Actor: claude
Resolved model: sonnet
Pickup session: 01MURVYZHRH2N8PX5I
Summary: Verification passed: both frame stores are flushed concurrently before termination is approved; failures are best effort.
