---
id: KRMA-616
title: Add canvas navigation, focus aids, and composition guides
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:39.972Z
updated: 2026-09-26T13:56:43.487Z
blockers: []
order: wkkkkkjo
board: product
---

## Objective

Make precise inspection and crop/geometry work faster and more legible.

## Context

Canvas navigation, crop geometry, and analysis overlays already have separate owners; keep guides presentation-only and coordinate-correct.

Derived from §9 Viewing, comparison, and proofing ergonomics; §11 Crop UX polish in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Add Fit, 1:1, and 2:1 commands with pixel readout and a navigator thumbnail showing the viewport.
- [ ] Add focus peaking at 100% and expose available focus/AF or depth/face evidence as optional overlays.
- [ ] Provide crop/straighten guides for thirds, diagonal, golden spiral, center, and aspect-safe framing.
- [ ] Support a secondary display or fullscreen preview while retaining crop and overlay coordinate alignment.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
