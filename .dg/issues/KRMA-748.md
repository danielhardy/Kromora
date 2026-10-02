---
id: KRMA-748
title: Reduce warm Edit first-pixel latency after source hashing is removed
type: bug
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
created: 2026-10-01T20:06:16.885Z
updated: 2026-10-01T22:51:54.813Z
depends_on:
  - KRMA-734
blockers: []
order: zv
board: product
---

## Objective

Reduce the remaining warm Edit first-pixel and Library/Edit remount latency exposed after portable source hashes are reused.

## Context

KRMA-747 resolves package browsing placeholders to persisted source identities off the main actor. On an M1 Pro / macOS 27 Release capture with DSC01019.ARW (30 iterations), warm Edit pre-suspension p95 is 1.99 ms, but first-pixel p95 is 289.7 ms; warm 30-cell grid p95 is 227.4 ms. The Time Profiler trace `/tmp/kromora-capture/KRMA-747-time-profiler.trace` showed the old SHA-256 hot path reduced to 64 samples, while remaining main-thread samples were dominated by SwiftUI graph/layout and Edit mount work (`Attribute.init`, `AG::Graph`, `ContentView.body`, `NSHostingView.updateEnvironment`).

## Acceptance criteria

- [ ] Attribute and reduce the remaining first-pixel delay across Edit mount, SwiftUI graph updates, inspector, and stored-frame lookup; retain correct-photo presentation and generation fencing.
- [ ] `scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW --iterations 30` reports warm Edit first-pixel p95 <= 50 ms and pre-suspension p95 <= 2 ms.
- [ ] Focused tests, Release build, `git diff --check`, and `dg validate` pass.

## Implementation notes

Non-gating per ADR-LKF-001: KRMA-734 and KRMA-728 do not wait on this. The grid budget is KRMA-749; the shared structural approach (keep Library and Edit mounted instead of remounting) is decided in KRMA-750. Do not open a child ticket per re-run: a measured miss with a profile is a handoff.

Continue from the package identity fix in KRMA-747. The caller measured 30 Release samples with the shipping content and package preview store; use Time Profiler around `LastKnownFrameReleaseBenchmark` while attributing first-pixel time.

### Comment — claude @ 2026-10-01T20:23:30.857Z

Superseded by KRMA-750 per ADR-LKF-001 (wall-clock budgets are non-gating release evidence). Parked in backlog; no work is lost. Anything this ticket produced stays in git history. Lead from the stopped KRMA-749 run (uncommitted AppViewModel handoff-animation change) is recorded in KRMA-750.

### Comment — claude @ 2026-10-01T20:25:45.049Z

Correction: I parked this as 'superseded by KRMA-750'; that was wrong. This is the Edit first-pixel budget and stays a real work item. KRMA-750 is now an umbrella that holds the shared structural approach and coordinates 748 and 749. Restored to ready, non-gating (ADR-LKF-001), and it waits on KRMA-734 only so its captures do not collide with the verifier's on the shared display and .build.

### Comment — claude @ 2026-10-01T22:51:54.811Z

Parked in backlog by the owner while the last-known-frame chain is verified. Optional polish toward the plan's 'instant' goal: warm Edit first pixel is about 290 ms and grid return about 235 ms in release (docs/TESTING.md), and it is not yet known whether that feels slow. Decide after trying a release build (swift run -c release). If it feels fine, close 748, 749, and 750 as won't-do; if not, promote KRMA-750 and do the work as one structural effort, supervised.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
