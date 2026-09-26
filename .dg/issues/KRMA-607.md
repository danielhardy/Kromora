---
id: KRMA-607
title: Add hierarchical keywords and face-based organization
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
created: 2026-09-26T13:56:33.824Z
updated: 2026-09-26T13:56:43.168Z
blockers: []
order: ouuuuuu6
board: product
---

## Objective

Make photos searchable by reusable keywords and confirmed people identities.

## Context

The evaluation notes that Vision face/person concepts exist for masks but are not promoted into catalog organization.

Derived from §6.1 Organization in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Create hierarchical keywords with synonyms, multi-select apply/remove, and Vision-based suggestions.
- [ ] Detect faces on device and support name, confirm, and cluster workflows with explicit user control.
- [ ] Filter the library by keywords and people.
- [ ] Persist metadata and export keywords through standard XMP subject fields.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
