---
id: KRMA-850
title: Move mask analysis failure banner from the Masks panel to the status bar
type: bug
status: backlog
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:02:26.280Z
updated: 2026-10-10T13:02:40.266Z
blockers: []
order: zy
board: product
---

## Objective

The "Mask analysis unavailable" / "failed" banner lived in the Masks inspector flow. It appeared and disappeared while the user hovered or clicked the mask, reflowing the panel so the mask row moved under the pointer.

## Work done

- `Sources/KromoraKit/Views/MaskingWorkspace.swift`: `renderStatus` no longer renders `.unavailable` / `.failed`; they join the no-op cases alongside the existing "transient progress lives in the status bar" rationale. The "Preview unavailable" banner is unchanged.
- `Sources/KromoraKit/Views/StatusBar.swift`: `MaskActivityIndicator` now takes a `retry` closure and shows a warning icon, "Mask analysis unavailable" and a Retry button for `.unavailable`/`.failed`, with the full message as help text and accessibility label. `.loading` is unchanged.

## Acceptance criteria

- The Masks panel never reflows when mask analysis fails or recovers.
- The status bar shows the failure with a working Retry (calls `retryMaskAnalysis`).
- VoiceOver reads the full message.
- Existing masking panel tests pass; a verifier may add a view-level assertion.
