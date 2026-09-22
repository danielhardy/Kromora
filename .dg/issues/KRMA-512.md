---
id: KRMA-512
title: Unify Edit window surface hierarchy to Apple chrome conventions
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Open inspector leaves one continuous top chrome surface
      result: pass
      notes: ContentView keeps the visible native window-toolbar material across the inspector column; forced inspector window fills were removed.
    - criterion: Inspector starts below the toolbar
      result: pass
      notes: Info, Crop, Look, and Masking roots no longer paint an opaque top-to-bottom slab, leaving the system inspector surface to own the column below the toolbar.
    - criterion: Filmstrip, culling, and status do not out-luminate the canvas with elevated .bar
      result: pass
      notes: The large secondary surfaces use KromoraTheme.secondaryChrome and retain existing selection accents and controls.
    - criterion: Light, dark, and Liquid Glass hierarchy remains system-owned
      result: pass
      notes: Toolbar and inspector use system surfaces; secondaryChrome is an AppKit dynamic semantic color; canvasBackground remains the dedicated stage.
    - criterion: Child tickets KRMA-513, KRMA-514, and KRMA-515 complete
      result: pass
      notes: All three child issues were completed against commit 04ff35a.
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
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-21T20:12:37.941Z
  session: 01MUBOD0YC1AMXUBCJ
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - ux
  - chrome
created: 2026-09-21T19:16:35.437Z
updated: 2026-09-21T20:12:37.942Z
order: a0
board: product
commits:
  - 04ff35a
---

## Objective

Make the Edit window follow Apple chrome hierarchy: one full-width toolbar, inspector under it, and secondary surfaces quieter than the photo canvas.

## Context

User report (2026-09-21 screenshot): surface colors are inconsistent — toolbar reads as multiple greys, inspector white runs to the window top, and the bright white filmstrip feels more important than the canvas.

Today’s stack (light mode):

| Region | Token / treatment | Problem |
|---|---|---|
| Toolbar | System + `.toolbarBackground(.visible)` (KRMA-462) | Material still mismatches inspector |
| Inspector | Forced `KromoraTheme.windowBackground` | White slab to top of window |
| Canvas | `canvasBackground` ~0.90 (KRMA-441) | Correctly recessed, but loses to white chrome |
| Filmstrip / culling / status | `.background(.bar)` | Elevated white billboard |

Apple pattern (HIG + WWDC25): toolbar spans full window width; inspector is a trailing column **under** that band; chrome uses system materials; content is the hero.

Related prior work: KRMA-462 (toolbar seam), KRMA-441 (canvas vs `.bar`).

## Children

- [KRMA-515](KRMA-515.md) — Codify surface roles in `KromoraTheme`
- [KRMA-513](KRMA-513.md) — Toolbar full-width; inspector underneath
- [KRMA-514](KRMA-514.md) — Demote filmstrip/culling/status off elevated `.bar`

## Acceptance criteria

- [ ] With inspector open, top chrome is one continuous surface edge-to-edge (no grey/white split).
- [ ] Inspector column starts below the toolbar, not as a full-height slab owning the top edge.
- [ ] Filmstrip / culling / status do not out-luminance the canvas surround; selection accents carry focus.
- [ ] Light + dark (and Liquid Glass where available) keep the same hierarchy without custom opaque overlays fighting system materials.
- [ ] Child tickets KRMA-513, KRMA-514, KRMA-515 complete.

## Implementation notes

Prefer system materials over invented greys. Avoid another opaque band-aid above the inspector. See children for scoped work.

## Agent log

- 2026-09-21T20:12:37.941Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Open inspector leaves one continuous top chrome surface (pass) — ContentView keeps the visible native window-toolbar material across the inspector column; forced inspector window fills were removed.
- [x] Inspector starts below the toolbar (pass) — Info, Crop, Look, and Masking roots no longer paint an opaque top-to-bottom slab, leaving the system inspector surface to own the column below the toolbar.
- [x] Filmstrip, culling, and status do not out-luminate the canvas with elevated .bar (pass) — The large secondary surfaces use KromoraTheme.secondaryChrome and retain existing selection accents and controls.
- [x] Light, dark, and Liquid Glass hierarchy remains system-owned (pass) — Toolbar and inspector use system surfaces; secondaryChrome is an AppKit dynamic semantic color; canvasBackground remains the dedicated stage.
- [x] Child tickets KRMA-513, KRMA-514, and KRMA-515 complete (pass) — All three child issues were completed against commit 04ff35a.
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
Resolved model: gpt-5.6-luna
Pickup session: 01MUBOD0YC1AMXUBCJ
Summary: Unified Edit chrome hierarchy: native full-width toolbar, transparent system-owned inspector roots below it, and a quieter semantic secondary-chrome family for source browser, filmstrip, culling, and status.
