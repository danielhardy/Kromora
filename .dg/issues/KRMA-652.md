---
id: KRMA-652
title: Remove tone curve file import/export while preserving copy/paste reuse
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - product
  - ui
  - cleanup
created: 2026-09-27T15:48:02.375Z
updated: 2026-09-27T15:48:27.571Z
order: zzzzq
board: product
---

## Objective

Remove tone-curve preset file import/export end to end. Users can already reuse curve adjustments through the edit copy/paste workflow, so keep that workflow intact and make sure copied Light adjustments continue to carry all tone curves.

## Context

Tone curve Import… and Export… controls expose a separate JSON file workflow that is redundant with copying and pasting edits. The existing preset format contains only the master and RGB curves, making it narrower than the broader edit transfer workflow. This is a product simplification; tone-curve editing itself remains part of the Light inspector.

Relevant implementation and documentation:

- `Sources/KromoraKit/Views/LightInspectorView.swift` — tone-curve editor UI and Import/Export buttons.
- `Sources/KromoraKit/ViewModels/AppViewModel+Light.swift` — file panel import/export actions.
- `Sources/KromoraKit/Models/LightAdjustments.swift` — `ToneCurvePreset` file format model, alongside durable edit-document tone-curve models.
- `Sources/KromoraKit/Models/EditClipboard.swift` and `Sources/KromoraKit/ViewModels/AppViewModel.swift` — value-only edit transfer, including selective category copy/paste.
- `docs/ENGINEERING_GUIDE.md` — tone-curve persistence and preset format documentation.

## Acceptance criteria

- [ ] Remove Import… and Export… from the tone-curve editor while retaining the channel selector, curve editing, and per-channel Reset behavior.
- [ ] Remove the dedicated tone-curve preset file workflow end to end: file-panel actions, preset-only serialization/model code, and tests that exist only for preset file import/export. Remove the documented external preset format contract.
- [ ] Preserve tone-curve persistence in `EditDocument`/`LightAdjustments`; existing saved edit documents and curve Codable schemas must continue to decode and render as before.
- [ ] Preserve existing edit copy/paste, including selective copying of Light adjustments. Copying Light adjustments from one photo and pasting to another must transfer the master, red, green, blue, and parametric tone-curve values; add or update focused regression coverage if needed.
- [ ] Leave general edit clipboard commands and behavior unchanged, and do not replace them with a new tone-curve-only transfer mechanism.
- [ ] Update any affected documentation and verify with the relevant build and tests.

## Implementation notes

Inspect the current working tree before editing and preserve unrelated pre-existing changes. `ToneCurvePreset` appears to be the file-transfer boundary; distinguish it from `LightToneCurve`, `ParametricToneCurve`, and the Codable fields used by persisted edit documents. Search for all preset references before removal so no dead import/export paths or stale documentation remain. Keep macOS 14, Swift 6, and zero-dependency constraints.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
