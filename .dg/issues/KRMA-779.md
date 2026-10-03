---
id: KRMA-779
title: Bound pending thumbnail frame writes after abrupt termination
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Fresh store reads settled batch after max age without flush/shutdown
      result: pass
    - criterion: Deterministic clock/scheduler seam
      result: pass
      notes: ThumbnailFrameStoreFlushTimer injectable sleep
    - criterion: 200-write burst rewrite bound
      result: pass
    - criterion: Write failure keeps prior frames readable and retry recovers
      result: pass
    - criterion: fast, serial, dg validate pass; docs match constant
      result: pass
      notes: Docs state two-second window matching maxPendingWriteAge
  checks_run:
    - swift test --filter ThumbnailFrameStoreTests (8 pass)
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial (468 pass)
    - dg validate (warnings only)
  findings:
    - "Low: under persistent write failure, retained pending records grow without bound and each write past 32 retries a flush; cache-only, non-blocking."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-03T05:00:15.630Z
  session: 01MURX31VRGXE28COO
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - cache
  - reliability
created: 2026-10-03T02:59:28.324Z
updated: 2026-10-03T05:00:15.632Z
blockers: []
order: a0
board: product
---

## Objective

Bound how long settled thumbnail frames can remain only in memory during a sustained write burst.

## Context

KRMA-768 tracks the overall frame-cache loss window. This child owns `ThumbnailFrameStore`'s packed thumbnail writes and index rewrite cost. Graceful shutdown is covered by KRMA-778; per-asset preview-frame writes are covered by KRMA-780.

Today the store flushes after 250 ms of quiet, at 32 pending records, or when `flush()`/`shutdown()` is called. Continuous settles can keep resetting the quiet delay, so a force quit can lose the newest batch. The packed store rewrites its whole index per append, so the new deadline must preserve batching and bound rewrite work.

## Scope

- Add a named maximum pending-write age measured from the first queued write in a batch, alongside the existing quiet-delay and count triggers. Use a two-second initial target; if implementation evidence requires another value, document the reason and update the contract before handoff.
- Coalesce writes and ensure the age trigger does not create repeated time-based flushes more often than its configured interval. Preserve the existing count-trigger behavior and account for it separately in the rewrite bound.
- Keep the write task cancellable and safe against overlap with a later batch.
- Document the loss window and batching policy in `docs/STORAGE_POLICY.md` and `docs/TESTING.md`.

## Acceptance criteria

- [ ] With continuous writes that prevent the quiet timer from firing, a fresh `ThumbnailFrameStore` over the same directory can read the settled batch after the configured maximum age, without an explicit `flush()` or `shutdown()`.
- [ ] The test uses a controllable clock/scheduler or another deterministic seam rather than relying on a long wall-clock sleep.
- [ ] A 200-write burst asserts index rewrites remain within the time-trigger bound plus existing count-triggered flushes; no per-record rewrite storm is introduced.
- [ ] Interruption or injected write failure leaves the previous indexed frames readable and a later retry can recover.
- [ ] `fast` and `serial` lanes and `dg validate` pass; the documented maximum loss window matches the named implementation constant.

## Implementation notes

- Keep frame data as disposable cache data; cache failures degrade to misses and never affect package truth.
- Do not run display-bound captures. Use deterministic store tests.
- Swift 6 language mode, macOS 26+ on Apple Silicon, no compatibility branches or third-party dependencies.
- Commit with a subject starting `KRMA-779:`; do not push.

### Comment — codex @ 2026-10-03T04:53:36.541Z

Implemented bounded thumbnail batching in db30e3f. Added a two-second maximum pending age alongside the resettable 250 ms quiet timer and 32-record trigger, fenced timer callbacks by batch/token, and retain failed batches for retry. Documented the loss window and batching policy. Verification passed: focused ThumbnailFrameStoreTests (8 tests), scripts/ci-tests.sh fast (1,498 tests), scripts/ci-tests.sh serial (468 tests), and dg validate (OK; existing model/context warnings).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-03T05:00:15.630Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Fresh store reads settled batch after max age without flush/shutdown (pass)
- [x] Deterministic clock/scheduler seam (pass) — ThumbnailFrameStoreFlushTimer injectable sleep
- [x] 200-write burst rewrite bound (pass)
- [x] Write failure keeps prior frames readable and retry recovers (pass)
- [x] fast, serial, dg validate pass; docs match constant (pass) — Docs state two-second window matching maxPendingWriteAge
Checks run:
- swift test --filter ThumbnailFrameStoreTests (8 pass)
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial (468 pass)
- dg validate (warnings only)
Findings:
- Low: under persistent write failure, retained pending records grow without bound and each write past 32 retries a flush; cache-only, non-blocking.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MURX31VRGXE28COO
