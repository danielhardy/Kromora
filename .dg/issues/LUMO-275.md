---
id: LUMO-275
title: Preview displayRevisions permanently cancel every mask overlay resolve
type: bug
status: done
priority: urgent
labels:
  - masking
  - render
created: 2026-09-07T03:53:52.800Z
updated: 2026-09-07T04:02:52.145Z
order: r7rxp1w9
board: product
branch: fix/overlay-revision-exempt
---

## Objective

Exempt the mask overlay from mask-request revision supersession. Previews note
`displayRevision` (bumped on every scheduled render, unbounded) into the same per-source
max-slot the overlay's `sourceRevision` (bumped once per photo open) uses — after the first
couple of preview renders, every overlay resolve was cancelled forever, for every mask type.

## Context

Incident: no overlay wash ever rendered in the masking workspace for any mask kind
(Person banner, silent linear/brush/radial absence), while the Info panel (direct
coordinator calls, no revision guards) and every probe (fresh engine, no concurrent
renders) worked. Reproduced: overlay resolves fine, then a main-preview render noting a
higher revision lands, and the same overlay request returns nil permanently.

Mechanism (`RenderEngine.swift`, `AppViewModel.swift`): `buildImage` calls
`noteMaskRequest(source:, revision: request.requestRevision)` with the preview's
`displayRevision` (~9 bump sites); the overlay passed `maskingSourceRevision`. The slot
keeps the max and `isCurrentMaskRequest` requires equality, so once `displayRevision`
outruns `sourceRevision` — within seconds of opening any photo, permanently, since one
counter resets per photo and the other never does — the overlay's per-component guard
throws `.cancelled` on every resolve. `retryPreview` (the Retry button) scheduled another
preview and re-poisoned the slot, so Retry was counterproductive. Symmetrically, an early
overlay note could cancel main renders until `displayRevision` caught up.

## Work

- Production overlay requests pass `requestRevision: 0` (skips noting, always reads
  current) in `AppViewModel.renderMaskOverlay`. Staleness stays owned by the workspace
  `.task(id:)` teardown, which restarts on any layer/selection/size/style change — the
  revision guard was redundant there (SwiftUI cancellation already discards superseded
  results) and invisible when it misfired.
- Deliberately NOT changed: the render domain keeps its guards (single-counter, correct
  semantics — a lagging nonzero request is still superseded, pinned by test), and the
  overlay task's own `requestRevision` (task identity) still uses `maskingSourceRevision`.

## Acceptance criteria

- [ ] Regression test: render noting revision 5, then production overlay resolves
      (`testProductionOverlayPathSurvivesPreviewRenders`); engine seam pinned both ways
      (`testOverlayResolveIsExemptFromRenderRevisionSupersession`).
- [ ] Negative control verified (production test fails pre-fix with nil wash).
- [ ] `swift build`, `swift test` pass with zero Swift 6 diagnostics and zero opt-outs.


### Comment — pi @ 2026-09-07T03:59:14.547Z

Merged to main (3416ca8). One-line production change (overlay requestRevision 0) + 2 regression tests. Full suite on branch: 929 tests, 0 failures. Verified on main.
