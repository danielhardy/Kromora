---
id: KRMA-538
title: Fix LUTWorkflowTests persistence and navigation timeouts
type: task
status: ready
priority: high
agent: codex
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - fast-lane
  - regression
  - lut
created: 2026-09-22T17:35:55.413Z
updated: 2026-09-22T17:36:25.652Z
estimate: 3
order: zs
board: product
---

## Objective

Restore durable LUT workflow behavior across import, navigation, copy/paste, undo, and relaunch.

## Evidence

The fast lane failed LUTWorkflowTests while waiting for persisted imported Looks, the second photo, and relaunched Looks. Copy/paste also lost the destination LUT and intensity, and the identical-referenced-photo test inherited or failed to persist the expected Look.

## Acceptance criteria

- [ ] The focused LUTWorkflowTests suite passes without timeout.
- [ ] Imported Looks become durable before assertions and relaunch.
- [ ] LUT copy/paste and undo preserve the expected LUT ID, intensity, and selection scope.
- [ ] Identical referenced photos do not cross-reference LUT state.
- [ ] The fast lane no longer reports this suite.
