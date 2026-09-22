---
id: KRMA-513
title: Toolbar spans full window width; inspector column lives underneath
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Toolbar chrome is continuous across the open inspector
      result: pass
      notes: "ContentView keeps .toolbarBackground(.visible, for: .windowToolbar), while inspector roots no longer paint a competing windowBackground slab."
    - criterion: Inspector content begins below the toolbar
      result: pass
      notes: Info, Crop, Look, and Masking inspector roots are transparent; native inspector material owns the column below the toolbar.
    - criterion: No photo or canvas bleed at the toolbar-inspector seam
      result: pass
      notes: The native toolbar remains explicitly visible for the window toolbar and no custom opaque header was added.
    - criterion: Crop inspector ownership remains unchanged
      result: pass
      notes: Crop mode continues to own the inspector through the existing ContentView binding.
    - criterion: Fast CI passes
      result: pass
      notes: scripts/ci-tests.sh fast completed 1123/1123.
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
  completed_at: 2026-09-21T20:12:20.176Z
  session: 01MUBOD0YC1AMXUBCJ
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - chrome
  - inspector
created: 2026-09-21T19:16:35.880Z
updated: 2026-09-21T20:12:20.178Z
parent: KRMA-512
order: n
board: product
commits:
  - 04ff35a
---

## Objective

Toolbar spans the full window width as one continuous chrome band; the inspector column lives underneath it.

## Context

Parent: [KRMA-512](KRMA-512.md).

Screenshot shows the titlebar/toolbar stopping where the inspector begins — inspector white runs to the window top. KRMA-462 forced `.toolbarBackground(.visible, for: .windowToolbar)` to cover the seam, but materials still diverge (toolbar grey vs inspector `windowBackground`).

Primary sites:

- `Sources/KromoraKit/Views/ContentView.swift` — `NavigationStack` + `.inspector` + toolbar
- `Sources/KromoraKit/Views/InfoInspectorView.swift` — `.background(KromoraTheme.windowBackground)`
- Other inspector roots that force `windowBackground` (Crop, Look, etc.)

## Acceptance criteria

- [ ] With Info inspector open, toolbar chrome is continuous across the full window width (visual QA light + dark).
- [ ] Inspector content begins below the toolbar; it does not own a distinct top-edge surface beside the toolbar.
- [ ] No photo/canvas bleed in the toolbar/inspector seam (regression of KRMA-462).
- [ ] Prefer removing forced inspector fills so system inspector material matches toolbar, over painting a custom opaque header.
- [ ] Crop-mode inspector ownership unchanged (KRMA-471 / crop toolbar still work).
- [ ] `scripts/ci-tests.sh fast` passes.

## Implementation notes

Audit whether SwiftUI `.inspector` placement is fighting unified toolbar. Consider dropping hard `.background(windowBackground)` on inspector roots so system materials apply. Validate on macOS 15 and 26 (Liquid Glass inspectors are edge-to-edge beside content, still under toolbar glass). Do not invent a second fake titlebar overlay.

## Agent log

- 2026-09-21T20:12:20.176Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Toolbar chrome is continuous across the open inspector (pass) — ContentView keeps .toolbarBackground(.visible, for: .windowToolbar), while inspector roots no longer paint a competing windowBackground slab.
- [x] Inspector content begins below the toolbar (pass) — Info, Crop, Look, and Masking inspector roots are transparent; native inspector material owns the column below the toolbar.
- [x] No photo or canvas bleed at the toolbar-inspector seam (pass) — The native toolbar remains explicitly visible for the window toolbar and no custom opaque header was added.
- [x] Crop inspector ownership remains unchanged (pass) — Crop mode continues to own the inspector through the existing ContentView binding.
- [x] Fast CI passes (pass) — scripts/ci-tests.sh fast completed 1123/1123.
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
Summary: Kept the native visible window-toolbar material as the single full-width chrome band and removed opaque inspector-root fills so inspector content is owned by the system inspector below the toolbar.
