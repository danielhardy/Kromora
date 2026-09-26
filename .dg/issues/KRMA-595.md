---
id: KRMA-595
title: Add per-channel and parametric tone curves
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
created: 2026-09-26T13:56:25.618Z
updated: 2026-09-26T13:56:42.721Z
blockers: []
order: ekkkkkk6
board: product
---

## Objective

Expand the master-only tone curve with RGB channel curves and parametric tonal-region controls.

## Context

The current `LightToneCurve` is a master curve. KRMA-588 separately tracks moving the existing curve endpoints; keep that interaction intact.

Derived from §2.1 White balance and tone fundamentals; §14 parity snapshot in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Edit master and red, green, and blue curves independently, with clear channel selection and identity reset.
- [ ] Provide Highlights, Lights, Darks, and Shadows controls with adjustable region splits.
- [ ] Support curve import/export in a documented format and preserve preview/export parity and existing curve documents.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
