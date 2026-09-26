---
id: KRMA-627
title: Add automatic and manual lens-profile corrections
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
created: 2026-09-26T14:07:07.556Z
updated: 2026-09-26T14:07:07.844Z
blockers: []
order: zzv
board: product
---

## Objective

Correct lens distortion, optical vignetting, chromatic aberration, and defringe using automatic profiles and manual controls.

## Context

Derived from §2.3 Optics and geometry in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Look up a lens profile using available body/lens metadata and show when no profile is available.
- [ ] Provide separate lens vignetting and creative vignette controls, plus manual distortion adjustment.
- [ ] Correct lateral chromatic aberration and provide purple/green defringe sampling and hue controls.
- [ ] Keep corrections non-destructive and consistent in preview and full-resolution export.

## Implementation notes

Preserve non-destructive edits, shared preview/export behavior, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation.
