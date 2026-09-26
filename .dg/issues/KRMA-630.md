---
id: KRMA-630
title: Polish brush and crop interaction controls
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
created: 2026-09-26T14:07:09.613Z
updated: 2026-09-26T14:07:09.896Z
blockers: []
order: zzz
board: product
---

## Objective

Make brush and crop interactions precise, discoverable, and comfortable with trackpads and supported input devices.

## Context

Derived from §11 Ease of use; §15 punchlist item 13 in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Show a live brush size/feather cursor ring and add smoothing/stabilization and flow controls where applicable.
- [ ] Support pressure-aware brush behavior and Apple Pencil shortcuts when the platform and device expose them.
- [ ] Add crop quick keys for preset selection and aspect inversion, clear commit/cancel behavior, and pixel feedback while resizing.
- [ ] Keep existing keyboard, VoiceOver, and crop/mask coordinate behavior intact.

## Implementation notes

Preserve non-destructive edits, shared preview/export behavior, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation.
