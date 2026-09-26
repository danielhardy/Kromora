---
id: KRMA-629
title: Add camera profile and DCP selection
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
created: 2026-09-26T14:07:08.908Z
updated: 2026-09-26T14:07:09.195Z
blockers: []
order: zzy
board: product
---

## Objective

Let photographers choose camera-matching profiles instead of relying only on decoder defaults.

## Context

Derived from §2.4 Color science depth in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Discover and display embedded or built-in camera profiles for the source when available.
- [ ] Support selecting compatible DCP profiles, including documented standard and camera-matching choices.
- [ ] Handle missing, unsupported, or mismatched profiles with a clear fallback and status.
- [ ] Persist profile selection and use the same color transform in preview and export.

## Implementation notes

Preserve non-destructive edits, shared preview/export behavior, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation.
