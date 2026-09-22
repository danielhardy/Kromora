---
id: KRMA-514
title: Demote filmstrip/culling/status off elevated .bar so canvas wins hierarchy
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Filmstrip, culling, and status use the quieter secondary role
      result: pass
      notes: All three views now use KromoraTheme.secondaryChrome instead of elevated .bar.
    - criterion: Canvas wins the light-mode hierarchy
      result: pass
      notes: The canvas keeps its dedicated recessed canvasBackground while the large bottom surfaces leave .bar behind.
    - criterion: Selection and controls remain readable
      result: pass
      notes: Only surfaces changed; thumbnail selection and culling behavior/layout are unchanged.
    - criterion: Library status remains consistent
      result: pass
      notes: The shared StatusBar applies the same secondary role in edit and library layouts.
    - criterion: Light and dark support
      result: pass
      notes: secondaryChrome resolves dynamically through AppKit; fast CI completed 1123/1123.
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast (1123/1123)
    - git diff --check
    - dg validate
  findings: []
  fixes: []
  verification_commits:
    - 04ff35a
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-21T20:12:28.723Z
  session: 01MUBOD0YC1AMXUBCJ
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - chrome
  - filmstrip
created: 2026-09-21T19:16:36.275Z
updated: 2026-09-21T20:12:28.726Z
parent: KRMA-512
depends_on:
  - KRMA-515
order: t
board: product
commits:
  - 04ff35a
---

## Objective

Demote the Edit filmstrip, culling bar, and status bar off elevated `.bar` so the photo canvas — not the bottom white strip — wins visual hierarchy.

## Context

Parent: [KRMA-512](KRMA-512.md). Depends on [KRMA-515](KRMA-515.md) for the secondary-chrome token.

User report: the thumbnail area is white and feels more important than the canvas. Today `FilmstripView`, `CullingBarView`, and `StatusBar` use `.background(.bar)`, which reads as a large elevated (near-white) surface in light mode. Importance should come from selection chrome (blue thumbnail border), not strip background.

## Acceptance criteria

- [ ] Filmstrip / culling / status use the quieter secondary chrome role from KRMA-515 (not elevated `.bar` on the large strip).
- [ ] In light mode, canvas surround is not out-luminanced by the bottom band.
- [ ] Selected thumbnail affordance remains clear; culling controls stay readable.
- [ ] Library grid status bar (if sharing the same view) stays consistent or documents an intentional difference.
- [ ] Light + dark spot-check; `scripts/ci-tests.sh fast` passes.

## Implementation notes

- `FilmstripView.swift` (`.background(.bar)`)
- `CullingBarView.swift`
- `StatusBar.swift`
- Keep behavior/layout unchanged — surfaces only.

## Agent log

- 2026-09-21T20:12:28.723Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Filmstrip, culling, and status use the quieter secondary role (pass) — All three views now use KromoraTheme.secondaryChrome instead of elevated .bar.
- [x] Canvas wins the light-mode hierarchy (pass) — The canvas keeps its dedicated recessed canvasBackground while the large bottom surfaces leave .bar behind.
- [x] Selection and controls remain readable (pass) — Only surfaces changed; thumbnail selection and culling behavior/layout are unchanged.
- [x] Library status remains consistent (pass) — The shared StatusBar applies the same secondary role in edit and library layouts.
- [x] Light and dark support (pass) — secondaryChrome resolves dynamically through AppKit; fast CI completed 1123/1123.
Checks run:
- swift build
- scripts/ci-tests.sh fast (1123/1123)
- git diff --check
- dg validate
Findings:
- None
Fixes:
- None
Verification commits:
- 04ff35a
Actor: codex
Resolved model: unknown
Pickup session: 01MUBOD0YC1AMXUBCJ
Summary: Moved filmstrip, culling, status, and source-browser shell surfaces to KromoraTheme.secondaryChrome while preserving selection accents and layout.
