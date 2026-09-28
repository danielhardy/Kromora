---
id: KRMA-677
title: Move or remove the Tone Curve Reset control
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - editor
  - inspector
  - tone-curve
  - ui
created: 2026-09-28T02:30:01.707Z
updated: 2026-09-28T02:30:16.142Z
order: zy
board: product
---

## Objective

Reduce the visual weight of the Tone Curve Reset control by removing it or moving it into the Tone Curve accordion header.

## User report

The prominent “Reset” text sits on its own row above the curve. It can be removed or replaced with a small, right-aligned icon on the same row as the Tone Curve title. The attached screenshot shows the current layout.

## Acceptance criteria

- Remove the standalone Reset text/link, or replace it with a compact reset icon aligned at the trailing edge of the Tone Curve accordion title row.
- Keep the Tone Curve title and accordion disclosure control clear and aligned.
- If reset remains available, the icon performs the existing reset action and has an accessible label describing that action.
- Review the updated inspector layout against the attached screenshot.

## Context

- Screenshot attached to this issue.

## Checks

- swift build
- Focused Tone Curve inspector tests, including reset behavior if the control remains.

![Tone Curve inspector with a standalone Reset link above the curve](../assets/KRMA-677/screenshot-2026-09-27-at-8-28-58-pm.png)
