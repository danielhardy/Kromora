---
id: KRMA-618
title: Add a work activity center and cache controls
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:41.325Z
updated: 2026-09-26T13:56:43.573Z
blockers: []
order: yaaaaa9c
board: product
---

## Objective

Make background work, cache usage, and degraded performance understandable and controllable.

## Context

Telemetry and bounded caches already exist; preserve bounded resource use and avoid adding another unbounded scheduler.

Derived from §10 Performance and scale in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Show import, preview-build, analysis, export, and mask-cache jobs in one activity center with progress, cancel, and pause where safe.
- [ ] Expose preview/mask/analysis cache sizes and purge controls, offline-volume behavior, and low-disk warnings.
- [ ] Add a per-device performance mode for battery or memory pressure and define how preview quality adapts.
- [ ] Publish a measurable slider-to-presented-frame latency budget and surface a degraded-preview state instead of silently lagging.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
