---
id: KRMA-770
title: "Guard against visible re-render regressions: a presentation-change budget across open, switch, relaunch, edit and Look rescan"
type: task
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - testing
created: 2026-10-02T13:44:25.380Z
updated: 2026-10-02T13:47:10.749Z
depends_on:
  - KRMA-762
blockers: []
order: zzzzv
board: product
---

## Objective

Turn "the app should feel fast and smooth: visible re-rendering only when something actually changed" into an automated budget that fails the build when a change makes a surface repaint, swap, or resize without a reason. This is the guard that keeps the relaunch fix from silently regressing.

## Background

The product rule (`.context/last-known-frame-plan.md`, user-visible invariants): a surface never shows another asset's pixels; a warm Edit open shows one cached frame followed by at most one refinement; a warm grid or filmstrip cell never regresses to the original and never changes geometry after first layout; cached pixels skip a render only when every current input matches. These are individually tested today but there is no single, scenario-level assertion of "how many visible changes did this surface go through", so a regression like the placeholder-identity miss slipped through all green suites.

## Work

1. Add a `PresentationChangeLedger` test seam (same style as the KRMA-761 lookup ledger; they may share infrastructure) that records, per surface (`editCanvas`, `gridCell(assetID)`, `filmstripCell(assetID)`), each **visible change**: a raster assignment (with source: stored, thumbnail, embedded, settled, refinement), a geometry change, and a crossfade. Hook it at the single place each surface assigns pixels (`PreviewSurface` presentation, `ImageCollection.Item` thumbnail setters) so a future code path cannot bypass it. Zero cost when no recorder is installed.
2. Add `PresentationBudgetTests` with one scenario per row, using the KRMA-762 two-session harness and the counting fake engine. Budgets are asserted as named constants with a one-line justification each:

| Scenario | Budget |
| --- | --- |
| Edit open, exact stored frame (same session and after relaunch) | 1 raster assignment, 0 render requests, 0 geometry changes |
| Edit open, stale stored frame (edit or pixelEpoch changed) | 2 raster assignments (stored, refinement), 1 render request, at most 1 crossfade |
| Edit open, cold (no frame) | at most 3 assignments (thumbnail or embedded, settled) and a canonical write |
| Photo A -> B -> A switch | 0 assignments of A's pixels to B's surface; each surface at most the rows above |
| Grid cell, exact stored edited frame (after relaunch) | 1 raster assignment, 0 geometry changes, 0 renders |
| Grid cell, edit changed | stored frame then one refinement; 0 geometry changes unless the crop changed |
| Look scan with identical Looks | 0 render admissions, 0 raster assignments, 0 invalidations of the collection projection |
| Look scan with one referenced Look changed | only photos referencing it re-render, once each |
| Slider drag then settle | interactive frames never written to the stores; one canonical write after settle |

3. Make each budget failure message print the surface, the ordered list of changes and their sources, so a failing run is diagnosable without a debugger.
4. Add the scenarios to `scripts/ci-tests.sh serial` (or `fast` where no Core Image is needed) so CI runs them; record the runtime in `docs/TESTING.md`.
5. Add a short "Presentation budget" section to `docs/ENGINEERING_GUIDE.md`: the table above, how to add a surface to the ledger, and the rule that any PR that changes it must say why.

## Acceptance criteria

- [ ] Every row in the table is implemented as a test that passes on the final tree. Rows that depend on KRMA-763-KRMA-766 may be wrapped in `XCTExpectFailure` with a comment naming the ticket **only if** those tickets have not landed when this one does; the wrappers are then removed by those tickets.
- [ ] Mutation check recorded in a ticket comment: temporarily re-introduce a placeholder-identity mismatch (or make the exact path render again) and show the relevant budget test fails with a readable message. Revert the mutation.
- [ ] Hooking is at the surface assignment point: adding a new code path that assigns canvas or cell pixels without going through the ledger is not possible without touching the hook (a short structural test, in the style of `PackageSettingsTests`, asserts the setters are only called from the hooked wrappers).
- [ ] The ledger adds no allocation or lock to the render/publish hot path when no recorder is installed (assert with a trivially inlined `guard` and show the Release benchmark `StoredEditAdoptionBenchmark` is unchanged within noise; do not run display captures).
- [ ] `fast` and `serial` lanes pass.

## Rules for an unattended run (read first)

- **Do not run the display-bound captures** (`scripts/run-kromora-capture.sh`, the last-known-frame benchmark). Everything here is verified by deterministic tests (`scripts/ci-tests.sh fast|serial`) that need no window and no unlocked display (see CLAUDE.md, "Display-bound benchmarks").
- **Do not open child tickets.** If a criterion cannot be met, record exactly what you measured and tried in a comment on this ticket, commit what is safe, and hand off to review.
- Keep the change to what this ticket lists. Swift 6 mode with zero escape hatches (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`). macOS 26 / Apple Silicon only; no `#available` branches and no third-party dependencies.
- Cache files are disposable presentation caches, never package truth. A cache failure must degrade to a miss, never to an error, a wrong-photo frame, or a blocked open.
- Commit with a subject that starts `KRMA-<this id>:`. Do not push. Do not stash, reset, or revert anyone else's uncommitted changes in the tree.
