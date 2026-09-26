---
id: KRMA-624
title: Make package schema upgrades rollback-safe
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
created: 2026-09-26T13:56:47.120Z
updated: 2026-09-26T13:56:47.413Z
blockers: []
order: zz
board: product
---

## Objective

Make library-format upgrades recoverable and explain refusal when a package comes from a newer app.

## Context

The evaluation found no rollback story for package schema changes. Coordinate this with package backup work without making migration depend on opaque external state.

Derived from §12 Stability, data safety, and trust in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Take and verify a rollback snapshot before a schema migration changes durable package data.
- [ ] Recover cleanly from interrupted migration and keep the pre-migration package available.
- [ ] Show an actionable message for a newer package version, including safe sidecar/export guidance.
- [ ] Present release notes alongside the existing updater flow.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
