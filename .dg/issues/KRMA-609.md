---
id: KRMA-609
title: Make photo metadata editable and map standard XMP fields
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
created: 2026-09-26T13:56:35.192Z
updated: 2026-09-26T13:56:43.241Z
blockers: []
order: qkkkkkju
board: product
---

## Objective

Allow metadata edits in the Info inspector and exchange common fields with other photo applications.

## Context

Metadata is currently read-only and XMP stores an opaque Kromora payload; preserve package durability and privacy policy.

Derived from §6.3 Metadata editing; §13 Interop and ecosystem in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Edit title, caption, copyright, creator, and supported location fields, including batch edits with undo.
- [ ] Persist edits through package records and sidecars and apply the documented export-location policy.
- [ ] Map exposure, white balance, crop, rating, labels, keywords, and IPTC fields to standard XMP while retaining the full-fidelity Kromora extension.
- [ ] Add round-trip tests for fields Kromora can represent and define behavior for unsupported external values.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
