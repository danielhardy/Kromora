---
id: KRMA-588
title: Make tone-curve endpoints draggable and remove Add Point control
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
created: 2026-09-26T00:50:47.108Z
updated: 2026-09-26T00:51:02.554Z
blockers: []
order: zv
board: product
---

## Objective

Let photographers reshape the tone curve by dragging both endpoint handles horizontally and vertically, and remove the redundant Add Point control because clicking the graph already adds a point.

## Context

The master RGB tone curve editor is `ToneCurveEditor` in `Sources/KromoraKit/Views/LightInspectorView.swift`. The graph currently supports click-to-add and dragging interior points. The editor comment says endpoint handles are fixed; `LightToneCurve.normalized` in `Sources/KromoraKit/Models/LightAdjustments.swift` always inserts endpoints at inputs 0 and 1, while `AppViewModel+Light.swift` only edits interior points. The Add Point button in the editor adds a midpoint even though the graph gesture already creates points directly on the curve.

Allowing both endpoint handles to move in either graph dimension may require changing the tone-curve model and edit operations while preserving normalized bounds, point ordering, rendering, and persisted-document behavior. Keep click-to-add and the existing reset action.

## Acceptance criteria

- [ ] Both tone-curve endpoint handles can be dragged horizontally and vertically within the graph, with their displayed positions and rendered curve updating to match.
- [ ] Endpoint movement preserves valid normalized coordinates, stable point ordering, and safe curve evaluation/rendering, including curves whose endpoints move inward from input 0 or 1.
- [ ] Endpoint edits persist and restore through the existing edit-document serialization path; existing tone-curve documents continue to decode with their current behavior.
- [ ] Interior-point dragging, click-to-add, point removal, accessibility editing, and Reset continue to work.
- [ ] Remove the Add Point button from the tone-curve UI; clicking the curve remains the way to add points.
- [ ] Add or update focused regression coverage for endpoint movement, normalization/persistence, and the editor interaction as appropriate.
- [ ] `swift build`, focused tone-curve tests, and `git diff --check` pass.

## Implementation notes

- Review `Sources/KromoraKit/Views/LightInspectorView.swift`, `Sources/KromoraKit/Models/LightAdjustments.swift`, and `Sources/KromoraKit/ViewModels/AppViewModel+Light.swift`.
- Review tone-curve coverage in `Tests/KromoraKitTests/` and add focused tests alongside the existing curve/model tests.
- Keep endpoints ordered and distinct from adjacent points when dragged horizontally. Preserve existing curve constraints and deterministic handling of older serialized curves.
