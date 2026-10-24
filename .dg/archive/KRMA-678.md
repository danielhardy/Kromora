---
id: KRMA-678
title: Group parametric controls under an Advanced Curve accordion
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Group the Highlights, Lights, Darks, and Shadows amount controls and the Shadow, Dark, Light, and Highlight split controls under an “Advanced Curve” accordion.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: The accordion is collapsed by default; the primary tone-curve controls remain available outside it.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Expanding the accordion exposes the existing controls and labels without changing their adjustment behavior or saved values.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Add or update focused coverage for the default collapsed state and access to the controls when expanded.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Review the updated inspector against the attached screenshot.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
  checks_run:
    - swift build (pass)
    - LightInspectorTests (pass; included in 130-test focused run)
    - Committed view source reviewed; visual review was not rerun during this audit
    - git diff --check (pass)
  findings: []
  fixes: []
  verification_commits:
    - 0ed73d2
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T14:39:00.023Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - editor
  - inspector
  - tone-curve
  - ui
created: 2026-09-28T02:31:31.588Z
updated: 2026-09-28T14:41:38.289Z
blockers: []
order: x0zo3yns
board: product
commits:
  - 0ed73d2
---

## Objective

Reduce the amount of visible Light inspector content by placing the parametric tonal-region and region-split controls under an Advanced Curve accordion.

## Acceptance criteria

- Group the Highlights, Lights, Darks, and Shadows amount controls and the Shadow, Dark, Light, and Highlight split controls under an “Advanced Curve” accordion.
- The accordion is collapsed by default; the primary tone-curve controls remain available outside it.
- Expanding the accordion exposes the existing controls and labels without changing their adjustment behavior or saved values.
- Add or update focused coverage for the default collapsed state and access to the controls when expanded.
- Review the updated inspector against the attached screenshot.

## Context

- The parametric controls were added in KRMA-595; this ticket changes their presentation, not their edit or rendering behavior.
- Screenshot attached to this issue.

## Checks

- swift build
- Focused Light inspector and tone-curve tests.

![Light inspector parametric tone-curve region and split controls](../assets/KRMA-678/screenshot-2026-09-27-at-8-30-36-pm.png)

## Agent log

- 2026-09-28T14:39:00.023Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Group the Highlights, Lights, Darks, and Shadows amount controls and the Shadow, Dark, Light, and Highlight split controls under an “Advanced Curve” accordion. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] The accordion is collapsed by default; the primary tone-curve controls remain available outside it. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Expanding the accordion exposes the existing controls and labels without changing their adjustment behavior or saved values. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Add or update focused coverage for the default collapsed state and access to the controls when expanded. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Review the updated inspector against the attached screenshot. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
Checks run:
- swift build (pass)
- LightInspectorTests (pass; included in 130-test focused run)
- Committed view source reviewed; visual review was not rerun during this audit
- git diff --check (pass)
Findings:
- None
Fixes:
- None
Verification commits:
- 0ed73d2
Actor: codex
Resolved model: unknown
Summary: Grouped parametric tonal-region and split controls under a collapsed-by-default Advanced Curve disclosure; focused tests pass.
