---
id: KRMA-610
title: Build a preview-based import workstation
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
created: 2026-09-26T13:56:35.866Z
updated: 2026-09-26T13:56:43.276Z
blockers: []
order: rfffffeo
board: product
---

## Objective

Give photographers a reviewable ingest flow with organization, duplicate checks, and defaults before files enter a package.

## Context

Existing import sources remain the entry points. This ticket adds ingest planning and progress while keeping the portable package as library owner.

Derived from §7 Import — from file opener to ingest station in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Provide a preview grid with check-all/none, loupe, sorting, destination summary, and already-imported duplicate hints.
- [ ] Support date-based organization, rename templates with live preview, and optional second-copy backup.
- [ ] Allow apply-on-import edit/metadata presets, keywords, labels, and advance defaults; offer preview-build choices.
- [ ] Support background import with pause/resume, per-file status, quarantine for bad files, and a finish report; remove or page beyond the current Photos batch cap.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
