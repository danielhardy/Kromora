---
id: KRMA-608
title: Expose library search, filters, sorting, and duplicate groups
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
created: 2026-09-26T13:56:34.498Z
updated: 2026-09-26T13:56:43.206Z
blockers: []
order: ppppppp0
board: product
---

## Objective

Let photographers find images using existing query capabilities and richer catalog facets.

## Context

`LibraryQuery` already includes search text and rich sort keys; the evaluation found the library surface exposes only a subset.

Derived from §6.2 Finding in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Expose search for filename, camera, lens, keyword, and caption, plus a visible sort menu.
- [ ] Add filter facets for edit/look/mask/spot/crop/Auto state, source availability, file type, orientation, and capture settings/date.
- [ ] Provide camera/lens/date metadata drill-down pills and saved-filter presets.
- [ ] Detect exact and likely near duplicates at import or library time and present reviewable groups without deleting originals.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
