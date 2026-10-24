---
id: KRMA-780
title: Make settled preview-frame writes bounded and crash-safe
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Fresh store reads frame within bound without flush/shutdown
      result: pass
      notes: Two-second maxSettleToDiskDelay, user-initiated priority; test polls fresh stores.
    - criterion: Persistence test not display-bound
      result: pass
    - criterion: Interruption leaves prior frame readable; success leaves new frame
      result: pass
      notes: Staged file plus rename(2); beforeAtomicReplace seam tested.
    - criterion: Stale/coalesced writes cannot overwrite newer frame
      result: pass
      notes: Token fencing in writePendingWrite and write.
    - criterion: Existing tests, fast, serial, dg validate pass; docs agree
      result: pass
      notes: Re-ran LatestPreviewFrameStoreTests (24 pass) and dg validate (existing warnings only); fast/serial taken from implementer report.
  checks_run:
    - swift test --filter LatestPreviewFrameStoreTests (24 passed)
    - dg validate (OK, pre-existing warnings)
    - code review of commit bde0e8d
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-03T05:18:14.368Z
  session: 01MURXXO9UR8KLAU68
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - cache
  - reliability
created: 2026-10-03T02:59:28.895Z
updated: 2026-10-03T05:18:14.370Z
blockers: []
order: a0
board: product
---

## Objective

Ensure a settled canonical preview frame reaches disk within a documented bound and replaces the prior frame atomically.

## Context

KRMA-768 tracks the overall frame-cache loss window. This child owns `LatestPreviewFrameStore`, which coalesces writes per asset and rasterizes/writes on its own task. Thumbnail pack batching is covered by KRMA-779; graceful termination integration is covered by KRMA-778.

Verify the current scheduling and persistence path instead of assuming that task submission means the frame is durable. A kill does not run shutdown hooks, so the settled-frame path itself needs a finite write bound. If a frame replaces an existing `.kframe`, interruption must leave either the prior complete frame or the new complete frame readable.

## Scope

- Trace canonical settle through rasterization, scheduling, and atomic file replacement.
- Ensure lower-priority queued work cannot defer a canonical write indefinitely; define a named maximum settle-to-disk delay of no more than two seconds, or document a measured reason and revised bound before handoff.
- Preserve per-asset coalescing and generation/source fences so stale work cannot replace a newer frame.
- Extend existing fault-injection coverage for interruption during write/replace, and document the write bound in `docs/STORAGE_POLICY.md` and `docs/TESTING.md`.

## Acceptance criteria

- [ ] After a canonical settle, a fresh `LatestPreviewFrameStore` over the same directory reads the frame within the documented bound without calling `flush()` or `shutdown()`.
- [ ] The persistence test does not depend on a display-bound capture and uses deterministic scheduling or a bounded store-level wait.
- [ ] Injected interruption before replacement leaves the prior complete frame readable; successful replacement leaves the new complete frame readable; no partial frame is accepted.
- [ ] Coalesced or stale queued writes cannot overwrite a newer frame for the same asset.
- [ ] Existing corruption/interrupted-write tests plus `fast`, `serial`, and `dg validate` pass; the docs and named bound agree.

## Implementation notes

- Cache failures degrade to a miss; never let this path block library open or edit persistence.
- Swift 6 language mode, macOS 26+ on Apple Silicon, no compatibility branches or third-party dependencies.
- Commit with a subject starting `KRMA-780:`; do not push.

### Comment — codex @ 2026-10-03T05:17:31.063Z

Implemented a fixed two-second per-asset write deadline at user-initiated priority, token-fenced coalescing, and staged atomic replacement. Added bounded fresh-store and interrupted-replacement coverage; updated storage and testing docs. Verified: LatestPreviewFrameStoreTests (24), fast (1,500), serial (468), dg validate (OK; existing warnings only). Commit bde0e8d.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-03T05:18:14.368Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Fresh store reads frame within bound without flush/shutdown (pass) — Two-second maxSettleToDiskDelay, user-initiated priority; test polls fresh stores.
- [x] Persistence test not display-bound (pass)
- [x] Interruption leaves prior frame readable; success leaves new frame (pass) — Staged file plus rename(2); beforeAtomicReplace seam tested.
- [x] Stale/coalesced writes cannot overwrite newer frame (pass) — Token fencing in writePendingWrite and write.
- [x] Existing tests, fast, serial, dg validate pass; docs agree (pass) — Re-ran LatestPreviewFrameStoreTests (24 pass) and dg validate (existing warnings only); fast/serial taken from implementer report.
Checks run:
- swift test --filter LatestPreviewFrameStoreTests (24 passed)
- dg validate (OK, pre-existing warnings)
- code review of commit bde0e8d
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MURXXO9UR8KLAU68
