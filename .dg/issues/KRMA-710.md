---
id: KRMA-710
title: Dismiss navigation spinner when the image is already loaded
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - navigation
  - loading
  - spinner
  - preview
  - ui
created: 2026-09-29T03:31:38.317Z
updated: 2026-09-29T03:31:53.260Z
order: zy
board: product
---

## Objective

Dismiss the navigation spinner promptly after the selected image is visibly loaded.

## Context

When navigating between images, the loading spinner can remain visible for 30 seconds or longer
even though the selected photo has already appeared and looks loaded. The indicator therefore
continues to report work after the user can see the destination image, making navigation appear
stuck.

## Acceptance criteria

- [ ] Reproduce the delayed spinner dismissal and distinguish the moment the current image is
      presented from completion of other background work.
- [ ] Clear the navigation spinner promptly when the selected image has usable pixels on screen;
      unrelated prefetch, analysis, or thumbnail work must not hold it open.
- [ ] Keep the spinner visible until the current destination has actually presented, and prevent
      stale completions from clearing the indicator for a newer navigation request.
- [ ] Clear the indicator on terminal load failure or cancellation as well as success.
- [ ] Add regression coverage for completion, cancellation, and rapid-navigation ordering, or
      document a repeatable visual check if presentation timing is UI-only.

## Implementation notes

Trace the spinner's ownership and the readiness signal used by the navigation/preview handoff.
Avoid tying dismissal to work that continues after the destination image is already visible.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
