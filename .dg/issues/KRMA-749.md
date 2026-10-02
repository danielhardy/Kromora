---
id: KRMA-749
title: Attribute and fix warm 30-cell grid re-entry (still 231 ms p95 after KRMA-745)
type: bug
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - performance
created: 2026-10-01T20:18:29.922Z
updated: 2026-10-01T22:51:55.864Z
parent: KRMA-750
depends_on:
  - KRMA-734
blockers: []
order: zq
board: product
---

## Objective

Attribute warm 30-cell Library grid re-entry time to concrete views/work and fix it so p95 <= 100 ms (unchanged KRMA-734 budget), with no visible-cell thumbnail swaps and no extra render admissions.

## Context

Verification of KRMA-745 re-ran the capture on an awake, unlocked display at HEAD 1145f266 (Release, Apple M1 Pro, macOS 27.0, DSC01019.ARW, 30 samples): warm-30-cell-grid p50/p95 = 217 / 231 ms; `LAST_KNOWN_FRAME_BUDGET_SUMMARY exact=PASS stale=PASS grid=FAIL edit=FAIL`. Report: `/tmp/kromora-capture/KROMORA-last-known-frame-DSC01019-20261001-141306-report.jsonl`. Per sample: 1 grid mount, 10 body evaluations, 0 renders.

KRMA-745 change 312fb63 (AppViewModel stored as a plain reference in LibraryGridView) did not move the number (baseline 193/214 ms; earlier re-run 197/202 ms). Observation narrowing is not the dominant cost. KRMA-745 also never produced the grid-only attribution it required; its Time Profiler trace spans setup and Edit handoffs.

## Acceptance criteria

- [ ] Grid-only attribution (os_signpost around mount/layout/display, or a profile restricted to the grid interval) naming the dominant views/work; record in docs/TESTING.md.
- [ ] Fix without changing the KRMA-734 targets.
- [ ] `scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW --iterations 30` reports `grid=PASS` on an awake display.
- [ ] Focused tests, Release build, git diff --check, dg validate.


### Comment — claude @ 2026-10-01T20:23:31.743Z

Superseded by KRMA-750 per ADR-LKF-001 (wall-clock budgets are non-gating release evidence). Parked in backlog; no work is lost. Anything this ticket produced stays in git history. Lead from the stopped KRMA-749 run (uncommitted AppViewModel handoff-animation change) is recorded in KRMA-750.


### Comment — claude @ 2026-10-01T20:25:45.413Z

Correction: I parked this as 'superseded by KRMA-750'; that was wrong. This is the warm 30-cell grid budget and stays a real work item (it also continues KRMA-745, which stays parked). KRMA-750 is now an umbrella that coordinates 748 and 749. Restored to ready, non-gating (ADR-LKF-001), parent changed to KRMA-750, and it waits on KRMA-734 only so its captures do not collide with the verifier's on the shared display and .build. The uncommitted handoff-animation lead from the stopped run is recorded in Implementation notes.


### Comment — claude @ 2026-10-01T22:51:55.861Z

Parked in backlog by the owner while the last-known-frame chain is verified. Optional polish toward the plan's 'instant' goal: warm Edit first pixel is about 290 ms and grid return about 235 ms in release (docs/TESTING.md), and it is not yet known whether that feels slow. Decide after trying a release build (swift run -c release). If it feels fine, close 748, 749, and 750 as won't-do; if not, promote KRMA-750 and do the work as one structural effort, supervised.
