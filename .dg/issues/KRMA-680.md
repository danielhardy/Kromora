---
id: KRMA-680
title: Simplify the Masking header controls
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - editor
  - masking
  - ui
created: 2026-09-28T02:36:13.161Z
updated: 2026-09-28T02:38:17.627Z
order: zzq
board: product
---

## Objective

Simplify the Masking workspace header by removing the standalone “Done” link and presenting Add Mask as a compact plus icon.

## Acceptance criteria

- The Masking header no longer shows the Done link beside Add Mask.
- Replace the labeled Add Mask dropdown with a compact plus icon button that opens the existing Add Mask menu.
- The plus button has an accessible label or help text identifying it as Add Mask.
- The visibility toggle and masking tools remain available and functional.
- Users can still leave the Masking workspace using the app’s existing navigation, without losing mask edits.
- Review the updated header against the attached screenshot.

## Context

- Screenshot attached to this issue.

## Checks

- swift build
- Focused masking UI/navigation tests.

![Masking workspace header with Done link beside Add Mask](../assets/KRMA-680/screenshot-2026-09-27-at-8-35-21-pm.png)
