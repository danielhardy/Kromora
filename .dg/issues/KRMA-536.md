---
id: KRMA-536
title: Fast-lane ThumbnailSwitchLifecycleTests/WorkspaceNavigationTests hang/timeout predates KRMA-521
type: task
status: ready
priority: high
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - testing
  - performance
  - observation
created: 2026-09-22T15:24:15.625Z
updated: 2026-09-22T15:27:17.299Z
depends_on:
  - KRMA-521
order: zw
board: product
---

## Objective

Resolve the fast-lane failures and hangs in `ThumbnailSwitchLifecycleTests` and `WorkspaceNavigationTests` that were reproduced against the pre-KRMA-521 baseline.

## Context and evidence

The fast lane times out while waiting for published thumbnail, histogram, and source-failure state to settle. The same suite hangs indefinitely against commit `16d478b`, immediately before the KRMA-521 implementation commit `8e8e394`, so the issue predates KRMA-521 and is tracked separately.

## Acceptance criteria

- [ ] `ThumbnailSwitchLifecycleTests` completes without published-state timeouts.
- [ ] `WorkspaceNavigationTests` completes without published-state timeouts.
- [ ] The fast lane passes with the regression fixed and no KRMA-521 behavior regressed.

