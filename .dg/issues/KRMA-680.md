---
id: KRMA-680
title: Simplify the Masking header controls
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The Masking header no longer shows the Done link beside Add Mask.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Replace the labeled Add Mask dropdown with a compact plus icon button that opens the existing Add Mask menu.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: The plus button has an accessible label or help text identifying it as Add Mask.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: The visibility toggle and masking tools remain available and functional.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Users can still leave the Masking workspace using the app’s existing navigation, without losing mask edits.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Review the updated header against the attached screenshot.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
  checks_run:
    - swift build (pass)
    - MaskingWorkspaceTests (pass; included in 130-test focused run)
    - Committed view source reviewed; visual review was not rerun during this audit
    - git diff --check (pass)
  findings: []
  fixes: []
  verification_commits:
    - 92ea826
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T14:39:01.750Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - editor
  - masking
  - ui
created: 2026-09-28T02:36:13.161Z
updated: 2026-09-28T14:41:38.423Z
blockers: []
order: xcvpfit2
board: product
commits:
  - 92ea826
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

## Agent log

- 2026-09-28T14:39:01.750Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The Masking header no longer shows the Done link beside Add Mask. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Replace the labeled Add Mask dropdown with a compact plus icon button that opens the existing Add Mask menu. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] The plus button has an accessible label or help text identifying it as Add Mask. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] The visibility toggle and masking tools remain available and functional. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Users can still leave the Masking workspace using the app’s existing navigation, without losing mask edits. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Review the updated header against the attached screenshot. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
Checks run:
- swift build (pass)
- MaskingWorkspaceTests (pass; included in 130-test focused run)
- Committed view source reviewed; visual review was not rerun during this audit
- git diff --check (pass)
Findings:
- None
Fixes:
- None
Verification commits:
- 92ea826
Actor: codex
Resolved model: unknown
Summary: Simplified the Masking workspace header and retained the Add Mask menu and accessibility label; focused masking tests pass.
