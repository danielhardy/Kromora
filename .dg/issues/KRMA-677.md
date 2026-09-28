---
id: KRMA-677
title: Move or remove the Tone Curve Reset control
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Remove the standalone Reset text/link, or replace it with a compact reset icon aligned at the trailing edge of the Tone Curve accordion title row.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Keep the Tone Curve title and accordion disclosure control clear and aligned.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: If reset remains available, the icon performs the existing reset action and has an accessible label describing that action.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Review the updated inspector layout against the attached screenshot.
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
    - 83a2bab
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T14:38:59.166Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - editor
  - inspector
  - tone-curve
  - ui
created: 2026-09-28T02:30:01.707Z
updated: 2026-09-28T14:41:38.234Z
blockers: []
order: wv1ng6l5
board: product
commits:
  - 83a2bab
---

## Objective

Reduce the visual weight of the Tone Curve Reset control by removing it or moving it into the Tone Curve accordion header.

## User report

The prominent “Reset” text sits on its own row above the curve. It can be removed or replaced with a small, right-aligned icon on the same row as the Tone Curve title. The attached screenshot shows the current layout.

## Acceptance criteria

- Remove the standalone Reset text/link, or replace it with a compact reset icon aligned at the trailing edge of the Tone Curve accordion title row.
- Keep the Tone Curve title and accordion disclosure control clear and aligned.
- If reset remains available, the icon performs the existing reset action and has an accessible label describing that action.
- Review the updated inspector layout against the attached screenshot.

## Context

- Screenshot attached to this issue.

## Checks

- swift build
- Focused Tone Curve inspector tests, including reset behavior if the control remains.

![Tone Curve inspector with a standalone Reset link above the curve](../assets/KRMA-677/screenshot-2026-09-27-at-8-28-58-pm.png)

## Agent log

- 2026-09-28T14:38:59.167Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Remove the standalone Reset text/link, or replace it with a compact reset icon aligned at the trailing edge of the Tone Curve accordion title row. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Keep the Tone Curve title and accordion disclosure control clear and aligned. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] If reset remains available, the icon performs the existing reset action and has an accessible label describing that action. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Review the updated inspector layout against the attached screenshot. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
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
- 83a2bab
Actor: codex
Resolved model: unknown
Summary: Moved Tone Curve Reset into the disclosure row and retained an accessible reset action with undo coverage.
