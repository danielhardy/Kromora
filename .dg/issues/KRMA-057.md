---
id: KRMA-057
title: Build repeatable large-library and render benchmark scenarios
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:quality
  - phase:10
created: 2026-08-30T18:30:36.847Z
updated: 2026-09-26T13:56:42.181Z
blockers: []
estimate: 5
order: 2kkkkkki
board: product
---

## Objective

Record a repeatable performance baseline for the shipped MVP workflow on representative hardware and library sizes.

## Context

Part of **Epic 10 — Image quality, performance, and MVP release gate**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Select one normal-use dataset and one stress dataset based on the current MVP's intended audience; document why those sizes and source images were chosen.
- Measure the user-visible path: open/import, grid browsing/culling, photo switch, representative adjustment response, and export.
- Record warm/cold cache state, hardware, OS, build configuration, and dataset characteristics.
- Use existing signposts and profiling tools; keep performance measurements out of timing-sensitive unit-test assertions.
- Propose concrete release targets only after the baseline is measured and reviewed.

## Acceptance criteria

- [ ] Chosen workloads and repeatable steps are documented.
- [ ] Results distinguish input-to-presentation latency from background render completion.
- [ ] A short report records responsiveness, memory/resource observations, and any visible failures.
- [ ] Any proposed target has a user-facing rationale and a reference machine.

## Verification

- Run the chosen scenarios on at least one supported Apple Silicon Mac and record summarized results.

## Out of scope

- Speculative optimization.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
