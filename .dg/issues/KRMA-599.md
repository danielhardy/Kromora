---
id: KRMA-599
title: Add non-destructive spot healing, cloning, and red-eye repair
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
created: 2026-09-26T13:56:28.362Z
updated: 2026-09-26T13:56:42.869Z
blockers: []
order: hzzzzzzi
board: product
---

## Objective

Add localized retouch tools for removing spots and repairing red-eye while keeping every correction editable.

## Context

The evaluation found no spot removal, healing, clone, red-eye, or dust-visualization tool. This is a new editing subsystem, not a change to existing local-mask behavior.

Derived from §3 Retouch — the single biggest functional hole in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Support content-aware heal and clone spots with editable source/offset, size, feather, opacity, and per-spot visibility.
- [ ] Support red-eye and pet-eye correction with adjustable pupil detection, size, and darkening.
- [ ] Add a high-contrast dust-finding view and navigation between spots at 1:1.
- [ ] Store spots per photo, allow copying them across related frames, and render them after geometry and before grain.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
