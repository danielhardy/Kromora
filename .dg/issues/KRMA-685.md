---
id: KRMA-685
title: Animate histogram transitions when switching photos
type: feature
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - editor
  - histogram
created: 2026-09-28T14:05:59.068Z
updated: 2026-09-28T14:08:26.071Z
blockers: []
order: zzy
board: product
---

## Objective

Keep the histogram visible while a newly selected photo is being analyzed, then animate the
displayed histogram to the new photo's distribution.

## User report

When moving from one photo to the next in Edit, the current histogram disappears and a loading
spinner is shown while the next histogram is calculated. The user wants the chart to remain present
and smoothly transition to the selected photo's histogram when it is ready.

## Context

This is a continuity and presentation issue during photo selection. KRMA-673 tracks the separate
case where the histogram is initially unavailable after opening a photo from the Library; this
ticket covers retaining and animating an already visible histogram during subsequent photo changes.

## Acceptance criteria

- [ ] When switching photos in Edit and a histogram is already displayed, keep the chart visible
      while the new photo's histogram is being computed instead of replacing it with a spinner.
- [ ] When a histogram for the currently selected photo is ready, animate the chart from the
      previous distribution to the new one.
- [ ] Rapid photo changes never animate to or leave behind a histogram belonging to an obsolete
      selection; the final chart represents the currently selected photo.
- [ ] Preserve an appropriate loading or unavailable state when there is no prior histogram to
      retain, such as the initial photo load.
- [ ] Add regression coverage for retaining the current histogram during a photo switch, animating
      the current result, and rejecting stale results from earlier selections.

## Implementation notes

Keep the last published histogram available while the next request is pending. Start the visual
transition only after the result passes the existing asset and display-revision checks. Coordinate
with KRMA-673 if changes to initial histogram readiness overlap.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
