---
id: LUMO-272
title: Stale component selection blinds the mask overlay
type: bug
status: review
priority: high
labels:
  - masking
created: 2026-09-07T01:57:58.869Z
updated: 2026-09-07T02:02:54.990Z
order: y
board: product
branch: fix/linear-overlay-stale-selection
---

## Objective

A stale selected-component id must not blind the mask overlay. When the selected layer has
no component matching the selection, fall back to all usable components (mirroring the
tooling) instead of resolving nothing — while keeping solo isolation strict.

## Context

Incident (2026-09-06): a Linear Gradient layer with Show overlay on at 100% rendered its
handles but no color wash, with no banner. Reproduced in a probe: `makeMaskOverlayImage`
with a draft layer (fresh ids, as produced live during creation) plus a stale
`selectedComponentID` returns nil.

Root cause: `resolvedLocalMasks` filters components by
`onlyComponentID = soloComponentID ?? selectedComponentID` with no fallback, while the
tooling draws via `targetComponentIndex` (selected if present, else first enabled) and the
unavailable-banner logic falls back to the first component the same way. So a selection
that goes stale — undo, component delete, or fresh draft ids during a creation drag while
the selection still names a previous component — shows handles with no wash and no banner,
which reads as "the wash is broken" rather than "the selection is stale". Linear isn't
semantic, so the failure is silent by design.

## Work

- In `makeMaskOverlayImage` (`RenderEngine.swift`): when `soloComponentID` is nil and the
  selected layer contains no component matching `selectedComponentID`, resolve with
  `onlyComponentID: nil` (all usable components). Solo stays strict — explicit isolation
  must keep failing closed on an unknown id.
- Deliberately engine-level rather than workspace-level: the render/export path never
  passes `onlyComponentID` (verified), so it is unaffected, and every overlay consumer
  heals at once.

## Acceptance criteria

- [ ] Regression test: draft layer + stale `selectedComponentID` renders a wash whose
      gradient actually varies (`testStaleSelectedComponentFallsBackToUsableComponents`).
- [ ] Solo strictness pinned: stale `soloComponentID` still resolves nothing
      (`testStaleSoloComponentStaysStrict`).
- [ ] Negative control verified (fallback test fails pre-fix, solo test passes both ways).
- [ ] `swift build`, `swift test` pass with zero Swift 6 diagnostics and zero opt-outs.


### Comment — pi @ 2026-09-07T02:02:54.140Z

Implemented on fix/linear-overlay-stale-selection. Engine-level fallback in makeMaskOverlayImage; render path unaffected (never passes onlyComponentID). 2 new regression tests; negative control verified (fallback test fails pre-fix, solo test passes both ways). Full suite: 922 tests, 0 failures. Ready for review.
