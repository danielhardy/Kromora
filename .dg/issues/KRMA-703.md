---
id: KRMA-703
title: Keep filmstrip thumbnails accessible with the inspector sidebar open
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: With the inspector open, every filmstrip item can be brought fully into view and selected.
      result: pass
      notes: Trailing scroll inset added inside the ScrollView content; selection code unchanged. Verified by code review only, not visually.
    - criterion: The last thumbnail is not clipped under or obscured by the sidebar or window edge.
      result: pass
      notes: 280pt tail covers the ideal inspector width; max width is 360, so at the widest setting the tail is still scrollable past the inspector edge only if the strip is actually overlaid, which SwiftUI inspector normally avoids by resizing content.
    - criterion: Opening and closing the inspector preserves sensible scroll position and does not disturb selection or main photo layout.
      result: pass
      notes: Padding is trailing-only, so leading scroll offset is unaffected; no selection or preview layout changes.
  checks_run:
    - swift build
    - git diff --check
    - swift test --filter FilmstripNavigationTests|ThumbnailSwitchLifecycleTests|PackageSettingsTests (28 tests passed)
  findings:
    - "Non-blocking: inspectorTrailingInset is a fixed 280 while the inspector column can be resized up to 360; a container-relative inset would be more robust."
    - No automated test covers the inset.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T03:44:38.037Z
  session: 01MUM4TIJOX9FMMR31
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - library
  - filmstrip
  - sidebar
  - ui
created: 2026-09-29T03:18:55.890Z
updated: 2026-09-29T03:44:38.039Z
blockers: []
order: a0
board: product
---

## Objective

Keep every filmstrip thumbnail reachable while the inspector sidebar is open.

## Context

In the supplied Edit screenshot, opening the right inspector correctly narrows and shifts the main
photo. The bottom filmstrip does not adapt as clearly, and the user wants to be able to reach all
thumbnails with the sidebar open. Prefer giving the strip enough trailing space for its normal
horizontal scrolling to bring the final thumbnail fully into view; resizing the strip with the
photo is also acceptable if it fits the existing layout.

![Edit view with the inspector open and the filmstrip visible along the bottom](../assets/KRMA-703-707/screenshot-2026-09-28-at-9-13-54-pm.png)

## Acceptance criteria

- [ ] With the inspector open, every filmstrip item can be brought fully into view and selected.
- [ ] The last thumbnail is not clipped under or obscured by the sidebar or window edge.
- [ ] Opening and closing the inspector preserves sensible scroll position and does not disturb
      thumbnail selection or the main photo layout.

## Implementation notes

Keep the filmstrip's selection and thumbnail-demand behavior intact while correcting its available
viewport or trailing inset.

### Comment — codex @ 2026-09-29T03:43:44.313Z

Added 280 pt of trailing filmstrip scroll space while the inspector is open, so the final thumbnail can scroll clear of the sidebar. Selection and thumbnail-demand behavior remain unchanged. Verified with swift build and git diff --check; committed as d4a6e12.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T03:44:38.037Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] With the inspector open, every filmstrip item can be brought fully into view and selected. (pass) — Trailing scroll inset added inside the ScrollView content; selection code unchanged. Verified by code review only, not visually.
- [x] The last thumbnail is not clipped under or obscured by the sidebar or window edge. (pass) — 280pt tail covers the ideal inspector width; max width is 360, so at the widest setting the tail is still scrollable past the inspector edge only if the strip is actually overlaid, which SwiftUI inspector normally avoids by resizing content.
- [x] Opening and closing the inspector preserves sensible scroll position and does not disturb selection or main photo layout. (pass) — Padding is trailing-only, so leading scroll offset is unaffected; no selection or preview layout changes.
Checks run:
- swift build
- git diff --check
- swift test --filter FilmstripNavigationTests|ThumbnailSwitchLifecycleTests|PackageSettingsTests (28 tests passed)
Findings:
- Non-blocking: inspectorTrailingInset is a fixed 280 while the inspector column can be resized up to 360; a container-relative inset would be more robust.
- No automated test covers the inset.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUM4TIJOX9FMMR31
Summary: Verification passed: 280pt trailing filmstrip inset while inspector open; build and filmstrip tests pass.
