---
id: LUMO-225
title: Compose mask components with Add, Subtract, and Intersect
type: feature
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - epic:masking
  - masking
  - editor
  - rendering
created: 2026-09-04T21:48:32.438Z
updated: 2026-09-04T21:54:17.220Z
depends_on:
  - LUMO-221
  - LUMO-222
  - LUMO-223
  - LUMO-224
order: zv
board: product
---

## Objective

Allow every mask layer to combine smart, brush, linear, and radial components through clear,
editable Add, Subtract, and Intersect operations.

## Context

A Lightroom-style mask is often a semantic selection refined by a brush or gradient. Flattening
that result would destroy editability; component definitions, operations, order, and inversion must
remain visible and deterministic.

## Acceptance criteria

- [ ] Add component creation actions for Add, Subtract, and Intersect using every supported source
      type; the first component has explicit replace semantics.
- [ ] Show expandable ordered component rows with type, operation, enabled state, invert, selection,
      rename where useful, delete, reorder where semantics allow, and solo inspection.
- [ ] Selecting a component restores and edits its own smart refinement, brush, linear, or radial
      controls without changing sibling definitions.
- [ ] Composition uses deterministic soft-mask rules: replace, max for Add, bounded subtraction,
      and min for Intersect, followed by layer inversion/amount.
- [ ] UI naming and summaries make combinations such as “Foreground minus Brush” and “Radial
      intersect Foreground” understandable without inspecting pixels.
- [ ] Component operations are undoable, redoable, persisted, reopened, copied, reset, and included
      in the definition/cache hash.
- [ ] Golden tests cover operation order, inversion, disabled/empty components, mixed resolutions,
      preview/export parity, and all cross-type combinations.
- [ ] Composition stays GPU-backed and meets bounded cache/memory behavior for at least ten layers
      with representative multi-component masks.

## Implementation notes

Follow the layer/component model in Section 4, workspace behavior in Section 5, renderer rules in
Section 6, and Step 8 of `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`.

Do not destructively flatten components into one authoritative bitmap. Cached composites are
derived resources and must be rebuildable from the saved definitions.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
