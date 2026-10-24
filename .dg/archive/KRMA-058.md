---
id: KRMA-058
title: Profile and fix the highest-impact measured bottlenecks
type: task
status: done
priority: high
labels:
  - mvp
  - epic:quality
  - phase:10
created: 2026-08-30T18:30:37.263Z
updated: 2026-10-24T12:59:35.000Z
depends_on:
  - KRMA-056
blockers: []
estimate: 8
order: zzzzv
board: product
---

## Objective

Fix only measured performance problems that materially harm the core MVP workflow, with before/after evidence.

## Context

Part of **Epic 10 — Image quality, performance, and MVP release gate**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Start from a bottleneck observed in KRMA-057 or a reproducible user-facing failure.
- Use an appropriate profiler to identify the cause before changing code.
- Make a narrow fix and repeat the same scenario on the same hardware/configuration.
- Track unrelated or lower-impact observations separately; do not optimize speculative paths.

## Acceptance criteria

- [ ] Each change addresses a reproducible, user-visible bottleneck or a target justified by KRMA-057.
- [ ] Before/after measurements use the same documented workload and machine.
- [ ] Core workflow behavior and correctness remain intact.
- [ ] Remaining performance findings are prioritized by user impact rather than arbitrary thresholds.

## Verification

- Repeat only the affected KRMA-057 scenario and inspect profiler evidence relevant to the identified bottleneck.

## Out of scope

- Micro-optimizations without measured benefit.

### Comment — claude @ 2026-10-11T13:11:11.770Z

Closing: the measured bottleneck (main-actor whole-file hashing) was fixed under KRMA-860. Remaining first-pixel/grid budgets are tracked by KRMA-748/749/750.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
