---
id: LUMO-224
title: Add persistent smart Foreground and Background local masks
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
  - photo-intelligence
  - rendering
created: 2026-09-04T21:48:31.831Z
updated: 2026-09-04T21:54:16.666Z
depends_on:
  - LUMO-201
  - LUMO-202
  - LUMO-219
  - LUMO-220
order: zq
board: product
---

## Objective

Turn the existing semantic mask foundation into durable, editable Foreground and Background local
adjustment layers with progressive preview/refinement and safe regeneration.

## Context

LUMO-201 exposes selection-only semantic previews and LUMO-202 provides render-quality refinement,
but cache-backed `RegionMask` pixels are not a durable edit. A saved layer must remember what to
select, regenerate after cache deletion, and never attach a late result to another photo.

## Acceptance criteria

- [ ] Add a stable user-facing Foreground target representing the union of usable foreground
      instances; instance numbering is not the primary Foreground UI.
- [ ] Foreground and Background share segmentation/in-flight work and are complementary when
      produced from the same result.
- [ ] Persist semantic target, generation compatibility/version, edge feather, edge shift,
      density, and inversion; do not make a `RegionMaskReference` the sole source of truth.
- [ ] Creating/reselecting a smart mask displays a valid cached or preview-quality result first and
      replaces it with refined render quality without changing the layer identity.
- [ ] Missing or version-invalid cache data regenerates through the existing coordinator/provider/
      store path; failures remain explicit and recoverable without deleting the definition.
- [ ] Asset ID, source fingerprint, request revision, quality, and provider version are checked
      before any async result is published or rendered.
- [ ] Rapid switching/cancellation cannot display or export another photo's mask.
- [ ] Export waits for the correct render-quality result or reports an actionable failure; any
      lower-quality fallback requires explicit user choice.
- [ ] Existing Subject, Person, and Face targets remain available through the same durable model.
- [ ] Cache hit, deduplication, cancellation, regeneration, progressive replacement, local slider,
      persistence/reopen, cache deletion, and preview/export tests pass.

## Implementation notes

Follow Sections 4.2 and 6 plus Step 7 of `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`. Reuse
`PhotoAnalysisCoordinator`, `VisionSemanticMaskProvider`, `MaskStore`, `MaskRefinement`,
`RegionMask`, and `MaskOperations`; do not create a parallel Vision/cache path.

All analysis remains on-device, asynchronous, cancellable, and independent from unrelated creative
slider values.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
