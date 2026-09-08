---
id: LUMO-269
title: Parallelize independent detailed-analysis stages
type: task
status: ready
priority: low
labels:
  - masking
  - performance
created: 2026-09-07T01:14:47.482Z
updated: 2026-09-08T01:21:23.299Z
order: z
board: product
---

## Objective

Find out whether the five `.detailed` analysis stages can run concurrently instead of
sequentially, and do it only if measurement says it matters.

## Context

`PhotoAnalysisCoordinator.defaultStages[.detailed]` runs subject → foregroundInstance(0) →
background → face → person as sequential awaits (each a Vision request on a 768px image,
one-time per photo thanks to `PhotoAnalysisCache`). The person gate needs face/foreground
signals cached first, which constrains ordering: subject, foreground-instance, and face are
independent of each other, but person must come after the signals land (background derives
from foreground, so it slots after the instance stage too).

## Work (measure-first)

- Time a cold `.detailed` analysis on a representative photo, per stage. If the total is
  comfortably sub-second, close this ticket with the numbers — the complexity is not worth it.
- If it matters: run subject + foregroundInstance(0) + face concurrently (task group),
  then background + person after their inputs land. Preserve the swallowed-stage semantics
  (a failed stage must not fail siblings or the analysis) and the in-flight dedup in
  `coordinator.mask`.
- Caveat to verify: Vision/ANE may serialize internally, in which case concurrency buys
  nothing but contention — the measurement decides.

## Acceptance criteria

- [ ] Cold-`.detailed` per-stage timings recorded in the ticket.
- [ ] Either concurrent stages land with a measured speedup and unchanged failure semantics
      (existing provider/coordinator tests pass unmodified in spirit), or the ticket closes
      with numbers justifying sequential.
