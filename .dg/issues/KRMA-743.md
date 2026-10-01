---
id: KRMA-743
title: Diagnose and fix warm Edit release latency budget miss
type: bug
status: ready
priority: urgent
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - performance
  - verification
created: 2026-10-01T03:37:04.583Z
updated: 2026-10-01T03:37:04.583Z
blockers: []
order: m
board: product
---

## Objective

Diagnose and fix the warm Edit selection latency measured by KRMA-742 against the unchanged KRMA-734 budgets.

## Context

KRMA-742 Release capture on stable Xcode 27.0 (27A266a), macOS 27.0 build 26A428, Apple M1 Pro,
commit `29496b3df7cea4bc9e1d6b24074f15b5551ccb9d`, DSC01019.ARW (9504×6336), 1440×897 point
viewport / 2880×1794 backing pixels, measured five warm Edit selections. Correct-photo first-pixel
p95 was 197.2 ms against <= 50 ms; synchronous AppViewModel selection work before asynchronous
tasks p95 was 289.0 ms against <= 2 ms. Exact warm and stale warm frame counts passed, and warm
30-cell grid p95 passed at 0.135 ms. Capture artifacts are in `/tmp/kromora-capture-krma742`.

## Acceptance criteria

- [ ] Attribute the warm Edit first-pixel and pre-suspension main-actor misses to concrete synchronous and asynchronous work.
- [ ] Fix the warm Edit path without changing the KRMA-734 targets.
- [ ] Re-run the last-known-frame Release capture on Apple Silicon with real drawable callbacks and enough warm Edit samples to report p50/p95.
- [ ] Meet warm Edit first-pixel p95 <= 50 ms and main-actor work before first suspension <= 2 ms.
- [ ] Run relevant focused tests, Release build, git diff --check, and dg validate.

## Implementation notes

Use `scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW`.
Keep actual presentation counts tied to PreviewSurface drawable callbacks.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
