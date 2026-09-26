---
id: KRMA-606
title: Add collections, virtual folders, stacks, and color labels
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
created: 2026-09-26T13:56:33.149Z
updated: 2026-09-26T13:56:43.123Z
blockers: []
order: nzzzzzzc
board: product
---

## Objective

Organize a package library into photographer-defined groups and views without restoring fragile folder bookmarks.

## Context

The current library is package-centered with culling basics; this ticket is for organization inside that model, not referenced-folder browsing.

Derived from §6.1 Organization in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Support manual and rule-based Smart Collections, nesting, and visible collection badges.
- [ ] Provide virtual folders based on date, camera, or Look, plus burst/HDR/panorama/version stacks with a selectable cover.
- [ ] Add configurable color labels and label filtering.
- [ ] Persist organization in the portable library and include supported labels in metadata/XMP exchange.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
