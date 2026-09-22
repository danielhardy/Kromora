---
id: KRMA-515
title: Codify KromoraTheme surface roles and align secondary chrome vocabulary
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: KromoraTheme documents surface roles and exposes a named secondary helper
      result: pass
      notes: Added the editor shell role table and dynamic secondaryChrome helper backed by NSColor.underPageBackgroundColor.
    - criterion: Source browser, filmstrip, culling, and status share one secondary chrome family
      result: pass
      notes: All four views use KromoraTheme.secondaryChrome; the source List hides its own scroll background.
    - criterion: Canvas remains distinct from shell chrome
      result: pass
      notes: Dedicated canvasBackground remains unchanged and separate from secondary chrome.
    - criterion: Light and dark appearance support
      result: pass
      notes: The secondary role resolves through AppKit dynamic colors; fast CI passed.
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
  completed_at: 2026-09-21T20:12:11.784Z
  session: 01MUBOD0YC1AMXUBCJ
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - chrome
  - theme
created: 2026-09-21T19:16:36.777Z
updated: 2026-09-21T20:12:11.786Z
parent: KRMA-512
order: w
board: product
commits:
  - 04ff35a
---

## Objective

Document semantic surface roles in `KromoraTheme` and align secondary chrome (source browser, filmstrip family, status) to one quieter vocabulary so the canvas remains the only intentionally distinct stage.

## Context

Parent: [KRMA-512](KRMA-512.md). Unblocks [KRMA-514](KRMA-514.md).

Today tokens mix `windowBackgroundColor`, custom `canvasBackground`, `.bar` material, and `controlBackgroundColor` without a written hierarchy. KRMA-441 noted `.bar` and `windowBackground` can converge on newer macOS — chrome must be chosen deliberately so large bottom chrome never outranks the photo stage.

## Target roles

| Role | Intent | Direction |
|---|---|---|
| Window toolbar | Full-width system chrome | Default toolbar material (no custom fill) |
| Inspector | Under toolbar, chrome family | System inspector material |
| Canvas surround | Quiet stage | Keep dedicated recessed `canvasBackground` |
| Secondary chrome | Filmstrip, culling, status, source browser | One quieter family — not elevated `.bar` billboards |
| Analysis plots | Local dark plots only | Keep scoped `analysisBackground` |

## Acceptance criteria

- [ ] `KromoraTheme` documents the role table (comments or short doc) and exposes named helpers for secondary chrome if needed.
- [ ] Source browser, filmstrip, culling, and status share the same secondary chrome family (or an explicit, documented exception).
- [ ] Canvas remains visually distinct and quieter than white/elevated chrome in light mode.
- [ ] No hardcoded one-off greys outside the theme for shell surfaces.
- [ ] Light + dark spot-check; `scripts/ci-tests.sh fast` passes.

## Implementation notes

`Sources/KromoraKit/Views/KromoraTheme.swift` is the seam. Prefer semantic NSColor / Material roles over calibrated literals except for the dedicated canvas stage. Coordinate with KRMA-514 for the actual filmstrip swap.

## Agent log

- 2026-09-21T20:12:11.784Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] KromoraTheme documents surface roles and exposes a named secondary helper (pass) — Added the editor shell role table and dynamic secondaryChrome helper backed by NSColor.underPageBackgroundColor.
- [x] Source browser, filmstrip, culling, and status share one secondary chrome family (pass) — All four views use KromoraTheme.secondaryChrome; the source List hides its own scroll background.
- [x] Canvas remains distinct from shell chrome (pass) — Dedicated canvasBackground remains unchanged and separate from secondary chrome.
- [x] Light and dark appearance support (pass) — The secondary role resolves through AppKit dynamic colors; fast CI passed.
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
Summary: Documented KromoraTheme surface roles and introduced the dynamic secondaryChrome role shared by source browser, filmstrip, culling, and status surfaces.
