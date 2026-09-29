---
id: KRMA-708
title: Prevent tone curve movement during loading and edit updates
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - tone-curve
  - inspector
  - navigation
  - ui
created: 2026-09-29T03:25:18.341Z
updated: 2026-09-29T03:29:28.615Z
order: zv
board: product
---

## Objective

Keep the Tone Curve inspector layout stable during photo loading and edit updates.

## Context

When moving between filmstrip thumbnails with the arrow keys, the Tone Curve section temporarily
expands or moves while the next photo is loading, then returns to its normal position after loading
finishes. The same movement also occurs while adjusting Exposure or other edit controls, without
changing photos. This points to the shared loading/update loop rather than keyboard navigation
alone, and causes the inspector layout to jump during ordinary editing and browsing.

## Acceptance criteria

- [ ] Reproduce the movement during arrow-key photo navigation and while adjusting Exposure or
      another edit control; identify which loading/update state changes the section's geometry.
- [ ] Keep the Tone Curve section in a stable position and at its normal size during loading,
      edit updates, and after each operation settles.
- [ ] Preserve tone curve controls, chart contents, and loading/error feedback within the stable
      layout.
- [ ] Add regression coverage for the sizing behavior, or document a repeatable visual check if
      it depends on asynchronous SwiftUI presentation.

## Implementation notes

Trace the shared loading/update loop and the state changes it publishes to the Tone Curve view and
its parent inspector. Avoid fixing the jump by hiding the curve or dropping useful loading feedback.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
