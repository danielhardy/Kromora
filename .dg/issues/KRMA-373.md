---
id: KRMA-373
title: Align local-adjustment setting fidelity with normal Adjust controls
type: bug
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - masking
created: 2026-09-12T03:51:48.663Z
updated: 2026-09-12T03:52:14.620Z
order: y
board: product
---

## Objective

Align local-adjustment controls inside the masking workspace with the corresponding normal Adjust controls while preserving their per-layer behavior.

## Context

Local adjustments currently use a separate compact slider/readout implementation in MaskingWorkspace. The normal Adjust surfaces provide a more complete control contract, including consistent numeric entry, formatting, reset behavior, ranges, accessibility, and preview-interaction handling. The same adjustment concepts should have the same fidelity whether applied globally or through a selected mask layer; only scope and compositing should differ.

## Acceptance criteria

- [ ] Common local and global controls use the same supported ranges, units, sign conventions, display precision, numeric-entry behavior, and neutral/reset semantics.
- [ ] Local controls provide the same level of interaction fidelity as normal Adjust controls, including direct value entry where available, reset actions, keyboard behavior, and VoiceOver labels/values.
- [ ] Slider interaction, debouncing, undo grouping, persistence, and preview updates remain consistent with the normal Adjust workflow.
- [ ] Changes are applied only to the selected local-adjustment layer and never mutate the global adjustment state; layer amount, mask geometry, inversion, and blending semantics remain unchanged.
- [ ] All currently supported local adjustment properties remain available, including Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Temperature, Tint, Saturation, Vibrance, Texture, Clarity, and Dehaze, unless a deliberate product decision documents a change.
- [ ] Local values round-trip through save/reopen, undo/redo, copy/paste, and preview/export without precision loss or range drift.
- [ ] Regression coverage compares local/global control mappings and verifies precision, reset, accessibility, per-layer isolation, persistence, and render behavior.
