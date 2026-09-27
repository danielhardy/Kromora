---
id: KRMA-650
title: Implement content-aware heal (texture synthesis) distinct from Clone
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - professional-polish
created: 2026-09-27T07:14:01.020Z
updated: 2026-09-27T07:14:01.020Z
parent: KRMA-599
blockers: []
order: zzzz
board: product
---

## Objective

Give Heal a content-aware texture synthesis result, distinct from Clone's plain sampled patch,
matching the acceptance criteria in KRMA-599 (parent).

## Context

KRMA-599 added editable per-photo spot recipes (`RetouchSpot`, `RetouchRenderer`) with a `heal`
and a `clone` mode. Both modes currently render through the same code path in
`Sources/KromoraKit/Models/RetouchRenderer.swift`: a feathered sampled patch translated from
`sourceOffset` onto the destination, blended with `CIBlendWithMask`. `RetouchSpot.feather`
defaults differently per mode (0.35 heal / 0.5 clone) but the sampling/compositing math is
identical.

KRMA-599's acceptance criteria call for "content-aware heal and clone spots," and its own
implementation comment and `docs/RETOUCH.md` both explicitly disclose that Heal is not yet
content-aware: "Heal currently uses a feathered sampled patch like Clone; full content-aware
texture synthesis is not implemented."

## Acceptance criteria

- [ ] Heal produces a texture-synthesized or otherwise content-aware fill that differs
      perceptibly from Clone's plain translated-patch result for the same source/destination.
- [ ] The distinction stays inside the render boundary (`RetouchRenderer`), keeping
      `RetouchSpot`/`RetouchSettings` Codable and Core-Image-object-free.
- [ ] Regression coverage that Heal and Clone produce different pixels for the same spot
      geometry (they currently produce identical results other than the default feather).

## Implementation notes

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
