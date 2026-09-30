---
id: KRMA-738
title: Measure KRMA-734 release drawable budgets on stable Xcode 27
type: task
status: backlog
priority: urgent
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - performance
created: 2026-09-30T23:39:00.887Z
updated: 2026-09-30T23:39:00.887Z
blockers: []
order: m
board: product
---

## Objective

Measure KRMA-734 release drawable budgets on stable Xcode 27

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

## Objective

Parent: KRMA-734. Install/select Xcode 27.0 stable (27A266a), then run the Release drawable capture (`scripts/run-kromora-capture.sh --benchmark metal-presentation`) and record the required fields and p50/p95 results in docs/TESTING.md. Verify every KRMA-734 architecture budget: warm Edit p95 <= 50 ms, <= 2 ms main-actor work before first suspension, exact warm Edit zero renders, 30-cell grid p95 <= 100 ms, and crossfade/swap/layout counts.

## Diagnosis

The 2026-09-30 verification found `xcode-select -p` still pointing at Xcode-beta.app (27A5252f) and no stable Xcode installed, although the human blocker was marked resolved. The Release XCTest bundle cannot link on the beta SDK, so no budget has been measured. Any measured miss needs its own urgent ticket; do not redefine targets.
