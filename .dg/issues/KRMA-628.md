---
id: KRMA-628
title: Add Upright geometry and straighten-by-drag
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
created: 2026-09-26T14:07:08.237Z
updated: 2026-09-26T14:07:08.523Z
blockers: []
order: zzx
board: product
---

## Objective

Provide guided and automatic perspective correction with practical crop and straighten controls.

## Context

Derived from §2.3 Optics and geometry; §11 Crop UX polish in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Offer Auto, Level, Vertical, and Full upright modes plus a guided two-line perspective tool.
- [ ] Allow a user-drawn horizon line to set straighten angle.
- [ ] Expose warp-to-fill versus constrain-crop behavior and follow-up scale, offset, aspect, and fine-rotation controls.
- [ ] Show composition and aspect guides while adjusting geometry and preserve the original non-destructive crop.

## Implementation notes

Preserve non-destructive edits, shared preview/export behavior, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation.
