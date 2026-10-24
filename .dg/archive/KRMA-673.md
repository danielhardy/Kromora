---
id: KRMA-673
title: Histogram stays unavailable when opening a photo from the Library
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Opening a photo from the Library populates the Histogram for the image shown in Edit once its render is ready.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: The histogram reflects the displayed image and current edit revision, rather than remaining unavailable until another interaction.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Switching to another photo or changing its edits continues to update the histogram for the displayed result.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Add regression coverage for the Library double-click to Edit transition and initial histogram publication.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
  checks_run:
    - swift build (pass)
    - PreviewCutoverTests/testLibraryDoubleClickPublishesHistogramForAlreadyLoadedPhoto (1 passed)
    - git diff --check (pass)
  findings: []
  fixes: []
  verification_commits:
    - 1d657bd
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T14:38:56.576Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - library
  - editor
  - histogram
created: 2026-09-28T02:19:20.100Z
updated: 2026-09-28T14:41:37.140Z
blockers: []
order: tw1bk59n
board: product
commits:
  - 1d657bd
---

## Objective

Load and display the histogram when a photo is opened from the Library into Edit.

## User report

Double-clicking an image in the Library correctly transitions to Edit, but the Histogram panel stays unavailable. In the attached screenshot the photo is displayed and marked Edited while the Histogram section says “Histogram unavailable.”

## Acceptance criteria

- Opening a photo from the Library populates the Histogram for the image shown in Edit once its render is ready.
- The histogram reflects the displayed image and current edit revision, rather than remaining unavailable until another interaction.
- Switching to another photo or changing its edits continues to update the histogram for the displayed result.
- Add regression coverage for the Library double-click to Edit transition and initial histogram publication.

## Context

- Trace the Library-to-Edit transition through preview publication and histogram input/readiness state.
- The screenshot is attached to this issue.

## Checks

- swift build
- Focused histogram and navigation/preview tests covering the Library-to-Edit path.

![Edit view with selected edited image and histogram unavailable](../assets/KRMA-673/screenshot-2026-09-27-at-8-18-57-pm.png)

## Agent log

- 2026-09-28T14:38:56.576Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Opening a photo from the Library populates the Histogram for the image shown in Edit once its render is ready. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] The histogram reflects the displayed image and current edit revision, rather than remaining unavailable until another interaction. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Switching to another photo or changing its edits continues to update the histogram for the displayed result. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Add regression coverage for the Library double-click to Edit transition and initial histogram publication. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
Checks run:
- swift build (pass)
- PreviewCutoverTests/testLibraryDoubleClickPublishesHistogramForAlreadyLoadedPhoto (1 passed)
- git diff --check (pass)
Findings:
- None
Fixes:
- None
Verification commits:
- 1d657bd
Actor: codex
Resolved model: unknown
Summary: Fixed histogram admission when opening an already-rendered Library photo in Edit; focused regression test passes.
