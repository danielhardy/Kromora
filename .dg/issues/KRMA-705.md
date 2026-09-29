---
id: KRMA-705
title: Normalize spacing around icons beside the Library/Edit control
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - toolbar
  - layout
  - ui
created: 2026-09-29T03:18:58.104Z
updated: 2026-09-29T03:19:56.486Z
order: z
board: product
---

## Objective

Make spacing and padding consistent for the toolbar icons beside Library/Edit.

## Context

In the supplied screenshot, the crop, enhancement, and comparison controls to the right of the
Library/Edit segmented control have uneven spacing and padding. The toolbar should read as a
deliberate, balanced group while preserving the current control functions.

![Edit toolbar icons beside the Library/Edit control](../assets/KRMA-703-707/screenshot-2026-09-28-at-9-13-54-pm.png)

## Acceptance criteria

- [ ] Adjacent toolbar icons use consistent gaps, alignment, and visual padding.
- [ ] Hit targets remain comfortable and controls retain their current actions and selected states.
- [ ] Spacing remains balanced with the inspector open and closed and as the window width changes.

## Implementation notes

Use the platform's standard toolbar sizing and spacing where possible; avoid one-off padding values
that cause neighboring controls to drift.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
