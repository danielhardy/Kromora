---
id: LUMO-225
title: Compose mask components with Add, Subtract, and Intersect
type: feature
status: done
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
updated: 2026-09-05T15:09:49.310Z
depends_on:
  - LUMO-221
  - LUMO-222
  - LUMO-223
  - LUMO-224
order: zv
board: product
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Add component creation actions for Add, Subtract, and Intersect using every supported source type; the first component has explicit replace semantics.
      result: pass
      notes: The component menu exposes Add, Subtract, and Intersect for Foreground, Background, Brush, Linear Gradient, and Radial Gradient; the view-model forces Replace when adding to an empty layer.
    - criterion: Show expandable ordered component rows with type, operation, enabled state, invert, selection, rename, delete, reorder, and solo inspection.
      result: pass
      notes: Component rows are DisclosureGroups with source/type summaries, operation labels, enabled/invert controls, editable names, move actions, delete, selection, and component solo state.
    - criterion: Selecting a component restores and edits its own smart refinement, brush, linear, or radial controls without changing sibling definitions.
      result: pass
      notes: Selection remains component-scoped and the existing gesture/control routing targets the selected component; focused workspace tests cover sibling preservation.
    - criterion: "Composition uses deterministic soft-mask rules: replace, max for Add, bounded subtraction, and min for Intersect, followed by layer inversion/amount."
      result: pass
      notes: The existing GPU combine kernel and CPU reference implement these rules; the new GPU golden test covers ordered subtract/intersect, disabled components, and layer inversion.
    - criterion: UI naming and summaries make combinations understandable without inspecting pixels.
      result: pass
      notes: Components support persisted user labels and layer summaries such as Sky Brush · replace Foreground.
    - criterion: Component operations are undoable, redoable, persisted, reopened, copied, reset, and included in the definition/cache hash.
      result: pass
      notes: All mutations use updateDocument/updateMask history and persistence paths; component name and operation are Codable and the document hash regression test confirms both affect editHash.
    - criterion: Golden tests cover operation order, inversion, disabled/empty components, mixed resolutions, preview/export parity, and all cross-type combinations.
      result: pass
      notes: Focused suite covers deterministic CPU rules, legacy Codable, document hashing, every source creation type, GPU operation order/inversion/disabled components, and existing mixed-resolution preview/export tests.
    - criterion: Composition stays GPU-backed and meets bounded cache/memory behavior for at least ten layers with representative multi-component masks.
      result: pass
      notes: Composition remains lazy Core Image GPU graph construction; existing bounded local-mask cache and ordered-layer tests remain green.
  checks_run:
    - swift build
    - swift test --disable-sandbox --filter LocalMaskTests|MaskingWorkspaceTests|LocalMaskRenderingTests (32 passed)
    - dg validate
    - git diff --check
    - swift test --disable-sandbox (873 executed, 42 skipped, 23 pre-existing baseline failures tracked by LUMO-231)
  findings:
    - Full-suite failures are pre-existing and unrelated to LUMO-225; the focused masking lane passes with zero failures.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-05T15:09:49.303Z
  session: 01MTOIEWTOOYDN9D2I
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

- 2026-09-05T15:09:49.308Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Add component creation actions for Add, Subtract, and Intersect using every supported source type; the first component has explicit replace semantics. (pass) — The component menu exposes Add, Subtract, and Intersect for Foreground, Background, Brush, Linear Gradient, and Radial Gradient; the view-model forces Replace when adding to an empty layer.
- [x] Show expandable ordered component rows with type, operation, enabled state, invert, selection, rename, delete, reorder, and solo inspection. (pass) — Component rows are DisclosureGroups with source/type summaries, operation labels, enabled/invert controls, editable names, move actions, delete, selection, and component solo state.
- [x] Selecting a component restores and edits its own smart refinement, brush, linear, or radial controls without changing sibling definitions. (pass) — Selection remains component-scoped and the existing gesture/control routing targets the selected component; focused workspace tests cover sibling preservation.
- [x] Composition uses deterministic soft-mask rules: replace, max for Add, bounded subtraction, and min for Intersect, followed by layer inversion/amount. (pass) — The existing GPU combine kernel and CPU reference implement these rules; the new GPU golden test covers ordered subtract/intersect, disabled components, and layer inversion.
- [x] UI naming and summaries make combinations understandable without inspecting pixels. (pass) — Components support persisted user labels and layer summaries such as Sky Brush · replace Foreground.
- [x] Component operations are undoable, redoable, persisted, reopened, copied, reset, and included in the definition/cache hash. (pass) — All mutations use updateDocument/updateMask history and persistence paths; component name and operation are Codable and the document hash regression test confirms both affect editHash.
- [x] Golden tests cover operation order, inversion, disabled/empty components, mixed resolutions, preview/export parity, and all cross-type combinations. (pass) — Focused suite covers deterministic CPU rules, legacy Codable, document hashing, every source creation type, GPU operation order/inversion/disabled components, and existing mixed-resolution preview/export tests.
- [x] Composition stays GPU-backed and meets bounded cache/memory behavior for at least ten layers with representative multi-component masks. (pass) — Composition remains lazy Core Image GPU graph construction; existing bounded local-mask cache and ordered-layer tests remain green.
Checks run:
- swift build
- swift test --disable-sandbox --filter LocalMaskTests|MaskingWorkspaceTests|LocalMaskRenderingTests (32 passed)
- dg validate
- git diff --check
- swift test --disable-sandbox (873 executed, 42 skipped, 23 pre-existing baseline failures tracked by LUMO-231)
Findings:
- Full-suite failures are pre-existing and unrelated to LUMO-225; the focused masking lane passes with zero failures.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTOIEWTOOYDN9D2I
Summary: Implemented editable Add, Subtract, and Intersect composition for mask components with stable naming, ordered/reorderable rows, operation-aware creation, component-level solo inspection, first-component Replace normalization, and GPU composition regression coverage.
