---
id: KRMA-603
title: Add user edit presets and an edit preset browser
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
created: 2026-09-26T13:56:31.086Z
updated: 2026-09-26T13:56:43.011Z
blockers: []
order: lfffffeu
board: product
---

## Objective

Let photographers save reusable edit settings separately from Looks and apply them with control over what changes.

## Context

The current Looks system handles LUTs; the evaluation identified reusable edit presets as a separate missing workflow.

Derived from §5 Presets, history, versions in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Create presets from the current edit with category/subset selection, favorites, and folders.
- [ ] Browse presets with preview and before/after comparison, and control application amount where meaningful.
- [ ] Import/export documented XMP-compatible preset files and update a preset from the current edit.
- [ ] Support optional rule-based application by camera or ISO without overriding settings excluded by the preset.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
