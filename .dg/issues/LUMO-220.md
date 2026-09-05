---
id: LUMO-220
title: Replace selection-only mask sheet with persistent Masking workspace
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
  - accessibility
created: 2026-09-04T21:48:29.898Z
updated: 2026-09-04T21:54:13.792Z
depends_on:
  - LUMO-217
  - LUMO-218
  - LUMO-219
order: w
board: product
---

## Objective

Build the persistent editor workspace that creates, selects, organizes, and re-edits saved mask
layers and their local adjustments.

## Context

The current modal `MaskingPanel` previews semantic results but has no document owner or active local
adjustment. A production workflow needs a stable mask list beside the main canvas, immediate access
to the selected layer's settings, and reliable transitions between masking, navigation, and crop.

## Acceptance criteria

- [ ] The toolbar Mask action activates a persistent Masking workspace rather than a disconnected
      Apply sheet; there is one masking product and one owner of selected mask state.
- [ ] Show ordered layers with overlay color, editable name, type summary, selected state,
      enable/disable, amount, invert, duplicate, delete, reorder, and reset actions.
- [ ] Selecting an existing layer restores its saved component controls and local-adjustment slider
      values; all durable changes route through `AppViewModel.updateDocument`.
- [ ] Local sliders and continuous controls use existing preview interaction/undo grouping so each
      gesture becomes one undo entry and the final value receives a settled preview.
- [ ] Overlay color/opacity, color-wash versus grayscale inspection, solo display, active tool,
      hover, and handle selection remain presentation-only.
- [ ] Loading, partial smart results, unavailable target, retry, and render failure are explicit and
      do not freeze or discard the layer definition.
- [ ] Source switching cancels drafts and stale async work, clears old overlays, and restores the
      selected layer belonging to the newly active photo.
- [ ] Crop and mask tools have mutually exclusive hit-test ownership; Space-pan, zoom, fit/fill,
      Escape/cancel, and existing comparison behavior remain usable.
- [ ] Core list/actions/sliders have VoiceOver labels, values, state, focus order, and keyboard access.

## Implementation notes

Follow Section 5 plus Step 3 of `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`. Likely integration
points are `ContentView.swift`, `PreviewView.swift`, `PreviewSurface.swift`, inspector state/routing,
keyboard/menu commands, `AppViewModel+Masking.swift`, and the new `MaskInteractionState`.

Retire `MaskingPanel.swift` or reduce it to genuinely shared semantic-result UI. Do not leave two
workflows with conflicting selection or apply semantics.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
