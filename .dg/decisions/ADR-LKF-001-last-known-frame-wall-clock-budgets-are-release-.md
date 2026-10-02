---
id: ADR-LKF-001
title: Last-known-frame wall-clock budgets are release evidence, not a 734/728 gate
date: 2026-10-01T20:23:02.977Z
status: accepted
---

## Status
Accepted (owner decision, 2026-10-01).

## Context
KRMA-734 required every architecture budget to pass and forbade redefining a target in verification, so each wall-clock miss spawned a child ticket and each child spawned another (KRMA-743 to 749). The targets (warm Edit first pixel p95 <= 50 ms, warm 30-cell grid p95 <= 100 ms) were written before any valid measurement existed. The KRMA-744 harness (8bb287a7) is the first trustworthy evidence: after the hash fixes in KRMA-746/747 the main-actor budget passes (p95 1.99 ms vs <= 2 ms) and warm Edit first pixel fell from 664 ms to about 290 ms, but first pixel (~290 ms vs 50) and grid re-entry (~230 ms vs 100) remain far over budget, and two rounds of targeted fixes (grid observation narrowing, hash reuse) did not close them. The remaining gap likely needs an architectural change (for example keeping the Edit and Library views mounted instead of remounting), not another incremental ticket.

## Decision
1. KRMA-734 and KRMA-728 close on their structural, fault-injection, identity, and documentation criteria plus the structural budgets (exact warm Edit: zero renders and one confirmed frame; stale warm Edit: one provisional and at most one confirmed; main-actor before first suspension <= 2 ms). The wall-clock first-pixel and grid budgets are recorded as release benchmark evidence in docs/TESTING.md, as KRMA-734 itself allows: "record the wall-clock result as release benchmark evidence. Do not silently drop the budget."
2. The 50 ms and 100 ms targets are NOT redefined or dropped. They are tracked, unchanged, by KRMA-748 (warm Edit first pixel) and KRMA-749 (warm 30-cell grid), both non-gating, under the umbrella KRMA-750, which holds the shared structural decision. KRMA-745, the first unsuccessful grid attempt, stays parked and is continued by 749.
3. A budget miss with a measured profile and an open ticket is a handoff, not a reason to open a new child ticket on every re-run.

## Consequences
The performance work continues on its own track without holding the qualification, and the evidence stays honest: the budgets are visibly unmet in docs/TESTING.md until KRMA-750 meets them.

## Amendment (owner decision, 2026-10-01): main-actor tolerance
The main-actor-before-first-suspension target stays <= 2 ms, but a measured p95 up to 3 ms (judged as the median over up to three captures) passes. The measured median is 2.03 ms (1.88-2.19 across runs), which is run-to-run variance on a figure that is a small fraction of one display frame (16.7 ms at 60 Hz, 8.3 ms at 120 Hz) and is not what a user feels; the felt latency is the first-pixel time, tracked in KRMA-748. This tolerance exists so verification does not fail or spawn a ticket on noise around the limit. It does not apply to the first-pixel or grid budgets.

