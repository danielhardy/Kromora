---
id: LUMO-223
title: Add smooth non-destructive brush masks
type: feature
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - epic:masking
  - masking
  - editor
  - rendering
  - performance
created: 2026-09-04T21:48:31.366Z
updated: 2026-09-04T21:54:15.894Z
depends_on:
  - LUMO-217
  - LUMO-219
  - LUMO-220
order: zh
board: product
---

## Objective

Deliver direct, low-latency mask painting with editable photographic brush controls and compact,
resolution-independent persistence.

## Context

Brush input arrives faster than a full image can be rerendered. The cursor and painted overlay must
track every useful sample immediately, while the durable document, history, hashing, and disk writes
update only at gesture boundaries. Export still needs the original vector intent at full resolution.

## Acceptance criteria

- [ ] Capture native pointer/coalesced samples and optional pressure; mouse input behaves as pressure
      1. Resample by source-space distance and simplify the committed path within a tested visual
      error bound.
- [ ] Expose brush Size, Feather, Flow/Intensity, and Density; bracket keys adjust size and
      Shift+bracket adjusts feather. Space temporarily pans without abandoning the tool.
- [ ] Use the plan's smooth radial falloff and repeated-stamp accumulation formula, with density as
      the opacity cap, identically for preview and export.
- [ ] Show a screen-aligned cursor and active stroke immediately through reusable GPU resources;
      avoid live-path GPU readback and full-history rerasterization per pointer event.
- [ ] Persist normalized vector strokes/settings, not raster tiles. Commit one document mutation and
      one undo entry per completed stroke; cancellation makes no history/persistence entry.
- [ ] Provide non-destructive erase through a subtracting brush component/stroke group.
- [ ] Cache completed stroke groups and incrementally composite only new active/committed work.
- [ ] A continuous 30-second stroke remains responsive, has bounded resampled sample/memory growth,
      and meets the p95 overlay/main-thread budgets recorded by LUMO-217.
- [ ] Brush masks survive deselect/reselect, reopen, zoom/crop changes, undo/redo, copy/paste, and
      full-resolution export with preview/export agreement.

## Implementation notes

Follow Section 4.3 and Step 6 of `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`. Likely work spans a
native pointer surface, `MaskInteractionState`, brush geometry/resampling helpers, overlay renderer,
mask render cache, and `AppViewModel+Masking.swift`.

Never append samples directly to `EditDocument` at pointer frequency or run JSON encoding/cache
hashing/full mask rasterization on the main thread during movement.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
