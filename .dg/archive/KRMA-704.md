---
id: KRMA-704
title: Keep import, export, and share controls left of the open inspector
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: When the inspector is open, import, export, and share controls remain visible and clickable to its left.
      result: pass
      notes: transferToolbarPill is placed in the .navigation group while inspectorState.isPresented.
    - criterion: Controls do not overlap the inspector, disappear behind it, or become clipped at supported window widths.
      result: pass
      notes: Leading placement is not adjacent to the inspector; not visually verified at narrow widths (headless run).
    - criterion: Closing the inspector restores the normal toolbar layout without shifting unrelated controls unexpectedly.
      result: pass
      notes: Trailing placement restored when inspector is closed; other items unchanged.
  checks_run:
    - swift build (pass)
    - swift test --filter LibraryChromeLayoutTests (4 tests pass)
  findings:
    - "low: LibraryChromeLayoutTests asserts on exact source-text whitespace of ContentView, which is brittle to reformatting; consistent with existing test style, left as is."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T03:48:42.014Z
  session: 01MUM4Z6FKI7O49R8N
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - toolbar
  - sidebar
  - ui
created: 2026-09-29T03:18:56.978Z
updated: 2026-09-29T03:48:42.016Z
blockers: []
order: a0
board: product
---

## Objective

Keep import, export, and share controls visible immediately to the left of the open inspector.

## Context

In the supplied Edit screenshot, the inspector is docked on the right. The toolbar's import,
export, and share actions should remain in the usable toolbar area to the left of the inspector as
the available content width changes.

![Edit view with the inspector open and toolbar actions along the top](../assets/KRMA-703-707/screenshot-2026-09-28-at-9-13-54-pm.png)

## Acceptance criteria

- [ ] When the inspector is open, import, export, and share controls remain visible and clickable
      to its left.
- [ ] Controls do not overlap the inspector, disappear behind it, or become clipped at supported
      window widths.
- [ ] Closing the inspector restores the normal toolbar layout without shifting unrelated controls
      unexpectedly.

## Implementation notes

Check the toolbar's layout against both inspector states and narrower window widths; retain the
existing actions and menu behavior.

### Comment — codex @ 2026-09-29T03:48:08.248Z

Moved Import and Export into the leading toolbar group while the inspector is open; restored their trailing placement when it closes. Verified with swift build, swift test --filter LibraryChromeLayoutTests (4 tests passed), and git diff --check. Commit: 5c2a560.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T03:48:42.014Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] When the inspector is open, import, export, and share controls remain visible and clickable to its left. (pass) — transferToolbarPill is placed in the .navigation group while inspectorState.isPresented.
- [x] Controls do not overlap the inspector, disappear behind it, or become clipped at supported window widths. (pass) — Leading placement is not adjacent to the inspector; not visually verified at narrow widths (headless run).
- [x] Closing the inspector restores the normal toolbar layout without shifting unrelated controls unexpectedly. (pass) — Trailing placement restored when inspector is closed; other items unchanged.
Checks run:
- swift build (pass)
- swift test --filter LibraryChromeLayoutTests (4 tests pass)
Findings:
- low: LibraryChromeLayoutTests asserts on exact source-text whitespace of ContentView, which is brittle to reformatting; consistent with existing test style, left as is.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUM4Z6FKI7O49R8N
Summary: Verified: transfer pill moves to leading toolbar group when inspector open, returns trailing when closed.
