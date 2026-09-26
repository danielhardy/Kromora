---
id: KRMA-623
title: Add a package health dashboard and support diagnostics bundle
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
created: 2026-09-26T13:56:46.418Z
updated: 2026-09-26T13:56:46.718Z
blockers: []
order: zy
board: product
---

## Objective

Turn package integrity and support diagnostics into understandable, repairable user workflows.

## Context

Package validation and recovery primitives exist; surface them without reducing corruption to a log entry or changing data silently.

Derived from §12 Stability, data safety, and trust in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Show package health on open and on demand, with background verification status and clear severity.
- [ ] List corrupt revisions, missing originals, and orphan sidecars with per-record repair/relink actions where possible.
- [ ] Export a sanitized diagnostics bundle with package validation, hardware/GPU, render version, and recent telemetry.
- [ ] Redact GPS and personal filenames by default and let the user review bundle contents.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
