---
id: KRMA-671
title: Show the current edited version in thumbnails without interaction
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - library
  - thumbnails
created: 2026-09-28T02:17:38.781Z
updated: 2026-09-28T02:17:49.926Z
order: y
board: product
---

## Objective

Show the current edited result in thumbnails as soon as the Library or filmstrip is displayed, without requiring user interaction to trigger the correct thumbnail.

## User report

Thumbnails do not always show the correctly edited version at first. The correct versions appear after interaction, but should already be visible.

## Acceptance criteria

- On initial display, photos with saved edits resolve to thumbnails for their current edit state, including after relaunch.
- Selecting, hovering, or otherwise interacting with a photo is not required to trigger or reveal its current edited thumbnail.
- A source/original thumbnail is not left presented as the settled result when a newer saved edit exists.
- Add regression coverage for initial display of edited thumbnails without selection or other interaction, including persisted edits after reopening where practical.

## Context

- Investigate initial thumbnail demand, cache identity/revision matching, and publication to the Library and filmstrip.
- Preserve current cancellation and stale-result protections while ensuring saved edits are represented on first display.

## Checks

- swift build
- Focused edited-thumbnail and Library/filmstrip tests covering initial display and persisted edits.
