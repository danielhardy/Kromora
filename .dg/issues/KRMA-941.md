---
id: KRMA-941
title: "Plan: move the preview pipeline from sRGB to Display P3 (matching export)"
type: task
status: backlog
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - color
  - needs-decomposition
created: 2026-10-13T14:47:51.052Z
updated: 2026-10-13T14:48:33.076Z
parent: KRMA-922
depends_on:
  - KRMA-923
blockers: []
order: pkubd9gi
board: product
---

## Objective

Produce a plan and child tickets for rendering the canvas in Display P3 (and optionally extended
linear/EDR) so what the user sees matches a Display P3 export.

> **Sizing note:** this ticket is a planning/investigation step. It is deliberately NOT an implementation ticket; its deliverable is a written plan plus child tickets small enough for a lower-capability agent. Label `needs-decomposition`.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S2.

- `Sources/KromoraKit/Models/WorkingSpace.swift`: `WorkingSpace.current = .sRGB`. LUT interpolation and
  output encoding both follow it, so the canvas is clipped to sRGB on P3 displays while Export offers
  Display P3.
- The doc comment on `WorkingSpace` records the prerequisite: `RecipeExtractor` is pinned to `.sRGB`
  and must be re-fit in P3 or stamp the build space onto `CubeLUT` before flipping `current`.
- Canvas tagging is ticket KRMA-923 (color-manage the editing canvas); this plan builds on it.
- Cache identities (`RenderCacheKey`, frame store, thumbnail caches) may need the working space in
  their keys so stale sRGB frames are not served as P3.

## Acceptance criteria

- [ ] `docs/P3_PREVIEW_PLAN.md` (new) answers: (1) what must change to flip `WorkingSpace.current` to
      `.displayP3` (list every consumer: `grep -rn "WorkingSpace" Sources`); (2) cache-key and
      persisted-frame invalidation needed; (3) derive/`RecipeExtractor`/LUT implications; (4) whether
      to go further to extended-linear `rgba16Float` + EDR and why/why not; (5) test strategy using
      generated fixtures with out-of-sRGB-gamut colors; (6) risks.
- [ ] 4-8 child tickets created (`dg issue create`, label `release-readiness,should-fix,color`),
      each small, with acceptance criteria, chained by `depends_on` and depending on ticket KRMA-923.
- [ ] No production code changes.

## Implementation notes

Do not flip `WorkingSpace.current` in this ticket.
