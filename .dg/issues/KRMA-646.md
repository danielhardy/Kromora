---
id: KRMA-646
title: Add ViewModel-level tests for per-channel tone curve editing
type: task
status: backlog
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-27T05:10:45.074Z
updated: 2026-09-29T01:16:02.220Z
parent: KRMA-595
blockers: []
order: "8"
board: product
---

## Objective

Add ViewModel-level tests for per-channel tone curve editing

## Context

Verification finding from KRMA-595: `AppViewModel+Light.swift` threads a `channel: ToneCurveChannel`
parameter through `setToneCurvePoint`, `addToneCurvePoint`, `removeToneCurvePoint`,
`moveToneCurvePoint`, and `resetToneCurve`, but `LightInspectorTests.swift` only exercises these
through their default (`.master`) parameter. `LightAdjustmentsTests` and `RenderPipelineTests` cover
the model and render layers for red/green/blue and parametric curves, so this is not a correctness
blocker — routing was verified by inline reading — but the ViewModel-facing API that the channel
picker in `LightInspectorView` actually calls has no direct regression coverage for non-master
channels or for `resetToneCurve(_:)` resetting only the selected channel.

## Acceptance criteria

- [ ] Add `LightInspectorTests` coverage exercising `addToneCurvePoint`/`setToneCurvePoint`/
      `removeToneCurvePoint`/`moveToneCurvePoint` with a non-master `channel`, confirming edits land
      on that channel's curve and leave the others untouched.
- [ ] Add coverage for `resetToneCurve(_:)` resetting only the given channel's curve to identity.

## Implementation notes

See `Sources/KromoraKit/ViewModels/AppViewModel+Light.swift` and
`Tests/KromoraKitTests/LightInspectorTests.swift`.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
