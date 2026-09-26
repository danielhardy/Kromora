---
id: KRMA-626
title: Surface camera/lens support and decide video-file behavior
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
created: 2026-09-26T13:56:48.500Z
updated: 2026-09-26T13:56:48.792Z
blockers: []
order: zzq
board: product
---

## Objective

Make camera compatibility and video import behavior explicit instead of silently implying support.

## Context

Profile selection is decoder-bound and video support is currently ambiguous; this issue includes the product decision needed before implementation.

Derived from §13 Interop and ecosystem in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Expose whether a camera/lens uses embedded or built-in profile data and identify the mapping version.
- [ ] Show an understandable basic-support state for unrecognized camera bodies or lenses.
- [ ] Make and document an explicit product decision to support selected video still workflows or exclude video files.
- [ ] Ensure unsupported media is clearly handled during import and never silently appears as an editable photo.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
