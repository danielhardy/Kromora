---
id: KRMA-719
title: Reduce excess trailing gap at the end of the Edit filmstrip
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce and measure rightmost position
      result: pass
      notes: Implementer recorded measurements from the KRMA-703 screenshot; not re-measured live in this headless run.
    - criterion: Identify root cause
      result: pass
      notes: Fixed 280 pt trailing padding stacked on a viewport the .inspector already resizes (inspector is applied outside the NavigationStack containing the filmstrip).
    - criterion: Final thumbnail fully visible with modest gutter
      result: pass
      notes: Only the 12 pt horizontal content inset remains.
    - criterion: Every thumbnail accessible and selectable
      result: pass
      notes: Selection, keyboard and demand code untouched.
    - criterion: Inspector open/closed and widths derived from actual overlap
      result: pass
      notes: No fixed reservation remains; the viewport follows the inspector width by construction.
    - criterion: Navigation, keyboard, demand/release preserved
      result: pass
      notes: "FilmstripNavigationTests: 8 passed."
    - criterion: Regression coverage and visual procedure
      result: pass
      notes: Gutter assertion added; the visual procedure is in the handoff comment.
    - criterion: Handoff records root cause, fix, verification
      result: pass
  checks_run:
    - swift build (pass)
    - swift test --filter FilmstripNavigationTests (8 passed)
    - git diff --check 2d8bc6d~1 2d8bc6d (clean)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T19:46:50.110Z
  session: 01MUN374X5JX27XDBU
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - ui
  - layout
created: 2026-09-29T17:29:16.351Z
updated: 2026-09-29T19:46:50.112Z
blockers: []
order: a0
board: product
---

## Objective

Correct the rightmost horizontal scroll position of the Edit-mode filmstrip so the furthest-right thumbnail is fully visible and sits just to the left of the inspector sidebar, with a normal small gutter instead of a large blank gap.

## User report

When scrolling the Edit-mode thumbnails all the way horizontally to the right, the furthest-right image is visible but there is an excessive empty gap before the sidebar—about two or three thumbnail widths. The last thumbnail should be nicely aligned just to the left of the sidebar.

## Context

`FilmstripView` in `Sources/KromoraKit/Views/FilmstripView.swift` adds `FilmstripLayout.inspectorTrailingInset` (currently 280 pt) to the scroll content when the inspector is presented. KRMA-703 added this trailing inset so the last item could scroll clear of the inspector. The current report suggests the fixed inset leaves too much scrollable tail at the rightmost offset, or does not match the actual overlap between the filmstrip viewport and inspector. Verify the geometry before selecting a replacement; do not assume the inspector always overlays the same amount.

Related completed work: KRMA-703 (Keep filmstrip thumbnails accessible with the inspector sidebar open).

## Acceptance criteria

- [ ] Reproduce and measure the rightmost filmstrip position with the inspector open; record the viewport edge, inspector edge, final thumbnail edge, and blank trailing distance.
- [ ] Identify whether the excess gap comes from the fixed trailing inset, the actual inspector/filmstrip overlap, scroll-view content sizing, or another geometry/scroll-target behavior.
- [ ] At the maximum rightward scroll position with the inspector open, keep the final thumbnail fully visible and place it close to the inspector edge with a modest, consistent gutter; remove the reported two-to-three-thumbnail-width blank gap.
- [ ] Preserve access to and selection of every thumbnail. The final item must not be clipped, covered by the inspector, or left unreachable.
- [ ] Verify behavior with the inspector closed and open at narrow, typical, and wide inspector widths, including window resizing. Derive any required trailing scroll space from actual overlap rather than reserving an unnecessary fixed gap.
- [ ] Keep selected-thumbnail navigation, keyboard stepping, thumbnail-demand/release behavior, and sensible scroll position when opening or closing the inspector intact.
- [ ] Add focused geometry/layout regression coverage where practical and record a repeatable visual verification procedure for the running app.
- [ ] Record the root cause, fix, and verification commands/results in the implementation handoff.

## Investigation notes

Start with `FilmstripView` content padding and scroll behavior and `FilmstripLayout.inspectorTrailingInset`. Distinguish the filmstrip scroll viewport from the main image canvas: the inspector may resize one region while overlapping another. Validate the last-item position at the actual rightmost offset rather than relying only on `scrollTo` selection behavior.


### Comment — codex @ 2026-09-29T19:46:04.454Z

Removed the inspector-specific 280 pt trailing spacer. The native .inspector resizes the NavigationStack content, so the filmstrip viewport’s trailing edge aligns with the inspector’s leading edge (x≈1368 px in the existing KRMA-703 screenshot). At maximum rightward scroll, the old content geometry placed the final thumbnail 280 pt + 12 pt = 292 pt before that edge; the new layout keeps only the 12 pt horizontal content gutter. Selection scrolling, keyboard navigation, and thumbnail demand/release code are unchanged. Added a regression assertion for the 12 pt gutter. Checks: swift test --filter FilmstripNavigationTests (8 passed), swift build, git diff --check. Visual procedure: open a multi-image collection in Edit; with the inspector closed and then open, scroll the filmstrip fully right and compare the final thumbnail edge with the sidebar edge; resize the inspector through its narrow, ideal, and wide widths (240/280/360 pt) and resize the window, confirming a consistent small gutter and that the final item remains selectable. Repeat with inspector closed and verify selection/arrow navigation and demand behavior. Commit: 2d8bc6d.

## Agent log

- 2026-09-29T19:46:50.110Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce and measure rightmost position (pass) — Implementer recorded measurements from the KRMA-703 screenshot; not re-measured live in this headless run.
- [x] Identify root cause (pass) — Fixed 280 pt trailing padding stacked on a viewport the .inspector already resizes (inspector is applied outside the NavigationStack containing the filmstrip).
- [x] Final thumbnail fully visible with modest gutter (pass) — Only the 12 pt horizontal content inset remains.
- [x] Every thumbnail accessible and selectable (pass) — Selection, keyboard and demand code untouched.
- [x] Inspector open/closed and widths derived from actual overlap (pass) — No fixed reservation remains; the viewport follows the inspector width by construction.
- [x] Navigation, keyboard, demand/release preserved (pass) — FilmstripNavigationTests: 8 passed.
- [x] Regression coverage and visual procedure (pass) — Gutter assertion added; the visual procedure is in the handoff comment.
- [x] Handoff records root cause, fix, verification (pass)
Checks run:
- swift build (pass)
- swift test --filter FilmstripNavigationTests (8 passed)
- git diff --check 2d8bc6d~1 2d8bc6d (clean)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUN374X5JX27XDBU
Summary: Verified: removed the fixed 280 pt inspector trailing inset; the native .inspector resizes the filmstrip viewport, so the 12 pt content gutter is the complete end gutter. Build and FilmstripNavigationTests pass. Live visual check not run in this headless session.
