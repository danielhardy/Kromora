---
id: KRMA-670
title: Launch into the Library instead of an empty editor state
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A normal app launch opens with Library as the active screen.
      result: pass
      notes: NavigationState and ContentView now launch in grid/Library mode.
    - criterion: When the library already contains photos, launch presents the Library collection instead of an empty drop/import canvas.
      result: pass
      notes: Committed tests cover launch with an existing package photo.
    - criterion: The initial screen is coherent when the library has no photos and still offers the existing import actions.
      result: pass
      notes: Committed tests cover empty-library startup; the existing Library empty state retains import actions.
    - criterion: Add focused regression coverage for the launch destination with both an existing library and an empty library.
      result: pass
      notes: NavigationStateTests cover both cases in commit 55eaa7c.
  checks_run:
    - swift build (pass)
    - "scripts/ci-tests.sh fast: launch tests passed; lane has separate failures in crop, inspector fallback, and thumbnail lifecycle tests"
  findings: []
  fixes: []
  verification_commits:
    - 55eaa7c
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T14:31:43.277Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - library
  - startup
created: 2026-09-28T02:15:08.105Z
updated: 2026-09-28T14:41:35.878Z
blockers: []
order: qf6xorq8
board: product
commits:
  - 55eaa7c
---

## Objective

Make the Library the default screen when Kromora opens. The current launch can land in an odd empty editor/import state while the photo strip shows existing library items.

## User report

“When opening the app, the default should be the library screen. For some reason it is in an odd state.” The attached screenshot shows the central “Drop an image or folder here” placeholder alongside a bottom strip containing 13 photos.

## Acceptance criteria

- A normal app launch opens with Library as the active screen.
- When the library already contains photos, launch presents the Library collection instead of an empty drop/import canvas.
- The initial screen is coherent when the library has no photos and still offers the existing import actions.
- Add focused regression coverage for the launch destination with both an existing library and an empty library.

## Context

- Investigate the app’s startup destination/state and how it chooses between Library and Edit/empty-import presentation.
- Screenshot attached to this issue.

## Checks

- swift build
- Focused startup or Library navigation tests covering the acceptance criteria.

![Kromora launch shows empty drop canvas with 13 photos in bottom strip](../assets/KRMA-670/screenshot-2026-09-27-at-8-14-03-pm.png)

## Agent log

- 2026-09-28T14:31:43.277Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A normal app launch opens with Library as the active screen. (pass) — NavigationState and ContentView now launch in grid/Library mode.
- [x] When the library already contains photos, launch presents the Library collection instead of an empty drop/import canvas. (pass) — Committed tests cover launch with an existing package photo.
- [x] The initial screen is coherent when the library has no photos and still offers the existing import actions. (pass) — Committed tests cover empty-library startup; the existing Library empty state retains import actions.
- [x] Add focused regression coverage for the launch destination with both an existing library and an empty library. (pass) — NavigationStateTests cover both cases in commit 55eaa7c.
Checks run:
- swift build (pass)
- scripts/ci-tests.sh fast: launch tests passed; lane has separate failures in crop, inspector fallback, and thumbnail lifecycle tests
Findings:
- None
Fixes:
- None
Verification commits:
- 55eaa7c
Actor: codex
Resolved model: unknown
Summary: Implemented and committed launch to Library, with regression coverage for empty and populated libraries; build and launch tests pass.
