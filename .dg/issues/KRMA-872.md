---
id: KRMA-872
title: "Light inspector: remove the Auto helper text under the title"
type: task
status: backlog
priority: low
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-11T01:11:23.889Z
updated: 2026-10-11T01:11:24.284Z
blockers: []
order: zzzzzq
board: product
---

## Objective

Remove the helper line under the Light inspector title: "Auto replaces global Light and Color values; other edits stay unchanged." It is not needed there.

## Work done

`LightInspectorView.header` (Sources/KromoraKit/Views/LightInspectorView.swift) is now just the title and the reset icon; the text and its wrapping `VStack` are gone. Nothing else referenced the string. The LightInspector tests that run are unchanged by this; the one failing assertion in that suite is KRMA-853.

## Acceptance criteria

- The Light tab shows no explanatory line under its title.
- The reset icon and its accessibility label and hint are unchanged.
