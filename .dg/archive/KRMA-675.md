---
id: KRMA-675
title: Make Edit History collapsible below Photo Analysis
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: In the Info panel, Photo Analysis appears above Edit History.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Edit History has an accordion control that expands and collapses its history content.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Edit History is collapsed by default when the Info panel is first shown.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Expanding the section preserves access to the existing history, snapshot, and virtual-copy actions.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Add or update focused coverage for section ordering, default collapsed state, and expand/collapse behavior.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
  checks_run:
    - swift build (pass)
    - InfoInspectorPresentationTests (pass; included in 130-test focused run)
    - git diff --check (pass)
  findings: []
  fixes: []
  verification_commits:
    - 79e4ed1
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T14:38:57.451Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - editor
  - inspector
  - info
created: 2026-09-28T02:22:35.919Z
updated: 2026-09-28T14:41:37.818Z
blockers: []
order: vpfitq2o
board: product
commits:
  - 79e4ed1
---

## Objective

Make Edit History a collapsible section in the Info panel, place it below Photo Analysis, and have it collapsed by default.

## Acceptance criteria

- In the Info panel, Photo Analysis appears above Edit History.
- Edit History has an accordion control that expands and collapses its history content.
- Edit History is collapsed by default when the Info panel is first shown.
- Expanding the section preserves access to the existing history, snapshot, and virtual-copy actions.
- Add or update focused coverage for section ordering, default collapsed state, and expand/collapse behavior.

## Checks

- swift build
- Focused Info panel/Edit History presentation tests.

## Agent log

- 2026-09-28T14:38:57.452Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] In the Info panel, Photo Analysis appears above Edit History. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Edit History has an accordion control that expands and collapses its history content. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Edit History is collapsed by default when the Info panel is first shown. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Expanding the section preserves access to the existing history, snapshot, and virtual-copy actions. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Add or update focused coverage for section ordering, default collapsed state, and expand/collapse behavior. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
Checks run:
- swift build (pass)
- InfoInspectorPresentationTests (pass; included in 130-test focused run)
- git diff --check (pass)
Findings:
- None
Fixes:
- None
Verification commits:
- 79e4ed1
Actor: codex
Resolved model: unknown
Summary: Made Edit History a collapsed-by-default disclosure below Photo Analysis and retained its history, snapshot, and virtual-copy actions.
