---
id: KRMA-619
title: Improve first-run onboarding and contextual learning
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
created: 2026-09-26T13:56:42.006Z
updated: 2026-09-26T13:56:43.834Z
blockers: []
order: z5555546
board: product
---

## Objective

Help new users move from a blank install to a confident first edit and discover existing controls.

## Context

The app already has rich editing and keyboard actions, but the evaluation found onboarding and discoverability gaps.

Derived from §11 Ease of use in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Provide a welcome flow, licensed sample library, first-import action, and short Library/Edit/Export tour.
- [ ] Give empty surfaces a clear next action, including no library, no selection, no results, no Looks, and completed export.
- [ ] Add guided-edit cards that apply annotated, undoable steps through the existing edit/preview path.
- [ ] Explain controls in place and expose a searchable in-app shortcut reference.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
