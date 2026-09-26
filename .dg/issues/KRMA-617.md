---
id: KRMA-617
title: Build edit-aware smart previews for large libraries
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
created: 2026-09-26T13:56:40.657Z
updated: 2026-09-26T13:56:43.523Z
blockers: []
order: xfffffei
board: product
---

## Objective

Make culling and offline browsing responsive without running a full RAW develop render for every grid cell.

## Context

Visible-neighborhood thumbnail prioritization and windowed queries already exist. This ticket covers preview pyramids and throughput beyond that work.

Derived from §10 Performance and scale in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Build bounded 2560-pixel edit-aware previews in the background with progress, pause, quality selection, and storage accounting.
- [ ] Use an appropriate RAW embedded-JPEG fast path and visibly identify previews that approximate current edits.
- [ ] Measure scrolling and cold-open behavior on large RAW catalogs and prioritize visible/prefetch-ahead work.
- [ ] Keep final canvas/export output sourced from the original and preserve preview/export parity.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
