---
id: KRMA-611
title: Add tethered camera capture
type: feature
status: backlog
priority: low
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:36.548Z
updated: 2026-09-26T14:15:06.423Z
blockers: []
order: saaaaa9i
board: product
---

## Objective

Support studio capture into the open package with immediate preview and configurable edit defaults.

## Context

The evaluation lists tethered capture as a studio workflow gap. Camera API support and the initial supported-device scope need an explicit product decision.

Derived from §7 Import — from file opener to ingest station in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Define and implement a supported native camera capture path for selected camera models.
- [ ] Ingest new captures into the active package with per-frame status and recoverable failures.
- [ ] Show live/near-live preview and optionally apply an import preset.
- [ ] Document unsupported cameras and keep normal editing and import responsive during capture.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
