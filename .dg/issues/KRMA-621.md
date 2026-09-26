---
id: KRMA-621
title: Complete accessibility, localization, and privacy affordances
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
created: 2026-09-26T13:56:44.955Z
updated: 2026-09-26T13:56:45.254Z
blockers: []
order: zs
board: product
---

## Objective

Make core library and editing workflows usable across assistive technologies, languages, and privacy expectations.

## Context

Keep macOS-native accessibility conventions and the no-third-party-dependency product constraint.

Derived from §11 Ease of use; §12 Stability, data safety, and trust in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Audit VoiceOver labels, focus order, and value announcements across grid, canvas, and controls.
- [ ] Support Dynamic Type, high-contrast mask overlays, and reduced-motion behavior.
- [ ] Localize user-visible strings and validate right-to-left layout in primary workflows.
- [ ] Explain on-device analysis and network behavior, and make face-recognition opt-in with clear disclosure.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
