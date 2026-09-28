---
id: KRMA-671
title: Show the current edited version in thumbnails without interaction
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: On initial display, photos with saved edits resolve to thumbnails for their current edit state, including after relaunch.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Selecting, hovering, or otherwise interacting with a photo is not required to trigger or reveal its current edited thumbnail.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: A source/original thumbnail is not left presented as the settled result when a newer saved edit exists.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Add regression coverage for initial display of edited thumbnails without selection or other interaction, including persisted edits after reopening where practical.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
  checks_run:
    - swift build (pass)
    - Focused EditedThumbnailCoordinatorTests (pass; included in 130-test focused run)
    - git diff --check (pass)
  findings: []
  fixes: []
  verification_commits:
    - ae7a8b3
    - ece2476
    - 92a43c5
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T14:38:55.719Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - library
  - thumbnails
created: 2026-09-28T02:17:38.781Z
updated: 2026-09-28T14:41:36.531Z
blockers: []
order: s8l4ycj9
board: product
commits:
  - ece2476
  - ae7a8b3
  - 92a43c5
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

## Agent log

- 2026-09-28T14:38:55.719Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] On initial display, photos with saved edits resolve to thumbnails for their current edit state, including after relaunch. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Selecting, hovering, or otherwise interacting with a photo is not required to trigger or reveal its current edited thumbnail. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] A source/original thumbnail is not left presented as the settled result when a newer saved edit exists. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Add regression coverage for initial display of edited thumbnails without selection or other interaction, including persisted edits after reopening where practical. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
Checks run:
- swift build (pass)
- Focused EditedThumbnailCoordinatorTests (pass; included in 130-test focused run)
- git diff --check (pass)
Findings:
- None
Fixes:
- None
Verification commits:
- ae7a8b3
- ece2476
- 92a43c5
Actor: codex
Resolved model: unknown
Summary: Implemented non-interactive publication of saved edited thumbnails, including reopened package revisions; committed thumbnail demand and cache revision fixes.
