---
id: KRMA-614
title: Add print, contact-sheet, slideshow, and web-gallery output
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
created: 2026-09-26T13:56:38.612Z
updated: 2026-09-26T13:56:43.416Z
blockers: []
order: uuuuuuu0
board: product
---

## Objective

Support client and print delivery directly from selected library photos.

## Context

Print and gallery workflows are absent from current export, which is focused on individual image files.

Derived from §8 Export, output, and sharing in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Create print layouts with page/margins/cell controls, contact sheets, print sharpening, and ICC/paper profile selection.
- [ ] Provide a fullscreen slideshow with configurable presentation styling.
- [ ] Export a static client gallery with chosen images and a useful visual theme.
- [ ] Make output options reproducible through saved settings and report partial failures clearly.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
