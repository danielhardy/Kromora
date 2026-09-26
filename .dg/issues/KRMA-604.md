---
id: KRMA-604
title: Add edit history, snapshots, and virtual copies
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
created: 2026-09-26T13:56:31.792Z
updated: 2026-09-26T13:56:43.046Z
blockers: []
order: maaaaa9o
board: product
---

## Objective

Make edit history visible and let photographers save alternate interpretations of one source.

## Context

The current edit workflow supports undo but not a visible history panel, snapshots, or virtual copies.

Derived from §5 Presets, history, versions in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Show an ordered, navigable history of edit commits and preview an earlier state.
- [ ] Support branching/forking from an earlier state and named snapshots within a photo.
- [ ] Support virtual copies with independent edits/history and a clear relationship to the original source.
- [ ] Keep copy/version identity, ratings, flags, and history understandable in the library and persistent across reopen.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
