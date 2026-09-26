---
id: KRMA-605
title: Add multi-photo sync and match-total-exposure tools
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
created: 2026-09-26T13:56:32.469Z
updated: 2026-09-26T13:56:43.081Z
blockers: []
order: n555554i
board: product
---

## Objective

Apply and synchronize edits across selected photos without repeating one-photo-at-a-time copy/paste.

## Context

Selective copy exists, but the evaluation found no multi-photo live sync or exposure matching.

Derived from §5 Presets, history, versions in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Provide a one-shot sync dialog using the same category-selection model as presets/selective copy.
- [ ] Support opt-in live Auto Sync while editing a selection, with clear source and target behavior.
- [ ] Match total exposure across selected photos using exposure and available ISO/capture metadata.
- [ ] Add reset-to-import, reset-crop-only, and reset-masks-only actions with undoable results.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
