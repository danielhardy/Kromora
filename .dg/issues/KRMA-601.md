---
id: KRMA-601
title: Expand semantic and edge-aware mask selection
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
created: 2026-09-26T13:56:29.727Z
updated: 2026-09-26T13:56:42.940Z
blockers: []
order: jpppppp6
board: product
---

## Objective

Make semantic and brush-based mask selection easier to create and refine.

## Context

Existing Vision mask components require assembly in the masking workflow. Sky selection is tracked separately in KRMA-580/583/584.

Derived from §4.1 Missing selectors; §4.3 Mask visualization and editing ergonomics in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Offer one-click Select Subject and People sub-targets such as skin, eyes, hair, teeth, and clothing where Vision supports them.
- [ ] Add a lasso/rectangle object-selection brush backed by segmentation and edge-aware Auto Mask options.
- [ ] Separate and explain brush feather and flow controls, with practical quick-adjust gestures.
- [ ] Preserve graceful fallback messaging when the image or system cannot provide a requested semantic target.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
