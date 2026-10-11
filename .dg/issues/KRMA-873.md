---
id: KRMA-873
title: Review app-wide tint policy for bordered buttons
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
parent: KRMA-871
created: 2026-10-11T03:11:55.163Z
updated: 2026-10-11T03:11:55.163Z
blockers: []
order: zzzz
board: product
---

## Objective

Determine and implement a consistent tint policy for ordinary bordered buttons across the app.

## Context

KRMA-871 found that sixteen other `.buttonStyle(.bordered)` call sites inherit the window-wide copper tint. They appear in the Library grid and culling bar, Look and Color inspectors, Crop, onboarding, and preview. The Masks chooser has a local `.tint(nil)` because its choices are one-shot actions. Review the other sites and distinguish ordinary actions from controls where the tint communicates an active or selected state.

## Acceptance criteria

- [ ] All bordered-button call sites affected by the window tint are audited and their intended visual state is documented.
- [ ] A consistent rule for ordinary bordered actions and stateful controls is selected and applied with an appropriately shared or scoped implementation.
- [ ] Affected UI behavior is verified in an active app window or by a test that exercises the rendered tint; offscreen inactive-window rendering alone is insufficient.

## Implementation notes

Keep the change scoped to button tint behavior. Preserve copper where it intentionally communicates an active state.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
